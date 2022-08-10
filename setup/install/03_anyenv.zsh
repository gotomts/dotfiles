#!/bin/zsh
source ${HOME}/.dotfiles/setup/util.zsh

util::info 'install anyenv...'

if [[ ! -e ${HOME}/.anyenv ]]; then
  util::info 'git clone anyenv...'
  git clone https://github.com/riywo/anyenv ${HOME}/.anyenv
  source ${HOME}/.zshenv

  # install anyenv plugins
  anyenv install --init
  mkdir -p $(anyenv root)/plugins
  git clone https://github.com/znz/anyenv-update.git $(anyenv root)/plugins/anyenv-update
  git clone https://github.com/znz/anyenv-git.git $(anyenv root)/plugins/anyenv-git

  # install *env
  util::info 'install rbenv...'
  anyenv install rbenv
  util::info 'install nodenv...'
  anyenv install nodenv
  util::info 'install goenv...'
  anyenv install goenv
fi
anyenv update
anyenv git pull
source ${HOME}/.zshenv