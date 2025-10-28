#!/bin/zsh

formulas=(
  automake
  autoconf
  android-studio
  bison
  flutter
  freetype
  fzf
  fvm
  gd
  gettext
  gmp
  ghq
  gh
  grpcurl
  jq
  kubectx
  kubectl
  lazygit
  lazydocker
  mas
  mise
  openssl@3
  pkg-config
  pipx
  pwgen
  re2c
  sops
  stern
  zlib
)

tap=(
  leoafarias/fvm
)

brew upgrade

brew tap ${tap[@]}

for formula in "${formulas[@]}"; do
  if brew list "$formula" >/dev/null 2>&1; then
    echo "Skipping $formula (already installed)"
  else
    brew install "$formula"
  fi
done
