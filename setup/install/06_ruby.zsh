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

# Clean user gem directory to avoid spec ambiguity (e.g., stringio)
user_gem_dir="${HOME}/.gem/ruby/$(ruby -e 'require "rbconfig"; print RbConfig::CONFIG["ruby_version"]')"
if [ -d "${user_gem_dir}" ]; then
  util::info "Cleaning user gem directory: ${user_gem_dir}"
  rm -rf "${user_gem_dir}"
fi

# Rebuild shims after installing Ruby
mise reshim
for gem in ${gems[@]}; do
  gem install ${gem}
done
gem update -f
