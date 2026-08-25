#!/usr/bin/env bats
# setup/tests/languages.bats

SETUP_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
REPO_ROOT="$(cd "${SETUP_DIR}/.." && pwd)"

# stub `mise` executable that records every invocation to MISE_LOG.
# `mise which node` returns a fixed path under a stub node bin dir that also
# contains a stub `corepack` executable (records to COREPACK_LOG).
_install_mise_stub() {
    local bin_dir="${1}"
    local node_bin_dir="${2}"
    mkdir -p "${bin_dir}" "${node_bin_dir}"

    cat > "${bin_dir}/mise" <<EOF
#!/bin/zsh
echo "\$*" >> "${MISE_LOG}"
if [[ "\$1" == "which" && "\$2" == "node" ]]; then
    echo "${node_bin_dir}/node"
fi
exit 0
EOF
    chmod +x "${bin_dir}/mise"

    cat > "${node_bin_dir}/corepack" <<EOF
#!/bin/zsh
echo "\$*" >> "${COREPACK_LOG}"
exit 0
EOF
    chmod +x "${node_bin_dir}/corepack"
}

setup() {
    STUB_BIN="${BATS_TEST_TMPDIR}/stub-bin"
    NODE_BIN_DIR="${BATS_TEST_TMPDIR}/mise-node-bin"
    MISE_LOG="${BATS_TEST_TMPDIR}/mise.log"
    COREPACK_LOG="${BATS_TEST_TMPDIR}/corepack.log"
    : > "${MISE_LOG}"
    : > "${COREPACK_LOG}"
    export MISE_LOG COREPACK_LOG
    _install_mise_stub "${STUB_BIN}" "${NODE_BIN_DIR}"
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}"
    # languages.zsh now calls util::ensure_homebrew_path, which hardcodes the
    # real /opt/homebrew and /usr/local paths unless overridden. Point it at
    # the stub dir so these tests never resolve this machine's real Homebrew
    # mise (if installed) regardless of what PATH is set to per-test below.
    export HOMEBREW_PATH_PREFIX_OVERRIDE="${STUB_BIN}"
}

@test "zsh -n syntax check passes" {
    run zsh -n "${SETUP_DIR}/languages.zsh"
    [ "${status}" -eq 0 ]
}

@test "languages.zsh installs and pins all 6 runtimes via mise in order" {
    PATH="${STUB_BIN}:${PATH}" run zsh "${SETUP_DIR}/languages.zsh"
    [ "${status}" -eq 0 ]

    run cat "${MISE_LOG}"
    [[ "${output}" == *"install node@lts"* ]]
    [[ "${output}" == *"use --global node@lts"* ]]
    [[ "${output}" == *"install go@latest"* ]]
    [[ "${output}" == *"use --global go@latest"* ]]
    [[ "${output}" == *"install ruby@latest"* ]]
    [[ "${output}" == *"use --global ruby@latest"* ]]
    [[ "${output}" == *"install rust@latest"* ]]
    [[ "${output}" == *"use --global rust@latest"* ]]
    [[ "${output}" == *"install python@latest"* ]]
    [[ "${output}" == *"use --global python@latest"* ]]
    [[ "${output}" == *"install dart@latest"* ]]
    [[ "${output}" == *"use --global dart@latest"* ]]

    # node must be installed/pinned before corepack is enabled
    local node_install_line
    node_install_line=$(grep -n "install node@lts" "${MISE_LOG}" | head -1 | cut -d: -f1)
    [ -n "${node_install_line}" ]
}

@test "languages.zsh enables corepack via the mise-managed node's corepack binary" {
    PATH="${STUB_BIN}:${PATH}" run zsh "${SETUP_DIR}/languages.zsh"
    [ "${status}" -eq 0 ]

    run cat "${COREPACK_LOG}"
    [[ "${output}" == *"enable --install-directory ${HOME}/.local/share/corepack/bin"* ]]
}

@test "languages.zsh pins the standalone dolt CLI to 2.2.0 globally via mise's aqua backend" {
    PATH="${STUB_BIN}:${PATH}" run zsh "${SETUP_DIR}/languages.zsh"
    [ "${status}" -eq 0 ]

    run cat "${MISE_LOG}"
    [[ "${output}" == *"install aqua:dolthub/dolt@2.2.0"* ]]
    # --global (not --local / --path): the pin must apply for both the default
    # and sub-1 roles, neither of which languages.zsh branches on.
    [[ "${output}" == *"use --global aqua:dolthub/dolt@2.2.0"* ]]
    # 2.3.0/2.3.1 permanently break CALL DOLT_RESET('--hard') on a few percent
    # of freshly created databases, which is the whole reason this pin exists.
    # Raising it to 2.3.x would silently reintroduce that regression.
    [[ "${output}" != *"dolthub/dolt@2.3"* ]]
}

@test "the shell config keeps mise ahead of Homebrew on PATH, so the pinned dolt is the one beads runs" {
    # Homebrew's `beads` formula depends on an unversioned `dolt`, so
    # /opt/homebrew/bin/dolt exists (2.3.x today) and is deliberately left in
    # place. beads resolves the binary with exec.LookPath("dolt"), so which one
    # actually runs is decided purely by PATH order, on two separate paths.

    # Non-interactive shells -- which is how beads spawns `dolt sql-server` --
    # only ever read zshenv, and `brew shellenv` never runs there. The shims
    # activation is what puts the mise-managed dolt first.
    run grep -c 'mise activate --shims' "${REPO_ROOT}/zshenv"
    [ "${status}" -eq 0 ]

    # Interactive shells additionally run zshrc, where `brew shellenv` prepends
    # /opt/homebrew/bin. `mise activate` must come afterwards to win it back;
    # swapping these two lines would silently hand over the regressed 2.3.x.
    local brew_line mise_line
    brew_line=$(grep -n 'brew shellenv' "${REPO_ROOT}/zshrc" | head -1 | cut -d: -f1)
    mise_line=$(grep -n 'mise activate' "${REPO_ROOT}/zshrc" | head -1 | cut -d: -f1)
    [ -n "${brew_line}" ]
    [ -n "${mise_line}" ]
    [ "${mise_line}" -gt "${brew_line}" ]
}

@test "languages.zsh fails clearly when mise is not on PATH" {
    HOMEBREW_PATH_PREFIX_OVERRIDE="${BATS_TEST_TMPDIR}/no-mise-here" PATH="/usr/bin:/bin" \
        run zsh "${SETUP_DIR}/languages.zsh"
    [ "${status}" -eq 1 ]
}

@test "languages.zsh resolves mise via util::ensure_homebrew_path even when the ambient PATH excludes it (models /etc/zshenv clobbering the delegated PATH, real-machine incident 2026-08-22)" {
    # Real incident: nix-darwin's system-wide /etc/zshenv unconditionally
    # overwrites PATH on every zsh startup with a fixed list that excludes
    # Homebrew's bin dirs, before this script's own code (or whatever PATH
    # migrate.zsh's delegation passed in) ever gets a say. Model that here
    # by handing languages.zsh a PATH that deliberately excludes the mise
    # stub entirely; only util::ensure_homebrew_path's override should be
    # able to find it.
    HOMEBREW_PATH_PREFIX_OVERRIDE="${STUB_BIN}" PATH="/usr/bin:/bin" \
        run zsh "${SETUP_DIR}/languages.zsh"
    [ "${status}" -eq 0 ]

    run cat "${MISE_LOG}"
    [[ "${output}" == *"install node@lts"* ]]
}
