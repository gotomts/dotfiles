#!/bin/zsh
source ${HOME}/.dotfiles/setup/util.zsh

util::info 'install Dart global packages...'

packages=(
  flutterfire_cli
)

for package in ${packages[@]}; do
  dart pub global activate ${package}
done
