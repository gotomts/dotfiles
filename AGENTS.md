# リポジトリ構造

このリポジトリは macOS の開発環境を再現するための dotfiles である。

- `aliase/` — 外部シェルスクリプト（エイリアスから呼び出される）
- `claude/` — Claude Code 設定（`~/.claude/` にシンボリックリンク）
- `claude/hooks/` — Claude Code フックスクリプト群（PreCompact / SessionStart / UserPromptSubmit）
- `claude/agents/` — マルチエージェント開発用サブエージェント定義（developer × 10 / reviewer × 3 / pr-publisher × 1 = 14 体。`~/.claude/agents/` にシンボリックリンク）
- `claude/RTK.md` — rtk (Rust Token Killer) 用ガイドライン。`claude/CLAUDE.md` から `@RTK.md` で取り込まれる
- `config/` — アプリケーション設定（starship, yazi, cmux）（`~/.config/` にシンボリックリンク）
- `docs/` — 設計ドキュメント・実装プラン（シンボリックリンク対象外）
- `functions/` — zsh カスタム関数（`~/.functions/` にシンボリックリンク）
- `gitconfig` — Git 設定（`~/.gitconfig` にシンボリックリンク）
- `gitignore_global` — グローバル gitignore（`~/.gitignore_global` にシンボリックリンク）
- `grip/` — grip 設定（`~/.grip/` にシンボリックリンク）
- `nix/` — nix-darwin + home-manager + flakes による環境構築定義（`darwin-rebuild` から参照される。詳細は `nix/README.md`）
- `ssh/` — SSH 設定（`~/.ssh/` にシンボリックリンク）
- `zsh/` — zsh 補完ファイル（`~/.zsh/` にシンボリックリンク）
- `zshrc` — zsh 設定（`~/.zshrc` にシンボリックリンク）
- `zshenv` — zsh 環境変数（`~/.zshenv` にシンボリックリンク）

# シンボリックリンク管理

シンボリックリンクは home-manager (`nix/modules/home/`) で管理する。新規 dotfiles は `nix/modules/home/` 以下で宣言すること。

# Homebrew パッケージ管理

- パッケージの追加・削除は `nix/modules/darwin/homebrew.nix` で管理する
- `default` role の手動 `brew install` は禁止（switch 時に zap される）
- `sub-1` role は手動 `brew install` 許容（cleanup = "none"）。ただし別 PC では復元されないため、再現性が必要なら `homebrew.nix` に追記する
- `homebrew.nix` は role 別 declarative セットの宣言。`Brewfile` は削除済み (DOT-29)
- 既存のパッケージのみを対象とする。ユーザーが明示的に依頼していないパッケージを追加しない
- `taps` / `brews` / `casks` / `masApps` の区分を守る
- nixpkgs 収録済みのパッケージは原則 `nix/modules/home/packages.nix` に置き、Homebrew は nixpkgs 未収録または macOS 特殊事情のあるものに限定する

# zsh スクリプト規約

- シバンは `#!/bin/zsh` を使用する
- 環境変数の参照は `${VAR}` 形式で統一する（`$VAR` ではなく）
- パスの参照には `${HOME}` を使用する（`~` ではなく）

# Claude Code 設定

- `claude/` 配下のファイルは home-manager (`nix/modules/home/claude.nix`) により `~/.claude/` にシンボリックリンクされる
- `claude/CLAUDE.md` はグローバル CLAUDE.md である。プロジェクト固有のルールはここに書かない
- `claude/settings.json` は全プロジェクト共通の設定（パーミッション、プラグイン、フック等）を管理する
- `claude/skills/` にはカスタムスキルを配置する
- `claude/hooks/` 配下のフックスクリプトは PreCompact で未 handover 時のコンパクトをブロックし、SessionStart / UserPromptSubmit で未消費メモを Claude に通知する
- `claude/RTK.md` は rtk (Rust Token Killer) のガイドライン。`claude/CLAUDE.md` 末尾の `@RTK.md` で取り込まれ、`claude/settings.json` の `PreToolUse: Bash` matcher に追加した `rtk hook claude` と連動して Bash 出力を圧縮する。rtk 本体は nix overlay (`nix/modules/overlays/rtk.nix`) 経由でビルドされ、`darwin-rebuild switch` で各 PC に展開される。PC ローカルな `~/Library/Application Support/rtk/filters.toml` は初回フック実行時に自動生成される。フック順序は「破壊的コマンドブロック → rtk hook」で、`rm -rf` / `git push --force` 等が rtk のリライトを通過する前に exit 2 で止まる

# Nix 環境

`~/.dotfiles/nix/` 配下で nix-darwin + home-manager + flakes による宣言的環境構築を行う。詳細手順は `nix/README.md` を参照。

## 主要コマンド

```sh
cd ~/.dotfiles/nix

# 副作用なしビルド確認 (CI と同じ検証を手元で)
USER=ciuser nix build .#darwinConfigurations.default.system --no-link --impure

# 適用 (sudo 必須、USER=$USER は sudo の env_reset で USER=root になるのを回避、--impure は username 動的解決のため必須)
sudo USER=$USER darwin-rebuild switch --flake .#default --impure

# 直前世代に戻す
sudo darwin-rebuild switch --rollback

# 世代一覧
darwin-rebuild --list-generations
```

## 重要な設計判断

- **`nix.enable = false`**: ローカル PC に Determinate Nix がインストールされている前提。nix-darwin の native Nix 管理は Determinate daemon と競合するため、`nix/darwin.nix` で明示的に無効化している。実験的機能 (nix-command / flakes) は Determinate がデフォルト有効化しているため別途宣言不要
- **PC 名・ユーザー名のリポジトリ非格納**: `darwinConfigurations.default` で output 名を hostname フリーに固定し、`username = builtins.getEnv "USER"` で macOS ローカルアカウント名を実行時解決する。公開リポジトリに PC 名や個人アカウント名を晒さないための設計。`--impure` フラグが必須になる代償と引き換え (S15)
- **`homebrew.onActivation.cleanup = "zap"`**: 宣言外パッケージは Cellar ごと削除する強い管理。宣言外のパッケージが残らないよう破壊的に同期する (`nix/modules/darwin/homebrew.nix` のコメント参照)
- **`rtk` overlay**: `flake.nix` の `rtk-src` input から `rustPlatform.buildRustPackage` でビルド。`nix/modules/overlays/rtk.nix` で `pkgs.rtk` として供給され、`home/packages.nix` から参照される

## 棚卸 → triage → 翻訳ワークフロー (S10)

macOS の `defaults` 値を `defaults.nix` に翻訳するための人間 in-the-loop プロセス:

1. `zsh nix/scripts/inventory.zsh` を実行 → `docs/inventory/<hostname>-<date>.md` 生成 (READ-ONLY)
2. 生成された Markdown を開き、各項目に `nix化 / 無視 / 検討` をマーク
3. triage 結果を `nix/modules/darwin/defaults.nix` に翻訳 (`nix/darwin.nix` から import)
4. `nix build` で検証 → `darwin-rebuild switch` で適用

triage で「無視」マークした項目は OS デフォルト値が PC 間で異なる可能性があるため、複数 PC で運用する場合は PC 別に再評価する必要がある。

## CI 検証 (`nix-check` workflow)

`.github/workflows/nix-check.yml` で PR ごとに以下を検証する:

- `nix flake check` (構文・型・依存解決)
- `USER=ciuser nix build .#darwinConfigurations.default.system --no-link --impure` (closure ビルド)

`darwin-rebuild switch` の activation 自体は CI 範囲外 (環境差で消耗するため)。実機での `darwin-rebuild build` → `switch` で検証する方針。

# AGENTS.md の自己更新

- リポジトリに新しいディレクトリやファイルを追加した場合、「リポジトリ構造」セクションを更新すること
- 新しい運用ルールが生じた場合、該当するセクションに追記するか、新しいセクションを作成すること
- 更新はユーザー承認後に行うこと

# General Instructions

- ユーザーが内容をそのまま維持する、または最小限の編集を求めた場合、指示通りに行うこと。周囲の内容を書き換えたり、補足したり、構造を変更しない
- ユーザーがアプローチを修正した場合や仮説を却下した場合、即座に受け入れて次に進むこと。却下されたアプローチを再提案したり、ユーザーが存在しないと言ったものを探し続けない

# Git Conventions

- コミットは常に新規作成すること。`--amend` や squash はユーザーが明示的に指示した場合のみ使用する
- 共有ブランチで `--amend` と `--force-push` を明示的な許可なく併用しない
- 変更を行う前に、正しいブランチ・正しいリポジトリにいることを確認すること。推測せず `git branch` と `git remote -v` で検証する

# TypeScript

- このプロジェクトでは `exactOptionalPropertyTypes` を含む strict 設定の TypeScript を使用する。型エラーを修正する際は、まず `tsconfig.json` を読み、strict フラグを考慮した上で解決策を提案すること

# Code Style & Conventions

- コミットメッセージのプレフィックス、コードスタイル、パターンは既存のプロジェクト規約に従うこと。`Co-Authored-By` ヘッダー、他で使われていないランタイム型チェック、確立されたパターンからの逸脱を確認なしに追加しない
