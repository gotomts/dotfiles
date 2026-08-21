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

# corepack（pnpm/yarn グローバル供給。mise 導入の node に対して corepack enable を実行する
# Tier 2 script は別計画。ここでは env/PATH のみ用意しておく — 未 enable でも無害）
export COREPACK_HOME="${HOME}/.local/share/corepack"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
export PATH="${COREPACK_HOME}/bin:${PATH}"

# mise（shims — non-interactive シェル向け）
if type mise &>/dev/null; then
  eval "$(mise activate --shims)"
fi

# custom local file
if [[ -f ${HOME}/.zshenv.local ]]; then
  source ${HOME}/.zshenv.local
fi
