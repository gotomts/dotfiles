# setup/

Tier 1（リアルタイム symlink）の実装。`darwin-rebuild switch` を使わず、このディレクトリの
script を直接実行して dotfiles を `$HOME` へ配置する。

設計の全体像・Tier 1/Tier 2 の境界・確定した設計判断は
`docs/superpowers/specs/2026-08-21-restore-script-management-inventory.md` を参照。

## 使い方

```sh
zsh ${HOME}/.dotfiles/setup/link.zsh
```

一度実行すれば、以後の repo 編集（`zshrc`/`aliases`/`claude/CLAUDE.md` 等）は symlink 越しに
即座に反映される。再実行が必要なのは「`setup/link.zsh` 自体に新しい対応行を追加したとき」だけ。

## 安全策（明示関数）

- `fs::link_file`（`lib/fs.zsh`）: symlink 先に既に実体ファイル/ディレクトリがある場合、
  黙って上書きせず `<path>.before-setup` に退避してから symlink を作る。誤って手元の変更を
  失わないための安全策。
- `fs::ensure_realfile`（`lib/fs.zsh`）: `~/.gitconfig` や Claude Code のマーカーファイルなど、
  「dotfiles リポジトリで追跡してはいけない値／状態」を書き込み可能な実体ファイルとして保護する。
  3rd party ツール（coderabbit CLI の machineId 書き込み等）や OAuth token を含む running
  config を壊さないための安全策。symlink のままだと read-only 相当の問題やリポジトリへの
  意図しない値の混入が起きる。
- 変数名は `path` を避ける（`fs::ensure_realfile` 参照）。zsh は `path` を `$PATH` と束縛された
  特殊配列として扱うため、同一スコープ内で `local path=...` すると `mkdir`/`touch` 等の
  コマンド解決が壊れる（実装中に発見。詳細は Tier 1 実装計画の Task 2 注記を参照）。

## テスト

```sh
bats setup/tests/*.bats
```

`fs::link_file`/`fs::ensure_realfile` は関数単位、`setup/link.zsh` は
`HOME` を一時ディレクトリに差し替えたサンドボックスでの統合テスト（実機には一切触れない）。

## 対象外（Tier 2、別計画）

Homebrew パッケージ・言語ランタイム(mise)・macOS defaults・IME・フォント・PAM・Claude plugin
sync・MCP servers merge・Codex config.toml seed-if-absent は、このディレクトリの対象外。
これらは「編集して即反映」ではなく「明示的にスクリプトを実行した時に反映されればよい」カテゴリ
であり、別途 Tier 2 の実装計画で扱う。
