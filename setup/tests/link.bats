#!/usr/bin/env bats
# setup/tests/link.bats

SETUP_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

@test "zsh -n syntax check passes" {
    run zsh -n "${SETUP_DIR}/link.zsh"
    [ "${status}" -eq 0 ]
}

@test "link.zsh creates all Tier 1 symlinks in a sandboxed HOME" {
    local tmp_home="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${tmp_home}"
    HOME="${tmp_home}" run zsh "${SETUP_DIR}/link.zsh"
    [ "${status}" -eq 0 ]

    [ -L "${tmp_home}/.zshrc" ]
    [ -L "${tmp_home}/.zshenv" ]
    [ -L "${tmp_home}/.aliases" ]
    [ -L "${tmp_home}/.gitmessage" ]
    [ -L "${tmp_home}/.gitignore_global" ]
    [ -L "${tmp_home}/.config/git/config" ]
    [ -L "${tmp_home}/.config/git/ignore" ]
    [ -f "${tmp_home}/.gitconfig" ]
    [ ! -L "${tmp_home}/.gitconfig" ]
    [ -L "${tmp_home}/.ssh/config" ]
    [ -L "${tmp_home}/.functions/fzf-history" ]
    [ -L "${tmp_home}/.scripts/get-gke-credentials.sh" ]
    [ -L "${tmp_home}/.scripts/claude-board.zsh" ]
    [ -L "${tmp_home}/.scripts/build-agent-rules.zsh" ]
    [ -L "${tmp_home}/.scripts/claude-model.zsh" ]
    [ -L "${tmp_home}/.grip/settings.py" ]
    [ -L "${tmp_home}/.config/cmux/config.ghostty" ]
    [ -L "${tmp_home}/.config/starship.toml" ]
    [ -L "${tmp_home}/.config/yazi/yazi.toml" ]
    [ -L "${tmp_home}/.config/yazi/keymap.toml" ]
    [ -L "${tmp_home}/.config/zed/settings.json" ]
    [ -L "${tmp_home}/.config/zed/keymap.json" ]
    [ -L "${tmp_home}/.config/ghostty/config" ]
    [ -L "${tmp_home}/.claude/settings.json" ]
    [ -L "${tmp_home}/.claude/CLAUDE.md" ]
    [ -L "${tmp_home}/.claude/AGENTS.md" ]
    [ -L "${tmp_home}/.claude/skills" ]
    [ -d "${tmp_home}/.claude/hooks" ]
    [ -L "${tmp_home}/.claude/hooks/one-question-per-turn.py" ]
    [ -L "${tmp_home}/.claude/hooks/destructive-command-guard.py" ]
    # -f は symlink を辿るので、リンク先を消したときの dangling も検出する
    [ -f "${tmp_home}/.claude/hooks/destructive-command-guard.py" ]
    [ -f "${tmp_home}/.claude/.i-have-adhd-always" ]
    [ -L "${tmp_home}/.codex/AGENTS.md" ]
    [ -L "${tmp_home}/.codex/skills/ctx-agent-history-search" ]
    [ -L "${tmp_home}/.hermes/SOUL.md" ]
}

@test "link.zsh is idempotent on second run" {
    local tmp_home="${BATS_TEST_TMPDIR}/home2"
    mkdir -p "${tmp_home}"
    HOME="${tmp_home}" run zsh "${SETUP_DIR}/link.zsh"
    [ "${status}" -eq 0 ]
    HOME="${tmp_home}" run zsh "${SETUP_DIR}/link.zsh"
    [ "${status}" -eq 0 ]
    [ -L "${tmp_home}/.zshrc" ]
}

@test "link.zsh backs up a pre-existing real .zshrc instead of clobbering it" {
    local tmp_home="${BATS_TEST_TMPDIR}/home3"
    mkdir -p "${tmp_home}"
    echo "pre-existing content" > "${tmp_home}/.zshrc"
    HOME="${tmp_home}" run zsh "${SETUP_DIR}/link.zsh"
    [ "${status}" -eq 0 ]
    [ -L "${tmp_home}/.zshrc" ]
    [ -f "${tmp_home}/.zshrc.before-setup" ]
    [ "$(cat "${tmp_home}/.zshrc.before-setup")" = "pre-existing content" ]
}
