#!/usr/bin/env bats

load helpers

setup() {
  setup_handover_env
  ROOT="${HOME}/.claude/handover/test-proj/main"
}

teardown() {
  teardown_handover_env
}

@test "removes ALL_COMPLETE entries older than 7 days" {
  old_dir="${ROOT}/20260101-000000"
  write_state "${old_dir}" "s1" "ALL_COMPLETE" "$(iso_days_ago 10)"
  run "${SCRIPTS_DIR}/cleanup.sh"
  [ "${status}" -eq 0 ]
  [ ! -d "${old_dir}" ]
}

@test "keeps READY entries even when older than 7 days" {
  old_dir="${ROOT}/20260101-000001"
  write_state "${old_dir}" "s2" "READY" "$(iso_days_ago 10)"
  run "${SCRIPTS_DIR}/cleanup.sh"
  [ "${status}" -eq 0 ]
  [ -d "${old_dir}" ]
}

@test "keeps ALL_COMPLETE entries within 7 days" {
  recent_dir="${ROOT}/20260425-000000"
  write_state "${recent_dir}" "s3" "ALL_COMPLETE" "$(iso_days_ago 3)"
  run "${SCRIPTS_DIR}/cleanup.sh"
  [ "${status}" -eq 0 ]
  [ -d "${recent_dir}" ]
}

@test "exits 0 when handover root does not exist" {
  rm -rf "${HOME}/.claude/handover"
  run "${SCRIPTS_DIR}/cleanup.sh"
  [ "${status}" -eq 0 ]
}

@test "scans across multiple projects and branches" {
  d1="${HOME}/.claude/handover/proj-a/main/20260101-000000"
  d2="${HOME}/.claude/handover/proj-b/feature-x/20260101-000000"
  write_state "${d1}" "x1" "ALL_COMPLETE" "$(iso_days_ago 10)"
  write_state "${d2}" "x2" "ALL_COMPLETE" "$(iso_days_ago 10)"
  run "${SCRIPTS_DIR}/cleanup.sh"
  [ ! -d "${d1}" ]
  [ ! -d "${d2}" ]
}
