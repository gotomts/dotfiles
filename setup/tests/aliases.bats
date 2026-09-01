#!/usr/bin/env bats
# setup/tests/aliases.bats

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"

@test "zsh -n syntax check passes for aliases" {
    run zsh -n "${REPO_ROOT}/aliases"
    [ "${status}" -eq 0 ]
}

@test "aliase/ directory no longer exists" {
    [ ! -d "${REPO_ROOT}/aliase" ]
}

@test "scripts/ contains all four helper scripts" {
    [ -f "${REPO_ROOT}/scripts/build-agent-rules.zsh" ]
    [ -f "${REPO_ROOT}/scripts/claude-board.zsh" ]
    [ -f "${REPO_ROOT}/scripts/claude-model.zsh" ]
    [ -f "${REPO_ROOT}/scripts/get-gke-credentials.sh" ]
}

@test "aliases references .scripts (not .aliase) paths" {
    run grep -c '\.scripts/' "${REPO_ROOT}/aliases"
    [ "${status}" -eq 0 ]
    run grep -c '\.aliase/' "${REPO_ROOT}/aliases"
    [ "${status}" -eq 1 ]
}
