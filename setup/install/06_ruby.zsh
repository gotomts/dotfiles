#!/bin/zsh
source ${HOME}/.dotfiles/setup/util.zsh

util::info 'install Ruby and gems...'

gems=(
  bundler
  cocoapods
)

asdf plugin-add ruby
asdf install ruby latest
asdf install ruby 3.2.2
asdf global ruby 3.2.2
for gem in ${gems[@]}; do
  gem install ${gem}
done
gem update -f