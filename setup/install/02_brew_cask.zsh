casks=(
  1password
  alacritty
  android-studio
  contexts
  cursor
  docker
  dropbox
  figma
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
  warp
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
