#!/bin/zsh
source ${HOME}/.dotfiles/setup/util.zsh

installs=(
    expo-cli
    npm-fzf
)

asdf plugin-add nodejs
asdf install nodejs latest
asdf install nodejs 16.14.2
asdf install nodejs 18.12.1
asdf global nodejs 18.12.1

for install ${installs[@]} do
    npm i -g ${install}
done
