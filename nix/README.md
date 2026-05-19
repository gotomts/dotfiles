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
| 言語ランタイム (グローバル) | `nix/modules/home/languages.nix` | `nodejs_24`, `python3` |
| 言語ランタイム (プロジェクトごと) | リポジトリ内の `devbox.json` | Node 18 が必要なレガシープロジェクト等 (後述) |
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

## プロジェクトごとの言語バージョン管理 (devbox)

`languages.nix` で宣言したグローバルランタイム (Node.js 24 / Python 3.13 / Ruby 3.4 等) と異なるバージョンを特定プロジェクトで使いたい場合は [devbox](https://www.jetify.com/devbox) を利用する。`mise` / `asdf` 相当のワンライナー UX を Nix 上で提供する wrapper で、内部で nixpkgs を参照するため再現性も担保される。

devbox 自体は `nix/modules/home/packages.nix` で nix 管理しているため、`darwin-rebuild switch` 後はそのまま使える。

### 役割分担

| 対象 | 配置先 | 例 |
|---|---|---|
| **グローバル**(全プロジェクト共通の標準バージョン) | `nix/modules/home/languages.nix` | `nodejs_24`, `python313`, `ruby_3_4` |
| **プロジェクトごと**(リポジトリ単位で固定) | リポジトリ内の `devbox.json` / `devbox.lock` | Node 18 が必要なレガシープロジェクト等 |

cd でプロジェクト外に出ると、direnv が自動でグローバル環境に戻す。

### 基本ワークフロー

```sh
cd path/to/project

# devbox.json を生成
devbox init

# 言語ランタイムを追加 (ワンライナー)
devbox add nodejs@18

# direnv 連携を生成 — .envrc 作成 + direnv allow まで自動で実行される
devbox generate direnv
```

生成される `.envrc` は以下:

```sh
eval "$(devbox generate direnv --print-envrc)"
```

これにより cd した瞬間に PATH が devbox 環境に切り替わり、`node --version` が `v18.x` を返すようになる。

### パッケージの削除

```sh
devbox rm nodejs
```

### 利用可能なバージョンの確認

```sh
devbox search nodejs
```

### 補足

- `devbox.json` と `devbox.lock` の両方をリポジトリにコミットすること(`flake.lock` 同様、再現性の根幹)
- `devbox.json` を変更すると direnv が自動的に環境を reset する。`~/.config/direnv/direnv.toml` でホワイトリストしていない限り、変更後に再度 `direnv allow` が要求される
- 言語ランタイム以外(`postgresql@15`, `redis@7` 等のサービス類)も `devbox add` で同じ流儀で管理可能

## 既存 PC 移行手順 (dir-symlink → proper directory)

旧 `setup.zsh` を使って構築した PC では、`~/.aliase` や `~/.functions` が
dotfiles ディレクトリへのシンボリックリンク (dir-symlink) として残っている場合がある。
home-manager が `~/.aliase/get-gke-credentials.sh` 等を nix store 経由で配置しようとすると
dir-symlink の先 = dotfiles リポジトリ内のファイルを上書きし、
`aliase/get-gke-credentials.sh.before-nix` がリポジトリに生まれる問題がある。

以下の手順で移行すること。

### ステップ 1: 現状確認 (dry-run)

```sh
zsh ~/.dotfiles/nix/scripts/migrate-symlinks.zsh --dry-run
```

削除予定のシンボリックリンクが一覧表示される。内容を確認する。

### ステップ 2: シンボリックリンクの削除

問題なければ実際に削除する:

```sh
zsh ~/.dotfiles/nix/scripts/migrate-symlinks.zsh
```

スクリプトが削除するシンボリックリンク:

| シンボリックリンク | 種類 | 理由 |
|---|---|---|
| `~/.aliase` | dir-symlink | home-manager が `.aliase/get-gke-credentials.sh` を管理 |
| `~/.functions` | dir-symlink | home-manager が `.functions/fzf-history` を管理 |
| `~/.aliases` | file-symlink | home-manager が nix store 経由で再配置 |
| `~/.gitignore_global` | file-symlink | home-manager が nix store 経由で再配置 |
| `~/.grip/settings.py` | file-symlink | home-manager が nix store 経由で再配置 |
| `~/.config/cmux/config.ghostty` | file-symlink | home-manager が nix store 経由で再配置 |
| `~/.config/starship/starship.toml` | file-symlink | home-manager は `~/.config/starship.toml` に配置 |

### ステップ 3: darwin-rebuild switch

```sh
sudo USER=$USER darwin-rebuild switch --flake ~/.dotfiles/nix#default --impure
```

home-manager が proper directory と nix store 経由のシンボリックリンクを再生成する。

### ステップ 4: 動作確認

```sh
# dir-symlink が解消され proper directory になっていることを確認
file ~/.aliase ~/.functions
# expected: directory (not symlink)

# home-manager 管理の symlink が nix store を指していることを確認
ls -la ~/.aliase/get-gke-credentials.sh ~/.functions/fzf-history
# expected: -> /nix/store/...

# .before-nix ファイルが dotfiles に生まれていないことを確認
git -C ~/.dotfiles status
# expected: clean (before-nix バックアップがない)
```

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
