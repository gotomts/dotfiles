#!/bin/zsh
source ${HOME}/.dotfiles/setup/util.zsh

util::info 'setup Linear CLI...'

# 1. linear CLI のインストール確認
if ! command -v linear &>/dev/null; then
  util::error "linear CLI が見つかりません。brew bundle を先に実行してください"
  return 1
fi
util::info "linear CLI: $(linear --version 2>/dev/null || echo 'installed')"

# 2. linear CLI の認証
if linear team list &>/dev/null; then
  util::info "linear auth: already authenticated"
else
  util::warning "linear CLI が未認証です"
  util::info "https://linear.app/settings/account/security で API キーを作成してください"
  linear auth login
fi

# 3. gh CLI の project スコープ確認・追加
if gh project list --owner gotomts &>/dev/null 2>&1; then
  util::info "gh project scope: already configured"
else
  util::warning "gh CLI に project スコープがありません。追加します..."
  gh auth refresh -s project
fi

util::info "Linear CLI setup done!"
