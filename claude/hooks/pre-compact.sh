#!/bin/zsh
# Claude Code の PreCompact フック。
# 現セッション ID で書かれた handover が存在しない時、コンパクトをブロックして
# ユーザーに /handover 実行を促す。
set -eu

session_id="${CLAUDE_SESSION_ID:-}"
[ -z "${session_id}" ] && exit 0

handover_root="${HOME}/.claude/handover"

found="false"
if [ -d "${handover_root}" ]; then
  setopt NULL_GLOB
  for state_file in "${handover_root}"/*/*/*/state.json; do
    [ ! -f "${state_file}" ] && continue
    if ! jq empty "${state_file}" >/dev/null 2>&1; then
      continue
    fi
    sid="$(jq -r '.session_id // ""' "${state_file}")"
    if [ "${sid}" = "${session_id}" ]; then
      found="true"
      break
    fi
  done
fi

if [ "${found}" = "true" ]; then
  exit 0
fi

cat <<'EOF'
{
  "decision": "block",
  "reason": "セッション開始後に /handover を実行してから再度コンパクトしてください。"
}
EOF
exit 0
