casks=(
  1password
  1password-cli
  alfred
  bettertouchtool
  contexts
  docker
  discord
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