#!/usr/bin/env bats
# setup/tests/zshrc.bats

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"

@test "zsh -n syntax check passes for zshrc" {
    run zsh -n "${REPO_ROOT}/zshrc"
    [ "${status}" -eq 0 ]
}

@test "zshrc sources ~/.aliases" {
    run grep -c '\.aliases' "${REPO_ROOT}/zshrc"
    [ "${status}" -eq 0 ]
}

@test "zshrc does not reference direnv" {
    run grep -c 'direnv' "${REPO_ROOT}/zshrc"
    [ "${status}" -eq 1 ]
}

@test "zshrc guards mise activation" {
    run grep -c 'type mise' "${REPO_ROOT}/zshrc"
    [ "${status}" -eq 0 ]
}
