#!/bin/zsh
# state.json から人間可読な handover.md を生成して stdout に出力する。
# state.json は唯一の真実、handover.md はそのビュー（直接編集禁止）。
set -eu

if [ "$#" -ne 1 ]; then
  printf 'Usage: render-md.sh <state.json path>\n' >&2
  exit 1
fi

state_file="$1"

if [ ! -f "${state_file}" ]; then
  printf 'Error: %s not found\n' "${state_file}" >&2
  exit 1
fi

jq -r '
  def task_line:
    "- [\(if .status == "completed" then "x" else " " end)] \(.id): \(.description) (\(.status))" +
    (if .next_action and .next_action != "" then "\n  - Next: \(.next_action)" else "" end);

  def decision_block:
    "- **\(.topic)**: \(.chosen)" +
    (if (.rejected // []) | length > 0 then "\n  - 却下: \(.rejected | join(", "))" else "" end) +
    "\n  - 理由: \(.rationale)";

  def header_time:
    .created_at | sub("T"; " ") | sub(":[0-9]+(\\.[0-9]+)?(\\+|Z|-).*$"; "");

  "# Handover: \(header_time)\n" +
  "\n**Project**: \(.project.path)\n" +
  "**Branch**: \(.project.branch)\n" +
  "**Status**: \(.status)\n" +
  "**Session**: \(.session_id)\n" +
  "\n## Session Summary\n\(.session_summary)\n" +
  "\n## Tasks\n" +
  (if (.tasks | length) > 0 then ([.tasks[] | task_line] | join("\n")) else "なし" end) +
  "\n\n## Decisions\n" +
  (if (.decisions | length) > 0 then ([.decisions[] | decision_block] | join("\n")) else "なし" end) +
  "\n\n## Blockers\n" +
  (if (.blockers | length) > 0 then ([.blockers[] | "- \(.)"] | join("\n")) else "なし" end)
' "${state_file}"
