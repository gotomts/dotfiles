{ inputs, hostname, username, ... }:

{
  # S3-S11 で各種モジュールを import していく。
  # imports = [ ../../modules/darwin/homebrew.nix ];

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
