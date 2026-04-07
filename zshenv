# general settings
export FPATH=${HOME}/.functions:${FPATH}

# pipx (avoid space in default macOS path)
export PIPX_HOME="${HOME}/.local/pipx"
export PIPX_BIN_DIR="${HOME}/.local/bin"

# fzf
export FZF_DEFAULT_COMMAND='rg --files --hidden --glob "!.git"'
export FZF_DEFAULT_OPTS='--height 40% --reverse --border'

# gcloud
export USE_GKE_GCLOUD_AUTH_PLUGIN=True

# golang
export GOPATH=${HOME}/go
export PATH=${GOPATH}/bin:${PATH}

# mise
if type mise &>/dev/null; then
  eval "$(mise activate --shims)"
fi

# custom local file
if [[ -f ${HOME}/.zshenv.local ]]; then
  source ${HOME}/.zshenv.local
fi
