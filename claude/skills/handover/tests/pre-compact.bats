#!/usr/bin/env bats

load helpers

setup() {
  setup_handover_env
  export CLAUDE_SESSION_ID="test-session-123"
}

teardown() {
  teardown_handover_env
}

@test "exit 0 with empty stdout when same session_id state.json exists" {
  d="${HOME}/.claude/handover/proj/main/20260430-100000"
  write_state "${d}" "${CLAUDE_SESSION_ID}" "READY" "$(iso_days_ago 0)"

  run "${HOOKS_DIR}/pre-compact.sh"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "outputs block JSON when no session_id matches" {
  d="${HOME}/.claude/handover/proj/main/20260430-100000"
  write_state "${d}" "other-session" "READY" "$(iso_days_ago 0)"

  run "${HOOKS_DIR}/pre-compact.sh"
  [ "${status}" -eq 0 ]
  decision="$(printf '%s' "${output}" | jq -r '.decision')"
  [ "${decision}" = "block" ]
  reason="$(printf '%s' "${output}" | jq -r '.reason')"
  [[ "${reason}" == *"/handover"* ]]
}

@test "outputs block JSON when handover root is missing" {
  rm -rf "${HOME}/.claude/handover"

  run "${HOOKS_DIR}/pre-compact.sh"
  [ "${status}" -eq 0 ]
  decision="$(printf '%s' "${output}" | jq -r '.decision')"
  [ "${decision}" = "block" ]
}

@test "exit 0 doing nothing when CLAUDE_SESSION_ID is unset" {
  unset CLAUDE_SESSION_ID

  run "${HOOKS_DIR}/pre-compact.sh"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "still checks valid files when invalid JSON is mixed in" {
  bad_dir="${HOME}/.claude/handover/proj/main/20260101-000000"
  good_dir="${HOME}/.claude/handover/proj/main/20260430-100000"
  mkdir -p "${bad_dir}"
  echo "not json" > "${bad_dir}/state.json"
  write_state "${good_dir}" "${CLAUDE_SESSION_ID}" "READY" "$(iso_days_ago 0)"

  run "${HOOKS_DIR}/pre-compact.sh"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}
