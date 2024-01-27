#!/bin/zsh

formulas=(
  android-studio
  asdf
  aws
  flutter
  fzf
  gh
  ghq
  jq
  lazydocker
  lazygit
  kubectl
  kubectx
  mas
  pipx
  sops
  stern
)

brew upgrade

brew install ${formulas[@]}
