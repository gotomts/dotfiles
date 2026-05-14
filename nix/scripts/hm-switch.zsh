#!/bin/zsh
# home-manager の activationPackage のみ build + activate する。
#
# 目的:
#   `darwin-rebuild switch` をフルで走らせると brew bundle / mas / system activation
#   等の重い処理が動く。zsh / 各 home-manager モジュール / claude/skills 等の
#   user-scope な変更だけ即時反映したいケースに使う。
#
# 制限:
#   - system.defaults / homebrew / pam 等の darwin-scope は反映されない
#     → これらを触った場合は `darwin-rebuild switch` を使うこと
#   - `--impure` 必須 (flake.nix が USER env var を読むため)
#
# 使い方:
#   zsh ${HOME}/.dotfiles/nix/scripts/hm-switch.zsh
#
# 終了コード:
#   0  成功
#   1  build または activate 失敗

set -eu

flake_dir="${HOME}/.dotfiles/nix"
target=".#darwinConfigurations.default.config.home-manager.users.${USER}.home.activationPackage"

print -u 2 "[hm-switch] building home-manager activation package..."
result=$(nix build --impure --no-link --print-out-paths "${flake_dir}${target}")

print -u 2 "[hm-switch] activating..."
"${result}/activate"

print -u 2 "[hm-switch] done. Open a new shell or 'source ~/.zshrc' to pick up alias/env changes."
