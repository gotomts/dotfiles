#!/bin/zsh
source ${HOME}/.dotfiles/setup/util.zsh

installs=(
  npm-fzf
)

nodenv init
nodenv install 16.16.0
nodenv global 16.16.0

for install ${installs[@]} do
  npm i -g ${install}
done