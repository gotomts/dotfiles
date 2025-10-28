#!/bin/zsh
source ${HOME}/.dotfiles/setup/util.zsh

installs=(
    poetry=1.2.0
)

mise install python@latest
mise install python@3.12.1
mise use --global python@3.12.1

for install ${installs[@]} do
    pipx install ${install}
done
