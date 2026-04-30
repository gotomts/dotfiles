#!/usr/bin/env bats

load helpers

setup() {
  setup_handover_env
  export CLAUDE_SESSION_ID="sess-ups-test"
  WORK_DIR="$(mktemp -d)"
  cd "${WORK_DIR}"
  git init -q -b main
  git -c user.email=a@a -c user.name=a commit --allow-empty -q -m init
  eval "$("${SCRIPTS_DIR}/resolve-path.sh")"
}

teardown() {
  cd /
  rm -rf "${WORK_DIR}"
  teardown_handover_env
}

@test "notifies and creates marker when no marker and active memo exists" {
  d="${HANDOVER_DIR}/20260430-100000"
  write_state "${d}" "old" "READY" "$(iso_days_ago 1)" "false"
  run "${HOOKS_DIR}/user-prompt-submit.sh"
  [ "${status}" -eq 0 ]
  name="$(printf '%s' "${output}" | jq -r '.hookSpecificOutput.hookEventName')"
  [ "${name}" = "UserPromptSubmit" ]
  [ -f "${TMPDIR}/claude-handover-checked-${CLAUDE_SESSION_ID}" ]
}

@test "does nothing when marker already exists (dedup suppression)" {
  touch "${TMPDIR}/claude-handover-checked-${CLAUDE_SESSION_ID}"
  d="${HANDOVER_DIR}/20260430-100000"
  write_state "${d}" "old" "READY" "$(iso_days_ago 1)" "false"
  run "${HOOKS_DIR}/user-prompt-submit.sh"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "does nothing and creates no marker when no active memo" {
  run "${HOOKS_DIR}/user-prompt-submit.sh"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ ! -f "${TMPDIR}/claude-handover-checked-${CLAUDE_SESSION_ID}" ]
}

@test "exits 0 doing nothing when CLAUDE_SESSION_ID is unset" {
  unset CLAUDE_SESSION_ID
  run "${HOOKS_DIR}/user-prompt-submit.sh"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}
