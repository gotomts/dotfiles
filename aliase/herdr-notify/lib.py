#!/usr/bin/env python3
"""herdr-notify の共有ロジック。

herdr agent の状態を追跡するレコードの永続化（1レコード1ファイル、原子的書き込み）と、
`herdr` CLI の呼び出しラッパーをまとめる。状態ファイルは dotfiles リポジトリの外
（既定 ~/.herdr-notify/）に置く。スレッド ID・エージェント名などユーザー実行時情報を
リポジトリへ残さないため（~/.hermes/ と同じ運用パターン）。
"""

from __future__ import annotations

import contextlib
import fcntl
import json
import os
import subprocess
import time
import uuid
from pathlib import Path
from typing import Callable, Optional

DEFAULT_STORE_DIR = Path.home() / ".herdr-notify"

TERMINAL_STATES = {"done", "blocked"}


class HerdrNotifyError(RuntimeError):
    """herdr 呼び出し・レコード操作の失敗。"""


# ---------------------------------------------------------------------------
# store layout
# ---------------------------------------------------------------------------


def store_dir(base: Optional[Path] = None) -> Path:
    base = base or DEFAULT_STORE_DIR
    base.mkdir(parents=True, exist_ok=True)
    return base


def records_dir(base: Optional[Path] = None) -> Path:
    d = store_dir(base) / "records"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _record_path(record_id: str, base: Optional[Path] = None) -> Path:
    return records_dir(base) / f"{record_id}.json"


def _now_iso() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _atomic_write(path: Path, data: dict) -> None:
    tmp = path.with_name(path.name + f".tmp{os.getpid()}")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    tmp.replace(path)  # 同一ファイルシステム内の rename は原子的


@contextlib.contextmanager
def tick_lock(base: Optional[Path] = None):
    """tick の同時実行を防ぐ排他ロック。取得できなければ即エラー。"""
    lock_path = store_dir(base) / "tick.lock"
    with open(lock_path, "a+") as fh:
        try:
            fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise HerdrNotifyError("別の tick が実行中です") from exc
        try:
            yield
        finally:
            fcntl.flock(fh, fcntl.LOCK_UN)


# ---------------------------------------------------------------------------
# record CRUD
# ---------------------------------------------------------------------------


def new_record(
    *,
    target: str,
    pane_id: str,
    repo: str,
    worktree: str,
    channel_id: str,
    thread_id: str,
    mention_user_id: Optional[str] = None,
    base: Optional[Path] = None,
) -> dict:
    record = {
        "id": str(uuid.uuid4()),
        "target": target,
        "pane_id": pane_id,
        "repo": repo,
        "worktree": worktree,
        "discord_channel_id": channel_id,
        "discord_thread_id": thread_id,
        "mention_user_id": mention_user_id,
        "submitted_at": _now_iso(),
        "status": "pending",
        "notified_at": None,
        "notified_state": None,
    }
    _atomic_write(_record_path(record["id"], base), record)
    return record


def list_records(base: Optional[Path] = None, status: Optional[str] = None) -> list[dict]:
    out = []
    for path in sorted(records_dir(base).glob("*.json")):
        try:
            data = json.loads(path.read_text())
        except (json.JSONDecodeError, OSError):
            continue
        if status is None or data.get("status") == status:
            out.append(data)
    return out


def load_record(record_id: str, base: Optional[Path] = None) -> dict:
    return json.loads(_record_path(record_id, base).read_text())


def transition(record: dict, *, status: str, base: Optional[Path] = None, **extra) -> dict:
    """record が保持する status を起点に、ディスク上のレコードを新状態へ原子的に進める。

    ディスク上の status が record["status"] と一致しない場合（別プロセスが既に処理した場合）は
    HerdrNotifyError を送出し、呼び出し側は静かにスキップできるようにする。二重通知を防ぐための
    compare-and-swap の代替（1 プロセス直列実行前提のため flock 相当のロックは呼び出し側の
    tick_lock に任せる）。
    """
    path = _record_path(record["id"], base)
    current = json.loads(path.read_text())
    if current["status"] != record["status"]:
        raise HerdrNotifyError(
            f"record {record['id']} の status が競合しています "
            f"(期待 {record['status']!r}, 実際 {current['status']!r})"
        )
    current["status"] = status
    current.update(extra)
    _atomic_write(path, current)
    return current


# ---------------------------------------------------------------------------
# herdr CLI wrappers
# ---------------------------------------------------------------------------


def _run_herdr(args: list[str], *, timeout: float = 15.0) -> dict:
    try:
        proc = subprocess.run(
            ["herdr", *args],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise HerdrNotifyError(f"herdr {' '.join(args)} の実行に失敗しました: {exc}") from exc

    try:
        payload = json.loads(proc.stdout) if proc.stdout.strip() else {}
    except json.JSONDecodeError as exc:
        raise HerdrNotifyError(
            f"herdr {' '.join(args)} の出力を JSON として解釈できません: {proc.stdout!r}"
        ) from exc

    if proc.returncode != 0 or "error" in payload:
        message = payload.get("error", {}).get("message") or proc.stderr.strip() or "unknown error"
        raise HerdrNotifyError(f"herdr {' '.join(args)} が失敗しました: {message}")
    return payload


def herdr_agent_get(target: str) -> dict:
    payload = _run_herdr(["agent", "get", target])
    return payload["result"]["agent"]


def herdr_agent_prompt(target: str, text: str) -> None:
    _run_herdr(["agent", "prompt", target, text])


# ---------------------------------------------------------------------------
# message rendering (捏造禁止: 作業内容・テスト結果の要約は書かない)
# ---------------------------------------------------------------------------


def render_message(record: dict, state: str) -> str:
    if state == "done":
        state_label = "done（Hermes検証待ち）"
        next_action = (
            f"`herdr agent read {record['target']}` で差分・テスト結果を確認し、"
            "Hermes/オーケストレーターが検証してから完了報告してください。"
        )
    elif state == "blocked":
        state_label = "blocked（質問を確認して中継が必要）"
        next_action = (
            f"`herdr agent read {record['target']}` でエージェントの最新の質問を確認し、"
            "回答を中継してください。"
        )
    else:
        raise HerdrNotifyError(f"通知対象外の状態です: {state}")

    lines = [
        f"🔔 `{record['target']}` が {state_label}",
        f"リポジトリ: {record['repo']}",
        f"worktree/cwd: {record['worktree']}",
        f"次アクション: {next_action}",
    ]
    if record.get("mention_user_id"):
        lines.append(f"<@{record['mention_user_id']}>")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# tick
# ---------------------------------------------------------------------------

Notifier = Callable[[dict, str], dict]


def run_tick(base: Optional[Path] = None, notifier: Optional[Notifier] = None) -> list[dict]:
    """pending レコードを 1 回分処理する。done/blocked を検知したものだけ通知して返す。

    冪等: pending 以外のレコードには触れない。同一レコードに対する二重通知は、
    投稿前に status を "notifying" へ原子的に倒す compare-and-swap で防ぐ。
    """
    if notifier is None:
        raise HerdrNotifyError("notifier は必須です")

    notified: list[dict] = []
    for record in list_records(base, status="pending"):
        try:
            agent = herdr_agent_get(record["target"])
        except HerdrNotifyError:
            # 対象が消えている（worktree 削除・セッション終了）可能性がある。
            # レコードは pending のまま残し、次回 tick で再試行する。
            continue

        state = agent.get("agent_status")
        if state not in TERMINAL_STATES:
            continue

        try:
            claimed = transition(record, base=base, status="notifying")
        except HerdrNotifyError:
            # 別プロセスが既に処理を始めている。
            continue

        try:
            body = render_message(claimed, state)
            notifier(claimed, body)
        except Exception:
            # 投稿失敗時は pending へ差し戻し、次回 tick で再試行できるようにする。
            transition(claimed, base=base, status="pending")
            raise

        notified.append(
            transition(
                claimed,
                base=base,
                status="notified",
                notified_at=_now_iso(),
                notified_state=state,
            )
        )
    return notified
