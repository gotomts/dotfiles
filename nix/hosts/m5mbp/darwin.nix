# ホスト m5mbp の nix-darwin モジュール集約点。
# mkHost.nix から直接 import される（default.nix 中間層は不使用）。
# extraSpecialArgs 由来: inputs / hostname / username (mkHost.nix から注入)
# 自動注入: pkgs / lib / config (... で受け取る)
{ inputs, hostname, username, ... }:

{
  # S3-S11 で nix-darwin モジュールを追加する際は ここに imports を列挙する。
  # 例: imports = [ ../../modules/darwin/homebrew.nix ];

  # nix-darwin が要求する最低限の宣言:
  # stateVersion: 1〜maxStateVersion(6) の整数を指定する (2026-05 時点)
  # 初回インストール時のバージョンを設定し、以後変更しないこと
  system.stateVersion = 6;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # ユーザー宣言（home-manager から参照される）
  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };
}
