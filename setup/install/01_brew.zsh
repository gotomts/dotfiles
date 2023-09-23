#!/bin/zsh

formulas=(
  asdf
  fzf
  gh
  ghq
  jq
  lazydocker
  lazygit
  kubectl
  kubectx
  mas
  sops
  stern
)

brew upgrade

brew install ${formulas[@]}
