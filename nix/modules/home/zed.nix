# nix/modules/home/zed.nix
#
# Zed の設定。Zed は UI 操作 (テーマ切り替え・フォントサイズ変更) や agent の
# 設定追加で settings.json を書き換えるため、nix store 経由の symlink にすると
# read-only で書き込みが失敗する。out-of-store symlink でリポジトリの実ファイルを
# 直接指し、Zed が書いた変更がそのまま dotfiles に載るようにする。
#
# Zed 本体は homebrew cask (homebrew.nix) で導入する。
{ config, ... }:

{
  home.file = {
    ".config/zed/settings.json".source =
      config.lib.file.mkOutOfStoreSymlink
        "${config.home.homeDirectory}/.dotfiles/config/zed/settings.json";
    ".config/zed/keymap.json".source =
      config.lib.file.mkOutOfStoreSymlink
        "${config.home.homeDirectory}/.dotfiles/config/zed/keymap.json";
  };
}
