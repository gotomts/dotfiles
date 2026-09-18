#!/usr/bin/env bats
# setup/tests/hermes-sync.bats

SETUP_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

# The one external command hermes-sync.zsh calls. Records its argv and models
# the only contract hermes-sync.zsh depends on: `rtk init --agent hermes`
# materializes ~/.hermes/plugins/rtk-rewrite/.
_install_rtk_stub() {
    cat > "${STUB_BIN}/rtk" <<'EOF'
#!/bin/bash
echo "$*" >> "${RTK_LOG}"
if [[ "${RTK_EXIT:-0}" -ne 0 ]]; then
    exit "${RTK_EXIT}"
fi
if [[ "$1" == "init" ]]; then
    mkdir -p "${HOME}/.hermes/plugins/rtk-rewrite"
fi
exit 0
EOF
    chmod +x "${STUB_BIN}/rtk"
}

# Hermes's own running config. Its presence is what marks the machine as one
# where Hermes actually runs -- the ~/.hermes directory alone does not, because
# Tier 1 (setup/link.zsh) creates it just to place SOUL.md.
_install_hermes() {
    mkdir -p "${HOME}/.hermes"
    : > "${HOME}/.hermes/config.yaml"
}

setup() {
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}"

    STUB_BIN="${BATS_TEST_TMPDIR}/stub-bin"
    mkdir -p "${STUB_BIN}"
    export RTK_LOG="${BATS_TEST_TMPDIR}/rtk.log"
    : > "${RTK_LOG}"
    export PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"
    # hermes-sync.zsh calls util::ensure_homebrew_path, which prepends the real
    # /opt/homebrew paths unless overridden. Point it at the stub dir so this
    # machine's real rtk (if installed) can never win.
    export HOMEBREW_PATH_PREFIX_OVERRIDE="${STUB_BIN}"
}

@test "zsh -n syntax check passes" {
    run zsh -n "${SETUP_DIR}/hermes-sync.zsh"
    [ "${status}" -eq 0 ]
}

@test "installs the RTK plugin when both Hermes and rtk are present" {
    _install_hermes
    _install_rtk_stub

    run zsh "${SETUP_DIR}/hermes-sync.zsh"
    [ "${status}" -eq 0 ]
    [ -d "${HOME}/.hermes/plugins/rtk-rewrite" ]

    run cat "${RTK_LOG}"
    [[ "${output}" == *"init --agent hermes"* ]]
    # Non-interactive: the confirmation prompt for a divergent managed file
    # must be pre-approved, otherwise migrate.zsh would block on stdin.
    [[ "${output}" == *"--auto-patch"* ]]
}

@test "does not opt in to telemetry" {
    _install_hermes
    # Record the env this invocation sees instead of its argv: the telemetry
    # switch is an environment variable, not a flag.
    cat > "${STUB_BIN}/rtk" <<'EOF'
#!/bin/bash
echo "RTK_TELEMETRY_DISABLED=${RTK_TELEMETRY_DISABLED:-unset}" >> "${RTK_LOG}"
exit 0
EOF
    chmod +x "${STUB_BIN}/rtk"

    run zsh "${SETUP_DIR}/hermes-sync.zsh"
    [ "${status}" -eq 0 ]
    run cat "${RTK_LOG}"
    [[ "${output}" == "RTK_TELEMETRY_DISABLED=1" ]]
}

@test "does nothing when Hermes is not installed on this machine" {
    _install_rtk_stub
    # The directory exists (Tier 1 puts SOUL.md there) but Hermes never ran,
    # so there is no config.yaml. This is the shape the directory check got
    # wrong, so assert it explicitly rather than testing an empty $HOME.
    mkdir -p "${HOME}/.hermes"

    run zsh "${SETUP_DIR}/hermes-sync.zsh"
    [ "${status}" -eq 0 ]
    [ ! -e "${HOME}/.hermes/plugins/rtk-rewrite" ]
    run cat "${RTK_LOG}"
    [ -z "${output}" ]
}

@test "fails open when rtk is missing (does not stop the rest of the migration)" {
    _install_hermes

    run zsh "${SETUP_DIR}/hermes-sync.zsh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"rtk 未インストール"* ]]
    [ ! -e "${HOME}/.hermes/plugins/rtk-rewrite" ]
}

@test "fails open when rtk init errors" {
    _install_hermes
    _install_rtk_stub

    RTK_EXIT=1 run zsh "${SETUP_DIR}/hermes-sync.zsh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"失敗"* ]]
}

@test "re-running is idempotent (rtk init is invoked again, plugin stays)" {
    _install_hermes
    _install_rtk_stub

    run zsh "${SETUP_DIR}/hermes-sync.zsh"
    [ "${status}" -eq 0 ]
    run zsh "${SETUP_DIR}/hermes-sync.zsh"
    [ "${status}" -eq 0 ]
    [ -d "${HOME}/.hermes/plugins/rtk-rewrite" ]

    # Deliberate: the adapter is a generated artifact tied to the installed rtk
    # version, so it is refreshed on every run rather than skipped once present.
    run grep -c "init --agent hermes" "${RTK_LOG}"
    [ "${output}" -eq 2 ]
}
