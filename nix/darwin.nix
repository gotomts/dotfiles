# nix-darwin モジュール集約点。
# flake.nix から直接 import される。
# specialArgs 由来: inputs / username / role (flake.nix から注入)
# 自動注入: pkgs / lib / config (... で受け取る)
#
# role: "default" | "sub-1"
#   - default: full app set
#   - sub-1: reduced profile (default-only パッケージを除外)
#   詳細は flake.nix の role 解決ロジック (/etc/dotfiles-role) を参照。
{ inputs, username, role, ... }:

{
  imports = [
    # cask + mas + brew。フォント/PAM/macOS defaults/IME/CLI tool/言語ランタイム/
    # running-config sync は Tier 3 で setup/*.zsh (Tier 1/2) へ移行済み。詳細は
    # docs/superpowers/specs/2026-08-22-restore-script-management-tier3-cutover-design.md
    ./modules/darwin/homebrew.nix
  ];

  # nix-darwin はデフォルトで EDITOR=nano を /etc/zshenv (set-environment) に
  # export するため、明示宣言で vim に上書きする。未宣言だと switch のたびに
  # nano に戻る (git commit 等の既定エディタが nano 化する原因だった)。
  environment.variables.EDITOR = "vim";

  # nix-darwin が要求する最低限の宣言:
  # stateVersion: 1〜maxStateVersion(6) の整数を指定する (2026-05 時点)
  # 初回インストール時のバージョンを設定し、以後変更しないこと
  system.stateVersion = 6;

  # nix-darwin の multi-user 移行に伴い、homebrew.enable 等の
  # ユーザースコープオプションは system.primaryUser で対象を明示する必要がある。
  system.primaryUser = username;

  # Determinate Nix (公式インストーラの最新版) と nix-darwin の native Nix 管理は
  # 同時稼働できないため、nix-darwin 側の管理を無効化する。有効にすると activation が
  # 以下で止まる:
  #   error: Determinate detected, aborting activation
  #   Determinate uses its own daemon to manage the Nix installation that
  #   conflicts with nix-darwin's native Nix management.
  #
  # この宣言の帰結として、/etc/nix/nix.conf は nix-darwin の管理対象から外れる
  # (nix-darwin は nix.settings 由来の設定一式を `mkIf nix.enable` で括っており、
  # off の間は nix.conf を一切生成しない)。したがって experimental-features
  # (nix-command / flakes) の所有者は Determinate 側であり、このリポジトリは
  # その値を宣言も保証もしない。Determinate を入れてあっても
  # nix-command が無効なホストは実在する。
  #
  # 契約: bare な `nix` サブコマンドを呼ぶ側が用途単位で
  # `--extra-experimental-features "nix-command flakes"` を明示する
  # (setup/cutover.zsh の pre-flight build、nix/tests/*.bats、nix/README.md の例)。
  # `darwin-rebuild` は自前で有効化して呼ぶ生成物なので明示不要。
  nix.enable = false;

  # ユーザー宣言（nix-darwin が users.users.<name> として要求する最低限の宣言）
  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };
}
