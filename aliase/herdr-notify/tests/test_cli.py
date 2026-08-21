#!/usr/bin/env python3
"""cli.py の統合テスト。herdr / Discord への実アクセスは一切行わない。"""

from __future__ import annotations

import io
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import cli  # noqa: E402
import discord  # noqa: E402
import lib  # noqa: E402


class SubmitTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.base = Path(self._tmp.name)
        self._patch_store = mock.patch.object(lib, "DEFAULT_STORE_DIR", self.base)
        self._patch_store.start()

    def tearDown(self) -> None:
        self._patch_store.stop()
        self._tmp.cleanup()

    def test_submit_records_and_sends_prompt(self) -> None:
        agent = {"cwd": "/repo/wt", "pane_id": "w1:p1"}
        prompt_calls = []

        with mock.patch.object(lib, "herdr_agent_get", return_value=agent), \
             mock.patch.object(lib, "herdr_agent_prompt", side_effect=lambda t, x: prompt_calls.append((t, x))), \
             mock.patch.object(cli, "_git_remote", return_value="git@github.com:example/repo.git"):
            out = io.StringIO()
            with redirect_stdout(out):
                code = cli.main(
                    ["submit", "agent-a", "hello", "--channel", "chan-1", "--thread", "thread-1"]
                )

        self.assertEqual(code, 0)
        self.assertEqual(prompt_calls, [("agent-a", "hello")])

        records = lib.list_records(self.base)
        self.assertEqual(len(records), 1)
        record = records[0]
        self.assertEqual(record["target"], "agent-a")
        self.assertEqual(record["pane_id"], "w1:p1")
        self.assertEqual(record["repo"], "git@github.com:example/repo.git")
        self.assertEqual(record["worktree"], "/repo/wt")
        self.assertEqual(record["discord_channel_id"], "chan-1")
        self.assertEqual(record["discord_thread_id"], "thread-1")
        self.assertEqual(out.getvalue().strip(), record["id"])

    def test_submit_does_not_record_when_target_missing(self) -> None:
        with mock.patch.object(
            lib, "herdr_agent_get", side_effect=lib.HerdrNotifyError("agent target x not found")
        ):
            err = io.StringIO()
            with redirect_stderr(err):
                code = cli.main(
                    ["submit", "missing", "hello", "--channel", "c", "--thread", "t"]
                )

        self.assertEqual(code, 1)
        self.assertIn("not found", err.getvalue())
        self.assertEqual(lib.list_records(self.base), [])

    def test_submit_reads_text_from_stdin(self) -> None:
        agent = {"cwd": "", "pane_id": "w1:p1"}
        with mock.patch.object(lib, "herdr_agent_get", return_value=agent), \
             mock.patch.object(lib, "herdr_agent_prompt") as prompt, \
             mock.patch("sys.stdin", io.StringIO("stdin本文")):
            out = io.StringIO()
            with redirect_stdout(out):
                code = cli.main(["submit", "agent-a", "-", "--channel", "c", "--thread", "t"])
        self.assertEqual(code, 0)
        prompt.assert_called_once_with("agent-a", "stdin本文")


class TickTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.base = Path(self._tmp.name)
        self._patch_store = mock.patch.object(lib, "DEFAULT_STORE_DIR", self.base)
        self._patch_store.start()

    def tearDown(self) -> None:
        self._patch_store.stop()
        self._tmp.cleanup()

    def test_tick_dry_run_does_not_call_discord_request(self) -> None:
        lib.new_record(
            target="agent-a", pane_id="p1", repo="/r", worktree="/r/wt",
            channel_id="c", thread_id="thread-1",
        )
        with mock.patch.object(lib, "herdr_agent_get", return_value={"agent_status": "done"}), \
             mock.patch.object(discord, "_request") as request:
            out = io.StringIO()
            with redirect_stdout(out):
                code = cli.main(["tick", "--dry-run"])

        self.assertEqual(code, 0)
        request.assert_not_called()
        self.assertIn("notified", out.getvalue())
        notified = lib.list_records(self.base, status="notified")
        self.assertEqual(len(notified), 1)

    def test_tick_is_idempotent_across_two_invocations(self) -> None:
        lib.new_record(
            target="agent-a", pane_id="p1", repo="/r", worktree="/r/wt",
            channel_id="c", thread_id="thread-1",
        )
        with mock.patch.object(lib, "herdr_agent_get", return_value={"agent_status": "blocked"}), \
             mock.patch.object(discord, "post_reply", return_value={"dry_run": True}) as post:
            out = io.StringIO()
            with redirect_stdout(out):
                cli.main(["tick", "--dry-run"])
                cli.main(["tick", "--dry-run"])

        self.assertEqual(post.call_count, 1)


if __name__ == "__main__":
    unittest.main()
