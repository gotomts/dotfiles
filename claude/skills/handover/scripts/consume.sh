#!/bin/zsh
# 指定された state.json に consumed=true, updated_at=現在時刻 を反映する。
# 用途: 自動読込でメモを「消費した」状態にする、または /handover clear で一括破棄する。
set -eu

if [ "$#" -ne 1 ]; then
  printf 'Usage: consume.sh <state.json path>\n' >&2
  exit 1
fi

state_file="$1"

if [ ! -f "${state_file}" ]; then
  printf 'Error: %s not found\n' "${state_file}" >&2
  exit 1
fi

if ! jq empty "${state_file}" >/dev/null 2>&1; then
  printf 'Error: %s is not valid JSON\n' "${state_file}" >&2
  exit 1
fi

now="$(date -Iseconds)"
tmp_file="$(mktemp)"
trap 'rm -f "${tmp_file}"' EXIT

jq --arg now "${now}" '.consumed = true | .updated_at = $now' "${state_file}" > "${tmp_file}"
mv "${tmp_file}" "${state_file}"
