#!/bin/zsh
# ~/.claude/handover/ 配下を走査し、status=ALL_COMPLETE かつ created_at が
# 7 日以上前のディレクトリを丸ごと削除する。
# /handover 実行のたびに呼ばれて、ストレージを綺麗に保つ。
set -eu

handover_root="${HOME}/.claude/handover"
[ ! -d "${handover_root}" ] && exit 0

threshold_seconds=$((7 * 24 * 60 * 60))
now_epoch="$(date +%s)"

# project_hash/branch/fingerprint/state.json の階層 = 4 段
find "${handover_root}" -mindepth 4 -maxdepth 4 -name state.json -type f 2>/dev/null | while IFS= read -r state_file; do
  if ! entry_status="$(jq -r '.status // ""' "${state_file}" 2>/dev/null)"; then
    continue
  fi
  [ "${entry_status}" != "ALL_COMPLETE" ] && continue

  created="$(jq -r '.created_at // ""' "${state_file}" 2>/dev/null)"
  [ -z "${created}" ] && continue

  # macOS の date は -j -f 形式、GNU date は -d。両対応。
  # ISO 8601 の timezone offset "+HH:MM" を "+HHMM" に正規化（macOS %z は colon なし形式を期待）
  created_normalized="$(printf '%s' "${created}" | sed 's/\([+-][0-9][0-9]\):\([0-9][0-9]\)$/\1\2/')"
  if created_epoch="$(date -j -f '%Y-%m-%dT%H:%M:%S%z' "${created_normalized}" +%s 2>/dev/null)"; then
    :
  elif created_epoch="$(date -d "${created}" +%s 2>/dev/null)"; then
    :
  else
    continue
  fi

  age=$((now_epoch - created_epoch))
  if [ "${age}" -gt "${threshold_seconds}" ]; then
    target_dir="$(dirname "${state_file}")"
    rm -rf "${target_dir}"
    printf 'cleanup: removed %s (age: %d days)\n' "${target_dir}" $((age / 86400)) >&2
  fi
done
