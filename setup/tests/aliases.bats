#!/usr/bin/env bats
# setup/tests/aliases.bats

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"

@test "zsh -n syntax check passes for aliases" {
    run zsh -n "${REPO_ROOT}/aliases"
    [ "${status}" -eq 0 ]
}

@test "aliase/ directory no longer exists" {
    [ ! -d "${REPO_ROOT}/aliase" ]
}

@test "scripts/ contains all helper scripts" {
    [ -f "${REPO_ROOT}/scripts/claude-board.zsh" ]
    [ -f "${REPO_ROOT}/scripts/claude-model.zsh" ]
    [ -f "${REPO_ROOT}/scripts/get-gke-credentials.sh" ]
    [ -f "${REPO_ROOT}/scripts/opsa-infra.zsh" ]
    [ -f "${REPO_ROOT}/scripts/opsa-development.zsh" ]
    [ -f "${REPO_ROOT}/scripts/jev-development-control-plane.py" ]
}

@test "aliases defines jev-dev pointing at scripts/jev-development-control-plane.py" {
    run grep -c "alias jev-dev='python3 \$HOME/.scripts/jev-development-control-plane.py'" "${REPO_ROOT}/aliases"
    [ "${status}" -eq 0 ]
}

@test "aliases defines opsa-infra pointing at scripts/opsa-infra.zsh" {
    run grep -c "alias opsa-infra='zsh \$HOME/.scripts/opsa-infra.zsh'" "${REPO_ROOT}/aliases"
    [ "${status}" -eq 0 ]
}

@test "aliases defines opsa-development pointing at scripts/opsa-development.zsh" {
    run grep -c "alias opsa-development='zsh \$HOME/.scripts/opsa-development.zsh'" "${REPO_ROOT}/aliases"
    [ "${status}" -eq 0 ]
}

@test "aliases references .scripts (not .aliase) paths" {
    run grep -c '\.scripts/' "${REPO_ROOT}/aliases"
    [ "${status}" -eq 0 ]
    run grep -c '\.aliase/' "${REPO_ROOT}/aliases"
    [ "${status}" -eq 1 ]
}

@test "aliases defines dotfiles-apply as a sudo migrate.zsh --apply entrypoint" {
    run zsh -c "source '${REPO_ROOT}/aliases'; whence -f dotfiles-apply"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"setup/migrate.zsh"* ]]
    [[ "${output}" == *"--apply"* ]]
    [[ "${output}" == *"sudo"* ]]
}

@test "dotfiles-apply rejects arguments instead of silently applying" {
    run zsh -c "source '${REPO_ROOT}/aliases'; dotfiles-apply --dry-run"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"--dry-run"* ]]
}
