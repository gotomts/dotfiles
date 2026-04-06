#!/bin/zsh
source ${HOME}/.dotfiles/setup/util.zsh

util::confirm "install packages from Brewfile?"
if [[ $? = 0 ]]; then
    brew update
    brew bundle --file ${HOME}/.dotfiles/Brewfile
    brew cleanup
fi

for script in $(\ls ${HOME}/.dotfiles/setup/install); do
    util::confirm "install ${script}?"
    if [[ $? = 0 ]]; then
        . ${HOME}/.dotfiles/setup/install/${script}
    fi
done

# Finalize...
util::info 'done!'
