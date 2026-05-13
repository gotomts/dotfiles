# dotfiles

`~/.dotfiles` の macOS 開発環境を **Nix（nix-darwin + home-manager + flakes）** で宣言的に再現するための dotfiles。`darwin-rebuild switch` 一発で全パッケージ・全設定が復元される。

詳細手順（ロールバック、新ホスト追加、トラブルシュート）は [`nix/README.md`](nix/README.md) を参照。

## 前提

- macOS (Apple Silicon: `aarch64-darwin` / Intel: `x86_64-darwin`)
- 既存ホスト構成は `m5mbp` のみ（`nix/flake.nix` で宣言済み）
- 新ホストを追加する場合は [`nix/README.md` の「別 PC への展開」](nix/README.md#別-pc-への展開) を参照

## セットアップ

以下を上から順に実行すれば完了する。

### 1. Full Disk Access を付与する

Nix インストーラは `/etc` 配下に書き込みを行うため、実行元ターミナル（Terminal.app, iTerm2 等）に **Full Disk Access (FDA)** が必要。macOS 15 では FDA なしでは root でも書き込みが拒否される。

1. **System Settings → Privacy & Security → Full Disk Access** を開く
2. 自分が使うターミナルアプリを追加して有効化する
3. ターミナルを**完全に終了**して起動し直す（プロセス再起動で TCC が反映される）

### 2. Xcode Command Line Tools をインストール

```sh
xcode-select --install
```

完了するまで待つ（GUI ダイアログが出る）。

### 3. リポジトリを clone

```sh
git clone https://github.com/gotomts/dotfiles.git ~/.dotfiles
```

### 4. Determinate Nix をインストール

```sh
zsh ~/.dotfiles/nix/scripts/install-nix.zsh
```

このスクリプトは:

- 既に Nix がインストール済みなら skip する
- FDA 未付与なら手順 1 に戻るよう促して停止する
- Determinate Nix の公式インストーラを非対話モードで起動する

インストール成功後、**ターミナルを再起動**するか以下を実行する:

```sh
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

### 5. ビルド確認（switch 前のドライラン）

```sh
cd ~/.dotfiles/nix
nix flake check --no-build
darwin-rebuild build --flake .#m5mbp
```

副作用なしに closure がビルドできれば次へ。

### 6. 適用

```sh
sudo darwin-rebuild switch --flake .#m5mbp
```

初回は nix-darwin のブートストラップが走るため、終了後に**ターミナルを再起動**する。

> ⚠ `homebrew.onActivation.cleanup = "zap"` 設定により、`nix/modules/darwin/homebrew.nix` に宣言されていない Homebrew パッケージは初回 switch で削除される。手元のパッケージが消えて困るものがあれば、先に `nix/modules/darwin/homebrew.nix` に追加してから switch すること。

## 完了確認

セットアップ後、以下が成立していれば成功:

- [ ] `which zsh` が nix-managed のパスを指す
- [ ] `starship --version` が応答する
- [ ] `yazi --version` が応答する
- [ ] `claude --version` が応答する（Claude Code）
- [ ] `ls -la ~/.claude/agents ~/.claude/skills` が **dotfiles 配下への symlink** になっている
- [ ] `rtk --version` が応答する（rtk overlay 経由）
- [ ] `node --version` / `dart --version` / `grip --version` が応答する（home-manager languages.nix）
- [ ] `brew list --cask` の出力が `nix/modules/darwin/homebrew.nix` の宣言と一致する
- [ ] `sudo pmset -g` を NOPASSWD で実行できる（sudoers.nix）
- [ ] Touch ID で `sudo` できる（pam.nix）

## 通常運用

```sh
cd ~/.dotfiles/nix

# inputs を最新化
nix flake update

# ビルド確認
darwin-rebuild build --flake .#m5mbp

# 適用
sudo darwin-rebuild switch --flake .#m5mbp

# 直前世代に戻す
sudo darwin-rebuild switch --rollback
```

詳細は [`nix/README.md`](nix/README.md) を参照。

## アーキテクチャ

- `nix/flake.nix` — inputs / outputs ルート
- `nix/hosts/m5mbp/{darwin,home}.nix` — ホスト固有の module 集約
- `nix/modules/darwin/` — nix-darwin module（homebrew, sudoers, fonts, pam）
- `nix/modules/home/` — home-manager module（packages, zsh, git, starship, yazi, ssh, claude, languages）
- `nix/modules/overlays/rtk.nix` — rtk (Rust Token Killer) を `pkgs.rtk` として供給する overlay
- `nix/scripts/install-nix.zsh` — Determinate Nix インストーラ薄ラッパー（FDA pre-check + idempotent skip）
- `setup/` / `Brewfile` — Phase B で削除予定のレガシー資産。新規セットアップでは使用しない
