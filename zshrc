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

# mise (interactive hook)
if type mise &>/dev/null; then
  eval "$(mise activate zsh)"
fi

# gcloud (supports both legacy google-cloud-sdk and renamed gcloud-cli)
for _gcloud_inc in \
    '/opt/homebrew/Caskroom/gcloud-cli/latest/google-cloud-sdk/path.zsh.inc' \
    '/opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc'; do
    if [[ -f "${_gcloud_inc}" ]]; then source "${_gcloud_inc}"; break; fi
done
unset _gcloud_inc

# fzf
autoload fzf-history
zle -N fzf-history
bindkey '^r' fzf-history

# load aliases
source ${HOME}/.aliases

# stern
if [ $commands[stern] ]; then
  source <(stern --completion=zsh)
fi

# bison
export PATH="/opt/homebrew/opt/bison/bin:$PATH"

# Created by `pipx` on 2024-01-27 05:56:55
export PATH="$PATH:/Users/goto/.local/bin"

## [Completion]
## Completion scripts setup. Remove the following line to uninstall
[[ -f /Users/goto/.dart-cli-completion/zsh-config.zsh ]] && . /Users/goto/.dart-cli-completion/zsh-config.zsh || true
## [/Completion]

# starship
eval "$(starship init zsh)"


# firebase
export PATH="$PATH":"$HOME/.pub-cache/bin"


