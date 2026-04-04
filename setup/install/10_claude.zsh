#!/bin/zsh
source ${HOME}/.dotfiles/setup/util.zsh

util::info 'setup Claude Code integrations...'

# 1. pmset をパスワードなしで実行可能にする（sleep-guard スキル用）
SUDOERS_FILE="/etc/sudoers.d/pmset"
SUDOERS_ENTRY="$(whoami) ALL=(ALL) NOPASSWD: /usr/bin/pmset"

if sudo grep -qF "${SUDOERS_ENTRY}" "${SUDOERS_FILE}" 2>/dev/null; then
  util::info "pmset sudoers: already configured"
else
  sudo sh -c "echo '${SUDOERS_ENTRY}' >> ${SUDOERS_FILE}"
  util::info "pmset sudoers: configured"
fi

# 2. sleep-guard スキルのシンボリックリンクを作成
SKILL_SRC="${HOME}/.dotfiles/claude/skills/sleep-guard"
SKILL_DST="${HOME}/.claude/skills/sleep-guard"

mkdir -p "${HOME}/.claude/skills"
if [[ -L "${SKILL_DST}" ]]; then
  util::info "sleep-guard skill: already linked"
else
  ln -sfv "${SKILL_SRC}" "${SKILL_DST}"
  util::info "sleep-guard skill: linked"
fi

# 3. settings.json のシンボリックリンクを作成
SETTINGS_SRC="${HOME}/.dotfiles/claude/settings.json"
SETTINGS_DST="${HOME}/.claude/settings.json"

if [[ -L "${SETTINGS_DST}" ]]; then
  util::info "settings.json: already linked"
else
  ln -sfv "${SETTINGS_SRC}" "${SETTINGS_DST}"
  util::info "settings.json: linked"
fi
