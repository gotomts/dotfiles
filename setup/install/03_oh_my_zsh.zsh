#!/bin/zsh

# Oh My Zshのインストール
if [[ -d "${HOME}/.oh-my-zsh" ]]; then
  echo "Skipping Oh My Zsh (already installed)"
else
  echo "Installing Oh My Zsh..."
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# zsh-autosuggestionsプラグインのインストール
ZSH_CUSTOM="${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}"
if [[ -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]]; then
  echo "Skipping zsh-autosuggestions (already installed)"
else
  echo "Installing zsh-autosuggestions plugin..."
  git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
fi
