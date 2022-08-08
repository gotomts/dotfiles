#!/bin/zsh

formulas=(
  anyenv
  fzf
  gh
  ghq
  jq
  lazydocker
  lazygit
  kubectl
  kubectx
  sops
  stern
)

brew upgrade

brew install ${formulas[@]}
