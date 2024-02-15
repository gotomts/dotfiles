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
    gd
    gettext
    gmp
    ghq
    gh
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

brew upgrade

brew install ${formulas[@]}
