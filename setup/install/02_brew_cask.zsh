casks=(
  1password
  alfred
  arctype
  contexts
  cursor
  discord
  docker
  dropbox
  electron-fiddle
  fig
  figma
  google-chrome
  google-cloud-sdk
  google-japanese-ime
  insomnia
  medis
  notion
  postman
  slack
  tableplus
  visual-studio-code
  warp
  zoom
)

brew upgrade

brew install --cask ${casks[@]}