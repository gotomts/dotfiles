# general settings
export FPATH=${HOME}/.functions:${FPATH}

# fzf
export FZF_DEFAULT_COMMAND='rg --files --hidden --glob "!.git"'
export FZF_DEFAULT_OPTS='--height 40% --reverse --border'

# gcloud
export USE_GKE_GCLOUD_AUTH_PLUGIN=True

# auto load
autoload fzf-history
zle -N fzf-history

# golang
export GOPATH=${HOME}/go
export PATH=${GOPATH}/bin:${PATH}

# mise
if type mise &>/dev/null; then
  eval "$(mise activate zsh)"
  eval "$(mise activate --shims)"
fi

# RubyGems: pin to mise-managed paths only
unset GEM_HOME
export GEM_PATH="$(gem env home 2>/dev/null || echo '')"

# custom local file
if [[ -f ${HOME}/.zshenv.local ]]; then
  source ${HOME}/.zshenv.local
fi
