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

Tier 3 カットオーバー（home-manager を含む flake からの移行）に失敗した場合は、
`setup/rollback.zsh` を使う（`.before-nix` 残骸を検出したら fail-closed で停止する安全策
付き）。詳細は `setup/README.md` および
`docs/superpowers/specs/2026-08-22-restore-script-management-tier3-cutover-design.md` を参照。

```sh
sudo zsh ~/.dotfiles/setup/rollback.zsh
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

## Claude plugin の定期メンテナンス

`setup/claude-sync.zsh`（Tier 2、旧 `claude.nix` の `home.activation.claudePlugins` を移植）は
`settings.json` の `enabledPlugins` のうち**未インストールのものだけを install** する。既存
plugin は自動更新されない (Homebrew の `upgrade = false` と同じ方針)。毎回 marketplace 更新と
全 plugin 更新を走らせると、宣言数ぶんのネットワーク往復と到達できない marketplace の
タイムアウト待ちで実行が数分単位で伸びるため。

週次または月次で手動実行すること:

```sh
# 1. marketplace を最新化 (plugin の更新元)
claude plugin marketplace update

# 2. 全 plugin を更新
claude plugin list --json | jq -r '.[].id' | while read -r p; do
  claude plugin update "$p"
done
```

- 更新は Claude Code の再起動後に反映される (`Restart to apply changes` と出る)
- 個別に更新する場合は `claude plugin update <id>`、対話的にやる場合は Claude Code 内で `/plugin`
- `Failed to clone marketplace repository` が出る marketplace は SSH 鍵か接続の問題。その plugin は更新されず、既存バージョンのまま残る (switch は止まらない)

新しい plugin を足すときは `claude/settings.json` の `enabledPlugins` に宣言してから `zsh ~/.dotfiles/setup/claude-sync.zsh` を実行する。marketplace が未登録なら `extraKnownMarketplaces` にも足す。

## アプリ・パッケージの追加

`brew install` を直接打つことは事実上禁止 (`homebrew.onActivation.cleanup = "zap"` により次回 `darwin-rebuild switch` で削除される)。**宣言してから入れる** 順序を強制する設計。

**Tier 3 完了メモ (2026-08-22)**: CLI tool・フォントは Homebrew (`homebrew.nix`) へ、
言語ランタイムは `setup/languages.zsh`（mise）へ完全移行済み。home-manager
(`nix/modules/home/**`) は削除済みで、Nix (nix-darwin) は Homebrew パッケージ管理のみを
担当する。詳細は
`docs/superpowers/specs/2026-08-21-restore-script-management-inventory.md`（6/7 節）と
`docs/superpowers/specs/2026-08-22-restore-script-management-tier3-cutover-design.md` を参照。

### 種別ごとの配置先

| 種別 | 配置先 | 例 |
|---|---|---|
| CLI (nixpkgs 未収録 / macOS 特殊事情) | `nix/modules/darwin/homebrew.nix` の `brews` | `jq`, `gh`, `mise` |
| GUI アプリ (.app) | `nix/modules/darwin/homebrew.nix` の `casks` | `visual-studio-code`, `slack` |
| Mac App Store アプリ | `nix/modules/darwin/homebrew.nix` の `coreMasApps` / `defaultOnlyMasApps` | `{ "Xcode" = { id = 497799835; bundleId = "com.apple.dt.Xcode"; }; }` |
| 言語ランタイム (グローバル) | `setup/languages.zsh`（mise、`mise::pin` 行を追加） | `node`, `go`, `ruby`, `rust`, `python`, `dart` |

### 追加 → 適用の流れ（Homebrew）

```sh
# 1. nix/modules/darwin/homebrew.nix の該当リストに 1 行追加 (例: coreBrews に "ripgrep")
# 2. ビルド確認 (副作用なし)
darwin-rebuild build --flake ~/.dotfiles/nix#default --impure
# 3. 適用 (sudo の env_reset で USER=root になるのを USER=$USER で回避)
sudo USER=$USER darwin-rebuild switch --flake ~/.dotfiles/nix#default --impure
```

削除も同じ流れ（リストから行を消して switch すると `zap` で消える。`sub-1` role は
`cleanup = "none"` のため削除されない）。

言語ランタイムの追加・バージョン変更は `setup/languages.zsh` の `mise::pin` 行を編集し、
対象マシンで `zsh setup/languages.zsh` を再実行する（`darwin-rebuild switch` は不要）。

### Mac App Store アプリの導入判定

MAS アプリは `homebrew.masApps` で宣言し、生成 Brewfile には宣言した全アプリの
`mas "<name>", id: <id>` 行が常に出る。そのうえで Brewfile 末尾に
`nix/modules/darwin/mas-guard.rb` を連結し、既に入っているアプリの **install だけ** を
`HOMEBREW_BUNDLE_MAS_SKIP` (`Homebrew::Bundle::Skipper` が空白区切りで読み、entry の
name か id と照合する) で飛ばす。

- 導入済みの判定は **同じ `CFBundleIdentifier` の `.app` が `/Applications` か
  `~/Applications` にあるか** だけ。バージョン比較・修復・削除・アップグレードはしない
- `mas` 行を落とさないのは、`brew bundle cleanup` (`default` role の zap) が Brewfile に
  載っていない MAS アプリを `mas uninstall` の候補にするため
  (`Homebrew::Bundle::MacAppStore.cleanup_items`)。導入済みの行だけ落とすと削除される
- 判定に Spotlight (`mdfind` / `mdls`) を使わないのは、`mas` 側の App Store アプリ検出が
  Spotlight の索引に依存しているため。索引が欠けた端末で導入済みの TestFlight が「未導入」と
  判定され、再インストールを試みた結果 PackageKit が既存 app への上書きを拒否して
  初回 `setup/migrate.zsh` が失敗した実機事故がある
- 新しい MAS アプリを追加するときは `id` に加えて `bundleId` も宣言する。値は
  `/usr/bin/plutil -extract CFBundleIdentifier raw -o - "/Applications/<App>.app/Contents/Info.plist"`
- 検証は `bats nix/tests/mas-guard.bats` (PR では `nix-check` workflow が実行する)

### 「お試し」のための逃げ道

`brew install` 即試用の代替手段:

| やりたいこと | コマンド |
|---|---|
| nixpkgs にある CLI を一時的に試す | `nix shell nixpkgs#ripgrep`（その shell セッション限定 / `exit` で消える） |
| nixpkgs 最新で試す | `nix run nixpkgs/master#foo` |
| 1 回だけ実行 | `nix run nixpkgs#foo -- --args` |
| nixpkgs に無い GUI を試す | 現実的には手動 `brew install` → 気に入ったら `casks` に追加 → switch / 気に入らなければ `brew uninstall` |

`nix shell` / `nix run` は永続インストールしないので、`zap` の影響を受けない。お試しは基本これに倒すこと。

## Per-host 構成 (/etc/dotfiles-role)

複数 Mac で dotfiles を運用する際、PC ごとに異なる subset を入れるための仕組み。`/etc/dotfiles-role` (root 所有、machine-wide 設定) で切り替える。

### 有効な role

| Role | 用途 | 含まれるアプリ |
|---|---|---|
| `default` | default profile | core + default-only (full set) |
| `sub-1` | reduced profile | core のみ (default-only パッケージを除外) |

具体的な package 内訳は `nix/modules/darwin/homebrew.nix` の `coreCasks` / `defaultOnlyCasks` / `coreMasApps` / `defaultOnlyMasApps` / `coreBrews` / `defaultOnlyBrews` を参照。

### role 解決ルール

- `/etc/dotfiles-role` が **存在しない / 空 / 全コメント** → `default` にフォールバック (CI 経路もこれ)
- ファイルの中身 (`#` で始まる行と空行は無視、最初の content 行) を role 値として採用
- 未知の値が書かれていると `darwin-rebuild` が `throw` で停止する (silent fail 防止)

### なぜ `/etc/` に置くか

role は「この物理 Mac の identity」でありマシン単位の宣言。ユーザー単位の設定ではないため `/etc/` 配下が semantically 正しい。また、`sudo darwin-rebuild` 実行時に Nix が security 上 `HOME` を passwd の root home (`/var/root`) にフォールバックさせる挙動があり、`~/` 配下に role file を置くと HOME ベースでの解決が壊れる。`/etc/` は root 所有なのでこの影響を受けない。

### sub-1 での初回セットアップ

```sh
# 1. dotfiles を clone
git clone <repo-url> ~/.dotfiles

# 2. role を宣言 (root 所有の machine-wide 設定)
echo sub-1 | sudo tee /etc/dotfiles-role

# 3. ビルド確認 (副作用なし)
cd ~/.dotfiles/nix
nix build .#darwinConfigurations.default.system --no-link --impure

# 4. 初回ブートストラップ + 実機適用
sudo USER=$USER nix run nix-darwin -- switch --flake .#default --impure
```

### role の切り替え

`/etc/dotfiles-role` の値を書き換えて `darwin-rebuild switch` を再実行する。

```sh
echo default | sudo tee /etc/dotfiles-role   # sub-1 → default に切り替え
sudo USER=$USER darwin-rebuild switch --flake ~/.dotfiles/nix#default --impure
```

`homebrew.onActivation.cleanup = "zap"` (default) により、role 切り替え時に不要になったアプリは自動で Cellar ごと削除される (`sub-1` は `cleanup = "none"` のため切り替え時の削除はなし)。

### sub-1 にだけ入れる package を追加したい

現状 `sub-1` は「core のみ」のフラットな subset。将来 sub-1 専用の package が必要になったら、`nix/modules/darwin/homebrew.nix` の `let` ブロックに `sub1OnlyCasks` 等を追加し、`casks = coreCasks ++ lib.optionals (role == "sub-1") sub1OnlyCasks` で合成する (YAGNI のため現状は未追加)。

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

`nix/darwin.nix` で `nix.enable = false;` が宣言されているか確認する。S14 で対処済みの本番ブロッカー。詳細は `nix/darwin.nix` のコメントを参照。

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
