# nix/

このディレクトリは `~/.dotfiles` の環境構築を **Nix（nix-darwin + home-manager + flakes）** で一元管理する Phase A の作業対象です。宣言的・再現可能・マルチホスト対応な環境を `darwin-rebuild switch` 一発で復元できる状態を目指します。

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
│       ├── default.nix     # ホスト固有の合成（薄い import 集約）
│       ├── darwin.nix      # nix-darwin module 集約
│       └── home.nix        # home-manager module 集約
├── lib/
│   └── mkHost.nix          # ホスト合成ヘルパー
└── modules/                # S3-S11 で順次追加予定
    ├── darwin/
    └── home/
```

## 前提条件

- **Xcode Command Line Tools** がインストール済みであること
- **Nix** がインストール済みであること（[Determinate Systems インストーラ](https://github.com/DeterminateSystems/nix-installer) 推奨）
- **nix-darwin** は flake から自動適用されるため、事前インストール不要

## 初回セットアップ手順

### 1. Xcode Command Line Tools のインストール

```sh
xcode-select --install
```

### 2. Nix のインストール（Determinate Systems インストーラ推奨）

```sh
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

インストール後、ターミナルを再起動するか以下を実行:

```sh
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

### 3. flake.lock の生成（初回 or 更新時）

```sh
cd ~/.dotfiles/nix
nix flake update
```

### 4. ビルド確認（switch 前の確認）

副作用なしにビルドが通るか確認する:

```sh
cd ~/.dotfiles/nix
darwin-rebuild build --flake .#m5mbp
```

### 5. 適用

```sh
cd ~/.dotfiles/nix
darwin-rebuild switch --flake .#m5mbp
```

初回実行時は nix-darwin のブートストラップも行われるため、ターミナルの再起動が必要な場合があります。

## 通常の更新手順

```sh
cd ~/.dotfiles/nix

# input を最新に更新
nix flake update

# ビルド確認
darwin-rebuild build --flake .#m5mbp

# 確認できたら適用
darwin-rebuild switch --flake .#m5mbp
```

## 別 PC への展開

### 新しいホストを追加する手順

1. `nix/hosts/<new-hostname>/` ディレクトリを作成する
2. `darwin.nix`・`home.nix`・`default.nix` を `m5mbp/` からコピーして編集する
3. `nix/flake.nix` の `outputs` に新しいホストを追加する:
   ```nix
   darwinConfigurations.<new-hostname> = mkHost {
     hostname = "<new-hostname>";
     system = "aarch64-darwin";  # Intel Mac の場合は "x86_64-darwin"
     username = "goto";
   };
   ```
4. 新しい PC で上記の初回セットアップ手順を実行する:
   ```sh
   darwin-rebuild switch --flake ~/.dotfiles/nix#<new-hostname>
   ```

## ロールバック

前の世代に戻す:

```sh
darwin-rebuild --rollback
```

特定の世代を指定して戻す:

```sh
# 利用可能な世代を確認
darwin-rebuild --list-generations

# 特定世代に切替
darwin-rebuild switch --flake .#m5mbp --switch-generation <generation-number>
```

home-manager のロールバック:

```sh
home-manager generations
home-manager switch --switch-generation <id>
```

## flake.lock の更新方針

- `nix flake update` で全 input を最新に更新できる
- 特定 input だけ更新する場合: `nix flake lock --update-input nixpkgs`
- 更新後は必ず `darwin-rebuild build` でビルドを確認してからコミットすること
- `flake.lock` は必ずコミットすること（再現性確保のため）

## トラブルシューティング

### flake.lock が壊れた / hash 不整合

```sh
git restore nix/flake.lock
nix flake update
```

### darwin-rebuild が失敗した場合

ビルドエラーのログを確認:

```sh
darwin-rebuild build --flake .#m5mbp 2>&1 | less
```

nix-darwin のロールバック:

```sh
darwin-rebuild --rollback
```

### nix-darwin の初回ブートストラップ

nix-darwin が未インストールの状態で初めて適用する場合:

```sh
nix run nix-darwin -- switch --flake ~/.dotfiles/nix#m5mbp
```

## 現在の状態（Phase A S2 完了時点）

- [x] S2: flake 雛形 + mkHost ヘルパー
- [ ] S3: home-manager packages.nix（CLI ツール群）
- [ ] S4: home-manager zsh.nix
- [ ] S5: home-manager git / starship / yazi / ssh
- [ ] S6: home-manager claude.nix
- [ ] S7: home-manager languages.nix
- [ ] S8: rtk overlay
- [ ] S9: nix-darwin homebrew.nix
- [ ] S10: nix-darwin defaults.nix
- [ ] S11: nix-darwin sudoers / fonts / pam
