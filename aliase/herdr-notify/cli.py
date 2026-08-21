#!/usr/bin/env python3
"""herdr-notify CLI.

  herdr-notify submit <target> <text> --channel <id> --thread <id> [--mention <id>]
      herdr agent prompt を送信し、送信元 Discord スレッドと紐づけて永続記録する。

  herdr-notify tick [--dry-run]
      pending レコードを 1 回分チェックし、done/blocked を検知したものだけ
      元スレッドへ通知する。cron 等から定期実行する想定（既定 1〜2 分間隔）。
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import discord  # noqa: E402
import lib  # noqa: E402


def _git_remote(cwd: str) -> str | None:
    if not cwd:
        return None
    try:
        proc = subprocess.run(
            ["git", "-C", cwd, "remote", "get-url", "origin"],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except OSError:
        return None
    if proc.returncode != 0:
        return None
    return proc.stdout.strip() or None


def cmd_submit(args: argparse.Namespace) -> int:
    text = sys.stdin.read() if args.text == "-" else args.text

    try:
        agent = lib.herdr_agent_get(args.target)
    except lib.HerdrNotifyError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    worktree = agent.get("cwd", "")
    repo = _git_remote(worktree) or worktree

    try:
        lib.herdr_agent_prompt(args.target, text)
    except lib.HerdrNotifyError as exc:
        print(f"error: prompt送信に失敗しました: {exc}", file=sys.stderr)
        return 1

    record = lib.new_record(
        target=args.target,
        pane_id=agent.get("pane_id", ""),
        repo=repo,
        worktree=worktree,
        channel_id=args.channel,
        thread_id=args.thread,
        mention_user_id=args.mention,
    )
    print(record["id"])
    return 0


def cmd_tick(args: argparse.Namespace) -> int:
    def notifier(record: dict, body: str) -> dict:
        return discord.post_reply(record["discord_thread_id"], body, dry_run=args.dry_run)

    try:
        with lib.tick_lock():
            notified = lib.run_tick(notifier=notifier)
    except lib.HerdrNotifyError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    for record in notified:
        print(f"notified {record['id']} ({record['target']} -> {record['notified_state']})")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="herdr-notify")
    sub = parser.add_subparsers(dest="command", required=True)

    p_submit = sub.add_parser(
        "submit", help="herdr agent prompt を送信し、Discordスレッドと紐づけて記録する"
    )
    p_submit.add_argument("target", help="herdr agent の target（name または pane_id）")
    p_submit.add_argument("text", help="プロンプト本文。'-' で標準入力から読む")
    p_submit.add_argument("--channel", required=True, help="送信元 Discord channel ID")
    p_submit.add_argument("--thread", required=True, help="送信元 Discord thread ID")
    p_submit.add_argument("--mention", default=None, help="通知時にメンションする Discord user ID")
    p_submit.set_defaults(func=cmd_submit)

    p_tick = sub.add_parser(
        "tick", help="pending レコードを1回分チェックし、done/blocked を通知する"
    )
    p_tick.add_argument(
        "--dry-run", action="store_true", help="実際には投稿せず、投稿内容だけ確認する"
    )
    p_tick.set_defaults(func=cmd_tick)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
