#!/usr/bin/env bats
# setup/tests/defaults.bats

SETUP_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
REPO_ROOT="$(cd "${SETUP_DIR}/.." && pwd)"

_install_defaults_stub() {
    local bin_dir="${1}"
    mkdir -p "${bin_dir}"
    cat > "${bin_dir}/defaults" <<EOF
#!/bin/zsh
echo "\$*" >> "${DEFAULTS_LOG}"
# real 'defaults export <domain> <path>' creates a plist file at <path>;
# reproduce that so callers relying on file-existence guards behave the same.
if [[ "\$1" == "export" ]]; then
    echo "stub plist" > "\$3"
fi
exit 0
EOF
    chmod +x "${bin_dir}/defaults"
}

setup() {
    STUB_BIN="${BATS_TEST_TMPDIR}/stub-bin"
    DEFAULTS_LOG="${BATS_TEST_TMPDIR}/defaults.log"
    : > "${DEFAULTS_LOG}"
    export DEFAULTS_LOG
    _install_defaults_stub "${STUB_BIN}"
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}"
    unset DOTFILES_ROLE_FILE
}

@test "zsh -n syntax check passes" {
    run zsh -n "${SETUP_DIR}/defaults.zsh"
    [ "${status}" -eq 0 ]
}

@test "defaults.zsh writes representative keys from each managed domain" {
    DOTFILES_ROLE_FILE="${BATS_TEST_TMPDIR}/no-such-role-file" \
        PATH="${STUB_BIN}:${PATH}" run zsh "${SETUP_DIR}/defaults.zsh"
    [ "${status}" -eq 0 ]

    run cat "${DEFAULTS_LOG}"
    [[ "${output}" == *"write com.apple.dock autohide -bool true"* ]]
    [[ "${output}" == *"write com.apple.finder FXPreferredViewStyle -string Nlsv"* ]]
    [[ "${output}" == *"write com.apple.menuextra.clock ShowDate"* ]] || \
        [[ "${output}" == *"write com.apple.menuextra.clock"* ]]
    [[ "${output}" == *"write NSGlobalDomain AppleInterfaceStyle -string Dark"* ]]
    [[ "${output}" == *"write com.apple.AppleMultitouchTrackpad Clicking -bool true"* ]]
    [[ "${output}" == *"write NSGlobalDomain AppleLocale -string ja_JP"* ]]
    [[ "${output}" == *"write com.apple.finder FXArrangeGroupViewBy -string Name"* ]]
    [[ "${output}" == *"write com.apple.controlcenter NSStatusItem VisibleCC WiFi -bool true"* ]]
    [[ "${output}" == *"write com.apple.AppleMultitouchTrackpad TrackpadHorizScroll -int 1"* ]]
}

@test "defaults.zsh defaults to role=default when role file is absent" {
    DOTFILES_ROLE_FILE="${BATS_TEST_TMPDIR}/no-such-role-file" \
        PATH="${STUB_BIN}:${PATH}" run zsh "${SETUP_DIR}/defaults.zsh"
    [ "${status}" -eq 0 ]

    run grep -c 'persistent-apps -array-add' "${DEFAULTS_LOG}"
    [ "${status}" -eq 0 ]
    [ "${output}" -eq 15 ]

    run grep -c '/Applications/Linear.app' "${DEFAULTS_LOG}"
    [ "${status}" -eq 0 ]
}

@test "defaults.zsh uses the sub-1 dock app list when role file says sub-1" {
    echo "sub-1" > "${BATS_TEST_TMPDIR}/role-sub1"
    DOTFILES_ROLE_FILE="${BATS_TEST_TMPDIR}/role-sub1" \
        PATH="${STUB_BIN}:${PATH}" run zsh "${SETUP_DIR}/defaults.zsh"
    [ "${status}" -eq 0 ]

    run grep -c 'persistent-apps -array-add' "${DEFAULTS_LOG}"
    [ "${status}" -eq 0 ]
    [ "${output}" -eq 16 ]

    run grep -c '/Applications/Linear.app' "${DEFAULTS_LOG}"
    [ "${status}" -eq 1 ]

    run grep -c '/Applications/Microsoft Teams.app' "${DEFAULTS_LOG}"
    [ "${status}" -eq 0 ]
}

@test "defaults.zsh fails clearly on an unknown role value" {
    echo "bogus-role" > "${BATS_TEST_TMPDIR}/role-bogus"
    DOTFILES_ROLE_FILE="${BATS_TEST_TMPDIR}/role-bogus" \
        PATH="${STUB_BIN}:${PATH}" run zsh "${SETUP_DIR}/defaults.zsh"
    [ "${status}" -eq 1 ]
}

@test "defaults.zsh backs up each domain once before first write, then skips on rerun" {
    DOTFILES_ROLE_FILE="${BATS_TEST_TMPDIR}/no-such-role-file" \
        PATH="${STUB_BIN}:${PATH}" run zsh "${SETUP_DIR}/defaults.zsh"
    [ "${status}" -eq 0 ]

    [ -f "${HOME}/.dotfiles-defaults-backup/com.apple.dock.plist.marker" ] || \
        run grep -c 'export com.apple.dock ' "${DEFAULTS_LOG}"

    run grep -c 'export com.apple.dock ' "${DEFAULTS_LOG}"
    [ "${status}" -eq 0 ]
    first_run_export_count="${output}"
    [ "${first_run_export_count}" -ge 1 ]

    : > "${DEFAULTS_LOG}"
    DOTFILES_ROLE_FILE="${BATS_TEST_TMPDIR}/no-such-role-file" \
        PATH="${STUB_BIN}:${PATH}" run zsh "${SETUP_DIR}/defaults.zsh"
    [ "${status}" -eq 0 ]

    run grep -c 'export com.apple.dock ' "${DEFAULTS_LOG}"
    [ "${status}" -eq 1 ]
}

@test "defaults.zsh imports HIToolbox/inputsources from the single-source nix plists" {
    DOTFILES_ROLE_FILE="${BATS_TEST_TMPDIR}/no-such-role-file" \
        PATH="${STUB_BIN}:${PATH}" run zsh "${SETUP_DIR}/defaults.zsh"
    [ "${status}" -eq 0 ]

    run cat "${DEFAULTS_LOG}"
    [[ "${output}" == *"import com.apple.HIToolbox ${REPO_ROOT}/nix/modules/darwin/hitoolbox.plist"* ]]
    [[ "${output}" == *"import com.apple.inputsources ${REPO_ROOT}/nix/modules/darwin/inputsources.plist"* ]]
}
