# ホスト m5mbp の home-manager モジュール集約点。
# mkHost.nix から直接 import される（default.nix 中間層は不使用）。
# extraSpecialArgs 由来: inputs / hostname / username (mkHost.nix から注入)
# 自動注入: pkgs / lib / config (... で受け取る)
{ inputs, hostname, username, ... }:

{
  # S3-S7 で home-manager モジュールを追加する際はここに imports を列挙する。
  # 例: imports = [ ../../modules/home/packages.nix ];

  home.username = username;
  home.homeDirectory = "/Users/${username}";
  # home-manager 25.11 (nixpkgs-unstable との組み合わせ) の stateVersion
  home.stateVersion = "25.11";
}
