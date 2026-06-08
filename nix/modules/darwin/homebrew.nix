# nix-darwin homebrew モジュール
# Homebrew パッケージ (tap / brew / cask / mas) を宣言管理する。
#
# specialArgs 由来: role (flake.nix から注入。"default" | "sub-1")
# 自動注入: pkgs / lib / config (... で受け取る)
#
# darwin.nix への配線:
#   imports = [ ./modules/darwin/homebrew.nix ];
#
# role 別構造:
#   core*           両方の role に入れる共通セット
#   defaultOnly*    role == "default" のときだけ追加するセット
#   sub-1 は今のところ "core のみ" の reduced profile。
#   後で sub-1 専用パッケージが必要になったら lib.optionals (role == "sub-1") で追加。
{ role, lib, ... }:

let
  # ----------------------------------------------------------------
  # casks: GUI アプリケーション
  # ----------------------------------------------------------------
  # core (両 role 共通)
  coreCasks = [
    "1password"
    "claude" # Anthropic Desktop app (claude-code CLI とは別)
    "claude-code"
    "cmux" # tap: manaflow-ai/cmux
    "coderabbit" # AI コードレビュー CLI (cask だが Binary artifact。`coderabbit` コマンド。公式 homebrew-cask なので tap 不要)
    "codex" # OpenAI Codex CLI (公式 prebuilt binary; nixpkgs 版が cache.nixos.org 未登録で CI timeout したため移行)
    "codex-app" # OpenAI Codex デスクトップアプリ (CLI は同 casks の codex で管理)
    "contexts"
    "cursor"
    "domzilla-caffeine" # Mac をスリープさせないためのメニューバー常駐アプリ (caffeine-app.net、新版でメンテ継続中)
    "dropbox"
    "figma"
    "gcloud-cli"
    "google-chrome"
    "google-japanese-ime"
    "imageoptim" # 一眼カメラ等の JPG/PNG 一括圧縮 GUI (MozJPEG / pngquant 等を内部で自動選択。初回は Preferences で Quality を 80〜85 に下げると削減率が上がる)
    "linear" # 旧 linear-linear、Homebrew で rename 済み
    "medis"
    "nani" # jp.kiok.nani — 公式 cask (brew install --cask nani)
    "notion"
    "orbstack" # 軽量 Docker 代替 (docker-desktop は削除済み)
    "postman"
    "raycast"
    "slack"
    "tableplus"
    "visual-studio-code"
    "zed"
    "zoom"
  ];

  # default-only casks (role == "default" のときだけ)
  defaultOnlyCasks = [
    "amazon-photos"
    "android-studio"
    "aqua-voice" # AI 整形付き音声入力 (Claude Code への dictation 用)
    "flutter"
    "obsidian"
    "tailscale-app" # 旧 cask 名 "tailscale" は rename 済み。kernel extension 承認が初回必要 (System Settings → Privacy & Security)
  ];

  # ----------------------------------------------------------------
  # masApps: Mac App Store アプリ
  # ----------------------------------------------------------------
  # core (両 role 共通)
  coreMasApps = {
    "Magnet" = 441258766;
    # Xcode は 15GB+ のため初回 darwin-rebuild switch に時間がかかる。
    # Apple ID で App Store にサインイン済みである必要がある。
    # Simulator.app は Xcode に bundled なので別途宣言不要。
    "Xcode" = 497799835;
  };

  # default-only masApps (role == "default" のときだけ)
  defaultOnlyMasApps = {
    "LINE" = 539883307;
    "TestFlight" = 899247664;
    "Apple Developer" = 640199958;
    "Transporter" = 1450874784;
  };

  # ----------------------------------------------------------------
  # brews: CLI (nixpkgs 未収録 / macOS 特殊事情)
  # ----------------------------------------------------------------
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

  # core (両 role 共通)
  coreBrews = [
    "worktrunk"
    "oven-sh/bun/bun" # tap: oven-sh/bun。S3 で「S7 で確認」とした保守的残置
    "pipx" # nixpkgs にもあるが、Python venv 周りの ergonomics で homebrew 版を選好
    "schpet/tap/linear" # tap: schpet/tap
  ];

  # default-only brews (role == "default" のときだけ)
  defaultOnlyBrews = [
    "leoafarias/fvm/fvm" # Flutter Version Manager (flutter cask に同期)
  ];

in
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
      # role 別 cleanup ポリシー:
      #   default: "zap" — 宣言外パッケージを Cellar ごと削除。declarative 厳格運用
      #   sub-1:   "none" — 何も削除しない。手動 brew install / 手動 MAS app 等を保護
      # sub-1 で手動 install したものは別 PC では復元されないため、再現性が必要なら
      # homebrew.nix に追記する運用 (AGENTS.md「Homebrew パッケージ管理」参照)。
      cleanup = if role == "sub-1" then "none" else "zap";
      # Homebrew 5.x 以降、`brew bundle --cleanup` は確認を要求するようになり
      # (--force / --force-cleanup / $HOMEBREW_ASK のいずれか必須)、非対話の
      # darwin-rebuild switch では activation が失敗する。zap (default role) の
      # 非対話 cleanup を維持するため --force-cleanup を付与する。cleanup="none" の
      # sub-1 では --cleanup 自体が出ないため付与しない。
      extraFlags = lib.optionals (role != "sub-1") [ "--force-cleanup" ];
    };

    taps = [
      "leoafarias/fvm"
      "manaflow-ai/cmux"
      "oven-sh/bun"
      "schpet/tap"
    ];

    brews = coreBrews ++ lib.optionals (role == "default") defaultOnlyBrews;

    casks = coreCasks ++ lib.optionals (role == "default") defaultOnlyCasks;

    masApps = coreMasApps // lib.optionalAttrs (role == "default") defaultOnlyMasApps;
  };
}
