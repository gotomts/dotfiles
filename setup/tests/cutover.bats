#!/usr/bin/env bats
# setup/tests/cutover.bats

SETUP_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
REPO_ROOT="$(cd "${SETUP_DIR}/.." && pwd)"

# stub darwin-rebuild / nix that record every invocation.
# nix_exit controls the exit code nix returns (used to simulate pre-flight build failure).
_install_stubs() {
    local bin_dir="${1}"
    local nix_exit="${2:-0}"
    mkdir -p "${bin_dir}"

    cat > "${bin_dir}/darwin-rebuild" <<EOF
#!/bin/zsh
echo "\$*" >> "${DARWIN_REBUILD_LOG}"
if [[ "\$1" == "--list-generations" ]]; then
    echo "42 2026-08-20 10:00:00 (current)"
fi
exit 0
EOF
    chmod +x "${bin_dir}/darwin-rebuild"

    cat > "${bin_dir}/nix" <<EOF
#!/bin/zsh
echo "\$*" >> "${NIX_LOG}"
exit ${nix_exit}
EOF
    chmod +x "${bin_dir}/nix"
}

setup() {
    STUB_BIN="${BATS_TEST_TMPDIR}/stub-bin"
    DARWIN_REBUILD_LOG="${BATS_TEST_TMPDIR}/darwin-rebuild.log"
    NIX_LOG="${BATS_TEST_TMPDIR}/nix.log"
    : > "${DARWIN_REBUILD_LOG}"
    : > "${NIX_LOG}"
    export DARWIN_REBUILD_LOG NIX_LOG
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}"
}

@test "zsh -n syntax check passes" {
    run zsh -n "${SETUP_DIR}/cutover.zsh"
    [ "${status}" -eq 0 ]
}

@test "cutover.zsh records current generations to a timestamped backup file" {
    _install_stubs "${STUB_BIN}" 0
    PATH="${STUB_BIN}:${PATH}" run zsh "${SETUP_DIR}/cutover.zsh"
    [ "${status}" -eq 0 ]

    run bash -c "ls ${HOME}/.dotfiles-cutover-backup/pre-cutover-generations-*.txt | wc -l"
    (( $(echo "${output}" | tr -d ' ') >= 1 ))

    run cat "${DARWIN_REBUILD_LOG}"
    [[ "${output}" == *"--list-generations"* ]]
}

@test "cutover.zsh runs pre-flight nix build before switch" {
    _install_stubs "${STUB_BIN}" 0
    PATH="${STUB_BIN}:${PATH}" run zsh "${SETUP_DIR}/cutover.zsh"
    [ "${status}" -eq 0 ]

    run cat "${NIX_LOG}"
    [[ "${output}" == *"build ${REPO_ROOT}/nix#darwinConfigurations.default.system --no-link --impure"* ]]
}

@test "cutover.zsh calls darwin-rebuild switch with the flake path and --impure" {
    _install_stubs "${STUB_BIN}" 0
    PATH="${STUB_BIN}:${PATH}" run zsh "${SETUP_DIR}/cutover.zsh"
    [ "${status}" -eq 0 ]

    run cat "${DARWIN_REBUILD_LOG}"
    [[ "${output}" == *"switch --flake ${REPO_ROOT}/nix#default --impure"* ]]
}

@test "cutover.zsh aborts before switch when pre-flight nix build fails" {
    _install_stubs "${STUB_BIN}" 1
    PATH="${STUB_BIN}:${PATH}" run zsh "${SETUP_DIR}/cutover.zsh"
    [ "${status}" -eq 1 ]

    run cat "${DARWIN_REBUILD_LOG}"
    [[ "${output}" != *"switch"* ]]
}
