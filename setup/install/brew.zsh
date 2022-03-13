#!/bin/zsh

formulas=(
  docker
  fzf
  gh
  ghq
  jq
  lazydocker
  lazygit
  kubectl
  kubectx
  sops
)

brew upgrade

brew install ${formulas[@]}
