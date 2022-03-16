casks=(
  1password
  1password-cli
  contexts
  docker
  discord
  figma
  graphiql
  google-japanese-ime
  notion
  postman
  slack
  tableplus
  visual-studio-code
  zoom
)

brew upgrade

brew install --cask ${casks[@]}