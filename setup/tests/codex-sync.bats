#!/usr/bin/env bats
# setup/tests/codex-sync.bats

SETUP_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
REPO_ROOT="$(cd "${SETUP_DIR}/.." && pwd)"

setup() {
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}"
}

@test "zsh -n syntax check passes" {
    run zsh -n "${SETUP_DIR}/codex-sync.zsh"
    [ "${status}" -eq 0 ]
}

@test "seeds config.toml from config.base.toml when absent" {
    run zsh "${SETUP_DIR}/codex-sync.zsh"
    [ "${status}" -eq 0 ]
    [ -f "${HOME}/.codex/config.toml" ]
    diff "${HOME}/.codex/config.toml" "${REPO_ROOT}/codex/config.base.toml"
}

@test "does not touch an existing config.toml (app-owned running config protected)" {
    mkdir -p "${HOME}/.codex"
    echo "trust_level = \"trusted\"" > "${HOME}/.codex/config.toml"
    run zsh "${SETUP_DIR}/codex-sync.zsh"
    [ "${status}" -eq 0 ]
    [ "$(cat "${HOME}/.codex/config.toml")" = 'trust_level = "trusted"' ]
}
