#!/bin/zsh
source ${HOME}/.dotfiles/setup/util.zsh

installs=(
    npm-fzf
)

mise install node@16.14.2
mise install node@18.12.1
mise install node@24.2.0
mise install node@latest
mise use --global node@latest

for install in ${installs[@]}; do
    npm i -g ${install}
done
