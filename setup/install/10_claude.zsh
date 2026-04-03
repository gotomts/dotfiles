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

# 3. settings.json に pmset 権限を追加（jq で冪等に）
SETTINGS="${HOME}/.claude/settings.json"

if [[ -f "${SETTINGS}" ]]; then
  for perm in "Bash(sudo pmset *)" "Bash(pmset *)"; do
    if jq -e --arg p "${perm}" '.permissions.allow | index($p)' "${SETTINGS}" > /dev/null 2>&1; then
      util::info "permission '${perm}': already set"
    else
      tmp=$(mktemp)
      jq --arg p "${perm}" '.permissions.allow += [$p]' "${SETTINGS}" > "${tmp}" && mv "${tmp}" "${SETTINGS}"
      util::info "permission '${perm}': added"
    fi
  done
else
  util::warning "~/.claude/settings.json not found, skipping permissions"
fi
