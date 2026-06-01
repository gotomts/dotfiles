# home-manager モジュール: 言語ランタイム + 開発ツールチェーン
#
# 移行元: setup/install/{04_node,05_go,06_ruby,07_rust,08_python,09_dart}.zsh (削除済み) で
# mise 経由でインストールしていたグローバルランタイムを nix に完全移管した。
#
# mise は Brewfile から外す方針 (本 sub-issue で削除)。
# プロジェクトローカルの mise 設定 (.mise.toml) は引き続き利用可能だが、
# グローバルランタイムの管理はこのモジュールで完結させる。
#
# pkgs は flake.nix で宣言済みの nixpkgs-unstable を参照 (mkHost.nix 経由で注入)。
# fenix overlay (nightly/beta Rust toolchain) は flake input 追加が必要なため、
# 本 sub-issue のスコープ外 (flake.nix 変更禁止制約)。
# Phase B または別 sub-issue で fenix overlay 移行を検討すること。
{ pkgs, ... }:

{
  home.packages = with pkgs; [

    # ===========================================================================
    # Node.js
    # ===========================================================================
    # グローバル: Node.js 24 LTS (2025-10-28 以降の Active LTS)。
    # 22 LTS は 2024-10-29 〜 2025-10-28 が Active LTS で、現在 (2026-05) は
    # Maintenance LTS フェーズ。グローバルは Active LTS を追従する方針。
    #
    # プロジェクトごとに別バージョンを使いたい場合は devbox を利用する
    # (mise / asdf 相当のワンライナー UX を Nix 上で提供する wrapper)。
    # 例: `devbox init && devbox add nodejs@18 && devbox generate direnv`
    # 詳細は nix/README.md の「プロジェクトごとの言語バージョン管理 (devbox)」節を参照。
    nodejs_24

    # pnpm / yarn: nixpkgs の固定版パッケージは使わず、nodejs_24 同梱の corepack で
    # グローバル供給する (プロジェクトの package.json packageManager 宣言を優先)。
    # 設定は corepack.nix を参照。
    # npm-fzf: nixpkgs 未収録のため Brewfile (S9 homebrew.nix) 残置 or `npm i -g npm-fzf` で対応

    # ===========================================================================
    # Go
    # ===========================================================================
    # 現状: mise install go@1.18.1 / 1.19.4 / 1.19.13 / latest
    #       mise use --global go@latest
    #
    # nixpkgs-unstable の go は最新安定版を追従する。
    # 旧バージョンが必要な場合は go_1_21 / go_1_22 等のバージョン固定パッケージを参照。
    go

    # ===========================================================================
    # Ruby
    # ===========================================================================
    # 現状: mise install ruby@3.2.2 / latest
    #       mise use --global ruby@latest
    #       gem install bundler cocoapods fastlane
    #
    # ruby_3_4 は nixpkgs-unstable に収録済み (2025 年 5 月現在の最新安定版)。
    # ruby_3_3 との選定理由: 3.4 は 2024 年 12 月リリースで安定し、
    # nixpkgs-unstable の default ruby も 3.3 → 3.4 に移行中。
    #
    # NOTE: bundler / cocoapods / fastlane は gem install で管理していたが、
    #       nix では ruby.gems.bundler 等を使うか、bundler を PATH に入れる方法がある。
    #       cocoapods / fastlane は macOS 依存が強いため S9 homebrew.nix または
    #       gem install で引き続き管理することを推奨。
    ruby_3_4

    # ===========================================================================
    # Rust (nixpkgs の rustc + cargo)
    # ===========================================================================
    # 現状: mise install rust@stable
    #       rustup component add rust-analyzer rustfmt clippy
    #       cargo install --locked cargo-nextest cargo-watch
    #
    # fenix overlay を使うと nightly / beta / stable channel を柔軟に切り替えられるが、
    # flake.nix に input 追加が必要 (本 sub-issue スコープ外)。
    # nixpkgs の rustc + cargo は stable channel に相当し、日常開発では十分。
    # Phase B / 別 sub-issue で fenix overlay 移行を検討すること。
    rustc
    cargo
    rust-analyzer
    rustfmt
    clippy

    # cargo install 相当 (nixpkgs に収録されているためビルド不要)
    cargo-nextest  # 高速テストランナー
    cargo-watch    # ファイル変更時の自動再実行

    # ===========================================================================
    # Python
    # ===========================================================================
    # 現状: mise install python@3.12.1 / latest
    #       mise use --global python@latest
    #       pipx install poetry==1.2.0
    #
    # python313 は nixpkgs-unstable に収録済み (2025 年 5 月現在の最新安定版)。
    # python312 との選定理由: 3.13 は 2024 年 10 月リリースで本番採用が進んでいる。
    # 既存スクリプトが python@3.12.1 を入れており、3.13 との互換性リスクがある場合は
    # python312 に戻すこと。
    #
    # NOTE: pipx は nixpkgs に収録されているが、poetry が nixpkgs に直接入るため不要。
    python313

    # pipx install poetry==1.2.0 の代替 (nixpkgs の poetry は最新安定版)
    poetry

    # pipx install grip (GitHub Readme Instant Preview) の代替。
    # nixpkgs では python3Packages.grip として収録 (joeyespo/grip v4.6.1)。
    # pkgs.grip トップレベルは GTK CD プレイヤーで別物のため注意。
    python3Packages.grip

    # ===========================================================================
    # Dart
    # ===========================================================================
    # 現状: 09_dart.zsh: dart pub global activate flutterfire_cli
    #       Brewfile: leoafarias/fvm/fvm (tap 経由), cask 'flutter'
    #
    # nixpkgs-unstable v3.11.4 時点で aarch64-darwin 対応済み (meta.platforms に明記)。
    # Flutter SDK は引き続き Brewfile (cask 'flutter') / S9 homebrew.nix で管理。
    # fvm (Flutter Version Manager) は nixpkgs 未収録のため Brewfile (S9 homebrew.nix) 残置。
    dart
    # fvm: nixpkgs 未収録のため Brewfile (S9 homebrew.nix) 残置

  ];
}
