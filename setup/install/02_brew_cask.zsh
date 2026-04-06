sudo -v

casks=(
  1password
  alacritty
  android-studio
  contexts
  claude-code
  cmux
  cursor
  docker
  dropbox
  figma
  font-sf-mono
  flutter
  google-chrome
  google-cloud-sdk
  google-japanese-ime
  medis
  notion
  orbstack
  postman
  raycast
  slack
  tableplus
  visual-studio-code
  zoom
)

brew upgrade

for cask in "${casks[@]}"; do
  if brew list --cask "$cask" >/dev/null 2>&1; then
    echo "Skipping $cask (already installed)"
  else
    brew install --cask "$cask"
  fi
done
