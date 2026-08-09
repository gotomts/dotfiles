#!/usr/bin/env python3
"""Stop hook: 1 応答に質問が 2 件以上あればブロックする (AGENTS.md 一問一答ルール)。

exit code は 0 (通過) か 2 (ブロック) のみ。それ以外の非ゼロは Claude Code が
non-blocking error として扱い hook が素通りするため、例外は全て 0 に倒す。
"""

import json
import re
import sys

FENCE = re.compile(r"^\s*```")
SKIP_LINE = re.compile(r"^\s*[>|]")
QUESTION_END = re.compile(r"[?？]\s*$")

MESSAGE = (
    "質問が {n} 件あります。AGENTS.md の一問一答ルールに反します。\n"
    "1 つに絞るか、AskUserQuestion ツールを使ってください。\n"
    "残りの質問は次のターンに回してください。"
)


def last_assistant_text(transcript_path):
    with open(transcript_path, encoding="utf-8") as f:
        lines = f.readlines()

    for line in reversed(lines):
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(entry, dict):
            continue
        # サブエージェントの応答は親の 1 ターンではないので対象外
        if entry.get("type") != "assistant" or entry.get("isSidechain"):
            continue

        content = (entry.get("message") or {}).get("content")
        if isinstance(content, str):
            return content
        if not isinstance(content, list):
            continue
        texts = [
            block.get("text", "")
            for block in content
            if isinstance(block, dict) and block.get("type") == "text"
        ]
        text = "\n".join(t for t in texts if t)
        if text.strip():
            return text
    return ""


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

    try:
        text = last_assistant_text(transcript_path)
    except Exception:
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
