#!/usr/bin/env python3
"""discord.py のユニットテスト。token を絶対にログ・出力しないことを検証する。"""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import discord  # noqa: E402


class LoadTokenTest(unittest.TestCase):
    def test_env_var_takes_priority(self) -> None:
        with mock.patch.dict("os.environ", {"DISCORD_BOT_TOKEN": "env-token"}):
            self.assertEqual(discord.load_token(), "env-token")

    def test_falls_back_to_hermes_env_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            hermes_home = Path(tmp)
            (hermes_home / ".env").write_text(
                "OTHER_VAR=ignored\nDISCORD_BOT_TOKEN=\"file-token\"\n"
            )
            with mock.patch.dict(
                "os.environ", {"HERMES_HOME": str(hermes_home)}, clear=True
            ):
                self.assertEqual(discord.load_token(), "file-token")

    def test_raises_when_nothing_configured(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            with mock.patch.dict(
                "os.environ", {"HERMES_HOME": str(Path(tmp) / "missing")}, clear=True
            ):
                with self.assertRaises(discord.DiscordPostError):
                    discord.load_token()


class PostReplyTest(unittest.TestCase):
    def test_dry_run_never_calls_request(self) -> None:
        with mock.patch.object(discord, "_request") as request:
            result = discord.post_reply("thread-1", "hello", dry_run=True)
        request.assert_not_called()
        self.assertEqual(result, {"dry_run": True, "thread_id": "thread-1", "content": "hello"})

    def test_real_post_calls_discord_api_once(self) -> None:
        with mock.patch.object(discord, "load_token", return_value="tok"):
            with mock.patch.object(discord, "_request", return_value={"id": "msg-1"}) as request:
                result = discord.post_reply("thread-1", "hello", dry_run=False)
        request.assert_called_once_with(
            "tok", "POST", "/channels/thread-1/messages", {"content": "hello"}
        )
        self.assertEqual(result, {"dry_run": False, "thread_id": "thread-1", "message_id": "msg-1"})


if __name__ == "__main__":
    unittest.main()
