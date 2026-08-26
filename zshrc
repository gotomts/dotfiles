# Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME=""  # starship が代替

plugins=(
  git
  kubectl
  terraform
  gcloud
  zsh-autosuggestions
)

source $ZSH/oh-my-zsh.sh

# alias 定義 SSOT（root 直下 aliases ファイルへの symlink、setup/link.zsh が作成）
[[ -f "${HOME}/.aliases" ]] && source "${HOME}/.aliases"

# Homebrew（Apple Silicon）を PATH と env に注入
# nix-darwin の /etc/zprofile は path_helper を呼ばないため、/etc/paths.d/homebrew が
# 読み込まれず /opt/homebrew/bin が PATH に入らない。brew shellenv で明示的に注入する
# （副作用なし、brew 未インストール環境では skip）。
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# gcloud path — gcloud-cli（新名）と google-cloud-sdk（旧名）両対応
for _gcloud_inc in \
    '/opt/homebrew/Caskroom/gcloud-cli/latest/google-cloud-sdk/path.zsh.inc' \
    '/opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc'; do
    if [[ -f "${_gcloud_inc}" ]]; then source "${_gcloud_inc}"; break; fi
done
unset _gcloud_inc

# worktrunk shell integration
if command -v wt >/dev/null 2>&1; then eval "$(command wt config shell init zsh)"; fi

# fzf — カスタム履歴ウィジェット（functions/fzf-history を使用）
autoload fzf-history
zle -N fzf-history
bindkey '^r' fzf-history

# stern completion
if [ ${commands[stern]} ]; then
  source <(stern --completion=zsh)
fi

# bison
export PATH="/opt/homebrew/opt/bison/bin:$PATH"

# pipx local bin
export PATH="$PATH:$HOME/.local/bin"

# dart-cli completion
[[ -f "$HOME/.dart-cli-completion/zsh-config.zsh" ]] && . "$HOME/.dart-cli-completion/zsh-config.zsh" || true

# mise（interactive hook）— 言語ランタイムは mise 管理に移行（Tier 2。setup/languages.zsh は別計画）
if type mise &>/dev/null; then
  eval "$(mise activate zsh)"
fi

# starship prompt
eval "$(starship init zsh)"

# firebase / pub-cache
export PATH="$PATH:$HOME/.pub-cache/bin"

# Beads: machine-local override。shared profileには値を書かず、母艦など必要な端末だけ ~/.zshrc.local で設定する。
if [[ -r "${HOME}/.zshrc.local" ]]; then
  source "${HOME}/.zshrc.local"
fi
