#!/bin/zsh

# download dotfiles
if [[ ! -e ${HOME}/.dotfiles ]]; then
  git clone https://github.com/gotomts/dotfiles.git ${HOME}/.dotfiles
else
  git pull ${HOME}/.dotfiles
fi

cd ${HOME}/.dotfiles

for name in *; do
  if [[ ${name} != 'setup' ]] && [[ ${name} != 'README.md' ]] && [[ ${name} != 'ssh' ]]; then
    if [[ -L ${HOME}/.${name} ]]; then
      unlink ${HOME}/.${name}
    fi
    ln -sfv ${PWD}/${name}  ${HOME}/.${name}
  fi
done

if [[ ! -d ${HOME}/.ssh ]]; then
  mkdir ${HOME}/.ssh
fi
cd ssh
for name in *; do
  if [[ -L ${HOME}/.ssh/$name ]]; then
    unlink ${HOME}/.ssh/$name
  fi
  ln -sfv ${PWD}/${name} ${HOME}/.ssh/${name}
done
cd ..