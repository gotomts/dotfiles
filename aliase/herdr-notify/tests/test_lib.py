#!/usr/bin/env python3
"""lib.py のユニットテスト（標準ライブラリ unittest のみ、外部依存なし）。"""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import lib  # noqa: E402


class RecordStoreTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.base = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_new_record_is_pending_and_persisted(self) -> None:
        record = lib.new_record(
            target="agent-a",
            pane_id="w1:p1",
            repo="/repo",
            worktree="/repo/wt",
            channel_id="chan-1",
            thread_id="thread-1",
            base=self.base,
        )
        self.assertEqual(record["status"], "pending")
        loaded = lib.load_record(record["id"], base=self.base)
        self.assertEqual(loaded, record)

    def test_list_records_filters_by_status(self) -> None:
        r1 = lib.new_record(
            target="a", pane_id="p1", repo="r", worktree="w",
            channel_id="c", thread_id="t", base=self.base,
        )
        lib.new_record(
            target="b", pane_id="p2", repo="r", worktree="w",
            channel_id="c", thread_id="t", base=self.base,
        )
        lib.transition(r1, base=self.base, status="notified")

        pending = lib.list_records(self.base, status="pending")
        notified = lib.list_records(self.base, status="notified")
        self.assertEqual(len(pending), 1)
        self.assertEqual(len(notified), 1)
        self.assertEqual(pending[0]["target"], "b")

    def test_transition_rejects_stale_status(self) -> None:
        record = lib.new_record(
            target="a", pane_id="p1", repo="r", worktree="w",
            channel_id="c", thread_id="t", base=self.base,
        )
        # ディスク上を直接進めて競合状態を模擬する
        lib.transition(record, base=self.base, status="notifying")

        with self.assertRaises(lib.HerdrNotifyError):
            # record 変数は古い status="pending" を保持したままなので拒否されるべき
            lib.transition(record, base=self.base, status="notified")


class RunTickTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.base = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def _make_record(self, target: str = "agent-a") -> dict:
        return lib.new_record(
            target=target,
            pane_id="w1:p1",
            repo="/repo",
            worktree="/repo/wt",
            channel_id="chan-1",
            thread_id="thread-1",
            base=self.base,
        )

    def test_tick_skips_non_terminal_states(self) -> None:
        self._make_record()
        with mock.patch.object(lib, "herdr_agent_get", return_value={"agent_status": "working"}):
            notified = lib.run_tick(base=self.base, notifier=mock.Mock())
        self.assertEqual(notified, [])
        self.assertEqual(len(lib.list_records(self.base, status="pending")), 1)

    def test_tick_notifies_once_for_done(self) -> None:
        self._make_record()
        calls = []

        def notifier(record: dict, body: str) -> dict:
            calls.append((record["id"], body))
            return {"ok": True}

        with mock.patch.object(lib, "herdr_agent_get", return_value={"agent_status": "done"}):
            notified = lib.run_tick(base=self.base, notifier=notifier)

        self.assertEqual(len(notified), 1)
        self.assertEqual(notified[0]["status"], "notified")
        self.assertEqual(notified[0]["notified_state"], "done")
        self.assertEqual(len(calls), 1)
        self.assertIn("done（Hermes検証待ち）", calls[0][1])

        # 二回目の tick は何も投稿しない（重複防止）
        with mock.patch.object(lib, "herdr_agent_get", return_value={"agent_status": "done"}):
            notified_again = lib.run_tick(base=self.base, notifier=notifier)
        self.assertEqual(notified_again, [])
        self.assertEqual(len(calls), 1)

    def test_tick_marks_blocked_with_relay_message(self) -> None:
        self._make_record()
        with mock.patch.object(lib, "herdr_agent_get", return_value={"agent_status": "blocked"}):
            notified = lib.run_tick(base=self.base, notifier=lambda r, b: {"ok": True})
        self.assertEqual(notified[0]["notified_state"], "blocked")

    def test_tick_leaves_pending_when_target_not_found(self) -> None:
        self._make_record()
        with mock.patch.object(
            lib, "herdr_agent_get", side_effect=lib.HerdrNotifyError("not found")
        ):
            notified = lib.run_tick(base=self.base, notifier=mock.Mock())
        self.assertEqual(notified, [])
        self.assertEqual(len(lib.list_records(self.base, status="pending")), 1)

    def test_tick_reverts_to_pending_when_notifier_fails(self) -> None:
        self._make_record()

        def failing_notifier(record: dict, body: str) -> dict:
            raise RuntimeError("discord down")

        with mock.patch.object(lib, "herdr_agent_get", return_value={"agent_status": "done"}):
            with self.assertRaises(RuntimeError):
                lib.run_tick(base=self.base, notifier=failing_notifier)

        pending = lib.list_records(self.base, status="pending")
        self.assertEqual(len(pending), 1)

    def test_tick_does_not_cross_wire_multiple_records(self) -> None:
        self._make_record(target="agent-a")
        self._make_record(target="agent-b")

        def agent_get(target: str) -> dict:
            return {"agent_status": "done" if target == "agent-a" else "working"}

        calls = []
        with mock.patch.object(lib, "herdr_agent_get", side_effect=agent_get):
            notified = lib.run_tick(
                base=self.base, notifier=lambda r, b: calls.append(r["target"])
            )

        self.assertEqual(len(notified), 1)
        self.assertEqual(notified[0]["target"], "agent-a")
        self.assertEqual(calls, ["agent-a"])


if __name__ == "__main__":
    unittest.main()
