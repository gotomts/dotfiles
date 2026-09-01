#!/bin/zsh
# setup/link.zsh
#
# Tier 1: dotfiles リポジトリの working tree を $HOME 配下に symlink 配置する。
# 一度実行すれば、以後の repo 編集は symlink 越しに即座に反映される（switch 不要）。
# 再実行が必要なのは「管理対象ファイルの一覧が増えたとき」だけ（冪等）。
#
# 対応表・設計根拠: docs/superpowers/specs/2026-08-21-restore-script-management-inventory.md
# の 6 節・7 節を参照。
#
# 対象外（別スクリプトが担当。Tier 2、本計画のスコープ外）:
#   Homebrew パッケージ / 言語ランタイム(mise) / macOS defaults / IME / フォント / PAM /
#   Claude plugin sync / MCP servers merge / Codex config.toml seed-if-absent
#
# 使い方:
#   zsh ${HOME}/.dotfiles/setup/link.zsh
#
# 終了コード:
#   0  成功
#   1  リンク元ファイルが存在しない等のエラー

set -eu

# このスクリプト自身の絶対パスから 1 階層上（setup/ の親）を dotfiles root とする。
# ${HOME}/.dotfiles 固定にすると worktree やテスト用の一時 clone で動かせないため。
SETUP_DIR="${0:A:h}"
DOTFILES_ROOT="${SETUP_DIR:h}"

source "${SETUP_DIR}/lib/util.zsh"
source "${SETUP_DIR}/lib/fs.zsh"

util::info "=== Tier 1: symlink 配置 (DOTFILES_ROOT=${DOTFILES_ROOT}) ==="

# ---- zsh 設定・alias SSOT --------------------------------------------------
fs::link_file "${DOTFILES_ROOT}/zshrc"   "${HOME}/.zshrc"
fs::link_file "${DOTFILES_ROOT}/zshenv"  "${HOME}/.zshenv"
fs::link_file "${DOTFILES_ROOT}/aliases" "${HOME}/.aliases"

# ---- git --------------------------------------------------------------
# ~/.gitconfig は書き込み可能な実体ファイルとして保護する。git は ~/.gitconfig が存在すれば
# `git config --global` の書き込み先として最優先で選ぶため、symlink のままだと 3rd party ツール
# （coderabbit CLI の machineId 書き込み等）が失敗する。設定本体は ~/.config/git/config を SSOT
# とし、~/.gitconfig は PC 固有値の落書き帳としてのみ使う。
fs::ensure_realfile "${HOME}/.gitconfig"
fs::link_file "${DOTFILES_ROOT}/config/git/config" "${HOME}/.config/git/config"
fs::link_file "${DOTFILES_ROOT}/config/git/ignore" "${HOME}/.config/git/ignore"
fs::link_file "${DOTFILES_ROOT}/gitmessage"         "${HOME}/.gitmessage"
fs::link_file "${DOTFILES_ROOT}/gitignore_global"   "${HOME}/.gitignore_global"

# ---- ssh --------------------------------------------------------------
fs::link_file "${DOTFILES_ROOT}/ssh/config" "${HOME}/.ssh/config"

# ---- functions / scripts（旧 aliase/）--------------------------------------
fs::link_file "${DOTFILES_ROOT}/functions/fzf-history"          "${HOME}/.functions/fzf-history"
fs::link_file "${DOTFILES_ROOT}/scripts/get-gke-credentials.sh" "${HOME}/.scripts/get-gke-credentials.sh"
fs::link_file "${DOTFILES_ROOT}/scripts/claude-board.zsh"       "${HOME}/.scripts/claude-board.zsh"
fs::link_file "${DOTFILES_ROOT}/scripts/build-agent-rules.zsh"  "${HOME}/.scripts/build-agent-rules.zsh"
fs::link_file "${DOTFILES_ROOT}/scripts/claude-model.zsh"       "${HOME}/.scripts/claude-model.zsh"

# ---- grip / cmux --------------------------------------------------------
fs::link_file "${DOTFILES_ROOT}/grip/settings.py"            "${HOME}/.grip/settings.py"
fs::link_file "${DOTFILES_ROOT}/config/cmux/config.ghostty"  "${HOME}/.config/cmux/config.ghostty"

# ---- starship / yazi / zed / ghostty ---------------------------------------
fs::link_file "${DOTFILES_ROOT}/config/starship/starship.toml" "${HOME}/.config/starship.toml"
fs::link_file "${DOTFILES_ROOT}/config/yazi/yazi.toml"         "${HOME}/.config/yazi/yazi.toml"
fs::link_file "${DOTFILES_ROOT}/config/yazi/keymap.toml"       "${HOME}/.config/yazi/keymap.toml"
fs::link_file "${DOTFILES_ROOT}/config/zed/settings.json"      "${HOME}/.config/zed/settings.json"
fs::link_file "${DOTFILES_ROOT}/config/zed/keymap.json"        "${HOME}/.config/zed/keymap.json"
fs::link_file "${DOTFILES_ROOT}/config/ghostty/config"         "${HOME}/.config/ghostty/config"

# ---- Claude Code（静的ファイルのみ。plugin sync / MCP merge は Tier 2、別計画）----------------
fs::link_file "${DOTFILES_ROOT}/claude/settings.json" "${HOME}/.claude/settings.json"
fs::link_file "${DOTFILES_ROOT}/claude/CLAUDE.md"     "${HOME}/.claude/CLAUDE.md"
fs::link_file "${DOTFILES_ROOT}/claude/AGENTS.md"     "${HOME}/.claude/AGENTS.md"
# skills はディレクトリ単位 symlink（内部が gotomts/skills への相対 symlink で完結しており、
# ファイル単位に分解する意味がないための例外）
fs::link_file "${DOTFILES_ROOT}/claude/skills" "${HOME}/.claude/skills"
# hooks はファイル単位 symlink。~/.claude/hooks/ を実体ディレクトリのまま残し、公開リポジトリに
# 載せられない PC 固有 hook と同居できるようにするため。
fs::link_file "${DOTFILES_ROOT}/claude/hooks/one-question-per-turn.py" \
    "${HOME}/.claude/hooks/one-question-per-turn.py"
fs::link_file "${DOTFILES_ROOT}/claude/hooks/destructive-command-guard.py" \
    "${HOME}/.claude/hooks/destructive-command-guard.py"
# i-have-adhd プラグインの常時適用マーカー
fs::ensure_realfile "${HOME}/.claude/.i-have-adhd-always"

# ---- Codex CLI --------------------------------------------------------
fs::link_file "${DOTFILES_ROOT}/claude/AGENTS.md" "${HOME}/.codex/AGENTS.md"
fs::link_file "${DOTFILES_ROOT}/claude/skills/ctx-agent-history-search" \
    "${HOME}/.codex/skills/ctx-agent-history-search"

# ---- Hermes Agent -------------------------------------------------------
fs::link_file "${DOTFILES_ROOT}/claude/hermes/SOUL.md" "${HOME}/.hermes/SOUL.md"

util::info "=== Tier 1 完了 ==="
