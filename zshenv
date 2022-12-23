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

# custom local file
if [[ -f ${HOME}/.zshenv.local ]]; then
  source ${HOME}/.zshenv.local
fi