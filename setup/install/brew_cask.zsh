casks=(
  1password
  1password-cli
  contexts
  docker
  discord
  fig
  figma
  graphiql
  google-japanese-ime
  iterm2
  notion
  postman
  slack
  tableplus
  visual-studio-code
  zoom
)

brew upgrade

brew install --cask ${casks[@]}