# nix-darwin homebrew モジュール
# Brewfile の内容を nix-darwin の homebrew オプションに移植する。
#
# extraSpecialArgs 由来: inputs / hostname / username (mkHost.nix から注入)
# 自動注入: pkgs / lib / config (... で受け取る)
#
# darwin.nix への配線:
#   imports = [ ../../modules/darwin/homebrew.nix ];
{ inputs, lib, ... }:

{
  homebrew = {
    enable = true;

    onActivation = {
      # 手動制御。CI 化する場合は true 検討
      autoUpdate = false;
      # 既存パッケージは upgrade する
      upgrade = true;
      # "zap": 宣言外パッケージを Cellar ごと削除する ("uninstall" より破壊的)。
      # Phase A 移行期は darwin-rebuild switch のたびに実行されるため、
      # homebrew.nix に載っていない手動インストール済みパッケージは即削除される。
      # 本ファイルが Brewfile の全量を網羅している前提なので実害は最小だが、
      # Phase A → Phase B (Brewfile 廃止) まで "uninstall" に下げる選択肢も検討する。
      cleanup = "zap";
    };

    taps = [
      "leoafarias/fvm"
      "manaflow-ai/cmux"
      "oven-sh/bun"
      "schpet/tap"
    ];

    brews = [
      # ============================================================
      # nixpkgs 未収録または nix で扱うのが煩雑なため Homebrew 経由を継続
      #
      # 除外方針:
      #   - S3 (packages.nix) で nix 化済みの brew は integration 時に削除
      #   - S7 (languages.nix) で nix 化済みの言語ツールも integration 時に削除
      #   - mise: S7 完全削除方針のため除外
      #   - rtk: S8 で flake input 化済みのため除外
      #   - mas (CLI): nixpkgs 収録済みのため S3 側で管理
      #
      # 不明なパッケージは保守的に残す。
      # S3/S7 結果を踏まえて親が integration 時に最終調整すること。
      # ============================================================

      # Utilities — nixpkgs 未収録または build 時依存のため残置
      "autoconf"
      "automake"
      "bison"
      "freetype"
      "gd"
      "gettext"
      "gmp"
      "jq"
      "bats-core"
      "libyaml"
      "openssl@3"
      "pkg-config"
      "re2c"
      "zlib"
      "pwgen"
      "qpdf"

      # Shell & Terminal
      "fzf"
      # mise: S7 完全削除方針のため除外

      # Git & Version Control
      "gh"
      "ghq"
      "lazygit"
      "lazydocker"
      "worktrunk"

      # Cloud & DevOps
      "kubectl"
      "kubectx"
      "stern"
      "sops"

      # Languages & Runtimes
      "oven-sh/bun/bun" # tap: oven-sh/bun
      "leoafarias/fvm/fvm" # tap: leoafarias/fvm
      "pipx"

      # Network & API
      "grpcurl"
      "tailscale"

      # Task Management
      "schpet/tap/linear" # tap: schpet/tap

      # AI Tooling
      # rtk: S8 で flake input 化済みのため除外
    ];

    casks = [
      # Brewfile の cask 全 25 件から font-sf-mono を除いた 24 件
      # font-sf-mono は darwin/fonts.nix (S11) で管理するため除外
      "1password"
      "amazon-photos"
      "android-studio"
      "claude-code"
      "cmux" # tap: manaflow-ai/cmux
      "contexts"
      "cursor"
      "docker-desktop"
      "dropbox"
      "figma"
      "flutter"
      "gcloud-cli"
      "google-chrome"
      "google-japanese-ime"
      "linear-linear"
      "medis"
      "notion"
      "orbstack"
      "postman"
      "raycast"
      "slack"
      "tableplus"
      "visual-studio-code"
      "zoom"
    ];

    masApps = {
      "LINE" = 539883307;
      "Magnet" = 441258766;
      "TestFlight" = 899247664;
      "Apple Developer" = 640199958;
      "Transporter" = 1450874784;
    };
  };
}
