#!/usr/bin/env bats

load helpers

setup() {
  setup_handover_env
  WORK_DIR="$(mktemp -d)"
  cd "${WORK_DIR}"
}

teardown() {
  cd /
  rm -rf "${WORK_DIR}"
  teardown_handover_env
}

@test "outputs PROJECT_HASH and BRANCH in a git repo" {
  git init -q -b main "${WORK_DIR}"
  git -C "${WORK_DIR}" -c user.email=a@a -c user.name=a commit --allow-empty -q -m init

  run "${SCRIPTS_DIR}/resolve-path.sh"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"PROJECT_PATH=${WORK_DIR}"* ]]
  [[ "${output}" == *"BRANCH=main"* ]]
  [[ "${output}" == *"PROJECT_HASH=$(basename "${WORK_DIR}")-"* ]]
  [[ "${output}" == *"FINGERPRINT="* ]]
  [[ "${output}" == *"HANDOVER_DIR="* ]]
}

@test "sanitizes / in branch name to -" {
  git init -q "${WORK_DIR}"
  git -C "${WORK_DIR}" -c user.email=a@a -c user.name=a commit --allow-empty -q -m init
  git -C "${WORK_DIR}" checkout -q -b "feat/foobarbaz"

  run "${SCRIPTS_DIR}/resolve-path.sh"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"BRANCH=feat-foobarbaz"* ]]
}

@test "outputs detached-{sha7} on detached HEAD" {
  git init -q -b main "${WORK_DIR}"
  git -C "${WORK_DIR}" -c user.email=a@a -c user.name=a commit --allow-empty -q -m init
  sha="$(git -C "${WORK_DIR}" rev-parse --short=7 HEAD)"
  git -C "${WORK_DIR}" checkout -q --detach

  run "${SCRIPTS_DIR}/resolve-path.sh"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"BRANCH=detached-${sha}"* ]]
}

@test "outputs BRANCH=nogit in non-git directory" {
  run "${SCRIPTS_DIR}/resolve-path.sh"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"BRANCH=nogit"* ]]
}

@test "FINGERPRINT is in YYYYMMDD-HHMMSS format" {
  run "${SCRIPTS_DIR}/resolve-path.sh"
  [[ "${output}" =~ FINGERPRINT=[0-9]{8}-[0-9]{6} ]]
}
