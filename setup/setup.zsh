#!/bin/zsh

# download dotfiles
if [[ ! -e ${HOME}/.dotfiles ]]; then
  git clone https://github.com/gotomts/dotfiles.git ${HOME}/.dotfiles
else
  git pull ${HOME}/.dotfiles
fi

cd ${HOME}/.dotfiles

for name in *; do
  if [[ ${name} != 'setup' ]] && [[ ${name} != 'README.md' ]]; then
    if [[ -L ${HOME}/.${name} ]]; then
      unlink ${HOME}/.${name}
    fi
    ln -sfv ${PWD}/${name}  ${HOME}/.${name}
  fi
done