#!/bin/zsh

formulas=(
  fzf
)

brew upgrade

for formula in ${formulas[@]}; do
  brew install ${formula}
done