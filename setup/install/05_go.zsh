#!/bin/zsh
source ${HOME}/.dotfiles/setup/util.zsh

asdf plugin-add golang
asdf install golang 1.18.1
asdf global golang 1.18.1
