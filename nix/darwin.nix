# nix-darwin モジュール集約点。
# flake.nix から直接 import される。
# specialArgs 由来: inputs / username (flake.nix から注入)
# 自動注入: pkgs / lib / config (... で受け取る)
{ inputs, username, ... }:

{
  imports = [
    # cask + mas + 例外 brew (S9 / KISSA-29)
    ./modules/darwin/homebrew.nix
    # pmset NOPASSWD (S11 / KISSA-31)
    ./modules/darwin/sudoers.nix
    # SF Mono 等 (S11)。空リストで雛形のみ
    ./modules/darwin/fonts.nix
    # Touch ID for sudo (S11)
    ./modules/darwin/pam.nix
    # S10 (defaults.nix) は棚卸 triage 完了後に追加
    # ./modules/darwin/defaults.nix
  ];

  # nix-darwin が要求する最低限の宣言:
  # stateVersion: 1〜maxStateVersion(6) の整数を指定する (2026-05 時点)
  # 初回インストール時のバージョンを設定し、以後変更しないこと
  system.stateVersion = 6;

  # nix-darwin の multi-user 移行に伴い、homebrew.enable 等の
  # ユーザースコープオプションは system.primaryUser で対象を明示する必要がある。
  system.primaryUser = username;

  # Determinate Nix (公式インストーラの最新版) と nix-darwin の native Nix 管理は
  # 同時稼働できないため、nix-darwin 側の管理を無効化する。
  # Determinate Nix は nix-command / flakes をデフォルトで有効化済みなので、
  # 旧来の `nix.settings.experimental-features` 宣言は不要。
  #
  # 本修正は CI 検証 (S14) で `darwin-rebuild switch` が以下のエラーで失敗した
  # ことから発見した本番ブロッカー:
  #   error: Determinate detected, aborting activation
  #   Determinate uses its own daemon to manage the Nix installation that
  #   conflicts with nix-darwin's native Nix management.
  nix.enable = false;

  # ユーザー宣言（home-manager から参照される）
  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };

  # rtk overlay 適用 (S8 / KISSA-28)
  # inputs.rtk-src を取得して pkgs.rtk として供給。home/packages.nix から参照可。
  nixpkgs.overlays = [
    (import ./modules/overlays/rtk.nix { inherit inputs; })
  ];
}
