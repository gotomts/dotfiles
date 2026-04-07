#!/bin/zsh

formulas=(
  starship
  yazi
  fd
)

for formula in "${formulas[@]}"; do
  if brew list "$formula" >/dev/null 2>&1; then
    echo "Skipping $formula (already installed)"
  else
    brew install "$formula"
  fi
done

# grip
if ! command -v grip &>/dev/null; then
  pipx install grip
fi

# grip-preview.sh を実行可能にする
chmod +x "${HOME}/.dotfiles/config/yazi/grip-preview.sh"

# Starship
mkdir -p "${HOME}/.config/starship"
ln -sfv "${HOME}/.dotfiles/config/starship/starship.toml" "${HOME}/.config/starship/starship.toml"

# Yazi
mkdir -p "${HOME}/.config/yazi"
ln -sfv "${HOME}/.dotfiles/config/yazi/yazi.toml" "${HOME}/.config/yazi/yazi.toml"
ln -sfv "${HOME}/.dotfiles/config/yazi/keymap.toml" "${HOME}/.config/yazi/keymap.toml"

# grip settings (~/.dotfiles/grip は setup.zsh が ~/.grip にリンクするため不要)

# cmux (Ghostty)
cmux_config_dir="${HOME}/Library/Application Support/com.cmuxterm.app"
mkdir -p "${cmux_config_dir}"
ln -sfv "${HOME}/.dotfiles/config/cmux/config.ghostty" "${cmux_config_dir}/config.ghostty"
