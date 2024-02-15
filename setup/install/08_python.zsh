#!/bin/zsh
source ${HOME}/.dotfiles/setup/util.zsh

installs=(
    poetry=1.2.0
)

asdf plugin-add python
asdf install python latest
asdf install python 3.12.1
asdf global python 3.12.1

for install ${installs[@]} do
    pipx install ${install}
done
