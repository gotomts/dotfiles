# nix/modules/home/ghostty.nix
#
# ghostty のターミナル設定。
# ~/.config/ghostty/config を nix store 経由ではなくリポジトリの実ファイルへ
# out-of-store symlink する。これにより config/ghostty/config を編集すると
# darwin-rebuild switch なしで反映される (ghostty 側は自動リロードしないため、
# 反映には ghostty のウィンドウで Cmd+Shift+, の Reload Config が必要)。
#
# ghostty 本体は homebrew cask (homebrew.nix) で導入するため
# programs.ghostty は使わない (nix パッケージの重複導入を回避)。
{ config, ... }:

{
  home.file.".config/ghostty/config".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/.dotfiles/config/ghostty/config";
}
