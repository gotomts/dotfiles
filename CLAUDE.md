# リポジトリ構造

このリポジトリは macOS の開発環境を再現するための dotfiles である。

- `aliases` — シェルエイリアス定義（`~/.aliases` にシンボリックリンク）
- `aliase/` — 外部シェルスクリプト（エイリアスから呼び出される）
- `Brewfile` — Homebrew パッケージ定義（Phase A 期間中は読み取り専用バックアップ、Phase B で削除予定）
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
- `nix/` — nix-darwin + home-manager + flakes による環境構築定義（Phase A の主管理対象。`darwin-rebuild` から参照される。詳細は `nix/README.md`）
- `setup/` — セットアップスクリプト群（シンボリックリンク対象外。Phase B で home-manager へ完全移行後に削除予定）
- `ssh/` — SSH 設定（`~/.ssh/` にシンボリックリンク）
- `zsh/` — zsh 補完ファイル（`~/.zsh/` にシンボリックリンク）
- `zshrc` — zsh 設定（`~/.zshrc` にシンボリックリンク）
- `zshenv` — zsh 環境変数（`~/.zshenv` にシンボリックリンク）

# シンボリックリンク管理

- **Phase A 期間中の方針**: 新規 dotfiles は `nix/modules/home/` 以下で home-manager 管理に倒す。`setup/setup.zsh` の symlink ループはレガシー扱い (Phase B で削除予定)
- `setup/setup.zsh` がリポジトリルートのファイル/ディレクトリを `~/.${name}` にシンボリックリンクする
- 以下はシンボリックリンク対象外として除外されている: `setup`, `README.md`, `ssh`, `claude`, `CLAUDE.md`, `docs`, `nix`
- `ssh/` と `claude/` は専用ループで個別にシンボリックリンクされる
- ルートにファイルやディレクトリを追加する場合、シンボリックリンクが不要なものは `setup.zsh` の除外条件に追加すること

# Brewfile

- **Phase A 注記**: `Brewfile` は読み取り専用バックアップとして残し、cask / mas / 例外 brew は `nix/modules/darwin/homebrew.nix` で管理する。**Brewfile を変更したら同 PR で `homebrew.nix` も更新すること**（CI の `nix-check` で drift 検知される）。Phase B で `Brewfile` 自体を削除予定
- パッケージの追加・削除は Brewfile のみで管理する。手動の `brew install` は禁止
- 既存のパッケージのみを対象とする。ユーザーが明示的に依頼していないパッケージを追加しない
- セクションコメント（`# Utilities`, `# Shell & Terminal` 等）に従って適切な位置に追記する
- `tap`, `brew`, `cask`, `mas` の区分を守る
- `# AI Tooling` セクション: AI/LLM ワークフロー用の CLI ツール（rtk 等）を配置する

# zsh スクリプト規約

- シバンは `#!/bin/zsh` を使用する
- setup/ 配下のスクリプトは既存の `util.zsh`（`util::confirm`, `util::info` 等）を利用する
- 環境変数の参照は `${VAR}` 形式で統一する（`$VAR` ではなく）
- パスの参照には `${HOME}` を使用する（`~` ではなく）
- install スクリプトのファイル名は `XX_name.zsh`（XX は連番）の命名規則に従う

# Claude Code 設定

- `claude/` 配下のファイルは `setup.zsh` により `~/.claude/` にシンボリックリンクされる
- `claude/CLAUDE.md` はグローバル CLAUDE.md である。プロジェクト固有のルールはここに書かない
- `claude/settings.json` は全プロジェクト共通の設定（パーミッション、プラグイン、フック等）を管理する
- `claude/skills/` にはカスタムスキルを配置する
- `claude/skills/handover/` は引き継ぎメモ管理スキル。`/handover` 実行で `~/.claude/handover/{project-hash}/{branch}/{fingerprint}/` 配下に `state.json` と `handover.md` を生成する
- `claude/skills/feature-team/` はマルチエージェント・フィーチャー開発オーケストレーションスキル。Phase 1〜6 の進行（brainstorming → writing-plans → create-issue → 並列実装 → 観点別レビュー → pr-publisher 並列起動）を制御する。`SKILL.md` / `README.md`（保守者向け俯瞰）/ `roles/_common.md`（子注入用プロトコル）/ `roles/parent.md`（親判断ガイド）で構成
- `claude/skills/create-issue/` は spec/plan を入力に Linear / GitHub の親 Issue + sub-issue を自律登録するスキル。引数 `<spec-path> <plan-path>` で受け取り、tracker は `.claude/project.yml` の `tracker.type` から自己解決する。`feature-team` Phase 2 から呼ばれる前提
- `claude/skills/pick-next/` は「次に何をやるか」を対話で決定するスキル。既存 active issue（Linear / GitHub）の優先度推奨と、新規テーマの 3 軸スコア比較を統合し、結果に応じて Issue 作成・既存 Issue 選定・保留の 3 分岐に振り分ける。`linear-next` の機能を内包しており、安定後に `linear-next` は削除予定
- `claude/hooks/` 配下のフックスクリプトは PreCompact で未 handover 時のコンパクトをブロックし、SessionStart / UserPromptSubmit で未消費メモを Claude に通知する
- `claude/RTK.md` は rtk (Rust Token Killer) のガイドライン。`claude/CLAUDE.md` 末尾の `@RTK.md` で取り込まれ、`claude/settings.json` の `PreToolUse: Bash` matcher に追加した `rtk hook claude` と連動して Bash 出力を圧縮する。各 PC への展開は `brew bundle` + `setup.zsh` で完結し、PC ローカルな `~/Library/Application Support/rtk/filters.toml` は初回フック実行時に自動生成される。フック順序は「破壊的コマンドブロック → rtk hook」で、`rm -rf` / `git push --force` 等が rtk のリライトを通過する前に exit 2 で止まる

# Nix 環境 (Phase A)

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
- **`homebrew.onActivation.cleanup = "zap"`**: 宣言外パッケージは Cellar ごと削除する強い管理。Brewfile 由来の旧パッケージが残らないよう破壊的に同期する。Phase A 移行期はリスクを認識した上で運用する (`nix/modules/darwin/homebrew.nix` のコメント参照)
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

## Phase A → Phase B

Phase A は **並存期間** (Brewfile / setup.zsh / nix の三重管理)。Phase B で:

- `Brewfile` 削除
- `setup/` 削除 (一部は `nix/scripts/` に残す)
- `aliases` / `functions` / `zshrc` 等の symlink を home-manager 経由に統一

Phase B の作業は別 plan で扱う。Phase A 完了 + 運用安定確認後に着手する。

# CLAUDE.md の自己更新

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
