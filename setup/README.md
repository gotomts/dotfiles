# setup/

Tier 1（リアルタイム symlink）・Tier 2（明示的スクリプト実行）の実装。`darwin-rebuild switch`
を使わず、このディレクトリの script を直接実行して dotfiles を `$HOME` へ配置・適用する。

設計の全体像・Tier 1/Tier 2 の境界・確定した設計判断は
`docs/superpowers/specs/2026-08-21-restore-script-management-inventory.md` を参照。
Tier 2 の実装計画（各スクリプトの詳細仕様・テスト戦略）は
`docs/superpowers/plans/2026-08-22-restore-script-management-tier2.md` を参照。

## 使い方

```sh
# Tier 1: repo → $HOME の symlink 配置 (一度実行すれば以後は symlink 越しに自動反映)
zsh ${HOME}/.dotfiles/setup/link.zsh

# Tier 2: 明示的に実行したときだけ反映されればよいもの (べき等、繰り返し実行してよい)
zsh ${HOME}/.dotfiles/setup/languages.zsh    # mise で言語ランタイム install/pin + corepack enable
zsh ${HOME}/.dotfiles/setup/defaults.zsh     # macOS defaults / Dock / IME
zsh ${HOME}/.dotfiles/setup/pam.zsh          # Touch ID for sudo (sudo が必要)
zsh ${HOME}/.dotfiles/setup/claude-sync.zsh  # skills clone / plugin sync / MCP servers merge
zsh ${HOME}/.dotfiles/setup/codex-sync.zsh   # config.toml seed-if-absent
```

`setup/link.zsh` は一度実行すれば、以後の repo 編集（`zshrc`/`aliases`/`claude/CLAUDE.md` 等）は
symlink 越しに即座に反映される。再実行が必要なのは「`setup/link.zsh` 自体に新しい対応行を
追加したとき」だけ。Tier 2 の各スクリプトは冪等なので、値を変更した後は該当スクリプトを
再実行すれば反映される。

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
- `pam.zsh`: 既存の `/etc/pam.d/sudo_local` の内容が想定と異なる場合、`.before-setup` に退避
  してから上書きする。退避先が既に存在する場合はエラーで停止し、既存ファイルには一切触れない
  （`fs::ensure_realfile` と同じ no-data-loss 方針）。書き込み先は `SUDO_LOCAL_PATH` 環境変数で
  上書きできる（テスト用）。
- `defaults.zsh`: 各 domain を初めて書き込む前に `defaults export <domain>
  ~/.dotfiles-defaults-backup/<domain>.plist` で現状のスナップショットを 1 回だけ取る
  （2 回目以降はスキップ）。IME/入力ソースの plist は複製せず `nix/modules/darwin/` を
  単一ソースとして参照する。role は `/etc/dotfiles-role`（`nix/flake.nix` と同じ規約）から
  解決し、テストでは `DOTFILES_ROLE_FILE` で上書きできる。
- `claude-sync.zsh`/`codex-sync.zsh`: 破壊的な操作を行わない（MCP merge は add-only、
  config.toml は seed-if-absent、skills repo clone は既存ディレクトリを一切変更しない）。

## テスト

```sh
bats setup/tests/*.bats
```

`fs::link_file`/`fs::ensure_realfile` は関数単位、`link.zsh`/`languages.zsh`/`defaults.zsh`/
`pam.zsh`/`claude-sync.zsh`/`codex-sync.zsh` は、実コマンド（`defaults`/`mise`/`corepack`/
`claude`/`git`）を PATH 上の stub 実行ファイルに差し替え、`$HOME` を一時ディレクトリに
差し替えたサンドボックスでの統合テスト（実機・実ネットワーク・実パッケージマネージャには
一切触れない）。CI は `.github/workflows/setup-check.yml` が `setup/**` の変更ごとに実行する。
