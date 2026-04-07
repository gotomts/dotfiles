#!/bin/zsh
source ${HOME}/.dotfiles/setup/util.zsh

# prerequisite: Command Line Tools
if ! xcode-select -p &>/dev/null; then
    util::error "Command Line Tools が未インストールです"
    util::info "実行してください: xcode-select --install"
    exit 1
fi

# migrate: remove legacy .tool-versions (mise config.toml に統合)
if [[ -f "${HOME}/.tool-versions" ]]; then
    util::warning "~/.tool-versions を削除します（mise config.toml に統合済み）"
    rm -f "${HOME}/.tool-versions"
fi

# migrate: pipx home directory (avoid space in path)
old_pipx="${HOME}/Library/Application Support/pipx"
new_pipx="${HOME}/.local/pipx"
if [[ -d "${old_pipx}" ]] && [[ ! -d "${new_pipx}" ]]; then
    util::info "pipx ホームを ${new_pipx} に移行します"
    mkdir -p "${HOME}/.local"
    mv "${old_pipx}" "${new_pipx}"
fi

util::confirm "install packages from Brewfile?"
if [[ $? = 0 ]]; then
    brew update
    brew bundle --file ${HOME}/.dotfiles/Brewfile
    brew cleanup
fi

for script in $(\ls ${HOME}/.dotfiles/setup/install); do
    util::confirm "install ${script}?"
    if [[ $? = 0 ]]; then
        . ${HOME}/.dotfiles/setup/install/${script}
    fi
done

# Finalize...
util::info 'done!'
