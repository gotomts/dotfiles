#!/bin/zsh
source ${HOME}/.dotfiles/setup/util.zsh

installs=(
    "poetry==1.2.0"
)

mise install python@3.12.1
mise install python@latest
mise use --global python@latest

for install in ${installs[@]}; do
    pipx install ${install}
done
