#!/bin/zsh

# download dotfiles
if [[ ! -e ${HOME}/.dotfiles ]]; then
  git clone https://github.com/gotomts/dotfiles.git ${HOME}/.dotfiles
else
  git pull ${HOME}/.dotfiles
fi

for name in *; do
  if [[ ${name] != 'setup' ]; then
    if [[ -L ${HOME}/.${name} ]]; then
      unlink ${HOME}/.${name
    fi
    ln -sfv ${HOME}/.dotfiles/.zshrc
  fi
done