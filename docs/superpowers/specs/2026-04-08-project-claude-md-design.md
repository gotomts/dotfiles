# プロジェクト CLAUDE.md デザイン

## 概要

dotfiles リポジトリ専用のプロジェクトレベル CLAUDE.md を作成し、このリポジトリで作業する際の Claude Code の振る舞いを定義する。

## 背景

- グローバル CLAUDE.md（`claude/CLAUDE.md` → `~/.claude/CLAUDE.md`）は全プロジェクト共通のルールを定義している
- dotfiles リポジトリ固有のルール（シンボリックリンク管理、Brewfile 方針、zsh 規約等）を記述する場所がない
- プロジェクトレベル CLAUDE.md をリポジトリルートに配置し、この課題を解決する

## 設計方針

- **フラットルール型:** グローバル CLAUDE.md と同じスタイルで、セクションごとに箇条書きルールを羅列する
- **自己更新:** リポジトリ構造やルールが変わった場合、この CLAUDE.md 自体も更新する

## 配置

- ファイルパス: `/Users/goto/.dotfiles/CLAUDE.md`（リポジトリルート）
- `setup.zsh` の除外条件に `CLAUDE.md` を追加し、`~/.CLAUDE.md` へのシンボリックリンクを防ぐ

## セクション構成

### 1. リポジトリ構造

このリポジトリは macOS の開発環境を再現するための dotfiles である。各ディレクトリ/ファイルの役割とシンボリックリンク先を記述する。

対象:
- `aliases` — シェルエイリアス定義（`~/.aliases`）
- `aliase/` — 外部シェルスクリプト（エイリアスから呼び出される）
- `Brewfile` — Homebrew パッケージ定義
- `claude/` — Claude Code 設定（`~/.claude/`）
- `config/` — アプリケーション設定（starship, yazi, cmux）（`~/.config/`）
- `functions/` — zsh カスタム関数（`~/.functions/`）
- `gitconfig` — Git 設定（`~/.gitconfig`）
- `gitignore_global` — グローバル gitignore（`~/.gitignore_global`）
- `grip/` — grip 設定（`~/.grip/`）
- `setup/` — セットアップスクリプト群（シンボリックリンク対象外）
- `ssh/` — SSH 設定（`~/.ssh/`）
- `zsh/` — zsh 補完ファイル（`~/.zsh/`）
- `zshrc` — zsh 設定（`~/.zshrc`）
- `zshenv` — zsh 環境変数（`~/.zshenv`）

### 2. シンボリックリンク管理

- `setup/setup.zsh` がリポジトリルートのファイル/ディレクトリを `~/.${name}` にシンボリックリンクする
- 除外リスト: `setup`, `README.md`, `ssh`, `claude`, `CLAUDE.md`
- `ssh/` と `claude/` は専用ループで個別にシンボリックリンクされる
- ルートにファイルやディレクトリを追加する場合、シンボリックリンクが不要なものは `setup.zsh` の除外条件に追加すること

### 3. Brewfile

- パッケージの追加・削除は Brewfile のみで管理する。手動の `brew install` は禁止
- 既存のパッケージのみを対象とする。ユーザーが明示的に依頼していないパッケージを追加しない
- セクションコメント（`# Utilities`, `# Shell & Terminal` 等）に従って適切な位置に追記する
- `tap`, `brew`, `cask`, `mas` の区分を守る

### 4. zsh スクリプト規約

- シバンは `#!/bin/zsh` を使用する
- setup/ 配下のスクリプトは既存の `util.zsh`（`util::confirm`, `util::info` 等）を利用する
- 環境変数の参照は `${VAR}` 形式で統一する（`$VAR` ではなく）
- パスの参照には `${HOME}` を使用する（`~` ではなく）
- install スクリプトのファイル名は `XX_name.zsh`（XX は連番）の命名規則に従う

### 5. Claude Code 設定

- `claude/` 配下のファイルは `setup.zsh` により `~/.claude/` にシンボリックリンクされる
- `claude/CLAUDE.md` はグローバル CLAUDE.md である。プロジェクト固有のルールはここに書かない
- `claude/settings.json` は全プロジェクト共通の設定（パーミッション、プラグイン、フック等）を管理する
- `claude/skills/` にはカスタムスキルを配置する

### 6. CLAUDE.md の自己更新

- リポジトリに新しいディレクトリやファイルを追加した場合、「リポジトリ構造」セクションを更新すること
- 新しい運用ルールが生じた場合、該当するセクションに追記するか、新しいセクションを作成すること
- 更新はユーザー承認後に行うこと

## 実装に必要な変更

1. `/Users/goto/.dotfiles/CLAUDE.md` を新規作成
2. `setup/setup.zsh` の除外条件に `CLAUDE.md` を追加

## スコープ外

- グローバル CLAUDE.md（`claude/CLAUDE.md`）の変更
- 言語・フレームワーク固有のルール
