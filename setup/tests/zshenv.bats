#!/usr/bin/env bats
# setup/tests/zshenv.bats

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"

@test "zsh -n syntax check passes for zshenv" {
    run zsh -n "${REPO_ROOT}/zshenv"
    [ "${status}" -eq 0 ]
}

@test "zshenv exports COREPACK_HOME" {
    run grep -c 'COREPACK_HOME' "${REPO_ROOT}/zshenv"
    [ "${status}" -eq 0 ]
}

@test "zshenv guards mise shims activation" {
    run grep -c 'mise activate --shims' "${REPO_ROOT}/zshenv"
    [ "${status}" -eq 0 ]
}
