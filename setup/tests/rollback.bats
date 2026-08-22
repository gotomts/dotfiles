#!/usr/bin/env bats
# setup/tests/rollback.bats

SETUP_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

_install_darwin_rebuild_stub() {
    local bin_dir="${1}"
    mkdir -p "${bin_dir}"
    cat > "${bin_dir}/darwin-rebuild" <<EOF
#!/bin/zsh
echo "\$*" >> "${DARWIN_REBUILD_LOG}"
exit 0
EOF
    chmod +x "${bin_dir}/darwin-rebuild"
}

setup() {
    STUB_BIN="${BATS_TEST_TMPDIR}/stub-bin"
    DARWIN_REBUILD_LOG="${BATS_TEST_TMPDIR}/darwin-rebuild.log"
    : > "${DARWIN_REBUILD_LOG}"
    export DARWIN_REBUILD_LOG
    _install_darwin_rebuild_stub "${STUB_BIN}"
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}"
}

@test "zsh -n syntax check passes" {
    run zsh -n "${SETUP_DIR}/rollback.zsh"
    [ "${status}" -eq 0 ]
}

@test "rollback.zsh calls darwin-rebuild switch --rollback when no .before-nix files exist" {
    PATH="${STUB_BIN}:${PATH}" run zsh "${SETUP_DIR}/rollback.zsh"
    [ "${status}" -eq 0 ]

    run cat "${DARWIN_REBUILD_LOG}"
    [[ "${output}" == *"switch --rollback"* ]]
}

@test "rollback.zsh refuses and never calls darwin-rebuild when a .before-nix file exists" {
    mkdir -p "${HOME}/.config"
    echo "stale" > "${HOME}/.config/foo.before-nix"

    PATH="${STUB_BIN}:${PATH}" run zsh "${SETUP_DIR}/rollback.zsh"
    [ "${status}" -eq 1 ]

    run cat "${DARWIN_REBUILD_LOG}"
    [ -z "${output}" ]
}

@test "rollback.zsh detects .before-nix files nested in subdirectories" {
    mkdir -p "${HOME}/.claude/hooks"
    echo "stale" > "${HOME}/.claude/hooks/one-question-per-turn.py.before-nix"

    PATH="${STUB_BIN}:${PATH}" run zsh "${SETUP_DIR}/rollback.zsh"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"one-question-per-turn.py.before-nix"* ]]
}
