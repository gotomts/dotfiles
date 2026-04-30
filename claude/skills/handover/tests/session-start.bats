#!/usr/bin/env bats

load helpers

setup() {
  setup_handover_env
  export CLAUDE_SESSION_ID="sess-start-test"
  WORK_DIR="$(mktemp -d)"
  cd "${WORK_DIR}"
  git init -q -b main
  git -c user.email=a@a -c user.name=a commit --allow-empty -q -m init
  # CWD ベースで HANDOVER_DIR を計算
  eval "$("${SCRIPTS_DIR}/resolve-path.sh")"
}

teardown() {
  cd /
  rm -rf "${WORK_DIR}"
  teardown_handover_env
}

@test "notifies via additionalContext and creates marker when active memo exists" {
  d="${HANDOVER_DIR}/20260430-100000"
  write_state "${d}" "old-session" "READY" "$(iso_days_ago 1)" "false"

  run "${HOOKS_DIR}/session-start.sh"
  [ "${status}" -eq 0 ]
  ctx="$(printf '%s' "${output}" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "${ctx}" == *"HANDOVER NOTICE"* ]]
  [[ "${ctx}" == *"20260430-100000"* ]]
  [ -f "${TMPDIR}/claude-handover-checked-${CLAUDE_SESSION_ID}" ]
}

@test "outputs nothing and creates no marker when no active memo" {
  run "${HOOKS_DIR}/session-start.sh"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ ! -f "${TMPDIR}/claude-handover-checked-${CLAUDE_SESSION_ID}" ]
}

@test "does not notify when consumed=true" {
  d="${HANDOVER_DIR}/20260430-100000"
  write_state "${d}" "old-session" "READY" "$(iso_days_ago 1)" "true"
  run "${HOOKS_DIR}/session-start.sh"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "does not notify when status is ALL_COMPLETE" {
  d="${HANDOVER_DIR}/20260430-100000"
  write_state "${d}" "old-session" "ALL_COMPLETE" "$(iso_days_ago 1)" "false"
  run "${HOOKS_DIR}/session-start.sh"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "does not notify when older than 7 day TTL" {
  d="${HANDOVER_DIR}/20260101-000000"
  write_state "${d}" "old-session" "READY" "$(iso_days_ago 10)" "false"
  run "${HOOKS_DIR}/session-start.sh"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "exits 0 doing nothing when CLAUDE_SESSION_ID is unset" {
  unset CLAUDE_SESSION_ID
  run "${HOOKS_DIR}/session-start.sh"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "output JSON has hookEventName SessionStart" {
  d="${HANDOVER_DIR}/20260430-100000"
  write_state "${d}" "old-session" "READY" "$(iso_days_ago 1)" "false"
  run "${HOOKS_DIR}/session-start.sh"
  name="$(printf '%s' "${output}" | jq -r '.hookSpecificOutput.hookEventName')"
  [ "${name}" = "SessionStart" ]
}
