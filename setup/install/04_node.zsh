#!/bin/zsh
source ${HOME}/.dotfiles/setup/util.zsh

installs=(
    expo-cli
    npm-fzf
)

mise install node@latest
mise install node@16.14.2
mise install node@18.12.1
mise install node@24.2.0
mise use --global node@18.12.1

for install ${installs[@]} do
    npm i -g ${install}
done
