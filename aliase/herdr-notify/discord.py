#!/usr/bin/env python3
"""既存 Discord スレッドへの返信投稿。

~/.hermes/scripts/post_discord_thread.py と同じ認証パターンを再利用する:
DISCORD_BOT_TOKEN は環境変数を優先し、無ければ ~/.hermes/.env（HERMES_HOME 配下）
から読む。token を標準出力・ログ・例外メッセージへ出さない。Discord REST API v10 を
Python stdlib の urllib のみで叩く（新規スレッド作成は行わない。既存スレッドへの
メッセージ投稿のみ）。
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from pathlib import Path

API = "https://discord.com/api/v10"


class DiscordPostError(RuntimeError):
    pass


def load_token() -> str:
    token = os.environ.get("DISCORD_BOT_TOKEN", "")
    if token:
        return token
    env_path = Path(os.environ.get("HERMES_HOME", str(Path.home() / ".hermes"))) / ".env"
    if not env_path.exists():
        raise DiscordPostError(
            "DISCORD_BOT_TOKEN が環境変数になく、"
            f"{env_path} も存在しません"
        )
    for raw in env_path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key.strip() == "DISCORD_BOT_TOKEN":
            return value.strip().strip('"').strip("'")
    raise DiscordPostError("DISCORD_BOT_TOKEN is not configured")


def _request(token: str, method: str, path: str, payload: dict | None = None) -> dict:
    data = None if payload is None else json.dumps(payload, ensure_ascii=False).encode()
    req = urllib.request.Request(
        API + path,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bot {token}",
            "Content-Type": "application/json",
            "User-Agent": "HerdrNotify/1.0",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            body = response.read()
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")
        raise DiscordPostError(f"Discord API error {exc.code}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise DiscordPostError(f"Discord API に到達できません: {exc}") from exc


def post_reply(thread_id: str, content: str, *, dry_run: bool = False) -> dict:
    """thread_id へメッセージを投稿する。dry_run=True なら実際には投稿しない。"""
    if dry_run:
        return {"dry_run": True, "thread_id": thread_id, "content": content}
    token = load_token()
    message = _request(token, "POST", f"/channels/{thread_id}/messages", {"content": content})
    return {"dry_run": False, "thread_id": thread_id, "message_id": message.get("id")}
