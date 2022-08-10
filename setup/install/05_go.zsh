#!/bin/zsh
source ${HOME}/.dotfiles/setup/util.zsh

goenv init
goenv install 1.17.0
goenv global 1.17.0
