{ inputs, pkgs, ... }:

{
  programs.starship = {
    enable = true;
    # 既存の starship.toml を builtins.fromTOML で直接読み込む。
    # TOML の構造をそのまま Nix 属性に変換するため手動変換は不要。
    settings = builtins.fromTOML (builtins.readFile ../../../config/starship/starship.toml);
  };
}
