# Tier 3（カットオーバー・ロールバック機構 + Nix 定義の廃止）設計

**ステータス**: 承認済み（2026-08-22、ユーザー承認）。実装未着手。
**スコープ境界**: 本 PR は全面サンドボックス検証のみ。`darwin-rebuild switch` の実行・実 `$HOME` への書き込み・`brew install/uninstall`・`defaults write/import`・PAM 書き込み・`mise install`・Claude/Codex sync 等の実機変更は一切行わない。実機カットオーバーは、本 PR がスタック上の terminal PR として存在した後、別ステップとして行う。

関連ドキュメント:
- `docs/superpowers/specs/2026-08-21-restore-script-management-inventory.md`（6/7 節: D 案確定設計）
- `docs/superpowers/plans/2026-08-22-restore-script-management-tier1.md` / `-tier2.md`
- `setup/README.md`（Tier 1/2 の使い方・安全策）

## 1. 目的

Tier 1（`setup/link.zsh`、PR #53）・Tier 2（`setup/*.zsh`、PR #54）は、Nix (home-manager +
一部 nix-darwin モジュール) が担っていた責務を script 側に**並行構築**した。両 PR とも既存の
Nix モジュールは削除せず、「実機切替は別途判断」として先送りしてきた
（`nix/modules/darwin/homebrew.nix` のコメント参照）。

Tier 3 はその「別途判断」を実施する最終層。具体的には:

1. script 側が Nix (home-manager 部分) の責務を過不足なくカバーしていることを監査する
2. 実機でカットオーバー（home-manager を含まない flake への切替）を安全に行うための
   `cutover.zsh` と、失敗時に前の状態へ戻すための `rollback.zsh` を用意する
3. 監査で問題が無ければ、home-manager 関連の Nix 定義（`nix/home.nix` /
   `nix/modules/home/**`）と、Tier 2 で script 側に移植済みの nix-darwin モジュール
   （`defaults.nix` / `hitoolbox.nix` / `pam.nix` / `fonts.nix`）を削除する
4. ドキュメントを新方式に合わせて更新する

## 2. カバレッジ監査（削除前提の確認）

凡例: ✅ = script 側 (Tier 1/2) or `homebrew.nix` へ移植済み、confirmed by direct comparison。

| 削除対象 nix ファイル | 内容 | 移植先 |
|---|---|---|
| `nix/modules/home/zsh.nix` | zshrc/zshenv/shellAliases | ✅ Tier1 `zshrc`/`zshenv`/`aliases`（root 直下）|
| `nix/modules/home/git.nix` | `~/.gitconfig` 保護 + `config/git/*` | ✅ Tier1 `link.zsh`（`fs::ensure_realfile` + `fs::link_file`）|
| `nix/modules/home/ssh.nix` | `~/.ssh/config` | ✅ Tier1 `link.zsh` |
| `nix/modules/home/starship.nix` `yazi.nix` `zed.nix` `ghostty.nix` | 設定ファイル symlink | ✅ Tier1 `link.zsh` |
| `nix/modules/home/misc.nix` | grip/cmux | ✅ Tier1 `link.zsh` |
| `nix/modules/home/claude.nix` | 静的ファイル symlink + skills clone + plugin sync + MCP merge | ✅ 静的ファイルは Tier1 `link.zsh`、clone/plugin/MCP は Tier2 `claude-sync.zsh`（1:1 移植、コメントで明記済み）|
| `nix/modules/home/codex.nix` | AGENTS.md/skills symlink + config.toml seed | ✅ 静的ファイルは Tier1 `link.zsh`、seed は Tier2 `codex-sync.zsh`（1:1 移植）|
| `nix/modules/home/hermes.nix` | SOUL.md symlink | ✅ Tier1 `link.zsh` |
| `nix/modules/home/languages.nix` | node/go/ruby/rust/python/dart（nixpkgs 固定） | ✅ Tier2 `languages.zsh`（mise、6.2 節で確定済みの意図的な方式転換）|
| `nix/modules/home/corepack.nix` | corepack shim 生成 | ✅ Tier2 `languages.zsh` 末尾（mise 管理 node の corepack を enable）|
| `nix/modules/home/packages.nix` | CLI tool 群（devbox 含む） | ✅ devbox 以外は `homebrew.nix`（Tier2 で追記済み、grep で確認済み: jq/bats-core/pwgen/qpdf/ffmpeg/ripgrep/fzf/gh/ghq/lazygit/lazydocker/jj/jjui/kubectl/kubectx/stern/sops/uv/agent-browser/tmux/mosh）。devbox は 2026-08-22 承認で廃止確定、移植先なし（意図的）|
| `nix/modules/home/direnv.nix` | direnv + nix-direnv | 廃止確定（2026-08-22 承認）。移植先なし（意図的）|
| `nix/modules/darwin/defaults.nix` | macOS defaults 73 件 + role 別 Dock | ✅ Tier2 `defaults.zsh`（1:1 移植、コメントで明記済み） |
| `nix/modules/darwin/hitoolbox.nix` | IME/入力ソース `defaults import` | ✅ Tier2 `defaults.zsh` 末尾（同一 plist ファイルを参照） |
| `nix/modules/darwin/pam.nix` | Touch ID for sudo | ✅ Tier2 `pam.zsh`（1:1 移植） |
| `nix/modules/darwin/fonts.nix` | UDEV Gothic / JetBrains Mono | ✅ `homebrew.nix` casks（Tier2 で追記済み、font-sf-mono と経路統一） |

**維持するファイル**: `nix/darwin.nix`（imports を `homebrew.nix` のみに縮小）、
`nix/flake.nix`（home-manager input/wiring を削除）、`nix/modules/darwin/homebrew.nix`（無変更）。

**副次的に削除するファイル**: `nix/scripts/migrate-symlinks.zsh`。home-manager の
`backupFileExtension` 起因の dir-symlink 問題を解消するための専用ツールであり、
home-manager 自体の廃止によって存在意義を失う（bats テスト対象外のため削除は安全）。

## 3. `setup/cutover.zsh`

**役割**: 実機で「home-manager を含む flake」から「Homebrew/CLI/mise 層のみの flake」へ
安全に切り替える。Tier 1/2 のスクリプト自体はオーケストレーションしない
（両者は既に独立して明示実行するものとして確立済みのため、責務を混ぜない）。

```
1. util::info "=== Tier 3: cutover ==="
2. 現行世代のバックアップ記録（初回のみ、defaults::backup_once と同じ思想）:
   ${HOME}/.dotfiles-cutover-backup/pre-cutover-generations-<timestamp>.txt に
   `darwin-rebuild --list-generations` の出力をそのまま保存（世代番号のパースはしない。
   壊れやすい文字列解析を避け、監査記録としてそのまま残す）
3. pre-flight ビルド確認（副作用なし）:
   `nix build "${DOTFILES_ROOT}/nix#darwinConfigurations.default.system" --no-link --impure`
   失敗したら exit 1（switch へ進まない）
4. 実カットオーバー:
   `darwin-rebuild switch --flake "${DOTFILES_ROOT}/nix#default" --impure`
5. 完了メッセージ + rollback 手順の案内（setup/rollback.zsh を参照する旨）
```

**呼び出し規約**: pam.zsh と同じく、スクリプト自身は `sudo` を内部で呼ばない。
実機での実行は `sudo USER=$USER zsh ${HOME}/.dotfiles/setup/cutover.zsh`
（root 権限と `USER` 環境変数の両方が必要なため、README にこの形で明記する）。

**テスト方針**: `darwin-rebuild`/`nix` を PATH 上の stub に差し替え、
- 世代バックアップファイルが作成されること
- pre-flight build 失敗時に switch が呼ばれないこと（ログに記録されないことで検証）
- pre-flight build 成功時に `switch --flake ... --impure` が正しい引数で呼ばれること
- 2 回目実行時は世代バックアップの重複作成をしない（ファイル名にタイムスタンプを含むため
  「同一ファイルへの重複書き込みをしない」ではなく「バックアップ自体は毎回スキップしない」
  仕様であることをテストで明示する。理由: 世代番号は switch のたびに変わるため、
  `defaults::backup_once` と異なり「初回のみ」ではなく「毎回記録」が正しい）

## 4. `setup/rollback.zsh`

**役割**: 実機カットオーバー失敗時に、`darwin-rebuild switch --rollback` で直前世代
（home-manager を含む生成物）へ戻す。ただし、home-manager 再活性化時に
`backupFileExtension = "before-nix"` が衝突する既知リスクを防ぐガードを持つ。

**リスクの詳細**: Tier 1 の `fs::link_file` は、home-manager が作った nix-store 経由の
symlink を検知すると unlink して repo 直結の plain symlink に張り替える。ロールバックで
home-manager を再度活性化すると、home-manager はこの plain symlink を「想定外の状態」と
みなし、`.before-nix` へ退避しようとする。だが `.before-nix` は初回 Nix 移行時に**既に
使用済み**のため、home-manager は「退避先が存在する」エラーで停止し、ロールバックが
中途半端な状態で失敗する可能性がある。

**対処（fail-closed、上書きオプションなし）**:

```
1. util::info "=== Tier 3: rollback ==="
2. ${HOME} 配下を再帰的に glob して *.before-nix ファイルを検出
   （zsh glob qualifier `(N)` で no-match を許容）
3. 1 件でも見つかれば一覧を出して exit 1（darwin-rebuild を一切呼ばない）
   - 理由: fs::ensure_realfile と同じ no-data-loss 方針（無条件の自動退避はしない）
   - 対処はユーザーに委ねる（手動で .before-nix を確認・退避してから再実行）
4. 衝突が無ければ `darwin-rebuild switch --rollback` を実行
5. 完了メッセージ
```

**テスト方針**: `darwin-rebuild` を stub に差し替え、
- `.before-nix` ファイルが存在する場合に exit 1 かつ stub が一切呼ばれないこと
- 存在しない場合に `switch --rollback` が呼ばれること

## 5. `nix/flake.nix` / `nix/darwin.nix` の変更

- `flake.nix`: `home-manager` input の宣言、`home-manager.darwinModules.home-manager`
  の import、`home-manager.*` 設定ブロック（`useGlobalPkgs`/`useUserPackages`/
  `backupFileExtension`/`users.${username}`/`extraSpecialArgs`）を削除。
  `darwinConfigurations.default.system.modules` は `[ ./darwin.nix ]` のみになる。
- `darwin.nix`: `imports` を `[ ./modules/darwin/homebrew.nix ]` のみに縮小。
  `fonts.nix`/`pam.nix`/`defaults.nix`/`hitoolbox.nix` の import 行とコメントを削除。
- `users.users.${username}` ブロック（コメントに「home-manager から参照される」とある）は
  nix-darwin 自体の user 宣言としても意味があるため維持する（削除しない）。

## 6. ドキュメント更新

| ファイル | 変更内容 |
|---|---|
| `setup/README.md` | `cutover.zsh`/`rollback.zsh` の使い方・安全策・実行規約を追記 |
| `AGENTS.md`（root） | リポジトリ構造節: `nix/` の説明を「Homebrew パッケージ管理のみ」に更新、`setup/` の説明に cutover/rollback を追記。「棚卸 → triage → 翻訳ワークフロー」の翻訳先を `defaults.nix` → `setup/defaults.zsh` に更新 |
| `nix/README.md` | 「既存 PC 移行手順 (dir-symlink → proper directory)」節を削除（対象ツール削除のため）。「プロジェクトごとの言語バージョン管理 (devbox)」節を削除（廃止確定のため）。「ロールバック」節の home-manager 個別ロールバックの記述を削除、Tier 3 rollback.zsh への導線を追記。「アプリ・パッケージの追加」節を Homebrew/mise 経由のみの手順に更新 |
| `README.md`（root） | 新規マシンのセットアップ手順に Tier 1 (`setup/link.zsh`) / Tier 2 (`setup/*.zsh`) の実行ステップを追記（新規機は home-manager 状態を持たないため `cutover.zsh` は不要、通常の nix apply + script 実行の順で足りる旨を明記） |

historical spec/plan doc（`2026-08-21-restore-script-management-inventory.md` 等）は過去の
決定記録として扱い、遡って書き換えない。

## 7. テスト戦略（TDD）

`setup/tests/cutover.bats` / `setup/tests/rollback.bats` を新設。既存の `pam.bats`/
`languages.bats`/`defaults.bats` と同じ stub パターン（PATH 上に `darwin-rebuild`/`nix` の
偽実行ファイルを置き、呼び出し引数をログファイルに記録して assertion する）を踏襲する。
実際の `darwin-rebuild switch`/`nix build` は一切実行されない。

nix 側の変更（`flake.nix`/`darwin.nix` の縮小、ファイル削除）は `nix flake check --impure`
と `USER=ciuser nix build .#darwinConfigurations.default.system --no-link --impure` で
サンドボックス検証する（既存 CI と同じコマンド、副作用なし）。

## 8. ロールバックの全体像（このドキュメントが提供する安全網）

1. **PR レベル**: 本 PR は git commit として分離されているため、実機カットオーバー前に
   問題が見つかれば PR を単純に閉じる/取り込まないだけで済む
2. **リポジトリレベル**: 実機カットオーバー後に問題が発覚した場合、`git revert` で
   `nix/home.nix` 等を復元できる（Nix ファイルは削除されるだけで書き換えられないため、
   revert は competing edits なしに機械的に成功する）
3. **実機レベル**: `setup/rollback.zsh` が `.before-nix` 衝突を検知した上で
   `darwin-rebuild switch --rollback` を実行し、直前世代（home-manager 込み）を復元する。
   nix の世代管理はストア上の実体に基づくため、リポジトリ側でファイルを削除した後でも
   ロールバック自体は機能する（ガベージコレクションされない限り）

## 9. 自己レビュー（プレースホルダ・矛盾・曖昧性チェック）

- プレースホルダ・TBD: なし
- 内部矛盾: cutover.zsh/rollback.zsh とも「sudo を内部で呼ばない」規約を pam.zsh と揃えて
  明記、テスト方針もその前提で記述、一貫している
- スコープ: Tier 1/2 を再オーケストレーションしない（責務境界を明確化）ことで、
  cutover.zsh を薄く保っている。単一 PR で完結する範囲に収まっている
- 曖昧性: 世代バックアップの「毎回記録 vs 初回のみ」の解釈差を明記して解消済み
