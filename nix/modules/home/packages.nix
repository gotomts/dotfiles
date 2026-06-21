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
    jujutsu # コマンド名は jj。Git 互換の DVCS
    jjui # jujutsu (jj) の TUI
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

    # devbox: プロジェクトごとの言語バージョン管理 (Nix 上の wrapper)。
    # `devbox add nodejs@18` 等のワンライナーで mise / asdf 相当の UX を提供する。
    # 役割分担: グローバル言語ランタイムは languages.nix / プロジェクト固有は devbox。
    # 使い方は nix/README.md の「プロジェクトごとの言語バージョン管理 (devbox)」節を参照。
    devbox

    # -------------------------------------------------------------------------
    # Network & API
    # -------------------------------------------------------------------------
    grpcurl
    # tailscale: CLI のみ運用に切り替え済み。darwin/homebrew.nix の brews に
    #   formula で残置 (旧 tailscale-app cask は廃止)。nixpkgs 版は macOS 向け
    #   tailscaled LaunchDaemon の起動ラッパが整備されていないため採用しない

    # -------------------------------------------------------------------------
    # Task Management
    # -------------------------------------------------------------------------
    # linear (schpet/tap): nixpkgs 未収録のため darwin/homebrew.nix (S9) 残置

    # -------------------------------------------------------------------------
    # AI Tooling
    # -------------------------------------------------------------------------
    # codex: nixpkgs 版 (v0.130.0) が cache.nixos.org に未登録で CI の closure
    # build が毎回 Rust ソースビルドして 20m timeout になったため、Homebrew cask
    # "codex" (OpenAI 公式 prebuilt binary) に移行した。

    # agent-browser: AI エージェント向けブラウザ自動化 CLI (Rust)。claude/skills/
    # agent-browser の stub スキルが実体を `agent-browser skills get core` で配信する
    # 前提のため CLI 本体が必要。nixpkgs 版はバイナリが cache.nixos.org 登録済みのため
    # codex のような CI ソースビルド timeout は起きない。nixpkgs はやや版ラグあり
    # (収録 0.25.x / upstream 0.28.x) だが、CLI が install 版と整合した skill 内容を
    # 配信する設計のため機能上の陳腐化は起きない。最新追従が要るなら Homebrew へ切替検討。
    agent-browser
  ];
}
