# setup/

Tier 1（リアルタイム symlink）・Tier 2（明示的スクリプト実行）・Tier 3（カットオーバー・
ロールバック）の実装。`darwin-rebuild switch` を使わず、このディレクトリの script を実行して
dotfiles を `$HOME` へ配置・適用する。

設計の全体像・Tier 1/Tier 2 の境界・確定した設計判断は
`docs/superpowers/specs/2026-08-21-restore-script-management-inventory.md` を参照。
Tier 2 の実装計画（各スクリプトの詳細仕様・テスト戦略）は
`docs/superpowers/plans/2026-08-22-restore-script-management-tier2.md` を参照。
Tier 3（カットオーバー・ロールバック機構、home-manager 関連 Nix 定義の廃止）の設計は
`docs/superpowers/specs/2026-08-22-restore-script-management-tier3-cutover-design.md` を参照。
Tier を跨いだ実行順序・部分適用の検出/復旧を担う `setup/migrate.zsh` の設計・過去のインシデント
分析は `docs/superpowers/specs/2026-08-22-migrate-orchestrator-recovery-plan.md` を参照。

## 使い方（実機での唯一のエントリポイントは `setup/migrate.zsh`）

Tier 1/2/3 の各スクリプト（`link.zsh`/`languages.zsh`/`defaults.zsh`/`pam.zsh`/
`claude-sync.zsh`/`codex-sync.zsh`/`cutover.zsh`）を実機で直接実行することは非推奨。
順序管理なしに個別実行すると部分適用インシデントを再現する（過去に実際に発生した）。
実機での実行は必ず `setup/migrate.zsh` からのみ行う:

```sh
# 現在の状態と実行計画を確認する（副作用なし。まずこれを実行する）
zsh ${HOME}/.dotfiles/setup/migrate.zsh --dry-run

# 計画を実行する。Phase 2 (cutover/pam) は root が必要なため、
# 促されたら sudo を付けて再実行する（最大 3 回の呼び出しになりうる。詳細は
# docs/superpowers/specs/2026-08-22-migrate-orchestrator-recovery-plan.md 参照）
zsh ${HOME}/.dotfiles/setup/migrate.zsh --apply
sudo USER=${USER} zsh ${HOME}/.dotfiles/setup/migrate.zsh --apply
zsh ${HOME}/.dotfiles/setup/migrate.zsh --apply

# 失敗時のロールバック（migrate.zsh は自動では一切呼ばない。人間の判断でのみ実行する）
sudo zsh ${HOME}/.dotfiles/setup/rollback.zsh
```

`migrate.zsh` は各ステップの実行状況を `~/.dotfiles-migrate/manifest.log` に永続化し、既に
success したステップは再実行しない（idempotent）。全ステップが success になるまで `--apply` は
非ゼロ終了コードを返し続ける（部分適用を健全な状態として扱わない）。

個別スクリプトの直接実行はメンテナンス目的（単体テスト・特定ステップだけをデバッグしたい場合等）
でのみ行う:

```sh
zsh ${HOME}/.dotfiles/setup/link.zsh
zsh ${HOME}/.dotfiles/setup/languages.zsh
zsh ${HOME}/.dotfiles/setup/defaults.zsh
zsh ${HOME}/.dotfiles/setup/pam.zsh
zsh ${HOME}/.dotfiles/setup/claude-sync.zsh
zsh ${HOME}/.dotfiles/setup/codex-sync.zsh
sudo USER=${USER} zsh ${HOME}/.dotfiles/setup/cutover.zsh
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
- `cutover.zsh`: 実行前に `darwin-rebuild --list-generations` の出力を
  `~/.dotfiles-cutover-backup/pre-cutover-generations-<timestamp>.txt` へ記録してから
  `nix build`（副作用なし）で pre-flight 確認し、成功したときだけ `darwin-rebuild switch`
  を実行する。build 失敗時は switch を実行しない。
- `rollback.zsh`: `darwin-rebuild switch --rollback` を実行する前に `$HOME` 配下の
  `*.before-nix` 残骸を検出する。1 件でも見つかれば一覧を出して停止し、`darwin-rebuild` を
  一切呼ばない（home-manager 再活性化時の backupFileExtension 衝突を防ぐため。
  `fs::ensure_realfile` と同じ no-data-loss 方針で、自動退避はしない）。
- `migrate.zsh`: Tier 1/2/3 を跨いだ唯一のオーケストレーター。実行順序は Phase 1
  (`link`) → Phase 2 (`cutover`/`pam`、root 必須) → Phase 3 (`languages`/`defaults`/
  `claude-sync`/`codex-sync`)。`languages.zsh` 自身が「mise は darwin-switch で事前導入
  済みが前提」と明記しているため、cutover を languages より先に置く。各ステップの結果は
  `~/.dotfiles-migrate/manifest.log` に永続化し、success 済みステップは再実行しない
  （idempotent な部分適用検出・再開）。権限不足なステップは blocked として記録し、その
  Phase 内の残りは試行を続けるが次の Phase へは進まない（Phase 境界は厳格）。実失敗は
  即座に全体を停止する（fail-closed）。`rollback.zsh` は一切呼ばない（no-automatic-rollback、
  常に人間の明示判断）。全ステップ success 後も、manifest の自己申告を信用せず各ステップの
  実際の効果をファイルシステムから再検証する health check を通らない限り成功とみなさない。
  設計根拠・過去のインシデント分析は
  `docs/superpowers/specs/2026-08-22-migrate-orchestrator-recovery-plan.md` を参照。

## テスト

```sh
bats setup/tests/*.bats
```

`fs::link_file`/`fs::ensure_realfile` は関数単位、`link.zsh`/`languages.zsh`/`defaults.zsh`/
`pam.zsh`/`claude-sync.zsh`/`codex-sync.zsh`/`cutover.zsh`/`rollback.zsh`/`migrate.zsh` は、
実コマンド（`defaults`/`mise`/`corepack`/`claude`/`git`/`darwin-rebuild`/`nix`）を PATH 上の
stub 実行ファイルに差し替え、`$HOME` を一時ディレクトリに差し替えたサンドボックスでの統合テスト
（実機・実ネットワーク・実パッケージマネージャ・実 `darwin-rebuild switch` には一切触れない）。
`migrate.zsh` のテストは Tier 1 が作る `~/.zshenv` symlink を経由して後続の子 `zsh` プロセスが
実際の zshenv を re-source する（Phase を跨いだ実行を初めて連結するテストのため、単独スクリプトの
テストでは踏まなかった経路）。stub 実行ファイルを `#!/bin/bash` にしているのはこのため
（`#!/bin/zsh` だと stub 自身が `~/.zshenv` を再度 source し、そこでの `mise activate --shims`
がまた `mise` を呼ぶ無限再帰になる）。CI は `.github/workflows/setup-check.yml` が `setup/**`
の変更ごとに実行する。
