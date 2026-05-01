# nix/modules/home/packages.nix
#
# CLI ツール群を home.packages として宣言する home-manager モジュール。
# home.nix の imports に追加することで有効化される（S3 integration commit で配線）。
#
# 自動注入: pkgs / lib / config (... で受け取る)
{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # -------------------------------------------------------------------------
    # Utilities
    # -------------------------------------------------------------------------
    # autoconf / automake / bison / freetype / gd / gettext / gmp / libyaml /
    # openssl@3 / pkg-config / re2c / zlib はビルド系ツールのため home.packages
    # には含めない。必要な場合は `nix shell nixpkgs#<pkg>` で一時利用する。
    jq
    bats       # Brewfile: bats-core（nixpkgs では bats）
    pwgen
    qpdf

    # -------------------------------------------------------------------------
    # Shell & Terminal
    # -------------------------------------------------------------------------
    # mise は S7 で削除予定のため S3 では含めない（Brewfile 残置）
    fzf

    # -------------------------------------------------------------------------
    # Git & Version Control
    # -------------------------------------------------------------------------
    gh
    ghq
    lazygit
    lazydocker
    # worktrunk: nixpkgs 未収録のため darwin/homebrew.nix (S9) 残置

    # -------------------------------------------------------------------------
    # Cloud & DevOps
    # -------------------------------------------------------------------------
    kubectl
    kubectx
    stern
    sops

    # -------------------------------------------------------------------------
    # Languages & Runtimes
    # -------------------------------------------------------------------------
    # bun: nixpkgs にも bun は存在する。oven-sh/bun tap 版とのバージョン追跡方針差を
    #   S7 で確認するまで Brewfile 残置（保守的判断）。
    # fvm (leoafarias/fvm): nixpkgs 未収録のため darwin/homebrew.nix (S9) 残置
    # pipx: S7 / homebrew 残置検討のため S3 では含めない（Brewfile 残置）

    # -------------------------------------------------------------------------
    # Network & API
    # -------------------------------------------------------------------------
    grpcurl
    # tailscale: macOS ではシステム拡張 + Cask 経由が推奨のため
    #   darwin/homebrew.nix (S9) 残置。nixpkgs に存在はするが
    #   tailscaled デーモンの管理方式が homebrew cask と異なるため除外

    # -------------------------------------------------------------------------
    # Task Management
    # -------------------------------------------------------------------------
    # linear (schpet/tap): nixpkgs 未収録のため darwin/homebrew.nix (S9) 残置

    # -------------------------------------------------------------------------
    # AI Tooling
    # -------------------------------------------------------------------------
    # rtk: nixpkgs 未収録のため darwin/homebrew.nix (S9) 残置
  ];
}
