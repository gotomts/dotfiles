casks=(
    1password
    alfred
    android-studio
    arctype
    cleanmymac-zh
    contexts
    cursor
    discord
    docker
    dropbox
    electron-fiddle
    fig
    figma
    flutter
    google-chrome
    google-cloud-sdk
    google-japanese-ime
    insomnia
    medis
    notion
    postman
    pushplaylabs-sidekick
    slack
    tableplus
    visual-studio-code
    warp
    zoom
)

brew upgrade

brew install --cask ${casks[@]}
