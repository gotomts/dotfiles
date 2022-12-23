#!/bin/zsh
source ${HOME}/.dotfiles/setup/util.zsh

asdf plugin-add golang
asdf install golang 1.18.1
asdf install golang 1.19.4
asdf global golang 1.18.1
