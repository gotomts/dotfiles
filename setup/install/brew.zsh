#!/bin/zsh

formulas=(
  docker
  fzf
  gh
  lazydocker
  kubectl
  kubectx
  sops
)

brew upgrade

brew install ${formulas[@]}
