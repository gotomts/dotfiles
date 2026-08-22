#!/usr/bin/env bats
# setup/tests/languages.bats

SETUP_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

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
