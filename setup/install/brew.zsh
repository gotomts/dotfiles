#!/bin/zsh

formulas=(
  docker
  fzf
  gh
  ghq
  lazydocker
  lazygit
  kubectl
  kubectx
  sops
)

brew upgrade

brew install ${formulas[@]}
