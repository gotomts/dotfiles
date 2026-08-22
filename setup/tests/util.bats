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

@test "util::ensure_homebrew_path prepends both Homebrew prefixes ahead of the existing PATH" {
    # -f (NO_RCS): skip /etc/zshenv and ~/.zshenv so this test's own PATH
    # assignment isn't itself clobbered before util::ensure_homebrew_path
    # runs — the exact real-machine failure mode this function fixes
    # (see util::ensure_homebrew_path's doc comment).
    run zsh -f -c "source '${SETUP_DIR}/lib/util.zsh'; PATH=/usr/bin:/bin; util::ensure_homebrew_path; echo \$PATH"
    [ "${status}" -eq 0 ]
    [[ "${output}" == "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin" ]]
}

@test "util::ensure_homebrew_path honors HOMEBREW_PATH_PREFIX_OVERRIDE (test hook)" {
    run zsh -f -c "source '${SETUP_DIR}/lib/util.zsh'; HOMEBREW_PATH_PREFIX_OVERRIDE=/fake/brew; PATH=/usr/bin; util::ensure_homebrew_path; echo \$PATH"
    [ "${status}" -eq 0 ]
    [[ "${output}" == "/fake/brew:/usr/bin" ]]
}
