#!/usr/bin/env python3
"""jev-development-control-plane.py の回帰テスト。

`python3 scripts/jev-development-control-plane.test.py` で実行する。
本体はファイル名にハイフンを含み import できないため importlib で読む。
実 HTTP は行わない（`jev.http_post` を差し替える）。
"""

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "jev-development-control-plane.py")

# リポジトリ内に __pycache__ を作らせない。
sys.dont_write_bytecode = True

_spec = importlib.util.spec_from_file_location("jev_development_control_plane", SCRIPT)
jev = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(jev)


VALID_INPUT = {
    "lane_id": "lane-dotfiles-001",
    "source": "claude-code",
    "observed_at": "2026-09-20T12:00:00Z",
    "agent_state": "実装済み。bats と unittest をローカルで実行し全て成功。未 commit。",
    "acceptance_conditions": [
        "新規 Python テストが成功する",
        "bats setup/tests/link.bats が成功する",
    ],
    "evidence": [
        "python3 scripts/jev-development-control-plane.test.py -> exit 0",
        "bats setup/tests/link.bats -> 4 tests, 0 failures",
    ],
    "summary": "開発 lane の状態照合を Jev に投げる前段の shadow-mode 入力",
}


def payload(**overrides):
    data = dict(VALID_INPUT)
    data.update(overrides)
    return json.dumps(data, ensure_ascii=False)


def run_cli(stdin_text, args=(), env=None):
    """CLI を実プロセスとして起動し (exit code, stdout, stderr) を返す。"""
    child_env = dict(os.environ)
    child_env.pop("TYPESAFE_API_KEY", None)
    if env:
        child_env.update(env)
    proc = subprocess.run(
        [sys.executable, SCRIPT, *args],
        input=stdin_text,
        capture_output=True,
        text=True,
        env=child_env,
    )
    return proc.returncode, proc.stdout, proc.stderr


class InputValidationTest(unittest.TestCase):
    def test_valid_input_is_accepted(self):
        parsed = jev.parse_input(payload())
        self.assertEqual(parsed["lane_id"], VALID_INPUT["lane_id"])

    def test_non_object_is_rejected(self):
        with self.assertRaises(jev.InputRejected):
            jev.parse_input("[1, 2, 3]")

    def test_broken_json_is_rejected(self):
        with self.assertRaises(jev.InputRejected):
            jev.parse_input("not-json")

    def test_missing_required_field_is_rejected(self):
        data = dict(VALID_INPUT)
        del data["evidence"]
        with self.assertRaises(jev.InputRejected):
            jev.parse_input(json.dumps(data))

    def test_unknown_field_is_rejected(self):
        """raw transcript / diff / ファイル内容の持ち込み口を塞ぐ。"""
        for extra in ("transcript", "git_diff", "file_contents"):
            with self.subTest(field=extra):
                with self.assertRaises(jev.InputRejected):
                    jev.parse_input(payload(**{extra: "..."}))

    def test_wrong_type_is_rejected(self):
        with self.assertRaises(jev.InputRejected):
            jev.parse_input(payload(evidence="単一文字列は不可"))
        with self.assertRaises(jev.InputRejected):
            jev.parse_input(payload(lane_id=123))

    def test_oversized_input_is_rejected(self):
        raw = payload(summary="あ" * (jev.MAX_INPUT_CHARS + 10))
        with self.assertRaises(jev.InputRejected):
            jev.parse_input(raw)

    def test_secret_like_key_name_is_rejected(self):
        for name in ("api_key", "TOKEN", "password", "private-key", "authorization"):
            with self.subTest(key=name):
                data = dict(VALID_INPUT)
                data[name] = "x"
                with self.assertRaises(jev.InputRejected):
                    jev.parse_input(json.dumps(data))

    def test_secret_like_value_is_rejected(self):
        secrets = [
            "Authorization: Bearer abcdef0123456789",
            "TYPESAFE_API_KEY=sk-0123456789abcdefghij",
            "-----BEGIN RSA PRIVATE KEY-----",
            "ghp_0123456789abcdefghijklmnopqrstuvwx",
            "AKIAIOSFODNN7EXAMPLE",
        ]
        for value in secrets:
            with self.subTest(value=value):
                with self.assertRaises(jev.InputRejected):
                    jev.parse_input(payload(summary=value))

    def test_benign_token_wording_is_not_rejected(self):
        """`input tokens` のような通常の散文は誤検出しない。"""
        parsed = jev.parse_input(payload(summary="最大 6,000 input tokens を予約する"))
        self.assertIn("tokens", parsed["summary"])


class DryRunTest(unittest.TestCase):
    def test_dry_run_reports_structure_without_state_or_authorization(self):
        code, stdout, _stderr = run_cli(
            payload(), args=("--dry-run",), env={"TYPESAFE_API_KEY": "sk-should-not-leak"}
        )
        self.assertEqual(code, 0)
        result = json.loads(stdout)
        self.assertEqual(result["status"], "dry_run")
        self.assertFalse(result["automatic_action"])

        request = result["request"]
        self.assertEqual(request["method"], "POST")
        self.assertEqual(request["url"], jev.DEFAULT_ENDPOINT)
        self.assertEqual(request["body_keys"], ["model", "questions", "state"])
        self.assertEqual(sorted(request["questions"]), sorted(jev.CHOICE_OPTIONS))
        # 機微は構造だけ: ヘッダは名前のみ、state は本文でなくフィールド名のみ。
        self.assertIn("authorization", request["header_names"])
        self.assertEqual(sorted(request["state_field_names"]), sorted(jev.ALLOWED_FIELDS))

        blob = json.dumps(result, ensure_ascii=False)
        self.assertNotIn("sk-should-not-leak", blob)
        self.assertNotIn(VALID_INPUT["agent_state"], blob)
        self.assertNotIn(VALID_INPUT["evidence"][0], blob)

    def test_dry_run_makes_no_http_call(self):
        calls = []
        original = jev.http_post
        jev.http_post = lambda *a, **kw: calls.append(a) or (200, b"{}")
        try:
            code = jev.main(["--dry-run"], stdin_text=payload(), stdout=_Sink())
        finally:
            jev.http_post = original
        self.assertEqual(code, 0)
        self.assertEqual(calls, [])

    def test_rejected_input_still_reports_automatic_action_false(self):
        code, stdout, _stderr = run_cli("not-json", args=("--dry-run",))
        self.assertEqual(code, 1)
        result = json.loads(stdout)
        self.assertEqual(result["status"], "rejected")
        self.assertFalse(result["automatic_action"])

    def test_without_api_key_no_call_is_made(self):
        code, stdout, _stderr = run_cli(payload())
        self.assertEqual(code, 0)
        result = json.loads(stdout)
        self.assertEqual(result["status"], "local_only")
        self.assertFalse(result["automatic_action"])


def answer(choice, confidence, probabilities=None):
    """公式契約の choice answer 形。"""
    return {
        "type": "choice",
        "choice": choice,
        "probabilities": probabilities or {choice: confidence},
        "confidence": confidence,
    }


class QuestionContractTest(unittest.TestCase):
    """request 側の公式契約: body は state / model / questions。"""

    def test_body_keys_match_the_contract(self):
        body = jev.build_body(VALID_INPUT, jev.DEFAULT_MODEL)
        self.assertEqual(sorted(body), ["model", "questions", "state"])
        self.assertNotIn("choices", body)
        self.assertEqual(body["state"], VALID_INPUT)

    def test_all_four_questions_ride_in_one_request(self):
        body = jev.build_body(VALID_INPUT, jev.DEFAULT_MODEL)
        self.assertEqual(
            sorted(body["questions"]),
            ["blocker_kind", "completion_evidence", "next_gate", "scope_integrity"],
        )

    def test_each_question_is_a_choice_with_criteria(self):
        for name, question in jev.QUESTIONS.items():
            with self.subTest(question=name):
                self.assertEqual(question["type"], "choice")
                self.assertTrue(question["instructions"].strip())
                criteria = question["criteria"]
                self.assertIsInstance(criteria, dict)
                self.assertGreaterEqual(len(criteria), 3)
                for option, description in criteria.items():
                    self.assertTrue(description.strip(), "%s の %s に説明が無い" % (name, option))
                # normalization が受け付ける選択肢は criteria と一致する。
                self.assertEqual(tuple(criteria), jev.CHOICE_OPTIONS[name])


class NormalizeResponseTest(unittest.TestCase):
    def test_high_confidence_is_proposed(self):
        proposals = jev.normalize_response(
            {"answers": {"next_gate": answer("commit_or_rebase", 0.91)}}
        )
        entry = proposals["next_gate"]
        self.assertEqual(entry["value"], "commit_or_rebase")
        self.assertEqual(entry["state"], "proposed")
        self.assertTrue(entry["usable_for_action"])

    def test_low_confidence_is_uncertain_and_unusable(self):
        for confidence in (0.0, 0.5, 0.8499):
            with self.subTest(confidence=confidence):
                proposals = jev.normalize_response(
                    {"answers": {"next_gate": answer("continue_work", confidence)}}
                )
                entry = proposals["next_gate"]
                self.assertEqual(entry["state"], "uncertain")
                self.assertFalse(entry["usable_for_action"])

    def test_confidence_threshold_boundary_is_inclusive(self):
        proposals = jev.normalize_response(
            {"answers": {"next_gate": answer("continue_work", jev.CONFIDENCE_FLOOR)}}
        )
        self.assertEqual(proposals["next_gate"]["state"], "proposed")

    def test_unknown_option_is_invalid(self):
        proposals = jev.normalize_response({"answers": {"blocker_kind": answer("ship_it", 0.99)}})
        entry = proposals["blocker_kind"]
        self.assertEqual(entry["state"], "invalid")
        self.assertIsNone(entry["value"])
        self.assertFalse(entry["usable_for_action"])

    def test_missing_answer_is_missing(self):
        proposals = jev.normalize_response({"answers": {}})
        self.assertEqual(sorted(proposals), sorted(jev.CHOICE_OPTIONS))
        for name, entry in proposals.items():
            with self.subTest(question=name):
                self.assertEqual(entry["state"], "missing")
                self.assertFalse(entry["usable_for_action"])

    def test_missing_confidence_is_uncertain(self):
        proposals = jev.normalize_response(
            {"answers": {"scope_integrity": {"type": "choice", "choice": "in_scope"}}}
        )
        entry = proposals["scope_integrity"]
        self.assertEqual(entry["value"], "in_scope")
        self.assertEqual(entry["state"], "uncertain")
        self.assertFalse(entry["usable_for_action"])

    def test_legacy_choices_shape_is_not_accepted(self):
        """独自の choices/value 形は正規 API の応答として受容しない。"""
        legacy = [
            {"choices": {"next_gate": {"value": "commit_or_rebase", "confidence": 0.99}}},
            {"next_gate": "commit_or_rebase"},
            {"choices": {"scope_integrity": ["in_scope"]}},
        ]
        for data in legacy:
            with self.subTest(data=data):
                proposals = jev.normalize_response(data)
                for name, entry in proposals.items():
                    with self.subTest(question=name):
                        self.assertEqual(entry["state"], "missing")
                        self.assertFalse(entry["usable_for_action"])

    def test_wrong_answer_type_fails_closed(self):
        proposals = jev.normalize_response(
            {"answers": {"next_gate": {"type": "text", "text": "commit_or_rebase"}}}
        )
        self.assertEqual(proposals["next_gate"]["state"], "missing")

    def test_garbage_response_does_not_crash(self):
        for data in (None, [], "text", {"answers": "text"}, {"answers": {"next_gate": 3}}):
            with self.subTest(data=data):
                proposals = jev.normalize_response(data)
                self.assertEqual(sorted(proposals), sorted(jev.CHOICE_OPTIONS))
                for entry in proposals.values():
                    self.assertFalse(entry["usable_for_action"])


class LedgerTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.state_dir = os.path.join(self._tmp.name, "state")
        self.addCleanup(self._tmp.cleanup)

    def ledger(self, cap=50.0):
        return jev.Ledger(self.state_dir, cap_usd=cap)

    def test_state_directory_is_private(self):
        self.ledger().close()
        mode = os.stat(self.state_dir).st_mode & 0o777
        self.assertEqual(mode, 0o700)

    def test_reservation_consumes_budget_until_cap(self):
        ledger = self.ledger(cap=jev.RESERVATION_USD * 2)
        self.addCleanup(ledger.close)
        self.assertIsNotNone(ledger.reserve())
        self.assertIsNotNone(ledger.reserve())
        self.assertIsNone(ledger.reserve(), "cap 超過は予約できない")

    def test_rollback_frees_the_reservation(self):
        ledger = self.ledger(cap=jev.RESERVATION_USD)
        self.addCleanup(ledger.close)
        reservation = ledger.reserve()
        self.assertIsNone(ledger.reserve())
        ledger.rollback(reservation)
        self.assertEqual(ledger.spent_usd(), 0.0)
        self.assertIsNotNone(ledger.reserve(), "取り消し後は再予約できる")

    def test_settlement_records_actual_usage(self):
        ledger = self.ledger()
        self.addCleanup(ledger.close)
        reservation = ledger.reserve()
        settled = ledger.settle(reservation, input_tokens=120)
        self.assertEqual(settled["input_tokens"], 120)
        self.assertAlmostEqual(ledger.spent_usd(), settled["usd"], places=9)
        self.assertLess(ledger.spent_usd(), jev.RESERVATION_USD)

    def test_ledger_survives_reopen(self):
        ledger = self.ledger()
        ledger.settle(ledger.reserve(), input_tokens=500)
        spent = ledger.spent_usd()
        ledger.close()

        reopened = self.ledger()
        self.addCleanup(reopened.close)
        self.assertAlmostEqual(reopened.spent_usd(), spent, places=9)


class ApiCallTest(unittest.TestCase):
    """http_post を差し替えて外部通信なしに経路を検証する。"""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.state_dir = os.path.join(self._tmp.name, "state")
        self._original_post = jev.http_post
        self._original_sleep = jev.time.sleep
        jev.time.sleep = lambda _seconds: None
        self.addCleanup(self._restore)

    def _restore(self):
        jev.http_post = self._original_post
        jev.time.sleep = self._original_sleep

    def env(self, **extra):
        base = {"TYPESAFE_API_KEY": "sk-test", "JEV_STATE_DIR": self.state_dir}
        base.update(extra)
        return base

    def invoke(self, env=None, argv=()):
        sink = _Sink()
        code = jev.main(list(argv), stdin_text=payload(), stdout=sink, env=self.env(**(env or {})))
        return code, json.loads(sink.text())

    def test_successful_call_settles_with_reported_usage(self):
        seen = {}

        def fake_post(url, body, headers, timeout):
            seen["url"] = url
            seen["headers"] = headers
            seen["body"] = json.loads(body.decode("utf-8"))
            return 200, json.dumps(
                {
                    "answers": {
                        name: answer(options[0], 0.9)
                        for name, options in jev.CHOICE_OPTIONS.items()
                    },
                    "usage": {"input_tokens": 321},
                }
            ).encode("utf-8")

        jev.http_post = fake_post
        code, result = self.invoke()

        self.assertEqual(code, 0)
        self.assertEqual(result["status"], "ok")
        self.assertFalse(result["automatic_action"])
        self.assertEqual(result["usage"]["input_tokens"], 321)
        self.assertEqual(result["model"], jev.DEFAULT_MODEL)
        self.assertEqual(seen["url"], jev.DEFAULT_ENDPOINT)

        # 公式契約の request 形で送っていること。
        self.assertEqual(sorted(seen["body"]), ["model", "questions", "state"])
        self.assertEqual(seen["body"]["model"], jev.DEFAULT_MODEL)
        self.assertEqual(seen["body"]["state"], VALID_INPUT)
        self.assertEqual(sorted(seen["body"]["questions"]), sorted(jev.CHOICE_OPTIONS))
        for name, question in seen["body"]["questions"].items():
            with self.subTest(question=name):
                self.assertEqual(question["type"], "choice")
                self.assertIn("instructions", question)
                self.assertEqual(sorted(question["criteria"]), sorted(jev.CHOICE_OPTIONS[name]))

        for name, entry in result["proposals"].items():
            with self.subTest(question=name):
                self.assertEqual(entry["state"], "proposed")

        ledger = jev.Ledger(self.state_dir, cap_usd=50.0)
        self.addCleanup(ledger.close)
        self.assertAlmostEqual(
            ledger.spent_usd(), 321 * jev.USD_PER_INPUT_TOKEN, places=12
        )

    def test_model_can_be_overridden(self):
        jev.http_post = lambda *a, **kw: (200, b'{"answers": {}, "usage": {"input_tokens": 1}}')
        _code, result = self.invoke(env={"JEV_MODEL": "jev-2.0.0"})
        self.assertEqual(result["model"], "jev-2.0.0")

    def test_budget_exhausted_skips_the_call(self):
        called = []
        jev.http_post = lambda *a, **kw: called.append(a) or (200, b"{}")
        code, result = self.invoke(env={"JEV_MONTHLY_USD_CAP": "0.000001"})
        self.assertEqual(code, 1)
        self.assertEqual(result["status"], "budget_exhausted")
        self.assertFalse(result["automatic_action"])
        self.assertEqual(called, [], "cap 超過では外部 API を呼ばない")

    def test_failure_rolls_back_the_reservation(self):
        def boom(*_args, **_kwargs):
            raise jev.ApiError("HTTP 500")

        jev.http_post = boom
        code, result = self.invoke()
        self.assertEqual(code, 1)
        self.assertEqual(result["status"], "api_error")

        ledger = jev.Ledger(self.state_dir, cap_usd=50.0)
        self.addCleanup(ledger.close)
        self.assertEqual(ledger.spent_usd(), 0.0)

    def test_retryable_status_is_retried_once(self):
        attempts = []

        def flaky(url, body, headers, timeout):
            attempts.append(1)
            if len(attempts) == 1:
                raise jev.ApiError("HTTP 429", status=429)
            return 200, b'{"answers": {}, "usage": {"input_tokens": 10}}'

        jev.http_post = flaky
        code, result = self.invoke()
        self.assertEqual(code, 0)
        self.assertEqual(result["status"], "ok")
        self.assertEqual(len(attempts), 2)

    def test_retry_happens_at_most_once(self):
        attempts = []

        def always_busy(*_args, **_kwargs):
            attempts.append(1)
            raise jev.ApiError("HTTP 529", status=529)

        jev.http_post = always_busy
        code, result = self.invoke()
        self.assertEqual(code, 1)
        self.assertEqual(result["status"], "api_error")
        self.assertEqual(len(attempts), 2)

    def test_non_retryable_status_is_not_retried(self):
        attempts = []

        def bad_request(*_args, **_kwargs):
            attempts.append(1)
            raise jev.ApiError("HTTP 400", status=400)

        jev.http_post = bad_request
        code, _result = self.invoke()
        self.assertEqual(code, 1)
        self.assertEqual(len(attempts), 1)

    def test_endpoint_and_timeout_are_overridable(self):
        seen = {}

        def fake_post(url, body, headers, timeout):
            seen["url"] = url
            seen["timeout"] = timeout
            return 200, b'{"answers": {}, "usage": {"input_tokens": 1}}'

        jev.http_post = fake_post
        self.invoke(env={"JEV_ENDPOINT": "http://127.0.0.1:1/v1/test", "JEV_TIMEOUT_SECONDS": "3"})
        self.assertEqual(seen["url"], "http://127.0.0.1:1/v1/test")
        self.assertEqual(seen["timeout"], 3.0)

    def test_api_key_never_appears_in_output(self):
        jev.http_post = lambda *a, **kw: (200, b'{"answers": {}, "usage": {"input_tokens": 1}}')
        _code, result = self.invoke(env={"TYPESAFE_API_KEY": "sk-super-secret-value"})
        self.assertNotIn("sk-super-secret-value", json.dumps(result, ensure_ascii=False))


class _Sink:
    """main() の出力を受ける最小の書き込み先。"""

    def __init__(self):
        self._chunks = []

    def write(self, chunk):
        self._chunks.append(chunk)

    def text(self):
        return "".join(self._chunks)


if __name__ == "__main__":
    unittest.main(verbosity=2)
