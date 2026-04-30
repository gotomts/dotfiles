#!/usr/bin/env bats

load helpers

setup() {
  setup_handover_env
  STATE_DIR="${HOME}/.claude/handover/test/main/20260430-100000"
  write_state "${STATE_DIR}" "sess-1" "READY" "2026-04-30T10:00:00+09:00" "false"
  STATE_FILE="${STATE_DIR}/state.json"
}

teardown() {
  teardown_handover_env
}

@test "updates consumed=false to true" {
  run "${SCRIPTS_DIR}/consume.sh" "${STATE_FILE}"
  [ "${status}" -eq 0 ]
  consumed="$(jq -r '.consumed' "${STATE_FILE}")"
  [ "${consumed}" = "true" ]
}

@test "updated_at changes" {
  before="$(jq -r '.updated_at' "${STATE_FILE}")"
  sleep 1
  run "${SCRIPTS_DIR}/consume.sh" "${STATE_FILE}"
  [ "${status}" -eq 0 ]
  after="$(jq -r '.updated_at' "${STATE_FILE}")"
  [ "${before}" != "${after}" ]
}

@test "idempotent when already consumed=true" {
  jq '.consumed = true' "${STATE_FILE}" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "${STATE_FILE}"
  run "${SCRIPTS_DIR}/consume.sh" "${STATE_FILE}"
  [ "${status}" -eq 0 ]
  consumed="$(jq -r '.consumed' "${STATE_FILE}")"
  [ "${consumed}" = "true" ]
}

@test "exits 1 for nonexistent file" {
  run "${SCRIPTS_DIR}/consume.sh" "${HOME}/nonexistent.json"
  [ "${status}" -ne 0 ]
}

@test "exits 1 for invalid JSON" {
  echo "not json" > "${STATE_FILE}"
  run "${SCRIPTS_DIR}/consume.sh" "${STATE_FILE}"
  [ "${status}" -ne 0 ]
}

@test "shows Usage and exits 1 with no args" {
  run "${SCRIPTS_DIR}/consume.sh"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Usage"* ]]
}
