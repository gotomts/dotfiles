#!/usr/bin/env python3
"""TypeSafe Jev に開発 lane の状態照合を投げる shadow-mode CLI。

位置づけ:
  Claude / Hermes の判断・実行権限は置換しない。この CLI が返すのは「型付きの提案」だけで、
  結果 JSON は常に `automatic_action: false` を持つ。実行根拠にはならない。

入力:
  stdin に JSON を 1 件。受け付けるのは明示的な開発制御面データだけで、raw transcript・
  git diff・ソースファイル内容は読まないし送らない（未知キーは拒否する）。

使い方:
  python3 scripts/jev-development-control-plane.py --dry-run < payload.json
  TYPESAFE_API_KEY=... python3 scripts/jev-development-control-plane.py < payload.json

環境変数:
  TYPESAFE_API_KEY      設定されているときだけ外部 API を呼ぶ（既定は呼ばない）
  JEV_MODEL             model の明示上書き（既定は DEFAULT_MODEL に pin）
  JEV_MONTHLY_USD_CAP   月次の hard cap（既定 50.00 USD）
  JEV_ENDPOINT          endpoint の上書き（テスト用）
  JEV_TIMEOUT_SECONDS   timeout の上書き（テスト用）
  JEV_STATE_DIR         ledger の置き場所の上書き（テスト用）

終了コード:
  0  正常（ok / dry_run / local_only）
  1  入力拒否・予算枯渇・API エラー

運用文書: docs/jev-development-control-plane.md
"""

import argparse
import json
import math
import os
import re
import sqlite3
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

DEFAULT_ENDPOINT = "https://api.typesafe.ai/v1/systemone"
DEFAULT_MODEL = "jev-1.13.0"
DEFAULT_TIMEOUT_SECONDS = 30.0
DEFAULT_MONTHLY_USD_CAP = "50.00"
DEFAULT_STATE_DIR = os.path.join("~", ".local", "state", "jev-development-control-plane")

MAX_INPUT_CHARS = 12_000

# 予約は「1 回の呼出しが使い得る上限」で取り、成功時に実測 usage で精算する。
RESERVED_INPUT_TOKENS = 6_000
# 公式の入力単価: $0.042 / 1,000,000 input tokens。
USD_PER_INPUT_TOKEN = 0.042 / 1_000_000
RESERVATION_USD = RESERVED_INPUT_TOKENS * USD_PER_INPUT_TOKEN

# これ未満の confidence は行動に使わせない。
CONFIDENCE_FLOOR = 0.85

RETRYABLE_STATUSES = (429, 529)
RETRY_BACKOFF_SECONDS = 1.0

# 1 request にまとめる原子的な choice question（公式契約: body の `questions`）。
QUESTIONS = {
    "completion_evidence": {
        "type": "choice",
        "instructions": "宣言された受入条件は、提示された evidence で満たされたと言えるか。",
        "criteria": {
            "verified": "受入条件のそれぞれに対応する evidence があり、内容も矛盾しない。",
            "insufficient": "evidence が足りず、満たされたとも満たされていないとも言えない。",
            "contradictory": "evidence が受入条件や agent_state と食い違っている。",
        },
    },
    "next_gate": {
        "type": "choice",
        "instructions": "この lane が次に通すべき gate はどれか。",
        "criteria": {
            "continue_work": "実装・修正が途中で、作業の続行が次の一手である。",
            "collect_evidence": "実装は進んだが、受入判断に必要な検証結果がまだ取れていない。",
            "commit_or_rebase": "変更が完結し検証も揃っており、履歴を整える段階にある。",
            "pr_or_close_cleanup": "commit 済みで、PR 作成や後片付けが残っている。",
            "needs_human_decision": "設計・境界・優先度の判断が未確定で、人間の決定が要る。",
        },
    },
    "blocker_kind": {
        "type": "choice",
        "instructions": "この lane を止めている要因があるとすれば、その種類はどれか。",
        "criteria": {
            "none": "進行を妨げている要因は見当たらない。",
            "next_step_missing": "次に何をすべきかが定まっていない。",
            "environment_or_tooling": "環境・ツール・依存の不備で作業や検証が進まない。",
            "requirement_ambiguity": "要件や受入条件の解釈が一意に定まらない。",
        },
    },
    "scope_integrity": {
        "type": "choice",
        "instructions": "観測された作業は、宣言された変更境界の内側に収まっているか。",
        "criteria": {
            "in_scope": "すべて宣言された境界の内側にある。",
            "mixed_scope": "境界内の作業に、境界外の変更が混ざっている。",
            "out_of_scope": "主要な作業が宣言された境界の外にある。",
        },
    },
}

# normalization が受け付ける選択肢は question の criteria そのもの（二重定義を作らない）。
CHOICE_OPTIONS = {name: tuple(question["criteria"]) for name, question in QUESTIONS.items()}

STRING_FIELDS = ("lane_id", "source", "observed_at", "agent_state", "summary")
LIST_FIELDS = ("acceptance_conditions", "evidence")
ALLOWED_FIELDS = frozenset(STRING_FIELDS + LIST_FIELDS)

# 秘密らしい鍵名。値ごと API へ出さずに拒否する。
SECRET_KEY_RE = re.compile(
    r"api[_-]?key|access[_-]?key|secret|token|password|passwd|credential"
    r"|authorization|bearer|private[_-]?key",
    re.IGNORECASE,
)

# 秘密らしい値。散文の「input tokens」等を巻き込まないよう、代入形か既知の接頭辞に限る。
SECRET_VALUE_RES = (
    re.compile(r"-----BEGIN[ A-Z]*PRIVATE KEY-----"),
    re.compile(r"\bBearer\s+[A-Za-z0-9\-._~+/]{8,}", re.IGNORECASE),
    re.compile(r"\bsk-[A-Za-z0-9_-]{16,}"),
    re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}"),
    re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{8,}"),
    re.compile(
        r"\b(api[_-]?key|secret|password|passwd|token|credential)\b\s*[:=]\s*\S{6,}",
        re.IGNORECASE,
    ),
)


class InputRejected(Exception):
    """入力を外部 API へ出さずに拒否した。"""


class ApiError(Exception):
    """外部 API 呼出しが失敗した。本文は載せない。"""

    def __init__(self, message, status=None):
        super().__init__(message)
        self.status = status


# ---- 入力検証 -----------------------------------------------------------


def _scan_secrets(node, path="$"):
    """秘密らしい鍵名・値の経路を列挙する。"""
    hits = []
    if isinstance(node, dict):
        for key, value in node.items():
            if isinstance(key, str) and SECRET_KEY_RE.search(key):
                hits.append("%s.%s (鍵名)" % (path, key))
            hits.extend(_scan_secrets(value, "%s.%s" % (path, key)))
    elif isinstance(node, list):
        for index, value in enumerate(node):
            hits.extend(_scan_secrets(value, "%s[%d]" % (path, index)))
    elif isinstance(node, str):
        for pattern in SECRET_VALUE_RES:
            if pattern.search(node):
                hits.append("%s (値)" % path)
                break
    return hits


def parse_input(raw):
    """stdin の生テキストを検証済みの制御面データへ変換する。"""
    if len(raw) > MAX_INPUT_CHARS:
        raise InputRejected(
            "入力が上限を超えている: %d 文字 (上限 %d)" % (len(raw), MAX_INPUT_CHARS)
        )
    try:
        payload = json.loads(raw)
    except ValueError as exc:
        raise InputRejected("JSON として読めない: %s" % exc) from None
    if not isinstance(payload, dict):
        raise InputRejected("最上位は JSON オブジェクトであること")

    unknown = sorted(set(payload) - ALLOWED_FIELDS)
    if unknown:
        raise InputRejected(
            "未知のフィールドは受け付けない（raw transcript / diff / ファイル内容の持ち込み防止）: %s"
            % ", ".join(unknown)
        )
    missing = sorted(ALLOWED_FIELDS - set(payload))
    if missing:
        raise InputRejected("必須フィールドが無い: %s" % ", ".join(missing))

    for field in STRING_FIELDS:
        if not isinstance(payload[field], str) or not payload[field].strip():
            raise InputRejected("%s は非空の文字列であること" % field)
    for field in LIST_FIELDS:
        value = payload[field]
        if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
            raise InputRejected("%s は文字列の配列であること" % field)

    hits = _scan_secrets(payload)
    if hits:
        raise InputRejected("秘密らしい内容を含むため API へ出さずに拒否した: %s" % ", ".join(hits))

    return payload


# ---- request 組み立て ---------------------------------------------------


def build_body(payload, model):
    """公式契約の request body: state / model / questions。payload は state としてのみ送る。"""
    return {
        "state": payload,
        "model": model,
        "questions": QUESTIONS,
    }


def estimate_input_tokens(body):
    """予約判断のための粗い見積もり（精算は API の usage で行う）。"""
    return math.ceil(len(json.dumps(body, ensure_ascii=False)) / 4)


def describe_request(body, endpoint, timeout, has_api_key):
    """機微でない構造だけを返す。state 本文と Authorization の値は含めない。"""
    header_names = ["content-type", "accept"]
    if has_api_key:
        header_names.append("authorization")
    return {
        "method": "POST",
        "url": endpoint,
        "timeout_seconds": timeout,
        "header_names": header_names,
        "body_keys": sorted(body),
        "model": body["model"],
        # question は静的な自前の問い。選択肢の一覧だけ出す（instructions / criteria 本文は出さない）。
        "questions": {name: list(options) for name, options in CHOICE_OPTIONS.items()},
        "state_field_names": sorted(body["state"]),
        "state_bytes": len(json.dumps(body["state"], ensure_ascii=False).encode("utf-8")),
        "estimated_input_tokens": estimate_input_tokens(body),
        "would_call_api": has_api_key,
    }


def local_view(payload, body, cap_usd):
    """API を呼ばずに分かるローカル判断。"""
    return {
        "lane_id": payload["lane_id"],
        "source": payload["source"],
        "observed_at": payload["observed_at"],
        "input_chars": len(json.dumps(payload, ensure_ascii=False)),
        "acceptance_condition_count": len(payload["acceptance_conditions"]),
        "evidence_count": len(payload["evidence"]),
        "has_evidence": bool(payload["evidence"]),
        "estimated_input_tokens": estimate_input_tokens(body),
        "reservation_usd": round(RESERVATION_USD, 8),
        "monthly_cap_usd": cap_usd,
    }


# ---- response 正規化 ----------------------------------------------------


def _entry(value, confidence, state):
    return {
        "value": value,
        "confidence": confidence,
        "state": state,
        "usable_for_action": state == "proposed",
    }


def _extract_answer(data, name):
    """公式契約の `answers` から (choice, confidence) を取り出す。

    受け付けるのは `{"type": "choice", "choice": <選択肢>, "probabilities": {...},
    "confidence": <number>}` だけ。これ以外の形は正規 API の応答として受容せず、
    fail closed で missing / uncertain に落とす。
    """
    answers = data.get("answers") if isinstance(data, dict) else None
    if not isinstance(answers, dict):
        return None, None
    raw = answers.get(name)
    if not isinstance(raw, dict) or raw.get("type") != "choice":
        return None, None

    choice = raw.get("choice")
    if not isinstance(choice, str):
        return None, None
    confidence = raw.get("confidence")
    if not isinstance(confidence, (int, float)) or isinstance(confidence, bool):
        confidence = None
    return choice, confidence


def normalize_response(data):
    """常に全 question を含む提案集合へ正規化する。行動可否は state が示す。"""
    proposals = {}
    for name, options in CHOICE_OPTIONS.items():
        choice, confidence = _extract_answer(data, name)
        if choice is None:
            proposals[name] = _entry(None, None, "missing")
        elif choice not in options:
            proposals[name] = _entry(None, confidence, "invalid")
        elif confidence is None or confidence < CONFIDENCE_FLOOR:
            proposals[name] = _entry(choice, confidence, "uncertain")
        else:
            proposals[name] = _entry(choice, confidence, "proposed")
    return proposals


# ---- 予算 ledger --------------------------------------------------------


class Ledger:
    """private state directory 上の SQLite 月次予算台帳。"""

    def __init__(self, state_dir, cap_usd):
        self.cap_usd = cap_usd
        os.makedirs(state_dir, mode=0o700, exist_ok=True)
        os.chmod(state_dir, 0o700)
        self._conn = sqlite3.connect(os.path.join(state_dir, "ledger.sqlite3"), isolation_level=None)
        self._conn.execute(
            """
            CREATE TABLE IF NOT EXISTS ledger (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                month        TEXT    NOT NULL,
                created_at   TEXT    NOT NULL,
                state        TEXT    NOT NULL,
                input_tokens INTEGER NOT NULL,
                usd          REAL    NOT NULL
            )
            """
        )
        self._conn.execute("CREATE INDEX IF NOT EXISTS ledger_month ON ledger (month, state)")

    @staticmethod
    def current_month():
        return datetime.now(timezone.utc).strftime("%Y-%m")

    def spent_usd(self, month=None):
        month = month or self.current_month()
        row = self._conn.execute(
            "SELECT COALESCE(SUM(usd), 0) FROM ledger WHERE month = ? AND state IN ('reserved', 'settled')",
            (month,),
        ).fetchone()
        return float(row[0])

    def reserve(self):
        """cap 内なら予約 id を返す。超過なら None（外部 API を呼ばせない）。"""
        month = self.current_month()
        self._conn.execute("BEGIN IMMEDIATE")
        try:
            if self.spent_usd(month) + RESERVATION_USD > self.cap_usd:
                self._conn.execute("ROLLBACK")
                return None
            cursor = self._conn.execute(
                "INSERT INTO ledger (month, created_at, state, input_tokens, usd) VALUES (?, ?, 'reserved', ?, ?)",
                (month, datetime.now(timezone.utc).isoformat(), RESERVED_INPUT_TOKENS, RESERVATION_USD),
            )
            self._conn.execute("COMMIT")
            return cursor.lastrowid
        except Exception:
            self._conn.execute("ROLLBACK")
            raise

    def settle(self, reservation_id, input_tokens):
        usd = input_tokens * USD_PER_INPUT_TOKEN
        self._conn.execute(
            "UPDATE ledger SET state = 'settled', input_tokens = ?, usd = ? WHERE id = ?",
            (input_tokens, usd, reservation_id),
        )
        return {"input_tokens": input_tokens, "usd": usd}

    def rollback(self, reservation_id):
        self._conn.execute(
            "UPDATE ledger SET state = 'rolled_back', input_tokens = 0, usd = 0 WHERE id = ?",
            (reservation_id,),
        )

    def close(self):
        self._conn.close()


# ---- HTTP ---------------------------------------------------------------


def http_post(url, body, headers, timeout):
    """stdlib だけで POST する。本文・API key はログに残さない。"""
    request = urllib.request.Request(url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as exc:
        raise ApiError("HTTP %d" % exc.code, status=exc.code) from None
    except urllib.error.URLError as exc:
        raise ApiError("network error: %s" % type(exc.reason).__name__) from None
    except OSError as exc:
        raise ApiError("network error: %s" % type(exc).__name__) from None


def call_api(url, body, api_key, timeout):
    """429 / 529 に限り短い backoff で最大 1 回だけリトライする。"""
    encoded = json.dumps(body, ensure_ascii=False).encode("utf-8")
    headers = {
        "content-type": "application/json",
        "accept": "application/json",
        "authorization": "Bearer %s" % api_key,
    }
    for attempt in range(2):
        try:
            status, raw = http_post(url, encoded, headers, timeout)
        except ApiError as exc:
            if attempt == 0 and exc.status in RETRYABLE_STATUSES:
                time.sleep(RETRY_BACKOFF_SECONDS)
                continue
            raise
        if status >= 400:
            if attempt == 0 and status in RETRYABLE_STATUSES:
                time.sleep(RETRY_BACKOFF_SECONDS)
                continue
            raise ApiError("HTTP %d" % status, status=status)
        try:
            return json.loads(raw.decode("utf-8"))
        except ValueError:
            raise ApiError("応答が JSON ではない") from None
    raise ApiError("リトライ後も失敗した")


# ---- CLI ----------------------------------------------------------------


def _float_env(env, name, default):
    raw = env.get(name)
    if raw is None or not raw.strip():
        return float(default)
    try:
        return float(raw)
    except ValueError:
        raise InputRejected("%s を数値として読めない: %r" % (name, raw)) from None


def _emit(stdout, status, exit_code, **fields):
    result = {"status": status, "automatic_action": False, "advisory_only": True}
    result.update(fields)
    stdout.write(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    return exit_code


def main(argv=None, stdin_text=None, stdout=None, env=None):
    parser = argparse.ArgumentParser(
        prog="jev-development-control-plane",
        description="開発 lane の状態照合を TypeSafe Jev へ shadow-mode で投げる。",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="外部 API を呼ばず、生成する request の機微でない構造とローカル判断だけを返す",
    )
    args = parser.parse_args(argv)

    env = os.environ if env is None else env
    stdout = sys.stdout if stdout is None else stdout

    if stdin_text is None:
        stdin_text = sys.stdin.read(MAX_INPUT_CHARS + 1)

    try:
        cap_usd = _float_env(env, "JEV_MONTHLY_USD_CAP", DEFAULT_MONTHLY_USD_CAP)
        timeout = _float_env(env, "JEV_TIMEOUT_SECONDS", DEFAULT_TIMEOUT_SECONDS)
        payload = parse_input(stdin_text)
    except InputRejected as exc:
        return _emit(stdout, "rejected", 1, reason=str(exc))

    endpoint = env.get("JEV_ENDPOINT") or DEFAULT_ENDPOINT
    model = env.get("JEV_MODEL") or DEFAULT_MODEL
    api_key = env.get("TYPESAFE_API_KEY")
    state_dir = os.path.expanduser(env.get("JEV_STATE_DIR") or DEFAULT_STATE_DIR)

    body = build_body(payload, model)
    local = local_view(payload, body, cap_usd)

    if args.dry_run:
        return _emit(
            stdout,
            "dry_run",
            0,
            model=model,
            local=local,
            request=describe_request(body, endpoint, timeout, bool(api_key)),
        )

    if not api_key:
        return _emit(
            stdout,
            "local_only",
            0,
            model=model,
            local=local,
            reason="TYPESAFE_API_KEY が無いため外部 API を呼ばない（shadow-mode の既定）",
        )

    ledger = Ledger(state_dir, cap_usd)
    try:
        reservation = ledger.reserve()
        if reservation is None:
            return _emit(
                stdout,
                "budget_exhausted",
                1,
                model=model,
                local=local,
                budget={
                    "month": ledger.current_month(),
                    "cap_usd": cap_usd,
                    "spent_usd": round(ledger.spent_usd(), 8),
                },
            )
        try:
            data = call_api(endpoint, body, api_key, timeout)
        except ApiError as exc:
            ledger.rollback(reservation)
            return _emit(stdout, "api_error", 1, model=model, local=local, reason=str(exc))

        usage = data.get("usage") if isinstance(data, dict) else None
        input_tokens = usage.get("input_tokens") if isinstance(usage, dict) else None
        if not isinstance(input_tokens, int) or isinstance(input_tokens, bool) or input_tokens < 0:
            input_tokens = RESERVED_INPUT_TOKENS
        settled = ledger.settle(reservation, input_tokens)

        return _emit(
            stdout,
            "ok",
            0,
            model=model,
            local=local,
            proposals=normalize_response(data),
            usage={"input_tokens": settled["input_tokens"], "usd": round(settled["usd"], 8)},
            budget={
                "month": ledger.current_month(),
                "cap_usd": cap_usd,
                "spent_usd": round(ledger.spent_usd(), 8),
            },
        )
    finally:
        ledger.close()


if __name__ == "__main__":
    sys.exit(main())
