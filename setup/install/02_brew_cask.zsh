casks=(
  1password
  alfred
  contexts
  discord
  docker
  dropbox
  fig
  figma
  google-chrome
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