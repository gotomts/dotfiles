#!/usr/bin/env bats
# setup/tests/util.bats

SETUP_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

@test "zsh -n syntax check passes" {
    run zsh -n "${SETUP_DIR}/lib/util.zsh"
    [ "${status}" -eq 0 ]
}

@test "util::info prints the message" {
    run zsh -c "source '${SETUP_DIR}/lib/util.zsh'; util::info 'hello'"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"hello"* ]]
}

@test "util::confirm returns 0 (yes) when FORCE=1" {
    run zsh -c "source '${SETUP_DIR}/lib/util.zsh'; FORCE=1 util::confirm 'proceed?'"
    [ "${status}" -eq 0 ]
}

@test "util::confirm returns 4 (no) on empty stdin without FORCE" {
    run zsh -c "source '${SETUP_DIR}/lib/util.zsh'; echo '' | util::confirm 'proceed?'"
    [ "${status}" -eq 4 ]
}
