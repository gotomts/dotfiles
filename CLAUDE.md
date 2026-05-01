# リポジトリ構造

このリポジトリは macOS の開発環境を再現するための dotfiles である。

- `aliases` — シェルエイリアス定義（`~/.aliases` にシンボリックリンク）
- `aliase/` — 外部シェルスクリプト（エイリアスから呼び出される）
- `Brewfile` — Homebrew パッケージ定義
- `claude/` — Claude Code 設定（`~/.claude/` にシンボリックリンク）
- `claude/hooks/` — Claude Code フックスクリプト群（PreCompact / SessionStart / UserPromptSubmit）
- `claude/agents/` — マルチエージェント開発用サブエージェント定義（developer × 10 / reviewer × 3 / pr-publisher × 1 = 14 体。`~/.claude/agents/` にシンボリックリンク）
- `config/` — アプリケーション設定（starship, yazi, cmux）（`~/.config/` にシンボリックリンク）
- `docs/` — 設計ドキュメント・実装プラン（シンボリックリンク対象外）
- `functions/` — zsh カスタム関数（`~/.functions/` にシンボリックリンク）
- `gitconfig` — Git 設定（`~/.gitconfig` にシンボリックリンク）
- `gitignore_global` — グローバル gitignore（`~/.gitignore_global` にシンボリックリンク）
- `grip/` — grip 設定（`~/.grip/` にシンボリックリンク）
- `setup/` — セットアップスクリプト群（シンボリックリンク対象外）
- `ssh/` — SSH 設定（`~/.ssh/` にシンボリックリンク）
- `zsh/` — zsh 補完ファイル（`~/.zsh/` にシンボリックリンク）
- `zshrc` — zsh 設定（`~/.zshrc` にシンボリックリンク）
- `zshenv` — zsh 環境変数（`~/.zshenv` にシンボリックリンク）

# シンボリックリンク管理

- `setup/setup.zsh` がリポジトリルートのファイル/ディレクトリを `~/.${name}` にシンボリックリンクする
- 以下はシンボリックリンク対象外として除外されている: `setup`, `README.md`, `ssh`, `claude`, `CLAUDE.md`, `docs`
- `ssh/` と `claude/` は専用ループで個別にシンボリックリンクされる
- ルートにファイルやディレクトリを追加する場合、シンボリックリンクが不要なものは `setup.zsh` の除外条件に追加すること

# Brewfile

- パッケージの追加・削除は Brewfile のみで管理する。手動の `brew install` は禁止
- 既存のパッケージのみを対象とする。ユーザーが明示的に依頼していないパッケージを追加しない
- セクションコメント（`# Utilities`, `# Shell & Terminal` 等）に従って適切な位置に追記する
- `tap`, `brew`, `cask`, `mas` の区分を守る

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
- `claude/skills/create-issue/` は spec/plan を入力に Linear / GitHub の親 Issue + sub-issue を自律登録するスキル。引数 `<tracker> <spec-path> <plan-path>` で tracker を切替。`feature-team` Phase 2 から呼ばれる前提で、対話起点の `linear-plan` / `github-plan` とは棲み分け
- `claude/hooks/` 配下のフックスクリプトは PreCompact で未 handover 時のコンパクトをブロックし、SessionStart / UserPromptSubmit で未消費メモを Claude に通知する

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
