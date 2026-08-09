#!/usr/bin/env python3
"""Stop hook: 1 応答に質問が 2 件以上あればブロックする (AGENTS.md 一問一答ルール)。

exit code は 0 (通過) か 2 (ブロック) のみ。それ以外の非ゼロは Claude Code が
non-blocking error として扱い hook が素通りするため、例外は全て 0 に倒す。

hook 起動時点では当該ターンの assistant メッセージがまだ transcript に
書かれておらず、そのまま読むと前ターンのテキストを誤判定する。全 user
エントリ (tool_result を含む) より後ろに assistant のテキストが現れるまで
待ち、時間内に確定しなければ判定を諦めて通す。
"""

import json
import re
import sys
import time

FENCE = re.compile(r"^\s*```")
SKIP_LINE = re.compile(r"^\s*[>|]")
QUESTION_END = re.compile(r"[?？]\s*$")

TAIL_BYTES = 512 * 1024
POLL_INTERVAL = 0.1
POLL_TIMEOUT = 3.0

MESSAGE = (
    "質問が {n} 件あります。AGENTS.md の一問一答ルールに反します。\n"
    "1 つに絞るか、AskUserQuestion ツールを使ってください。\n"
    "残りの質問は次のターンに回してください。"
)


def tail_entries(path):
    """transcript 末尾のみ読む (数 MB 規模を毎ポーリング全読みしないため)。"""
    with open(path, "rb") as f:
        f.seek(0, 2)
        size = f.tell()
        f.seek(max(0, size - TAIL_BYTES))
        chunk = f.read()
    if size > TAIL_BYTES:
        _, _, chunk = chunk.partition(b"\n")

    entries = []
    for line in chunk.decode("utf-8", "replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(entry, dict):
            entries.append(entry)
    return entries


def block_text(content):
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return ""
    return "\n".join(
        b.get("text", "")
        for b in content
        if isinstance(b, dict) and b.get("type") == "text" and b.get("text")
    )


def settled_text(entries):
    """当該ターンの assistant テキスト。未確定なら None。"""
    last_user = -1
    last_assistant = -1
    text = ""
    for i, entry in enumerate(entries):
        # サブエージェントの応答は親の 1 ターンではないので対象外
        if entry.get("isSidechain"):
            continue
        kind = entry.get("type")
        if kind == "user":
            last_user = i
        elif kind == "assistant":
            candidate = block_text((entry.get("message") or {}).get("content"))
            if candidate.strip():
                last_assistant = i
                text = candidate
    return text if last_assistant > last_user else None


def wait_for_text(transcript_path):
    deadline = time.time() + POLL_TIMEOUT
    while True:
        try:
            text = settled_text(tail_entries(transcript_path))
        except Exception:
            text = None
        if text is not None:
            return text
        if time.time() >= deadline:
            return None
        time.sleep(POLL_INTERVAL)


def count_questions(text):
    count = 0
    in_fence = False
    for line in text.splitlines():
        if FENCE.match(line):
            in_fence = not in_fence
            continue
        if in_fence or SKIP_LINE.match(line):
            continue
        if QUESTION_END.search(line):
            count += 1
    return count


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0

    # ブロック後の再応答でまた引っかかると停止ループになるため 1 回で打ち切る
    if payload.get("stop_hook_active"):
        return 0

    transcript_path = payload.get("transcript_path")
    if not transcript_path:
        return 0

    text = wait_for_text(transcript_path)
    if text is None:
        return 0

    n = count_questions(text)
    if n >= 2:
        print(MESSAGE.format(n=n), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)
