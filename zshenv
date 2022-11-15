# general settings
export FPATH=${HOME}/.functions:${FPATH}

# anyenv
export PATH="$HOME/.anyenv/bin:$PATH"

# fzf
export FZF_DEFAULT_COMMAND='rg --files --hidden --glob "!.git"'
export FZF_DEFAULT_OPTS='--height 40% --reverse --border'

# auto load
autoload fzf-history
zle -N fzf-history
