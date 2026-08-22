#!/usr/bin/env bats
# setup/tests/pam.bats

SETUP_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

setup() {
    TMP="${BATS_TEST_TMPDIR}"
}

@test "zsh -n syntax check passes" {
    run zsh -n "${SETUP_DIR}/pam.zsh"
    [ "${status}" -eq 0 ]
}

@test "pam.zsh creates sudo_local with Touch ID line when absent" {
    local target="${TMP}/sudo_local"
    SUDO_LOCAL_PATH="${target}" run zsh "${SETUP_DIR}/pam.zsh"
    [ "${status}" -eq 0 ]
    [ -f "${target}" ]
    run grep -c 'pam_tid.so' "${target}"
    [ "${status}" -eq 0 ]
}

@test "pam.zsh is idempotent on second run (no .before-setup created)" {
    local target="${TMP}/sudo_local2"
    SUDO_LOCAL_PATH="${target}" run zsh "${SETUP_DIR}/pam.zsh"
    [ "${status}" -eq 0 ]
    SUDO_LOCAL_PATH="${target}" run zsh "${SETUP_DIR}/pam.zsh"
    [ "${status}" -eq 0 ]
    [ ! -e "${target}.before-setup" ]
}

@test "pam.zsh backs up differing existing content before overwriting" {
    local target="${TMP}/sudo_local3"
    echo "# some other pam config" > "${target}"
    SUDO_LOCAL_PATH="${target}" run zsh "${SETUP_DIR}/pam.zsh"
    [ "${status}" -eq 0 ]
    [ -f "${target}.before-setup" ]
    [ "$(cat "${target}.before-setup")" = "# some other pam config" ]
    run grep -c 'pam_tid.so' "${target}"
    [ "${status}" -eq 0 ]
}

@test "pam.zsh refuses to overwrite when a .before-setup backup already exists" {
    local target="${TMP}/sudo_local4"
    echo "# original" > "${target}"
    echo "# pre-existing backup, do not clobber" > "${target}.before-setup"
    SUDO_LOCAL_PATH="${target}" run zsh "${SETUP_DIR}/pam.zsh"
    [ "${status}" -eq 1 ]
    [ "$(cat "${target}")" = "# original" ]
    [ "$(cat "${target}.before-setup")" = "# pre-existing backup, do not clobber" ]
}
