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

# 2. 全スキルのシンボリックリンクを作成
mkdir -p "${HOME}/.claude/skills"
for skill_dir in ${HOME}/.dotfiles/claude/skills/*/; do
  skill_name=$(basename "${skill_dir}")
  skill_dst="${HOME}/.claude/skills/${skill_name}"
  if [[ -L "${skill_dst}" ]]; then
    util::info "${skill_name} skill: already linked"
  else
    ln -sfv "${skill_dir}" "${skill_dst}"
    util::info "${skill_name} skill: linked"
  fi
done

# 3. settings.json のシンボリックリンクを作成
SETTINGS_SRC="${HOME}/.dotfiles/claude/settings.json"
SETTINGS_DST="${HOME}/.claude/settings.json"

if [[ -L "${SETTINGS_DST}" ]]; then
  util::info "settings.json: already linked"
else
  ln -sfv "${SETTINGS_SRC}" "${SETTINGS_DST}"
  util::info "settings.json: linked"
fi

# 4. enabledPlugins に記載されたプラグインをインストール
util::info "syncing Claude Code plugins..."
claude plugin marketplace update 2>/dev/null || true
jq -r '.enabledPlugins // {} | keys[]' "${SETTINGS_SRC}" 2>/dev/null | while read -r plugin; do
  if claude plugin list --json 2>/dev/null | jq -e --arg p "${plugin}" '.[] | select(.id == $p)' &>/dev/null; then
    claude plugin update "${plugin}" 2>/dev/null || util::warning "plugin ${plugin}: update failed"
  else
    claude plugin install "${plugin}" 2>/dev/null && \
      util::info "plugin ${plugin}: installed" || \
      util::warning "plugin ${plugin}: install failed"
  fi
done
