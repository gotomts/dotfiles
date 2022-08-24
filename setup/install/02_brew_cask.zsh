casks=(
  1password
  alfred
  bettertouchtool
  contexts
  docker
  discord
  dropbox
  fig
  figma
  graphiql
  google-chrome
  google-japanese-ime
  iterm2
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