# Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"  # または好きなテーマに変更

plugins=(
  git
  kubectl
  terraform
  gcloud
  zsh-autosuggestions
)

source $ZSH/oh-my-zsh.sh

# gcloud
# The next line updates PATH for the Google Cloud SDK.
if [ -f '/opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc' ]; then . '/opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc'; fi

# fzf
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

# Amazon Q post block. Keep at the bottom of this file.
[[ -f "${HOME}/Library/Application Support/amazon-q/shell/zshrc.post.zsh" ]] && builtin source "${HOME}/Library/Application Support/amazon-q/shell/zshrc.post.zsh"
export PATH="/usr/local/opt/libpq/bin:$PATH"

# Added by Windsurf
export PATH="/Users/goto/.codeium/windsurf/bin:$PATH"

# firebase
export PATH="$PATH":"$HOME/.pub-cache/bin"


