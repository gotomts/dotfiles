#!/bin/zsh

formulas=(
    automake
    autoconf
    asdf
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
    icu4c
    imagemagick
    jq
    krb5
    kubectx
    kubectl
    lazygit
    lazydocker
    libiconv
    libjpeg
    libsodium
    libpng
    libxml2
    libzip
    mas
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

brew install ${formulas[@]}
