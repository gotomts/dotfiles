# nix/

`darwin-rebuild` 適用後の事故対応・運用ポリシー集。クイックスタートはルート [`README.md`](../README.md) を参照。

関連ドキュメント:

- spec: `docs/superpowers/specs/2026-05-02-nix-migration-design.md`
- plan: `docs/superpowers/plans/2026-05-02-nix-migration.md`

## ロールバック

直前世代に戻す:

```sh
sudo darwin-rebuild switch --rollback
```

世代一覧の確認と特定世代への切替:

```sh
darwin-rebuild --list-generations
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
- 更新後は必ず `darwin-rebuild build --flake .#default --impure` で検証してからコミット
- `flake.lock` は必ずコミットする（再現性確保のため）
- 更新頻度の方針: **必要時のみ**（依存ライブラリの脆弱性 / nixpkgs に必要なパッケージが入ったタイミング等）

## Homebrew パッケージの定期メンテナンス

`homebrew.onActivation.upgrade = false` により、`darwin-rebuild switch` では新規インストールのみ実行され、既存パッケージは自動 upgrade されない。週次または月次で手動実行すること:

```sh
brew upgrade && brew cleanup
```

- `brew upgrade`: 全パッケージを最新版へ更新
- `brew cleanup`: 旧バージョンの Cellar を削除してディスク節約

この設計は `flake.lock` と同様に「明示的に更新する」哲学と整合する。

## アプリ・パッケージの追加

`brew install` を直接打つことは事実上禁止 (`homebrew.onActivation.cleanup = "zap"` により次回 `darwin-rebuild switch` で削除される)。**宣言してから入れる** 順序を強制する設計。

### 種別ごとの配置先

| 種別 | 配置先 | 例 |
|---|---|---|
| CLI (nixpkgs 収録あり) | `nix/modules/home/packages.nix` の `home.packages` | `ripgrep`, `fzf`, `jq` |
| 言語ランタイム | `nix/modules/home/languages.nix` | `nodejs_22`, `python3` |
| CLI (nixpkgs 未収録 / 最新版が必要) | `nix/modules/darwin/homebrew.nix` の `brews` (例外扱い) | `mas` |
| GUI アプリ (.app) | `nix/modules/darwin/homebrew.nix` の `casks` | `visual-studio-code`, `slack` |
| Mac App Store アプリ | `nix/modules/darwin/homebrew.nix` の `masApps` | `{ "Xcode" = 497799835; }` |
| 独自ビルド (nixpkgs 外のソース) | `nix/modules/overlays/` に overlay 定義 + `home.packages` から参照 | `rtk` |

### 追加 → 適用の流れ

```sh
# 1. 該当の .nix に 1 行追加 (例: packages.nix の home.packages に pkgs.ripgrep)
# 2. ビルド確認 (副作用なし)
darwin-rebuild build --flake ~/.dotfiles/nix#default --impure
# 3. 適用 (sudo の env_reset で USER=root になるのを USER=$USER で回避)
sudo USER=$USER darwin-rebuild switch --flake ~/.dotfiles/nix#default --impure
```

削除も同じ流れ (`.nix` から行を消して switch すると `zap` で消える)。

### 「お試し」のための逃げ道

`brew install` 即試用の代替手段:

| やりたいこと | コマンド |
|---|---|
| nixpkgs にある CLI を一時的に試す | `nix shell nixpkgs#ripgrep`（その shell セッション限定 / `exit` で消える） |
| nixpkgs 最新で試す | `nix run nixpkgs/master#foo` |
| 1 回だけ実行 | `nix run nixpkgs#foo -- --args` |
| nixpkgs に無い GUI を試す | 現実的には手動 `brew install` → 気に入ったら `casks` に追加 → switch / 気に入らなければ `brew uninstall` |

`nix shell` / `nix run` は永続インストールしないので、`zap` の影響を受けない。お試しは基本これに倒すこと。

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

`nix/darwin.nix` で `nix.enable = false;` が宣言されているか確認する。S14 (KISSA-46) で対処済みの本番ブロッカー。詳細は `nix/darwin.nix` のコメントを参照。

### `USER env var is empty` で `darwin-rebuild` が落ちる

`--impure` フラグなしで実行している、または `sudo` 経由で `USER` が `root` に置き換わっている。`nix/flake.nix` は `builtins.getEnv "USER"` で実行ユーザー名を動的解決するため、`--impure` と `USER=$USER` の両方が必須:

```sh
sudo USER=$USER darwin-rebuild switch --flake .#default --impure
```

### flake.lock が壊れた / hash 不整合

```sh
git restore nix/flake.lock
nix flake update
```

### `darwin-rebuild` がビルドエラーで失敗する

ビルドエラーのログを確認:

```sh
darwin-rebuild build --flake .#default --impure 2>&1 | less
```

nix-darwin のロールバック:

```sh
sudo darwin-rebuild switch --rollback
```

### nix-darwin の初回ブートストラップ

nix-darwin が未インストールの状態で初めて適用する場合:

```sh
cd ~/.dotfiles/nix
nix run nix-darwin -- switch --flake .#default --impure
```

### Homebrew パッケージが消えた

`homebrew.onActivation.cleanup = "zap"` 設定により、`nix/modules/darwin/homebrew.nix` に宣言されていない Homebrew パッケージは初回 switch で削除される。残したいパッケージは `nix/modules/darwin/homebrew.nix` に追加してから switch すること。
