#!/bin/zsh
# Claude Code の UserPromptSubmit フック。
# session-start.sh と同等のロジックだが、マーカーで重複抑止し、
# hookEventName を UserPromptSubmit にする。
set -eu

session_id="${CLAUDE_SESSION_ID:-}"
[ -z "${session_id}" ] && exit 0

marker_dir="${TMPDIR:-/tmp}"
marker="${marker_dir}/claude-handover-checked-${session_id}"
[ -f "${marker}" ] && exit 0

scripts_dir="${HOME}/.claude/skills/handover/scripts"
[ ! -d "${scripts_dir}" ] && exit 0

active_json="$("${scripts_dir}/list-active.sh" 2>/dev/null || printf '[]')"
count="$(printf '%s' "${active_json}" | jq 'length' 2>/dev/null || printf '0')"
[ "${count}" = "0" ] && exit 0

ctx="$(printf '%s' "${active_json}" | jq -r '
  "[HANDOVER NOTICE]\n未消費の handover が見つかりました:\n" +
  ([.[] | "- \(.fingerprint): \(.summary) (\(.created_at))\n  パス: \(.abs_path)/handover.md"] | join("\n")) +
  "\n\nユーザーに「引き継ぎますか？それとも新規会話にしますか？」を確認してください。\n - 引き継ぐ → 上記 handover.md の内容を Read で読み込み、~/.claude/skills/handover/scripts/consume.sh <abs_path>/state.json を Bash で実行\n - 新規 → consume.sh のみ実行（読込はしない）"
')"

jq -n --arg ctx "${ctx}" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'

mkdir -p "${marker_dir}"
touch "${marker}"
