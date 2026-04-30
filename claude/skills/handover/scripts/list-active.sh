#!/bin/zsh
# 未消費・READY・TTL(7日)内の handover メモを JSON 配列で返す。
# Usage:
#   list-active.sh                              # CWD から自動解決
#   list-active.sh <project_hash> <branch>      # 明示指定
#   list-active.sh <project_hash> <branch> <session_id>  # session_id でフィルタ
set -eu

project_hash="${1:-}"
branch="${2:-}"
session_filter="${3:-}"

if [ -z "${project_hash}" ] || [ -z "${branch}" ]; then
  eval "$("${0:A:h}/resolve-path.sh")"
  project_hash="${PROJECT_HASH}"
  branch="${BRANCH}"
fi

scope_dir="${HOME}/.claude/handover/${project_hash}/${branch}"
if [ ! -d "${scope_dir}" ]; then
  printf '[]\n'
  exit 0
fi

threshold_seconds=$((7 * 24 * 60 * 60))
now_epoch="$(date +%s)"

results='[]'
setopt NULL_GLOB
for state_file in "${scope_dir}"/*/state.json; do
  [ ! -f "${state_file}" ] && continue
  if ! jq empty "${state_file}" >/dev/null 2>&1; then
    printf 'warn: skip invalid JSON %s\n' "${state_file}" >&2
    continue
  fi

  consumed="$(jq -r '.consumed // false' "${state_file}")"
  entry_status="$(jq -r '.status // ""' "${state_file}")"
  created="$(jq -r '.created_at // ""' "${state_file}")"
  session_id="$(jq -r '.session_id // ""' "${state_file}")"
  summary="$(jq -r '.session_summary // ""' "${state_file}")"

  [ "${consumed}" = "true" ] && continue
  [ "${entry_status}" != "READY" ] && continue
  [ -z "${created}" ] && continue

  # macOS の date -j -f は +0900 形式を要求。date -Iseconds は +09:00 を出力するので正規化。
  created_normalized="$(printf '%s' "${created}" | sed 's/\([+-][0-9][0-9]\):\([0-9][0-9]\)$/\1\2/')"
  if created_epoch="$(date -j -f '%Y-%m-%dT%H:%M:%S%z' "${created_normalized}" +%s 2>/dev/null)"; then
    :
  elif created_epoch="$(date -d "${created}" +%s 2>/dev/null)"; then
    :
  else
    continue
  fi

  age=$((now_epoch - created_epoch))
  [ "${age}" -gt "${threshold_seconds}" ] && continue

  if [ -n "${session_filter}" ] && [ "${session_id}" != "${session_filter}" ]; then
    continue
  fi

  fingerprint="$(basename "$(dirname "${state_file}")")"
  abs_path="$(dirname "${state_file}")"

  results="$(printf '%s' "${results}" | jq \
    --arg fp "${fingerprint}" \
    --arg sm "${summary}" \
    --arg ca "${created}" \
    --arg ap "${abs_path}" \
    --arg sid "${session_id}" \
    '. + [{fingerprint: $fp, summary: $sm, created_at: $ca, abs_path: $ap, session_id: $sid}]')"
done

printf '%s\n' "${results}"
