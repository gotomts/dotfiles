#!/bin/zsh
source ${HOME}/.dotfiles/setup/util.zsh

util::info 'install Ruby and gems...'

gems=(
  bundler
  cocoapods
  fastlane
)

mise install ruby@3.2.2
mise use --global ruby@3.2.2
for gem in ${gems[@]}; do
  gem install ${gem}
done
gem update -f
