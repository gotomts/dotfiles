# nix-darwin homebrew モジュール
# Homebrew パッケージ (tap / brew / cask / mas) を宣言管理する。
#
# specialArgs 由来: inputs / username (flake.nix から注入)
# 自動注入: pkgs / lib / config (... で受け取る)
# 本モジュールでは上記引数を使用しないため { ... } で受け取る
#
# darwin.nix への配線:
#   imports = [ ./modules/darwin/homebrew.nix ];
{ ... }:

{
  homebrew = {
    enable = true;

    onActivation = {
      # 手動制御。CI 化する場合は true 検討
      autoUpdate = false;
      # 再現性確保のため upgrade は手動で実行する (brew upgrade && brew cleanup)。
      # darwin-rebuild switch のたびに全パッケージが更新される状態を避け、
      # flake.lock 哲学と整合する再現性ベースの運用に切り替える。
      upgrade = false;
      # "zap": 宣言外パッケージを Cellar ごと削除する ("uninstall" より破壊的)。
      # darwin-rebuild switch のたびに実行されるため、
      # homebrew.nix に載っていない手動インストール済みパッケージは即削除される。
      # Brewfile 廃止済み。"zap" で問題なければこのまま運用。必要に応じて "uninstall" に下げる。
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
      # nixpkgs 未収録または macOS 特殊事情で Homebrew 経由が継続必要なもの
      #
      # 除外済 (親 integration commit で削除):
      #   - jq / bats-core / pwgen / qpdf / fzf / gh / ghq / lazygit /
      #     lazydocker / kubectl / kubectx / stern / sops / grpcurl
      #     → S3 (packages.nix) で nixpkgs から提供
      #   - autoconf / automake / bison / freetype / gd / gettext /
      #     gmp / libyaml / openssl@3 / pkg-config / re2c / zlib
      #     → ビルド系。必要時は `nix shell nixpkgs#<pkg>` で一時利用 (S3 ポリシー)
      #   - mise: S7 完全削除方針
      #   - rtk: S8 flake input 化済み
      #   - mas (CLI): nixpkgs 収録済みだが現状 nix 側にも S3 不在。必要なら後付け
      # ============================================================

      # nixpkgs 未収録 (homebrew 専用 tap or macOS でのみ実用)
      "worktrunk"
      "oven-sh/bun/bun" # tap: oven-sh/bun。S3 で「S7 で確認」とした保守的残置
      "leoafarias/fvm/fvm" # tap: leoafarias/fvm
      "pipx" # nixpkgs にもあるが、Python venv 周りの ergonomics で homebrew 版を選好
      "schpet/tap/linear" # tap: schpet/tap

      # macOS 特殊事情 (システム拡張・cask 連携)
      "tailscale" # nixpkgs にもあるが macOS は cask + system extension が公式推奨
    ];

    casks = [
      # Brewfile の cask 全 25 件から font-sf-mono を除いた 24 件
      # font-sf-mono は darwin/fonts.nix (S11) で管理するため除外
      "1password"
      "amazon-photos"
      "android-studio"
      "aqua-voice" # AI 整形付き音声入力 (Claude Code への dictation 用、個人 PC のみ)
      "claude" # Anthropic Desktop app (claude-code CLI とは別)
      "claude-code"
      "cmux" # tap: manaflow-ai/cmux
      "codex-app" # OpenAI Codex デスクトップアプリ (CLI は packages.nix の codex)
      "contexts"
      "cursor"
      "docker-desktop"
      "domzilla-caffeine" # Mac をスリープさせないためのメニューバー常駐アプリ (caffeine-app.net、新版でメンテ継続中)
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
      "zed"
      "zoom"
    ];

    masApps = {
      "LINE" = 539883307;
      "Magnet" = 441258766;
      "TestFlight" = 899247664;
      "Apple Developer" = 640199958;
      "Transporter" = 1450874784;
      # Xcode は 15GB+ のため初回 darwin-rebuild switch に時間がかかる。
      # Apple ID で App Store にサインイン済みである必要がある。
      # Simulator.app は Xcode に bundled なので別途宣言不要。
      "Xcode" = 497799835;
    };
  };
}
