#!/usr/bin/env bats

load helpers

setup() {
  setup_handover_env
  ROOT="${HOME}/.claude/handover/proj/main"
}

teardown() {
  teardown_handover_env
}

@test "returns unconsumed READY entries within TTL" {
  d="${ROOT}/20260430-100000"
  write_state "${d}" "s1" "READY" "$(iso_days_ago 1)" "false"
  run "${SCRIPTS_DIR}/list-active.sh" "proj" "main"
  [ "${status}" -eq 0 ]
  count="$(printf '%s' "${output}" | jq 'length')"
  [ "${count}" = "1" ]
  fp="$(printf '%s' "${output}" | jq -r '.[0].fingerprint')"
  [ "${fp}" = "20260430-100000" ]
}

@test "excludes consumed=true" {
  d="${ROOT}/20260430-100000"
  write_state "${d}" "s1" "READY" "$(iso_days_ago 1)" "true"
  run "${SCRIPTS_DIR}/list-active.sh" "proj" "main"
  [ "${status}" -eq 0 ]
  [ "${output}" = "[]" ]
}

@test "excludes ALL_COMPLETE" {
  d="${ROOT}/20260430-100000"
  write_state "${d}" "s1" "ALL_COMPLETE" "$(iso_days_ago 1)" "false"
  run "${SCRIPTS_DIR}/list-active.sh" "proj" "main"
  [ "${status}" -eq 0 ]
  [ "${output}" = "[]" ]
}

@test "excludes entries older than 7 days" {
  d="${ROOT}/20260101-000000"
  write_state "${d}" "s1" "READY" "$(iso_days_ago 10)" "false"
  run "${SCRIPTS_DIR}/list-active.sh" "proj" "main"
  [ "${status}" -eq 0 ]
  [ "${output}" = "[]" ]
}

@test "filters by session_id" {
  d1="${ROOT}/20260430-100000"
  d2="${ROOT}/20260430-110000"
  write_state "${d1}" "sess-a" "READY" "$(iso_days_ago 1)" "false"
  write_state "${d2}" "sess-b" "READY" "$(iso_days_ago 1)" "false"
  run "${SCRIPTS_DIR}/list-active.sh" "proj" "main" "sess-a"
  [ "${status}" -eq 0 ]
  count="$(printf '%s' "${output}" | jq 'length')"
  [ "${count}" = "1" ]
  sid="$(printf '%s' "${output}" | jq -r '.[0].session_id')"
  [ "${sid}" = "sess-a" ]
}

@test "returns empty array when scope dir does not exist" {
  run "${SCRIPTS_DIR}/list-active.sh" "nonexistent" "main"
  [ "${status}" -eq 0 ]
  [ "${output}" = "[]" ]
}

@test "auto-resolves from CWD when no args given" {
  cd "$(mktemp -d)"
  eval "$("${SCRIPTS_DIR}/resolve-path.sh")"
  write_state "${HANDOVER_DIR}/${FINGERPRINT}" "auto-sess" "READY" "$(iso_days_ago 1)" "false"
  run "${SCRIPTS_DIR}/list-active.sh"
  [ "${status}" -eq 0 ]
  count="$(printf '%s' "${output}" | jq 'length')"
  [ "${count}" -ge 1 ]
}
