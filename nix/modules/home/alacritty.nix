# nix/modules/home/alacritty.nix
#
# alacritty のターミナル設定。
# alacritty の live_config_reload (デフォルト有効) を活かすため、
# ~/.config/alacritty/alacritty.toml を nix store 経由ではなく
# リポジトリの実ファイルへ out-of-store symlink する。
# これにより config/alacritty/alacritty.toml を編集すると、
# darwin-rebuild switch なしで開いているウィンドウに即反映される。
#
# alacritty 本体は homebrew cask (homebrew.nix) で導入するため
# programs.alacritty は使わない (nix パッケージの重複導入を回避)。
{ config, ... }:

{
  home.file.".config/alacritty/alacritty.toml".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/.dotfiles/config/alacritty/alacritty.toml";
}
