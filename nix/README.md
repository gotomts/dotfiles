# nix/

このディレクトリは `~/.dotfiles` の環境構築を **Nix（nix-darwin + home-manager + flakes）** で一元管理する。宣言的・再現可能・マルチホスト対応な環境を `darwin-rebuild switch` 一発で復元する。

新規セットアップ手順は [ルート README](../README.md) を参照。本ドキュメントは詳細・運用・トラブルシュートを扱う。

関連ドキュメント:

- spec: `docs/superpowers/specs/2026-05-02-nix-migration-design.md`
- plan: `docs/superpowers/plans/2026-05-02-nix-migration.md`

## ディレクトリ構造

```
nix/
├── flake.nix               # inputs / outputs ルート
├── flake.lock              # 全 input のロック（コミット対象）
├── README.md               # このファイル
├── hosts/
│   └── m5mbp/
│       ├── darwin.nix      # nix-darwin module 集約（mkHost.nix から直接 import）
│       └── home.nix        # home-manager module 集約（mkHost.nix から直接 import）
├── lib/
│   └── mkHost.nix          # ホスト合成ヘルパー
├── modules/
│   ├── darwin/             # nix-darwin module (homebrew / sudoers / fonts / pam)
│   ├── home/               # home-manager module (packages / zsh / git / starship / yazi / ssh / claude / languages)
│   └── overlays/
│       └── rtk.nix         # rtk (Rust Token Killer) を pkgs.rtk として供給する overlay
└── scripts/
    ├── install-nix.zsh     # Determinate Nix インストーラ薄ラッパー
    ├── inventory.zsh       # macOS defaults / brew 棚卸スクリプト (S1)
    └── tests/
        └── inventory.bats  # inventory.zsh の bats テスト
```

## 前提条件

- **macOS** (Apple Silicon: `aarch64-darwin` / Intel: `x86_64-darwin`)
- **Xcode Command Line Tools** がインストール済み
- **Full Disk Access (FDA)** が実行元ターミナルに付与済み（`/etc` 書き込みに必須）
- **Determinate Nix** がインストール済み（`nix/scripts/install-nix.zsh` 経由でインストール）

nix-darwin / home-manager は flake から自動適用されるため、事前インストール不要。

## 通常運用

```sh
cd ~/.dotfiles/nix

# inputs を最新化
nix flake update

# ビルド確認 (副作用なし)
darwin-rebuild build --flake .#m5mbp

# 適用
sudo darwin-rebuild switch --flake .#m5mbp

# CI と同じ closure ビルドだけを確認
nix build .#darwinConfigurations.m5mbp.system --no-link --print-out-paths
```

## 別 PC への展開

### 既存ホスト (m5mbp) と同等のセットアップを別 PC で再現する

新しい PC でも `hostname = "m5mbp"` のままなら、[ルート README のセットアップ手順](../README.md#セットアップ)を上から実行するだけで完了する。`install-nix.zsh` が冪等なので、既に Nix がある環境でも安全に再実行できる。

### 新しいホストを追加する

別の hostname（例: `m6mbp`）で運用したい場合:

1. `nix/hosts/m6mbp/` ディレクトリを作成する
2. `darwin.nix` / `home.nix` を `m5mbp/` からコピーして編集する
3. `nix/flake.nix` の `outputs` に新しいホストを追加する:
   ```nix
   darwinConfigurations.m6mbp = mkHost {
     hostname = "m6mbp";
     system = "aarch64-darwin";  # Intel Mac の場合は "x86_64-darwin"
     username = "goto";
   };
   ```
4. 新しい PC で初回セットアップ:
   ```sh
   # ルート README の手順 1-4 を実行 (FDA / CLT / clone / install-nix.zsh)
   cd ~/.dotfiles/nix
   darwin-rebuild build --flake .#m6mbp
   sudo darwin-rebuild switch --flake .#m6mbp
   ```

## ロールバック

直前世代に戻す:

```sh
sudo darwin-rebuild switch --rollback
```

世代一覧の確認と特定世代への切替:

```sh
# 利用可能な世代を確認
darwin-rebuild --list-generations

# 特定世代に切替（flake 指定なし。世代番号で直接切替）
sudo darwin-rebuild switch -G <generation-number>
```

home-manager 個別のロールバック:

```sh
home-manager generations
home-manager switch --switch-generation <id>
```

## flake.lock の更新運用

- `nix flake update` で全 input を最新に更新できる
- 特定 input だけ更新する場合: `nix flake lock --update-input nixpkgs`
- 更新後は必ず `darwin-rebuild build` でビルドを確認してからコミットすること
- `flake.lock` は必ずコミットすること（再現性確保のため）
- 更新頻度の方針: **必要時のみ**（依存ライブラリの脆弱性 / nixpkgs に必要なパッケージが入ったタイミング等）。定期更新は CI に依存しない手動運用

## トラブルシューティング

### Full Disk Access (FDA) 未付与で `install-nix.zsh` が停止する

スクリプトが以下のエラーで停止した場合:

```
Full Disk Access is NOT granted to the current terminal.
```

1. **System Settings → Privacy & Security → Full Disk Access** を開く
2. 自分が使うターミナルアプリ（Terminal.app, iTerm2, etc.）を追加して有効化する
3. ターミナルを**完全に終了**して起動し直す（プロセス再起動で TCC が反映される）
4. `zsh ~/.dotfiles/nix/scripts/install-nix.zsh` を再実行

macOS 15 では FDA なしでは root でも `/etc` への書き込みが TCC で拒否されるため、`sudo` をつけても回避できない。Claude Code 経由 (osascript with administrator privileges) でも同様に回避不可。

### Determinate Nix と nix-darwin が競合する

`darwin-rebuild switch` 実行時に以下のエラーで失敗した場合:

```
error: Determinate detected, aborting activation
Determinate uses its own daemon to manage the Nix installation that
conflicts with nix-darwin's native Nix management.
```

`nix/hosts/<host>/darwin.nix` で `nix.enable = false;` が宣言されているか確認する。S14 (KISSA-46) で対処済みの本番ブロッカー。詳細は `hosts/m5mbp/darwin.nix` のコメントを参照。

### flake.lock が壊れた / hash 不整合

```sh
git restore nix/flake.lock
nix flake update
```

### `darwin-rebuild` がビルドエラーで失敗する

ビルドエラーのログを確認:

```sh
darwin-rebuild build --flake .#m5mbp 2>&1 | less
```

nix-darwin のロールバック:

```sh
sudo darwin-rebuild switch --rollback
```

### nix-darwin の初回ブートストラップ

nix-darwin が未インストールの状態で初めて適用する場合:

```sh
cd ~/.dotfiles/nix
nix run nix-darwin -- switch --flake .#m5mbp
```

### Homebrew パッケージが消えた

`homebrew.onActivation.cleanup = "zap"` 設定により、`nix/modules/darwin/homebrew.nix` に宣言されていない Homebrew パッケージは初回 switch で削除される。残したいパッケージは `nix/modules/darwin/homebrew.nix` に追加してから switch すること。

## Phase A の進捗

- [x] S1: 棚卸スクリプト + bats テスト (KISSA-21)
- [x] S2: flake 雛形 + mkHost ヘルパー (KISSA-22)
- [x] S3: home-manager packages.nix (KISSA-23)
- [x] S4: home-manager zsh.nix (KISSA-24)
- [x] S5: home-manager git / starship / yazi / ssh (KISSA-25)
- [x] S6: home-manager claude.nix - plugin sync activation (KISSA-26)
- [x] S7: home-manager languages.nix - mise 完全置換 (KISSA-27)
- [x] S8: rtk overlay (KISSA-28)
- [x] S9: nix-darwin homebrew.nix - cask + mas + 例外 brew (KISSA-29)
- [ ] S10: nix-darwin defaults.nix - 棚卸 triage 翻訳 (KISSA-30, 別途着手予定)
- [x] S11: nix-darwin sudoers / fonts / pam (KISSA-31)
- [x] S12: 検証 + README + 別 PC 手順 + install-nix.zsh (KISSA-32)
- [x] S13: CLAUDE.md に Nix 環境セクション追記 (KISSA-33)
- [x] S14: GitHub Actions nix flake check + closure build (KISSA-46)

Phase B（`setup/setup.zsh` / `Brewfile` の削除等）は別エピックで実施予定。
