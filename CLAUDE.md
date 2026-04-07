# リポジトリ構造

このリポジトリは macOS の開発環境を再現するための dotfiles である。

- `aliases` — シェルエイリアス定義（`~/.aliases` にシンボリックリンク）
- `aliase/` — 外部シェルスクリプト（エイリアスから呼び出される）
- `Brewfile` — Homebrew パッケージ定義
- `claude/` — Claude Code 設定（`~/.claude/` にシンボリックリンク）
- `config/` — アプリケーション設定（starship, yazi, cmux）（`~/.config/` にシンボリックリンク）
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
- 以下はシンボリックリンク対象外として除外されている: `setup`, `README.md`, `ssh`, `claude`, `CLAUDE.md`
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

# CLAUDE.md の自己更新

- リポジトリに新しいディレクトリやファイルを追加した場合、「リポジトリ構造」セクションを更新すること
- 新しい運用ルールが生じた場合、該当するセクションに追記するか、新しいセクションを作成すること
- 更新はユーザー承認後に行うこと
