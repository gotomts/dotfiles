# Tier 3（カットオーバー・ロールバック機構 + Nix 定義の廃止）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `setup/cutover.zsh`/`setup/rollback.zsh` を新設し、home-manager 関連の Nix 定義
（`nix/home.nix`・`nix/modules/home/**`）と Tier 2 で script 側へ移植済みの nix-darwin
モジュール（`defaults.nix`/`hitoolbox.nix`/`pam.nix`/`fonts.nix`）を削除、`flake.nix`/
`darwin.nix` を Homebrew のみの構成に縮小し、ドキュメントを更新する。

**Architecture:** Tier 1 (`setup/link.zsh`) / Tier 2 (`setup/*.zsh`) は既に home-manager の
責務を script 側へ並行構築済み（PR #53/#54）。本 PR はその「並行構築」を「唯一の実装」へ
一本化する最終層。`cutover.zsh`/`rollback.zsh` は Tier 1/2 をオーケストレーションしない薄い
ラッパで、実 `darwin-rebuild`/`nix` コマンドは stub 経由でテストする（既存 `pam.bats`/
`languages.bats` と同じパターン）。

**Tech Stack:** zsh（`set -eu`）、bats（`setup/tests/*.bats`）、Nix flakes。

**Spec:** `docs/superpowers/specs/2026-08-22-restore-script-management-tier3-cutover-design.md`

## Global Constraints

- 本 PR の範囲では `darwin-rebuild switch` を一切実行しない（`nix build`/`nix flake check`
  は副作用なしのため実行可）。実 `$HOME`/`brew install`/`defaults write`/PAM 書き込み/
  `mise install`/Claude・Codex sync も同様に一切実行しない。
- `cutover.zsh`/`rollback.zsh` は内部で `sudo` を呼ばない（`pam.zsh` と同じ規約）。
- `rollback.zsh` の `.before-nix` 衝突ガードは fail-closed・自動退避なし（上書きオプション
  を持たない）。
- テストは PATH 上の stub 実行ファイルと一時 `$HOME` のみで完結させる（既存 `setup/tests/`
  の全ファイルと同じサンドボックス方針）。
- `nix/modules/darwin/hitoolbox.plist`/`inputsources.plist` は削除しない
  （`setup/defaults.zsh` が単一ソースとして直接参照しているデータファイルのため）。

---

## Task 1: `setup/cutover.zsh`

**Files:**
- Create: `setup/cutover.zsh`
- Test: `setup/tests/cutover.bats`

**Interfaces:**
- Consumes: `setup/lib/util.zsh`（`util::info`/`util::action`/`util::error`）
- Produces: 実行可能スクリプト。呼び出し規約は `sudo USER=$USER zsh setup/cutover.zsh`
  （後続タスクの `setup/README.md` から参照される）

- [ ] **Step 1: テストディレクトリに stub ヘルパー付きの失敗するテストを書く**

`setup/tests/cutover.bats` を新規作成:

```bash
#!/usr/bin/env bats
# setup/tests/cutover.bats

SETUP_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
REPO_ROOT="$(cd "${SETUP_DIR}/.." && pwd)"

# stub darwin-rebuild / nix that record every invocation.
# nix_exit controls the exit code nix returns (used to simulate pre-flight build failure).
_install_stubs() {
    local bin_dir="${1}"
    local nix_exit="${2:-0}"
    mkdir -p "${bin_dir}"

    cat > "${bin_dir}/darwin-rebuild" <<EOF
#!/bin/zsh
echo "\$*" >> "${DARWIN_REBUILD_LOG}"
if [[ "\$1" == "--list-generations" ]]; then
    echo "42 2026-08-20 10:00:00 (current)"
fi
exit 0
EOF
    chmod +x "${bin_dir}/darwin-rebuild"

    cat > "${bin_dir}/nix" <<EOF
#!/bin/zsh
echo "\$*" >> "${NIX_LOG}"
exit ${nix_exit}
EOF
    chmod +x "${bin_dir}/nix"
}

setup() {
    STUB_BIN="${BATS_TEST_TMPDIR}/stub-bin"
    DARWIN_REBUILD_LOG="${BATS_TEST_TMPDIR}/darwin-rebuild.log"
    NIX_LOG="${BATS_TEST_TMPDIR}/nix.log"
    : > "${DARWIN_REBUILD_LOG}"
    : > "${NIX_LOG}"
    export DARWIN_REBUILD_LOG NIX_LOG
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}"
}

@test "zsh -n syntax check passes" {
    run zsh -n "${SETUP_DIR}/cutover.zsh"
    [ "${status}" -eq 0 ]
}

@test "cutover.zsh records current generations to a timestamped backup file" {
    _install_stubs "${STUB_BIN}" 0
    PATH="${STUB_BIN}:${PATH}" run zsh "${SETUP_DIR}/cutover.zsh"
    [ "${status}" -eq 0 ]

    run bash -c "ls ${HOME}/.dotfiles-cutover-backup/pre-cutover-generations-*.txt | wc -l"
    (( $(echo "${output}" | tr -d ' ') >= 1 ))

    run cat "${DARWIN_REBUILD_LOG}"
    [[ "${output}" == *"--list-generations"* ]]
}

@test "cutover.zsh runs pre-flight nix build before switch" {
    _install_stubs "${STUB_BIN}" 0
    PATH="${STUB_BIN}:${PATH}" run zsh "${SETUP_DIR}/cutover.zsh"
    [ "${status}" -eq 0 ]

    run cat "${NIX_LOG}"
    [[ "${output}" == *"build ${REPO_ROOT}/nix#darwinConfigurations.default.system --no-link --impure"* ]]
}

@test "cutover.zsh calls darwin-rebuild switch with the flake path and --impure" {
    _install_stubs "${STUB_BIN}" 0
    PATH="${STUB_BIN}:${PATH}" run zsh "${SETUP_DIR}/cutover.zsh"
    [ "${status}" -eq 0 ]

    run cat "${DARWIN_REBUILD_LOG}"
    [[ "${output}" == *"switch --flake ${REPO_ROOT}/nix#default --impure"* ]]
}

@test "cutover.zsh aborts before switch when pre-flight nix build fails" {
    _install_stubs "${STUB_BIN}" 1
    PATH="${STUB_BIN}:${PATH}" run zsh "${SETUP_DIR}/cutover.zsh"
    [ "${status}" -eq 1 ]

    run cat "${DARWIN_REBUILD_LOG}"
    [[ "${output}" != *"switch"* ]]
}
```

- [ ] **Step 2: テストを実行して FAIL することを確認**

Run: `bats setup/tests/cutover.bats`
Expected: FAIL（`setup/cutover.zsh` が存在しないため全テストがエラー）

- [ ] **Step 3: `setup/cutover.zsh` を実装する**

```bash
#!/bin/zsh
# setup/cutover.zsh
#
# Tier 3: home-manager を含む flake から Homebrew/CLI/mise 層のみの flake へ
# 実機を切り替える。Tier 1 (setup/link.zsh) / Tier 2 (setup/*.zsh) 自体はオーケストレーション
# しない（責務を混ぜない。両者は独立して明示実行するものとして既に確立済み）。
#
# 設計根拠: docs/superpowers/specs/2026-08-22-restore-script-management-tier3-cutover-design.md
#
# 呼び出し規約: pam.zsh と同じくスクリプト自身は sudo を内部で呼ばない。
# 実機での実行は以下の形で行う（root 権限と USER 環境変数の両方が必要）:
#   sudo USER=$USER zsh ${HOME}/.dotfiles/setup/cutover.zsh
#
# 終了コード:
#   0  成功
#   1  pre-flight build 失敗（switch は実行されない）

set -eu

SETUP_DIR="${0:A:h}"
DOTFILES_ROOT="${SETUP_DIR:h}"
source "${SETUP_DIR}/lib/util.zsh"

util::info "=== Tier 3: cutover ==="

# ---------------------------------------------------------------------------
# 1. 現行世代を記録する（監査用ログ）。defaults.zsh の backup_once と異なり毎回記録する。
#    世代番号は switch のたびに変わるため「初回のみ」は不適切。
# ---------------------------------------------------------------------------
BACKUP_DIR="${HOME}/.dotfiles-cutover-backup"
mkdir -p "${BACKUP_DIR}"

timestamp="$(date +%Y%m%d%H%M%S)"
generations_log="${BACKUP_DIR}/pre-cutover-generations-${timestamp}.txt"

util::action "現行世代を記録: ${generations_log}"
darwin-rebuild --list-generations > "${generations_log}"

# ---------------------------------------------------------------------------
# 2. pre-flight ビルド確認（副作用なし）
# ---------------------------------------------------------------------------
util::info "=== pre-flight: nix build ==="
if ! nix build "${DOTFILES_ROOT}/nix#darwinConfigurations.default.system" --no-link --impure; then
    util::error "nix build に失敗しました。switch は実行しません"
    exit 1
fi

# ---------------------------------------------------------------------------
# 3. 実カットオーバー
# ---------------------------------------------------------------------------
util::info "=== darwin-rebuild switch ==="
darwin-rebuild switch --flake "${DOTFILES_ROOT}/nix#default" --impure

util::info "=== Tier 3: cutover 完了 ==="
util::info "問題が発生した場合は setup/rollback.zsh を実行してください"
```

- [ ] **Step 4: 実行権限を付与しテストを実行して PASS することを確認**

```bash
chmod +x setup/cutover.zsh
bats setup/tests/cutover.bats
```

Expected: PASS（4 tests, 0 failures）

- [ ] **Step 5: commit**

```bash
git add setup/cutover.zsh setup/tests/cutover.bats
git commit -m "feat(setup): add Tier 3 cutover.zsh (pre-flight build + darwin-rebuild switch)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 2: `setup/rollback.zsh`

**Files:**
- Create: `setup/rollback.zsh`
- Test: `setup/tests/rollback.bats`

**Interfaces:**
- Consumes: `setup/lib/util.zsh`
- Produces: 実行可能スクリプト。呼び出し規約は `sudo zsh setup/rollback.zsh`

- [ ] **Step 1: 失敗するテストを書く**

`setup/tests/rollback.bats` を新規作成:

```bash
#!/usr/bin/env bats
# setup/tests/rollback.bats

SETUP_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

_install_darwin_rebuild_stub() {
    local bin_dir="${1}"
    mkdir -p "${bin_dir}"
    cat > "${bin_dir}/darwin-rebuild" <<EOF
#!/bin/zsh
echo "\$*" >> "${DARWIN_REBUILD_LOG}"
exit 0
EOF
    chmod +x "${bin_dir}/darwin-rebuild"
}

setup() {
    STUB_BIN="${BATS_TEST_TMPDIR}/stub-bin"
    DARWIN_REBUILD_LOG="${BATS_TEST_TMPDIR}/darwin-rebuild.log"
    : > "${DARWIN_REBUILD_LOG}"
    export DARWIN_REBUILD_LOG
    _install_darwin_rebuild_stub "${STUB_BIN}"
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}"
}

@test "zsh -n syntax check passes" {
    run zsh -n "${SETUP_DIR}/rollback.zsh"
    [ "${status}" -eq 0 ]
}

@test "rollback.zsh calls darwin-rebuild switch --rollback when no .before-nix files exist" {
    PATH="${STUB_BIN}:${PATH}" run zsh "${SETUP_DIR}/rollback.zsh"
    [ "${status}" -eq 0 ]

    run cat "${DARWIN_REBUILD_LOG}"
    [[ "${output}" == *"switch --rollback"* ]]
}

@test "rollback.zsh refuses and never calls darwin-rebuild when a .before-nix file exists" {
    mkdir -p "${HOME}/.config"
    echo "stale" > "${HOME}/.config/foo.before-nix"

    PATH="${STUB_BIN}:${PATH}" run zsh "${SETUP_DIR}/rollback.zsh"
    [ "${status}" -eq 1 ]

    run cat "${DARWIN_REBUILD_LOG}"
    [ -z "${output}" ]
}

@test "rollback.zsh detects .before-nix files nested in subdirectories" {
    mkdir -p "${HOME}/.claude/hooks"
    echo "stale" > "${HOME}/.claude/hooks/one-question-per-turn.py.before-nix"

    PATH="${STUB_BIN}:${PATH}" run zsh "${SETUP_DIR}/rollback.zsh"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"one-question-per-turn.py.before-nix"* ]]
}
```

- [ ] **Step 2: テストを実行して FAIL することを確認**

Run: `bats setup/tests/rollback.bats`
Expected: FAIL（`setup/rollback.zsh` が存在しないため全テストがエラー）

- [ ] **Step 3: `setup/rollback.zsh` を実装する**

```bash
#!/bin/zsh
# setup/rollback.zsh
#
# Tier 3: setup/cutover.zsh 実行後に問題が見つかった場合、直前世代（home-manager を
# 含む生成物）へ戻す。home-manager 再活性化時に backupFileExtension = "before-nix" が
# 既存の .before-nix と衝突して失敗する既知リスクがあるため、実行前に .before-nix
# ファイルの残骸を検出し、見つかった場合は fail-closed で停止する
# （fs::ensure_realfile と同じ no-data-loss 方針。自動退避はしない）。
#
# 設計根拠: docs/superpowers/specs/2026-08-22-restore-script-management-tier3-cutover-design.md
#
# 呼び出し規約: pam.zsh/cutover.zsh と同じくスクリプト自身は sudo を内部で呼ばない。
# 実機での実行は以下の形で行う:
#   sudo zsh ${HOME}/.dotfiles/setup/rollback.zsh
#
# 終了コード:
#   0  成功
#   1  .before-nix の残骸を検出したため停止（darwin-rebuild は一切呼ばれない）

set -eu

SETUP_DIR="${0:A:h}"
source "${SETUP_DIR}/lib/util.zsh"

util::info "=== Tier 3: rollback ==="

# ---------------------------------------------------------------------------
# 1. .before-nix 残骸の検出（fail-closed）
#    (N) glob qualifier: マッチしない場合に空配列を返す（nullglob をこのパターンだけに適用）
# ---------------------------------------------------------------------------
stale_backups=("${HOME}"/**/*.before-nix(N))

if (( ${#stale_backups[@]} > 0 )); then
    util::error "以下の .before-nix バックアップが既に存在するため rollback を中止します:"
    for backup_file in "${stale_backups[@]}"; do
        util::error "  ${backup_file}"
    done
    util::error "home-manager 再活性化時にこれらと衝突する可能性があります。"
    util::error "手動で確認・退避してから再実行してください（darwin-rebuild は実行していません）"
    exit 1
fi

# ---------------------------------------------------------------------------
# 2. rollback 実行
# ---------------------------------------------------------------------------
util::info "=== darwin-rebuild switch --rollback ==="
darwin-rebuild switch --rollback

util::info "=== Tier 3: rollback 完了 ==="
```

- [ ] **Step 4: 実行権限を付与しテストを実行して PASS することを確認**

```bash
chmod +x setup/rollback.zsh
bats setup/tests/rollback.bats
```

Expected: PASS（4 tests, 0 failures）

- [ ] **Step 5: commit**

```bash
git add setup/rollback.zsh setup/tests/rollback.bats
git commit -m "feat(setup): add Tier 3 rollback.zsh (.before-nix fail-closed guard)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 3: `setup/README.md` を更新

**Files:**
- Modify: `setup/README.md`

**Interfaces:**
- Consumes: Task 1/2 で確定した呼び出し規約（`sudo USER=$USER zsh setup/cutover.zsh` /
  `sudo zsh setup/rollback.zsh`）

- [ ] **Step 1: 「使い方」節に Tier 3 コマンドを追記**

`setup/README.md` の使い方コードブロック（Tier 2 の行の直後）に追記:

```
old_string:
zsh ${HOME}/.dotfiles/setup/codex-sync.zsh  # config.toml seed-if-absent
```
```

```
new_string:
zsh ${HOME}/.dotfiles/setup/codex-sync.zsh  # config.toml seed-if-absent

# Tier 3: home-manager を含まない flake への実機切替（既存 PC のみ、新規 PC は不要）
sudo USER=${USER} zsh ${HOME}/.dotfiles/setup/cutover.zsh   # 切替
sudo zsh ${HOME}/.dotfiles/setup/rollback.zsh                # 失敗時のロールバック
```

- [ ] **Step 2: 冒頭の説明文に Tier 3 の位置づけを追記**

```
old_string:
Tier 2 の実装計画（各スクリプトの詳細仕様・テスト戦略）は
`docs/superpowers/plans/2026-08-22-restore-script-management-tier2.md` を参照。
```

```
new_string:
Tier 2 の実装計画（各スクリプトの詳細仕様・テスト戦略）は
`docs/superpowers/plans/2026-08-22-restore-script-management-tier2.md` を参照。
Tier 3（カットオーバー・ロールバック機構、home-manager 関連 Nix 定義の廃止）の設計は
`docs/superpowers/specs/2026-08-22-restore-script-management-tier3-cutover-design.md` を参照。
```

- [ ] **Step 3: 「安全策」節に cutover/rollback の説明を追記**

`setup/README.md` の「安全策」節、`claude-sync.zsh`/`codex-sync.zsh` の箇条書きの直後に追記:

```
old_string:
- `claude-sync.zsh`/`codex-sync.zsh`: 破壊的な操作を行わない（MCP merge は add-only、
  config.toml は seed-if-absent、skills repo clone は既存ディレクトリを一切変更しない）。
```

```
new_string:
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
```

- [ ] **Step 4: 「テスト」節の対象スクリプト一覧に cutover/rollback を追記**

```
old_string:
`fs::link_file`/`fs::ensure_realfile` は関数単位、`link.zsh`/`languages.zsh`/`defaults.zsh`/
`pam.zsh`/`claude-sync.zsh`/`codex-sync.zsh` は、実コマンド（`defaults`/`mise`/`corepack`/
`claude`/`git`）を PATH 上の stub 実行ファイルに差し替え、`$HOME` を一時ディレクトリに
差し替えたサンドボックスでの統合テスト（実機・実ネットワーク・実パッケージマネージャには
一切触れない）。CI は `.github/workflows/setup-check.yml` が `setup/**` の変更ごとに実行する。
```

```
new_string:
`fs::link_file`/`fs::ensure_realfile` は関数単位、`link.zsh`/`languages.zsh`/`defaults.zsh`/
`pam.zsh`/`claude-sync.zsh`/`codex-sync.zsh`/`cutover.zsh`/`rollback.zsh` は、実コマンド
（`defaults`/`mise`/`corepack`/`claude`/`git`/`darwin-rebuild`/`nix`）を PATH 上の stub
実行ファイルに差し替え、`$HOME` を一時ディレクトリに差し替えたサンドボックスでの統合テスト
（実機・実ネットワーク・実パッケージマネージャ・実 `darwin-rebuild switch` には一切触れない）。
CI は `.github/workflows/setup-check.yml` が `setup/**` の変更ごとに実行する。
```

- [ ] **Step 5: commit**

```bash
git add setup/README.md
git commit -m "docs(setup): document Tier 3 cutover/rollback usage

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 4: home-manager 関連 Nix 定義を削除し `flake.nix`/`darwin.nix` を縮小

**Files:**
- Delete: `nix/home.nix`
- Delete: `nix/modules/home/` (全 15 ファイル: `claude.nix` `codex.nix` `corepack.nix`
  `direnv.nix` `ghostty.nix` `git.nix` `hermes.nix` `languages.nix` `misc.nix` `packages.nix`
  `ssh.nix` `starship.nix` `yazi.nix` `zed.nix` `zsh.nix`)
- Delete: `nix/modules/darwin/defaults.nix`
- Delete: `nix/modules/darwin/hitoolbox.nix`（`hitoolbox.plist`/`inputsources.plist` は
  `setup/defaults.zsh` が直接参照するデータファイルのため**削除しない**）
- Delete: `nix/modules/darwin/pam.nix`
- Delete: `nix/modules/darwin/fonts.nix`
- Delete: `nix/scripts/migrate-symlinks.zsh`（home-manager の dir-symlink 問題専用ツールで
  対象喪失により無意味化。bats テスト対象外のため削除は安全）
- Modify: `nix/flake.nix`
- Modify: `nix/darwin.nix`

**Interfaces:**
- Consumes: Task 2 のカバレッジ監査結果（`docs/superpowers/specs/2026-08-22-restore-script-management-tier3-cutover-design.md` 2 節）
- Produces: `nix build .#darwinConfigurations.default.system` が home-manager なしで成功する
  状態（後続タスクのドキュメント更新が前提とする）

- [ ] **Step 1: home-manager 系ファイルを削除**

```bash
git rm nix/home.nix
git rm -r nix/modules/home
git rm nix/modules/darwin/defaults.nix
git rm nix/modules/darwin/hitoolbox.nix
git rm nix/modules/darwin/pam.nix
git rm nix/modules/darwin/fonts.nix
git rm nix/scripts/migrate-symlinks.zsh
```

- [ ] **Step 2: `nix/flake.nix` から home-manager の input/wiring を削除**

```
old_string:
{
  description = "gotomts macOS dotfiles via nix-darwin + home-manager";

  inputs = {
    # Phase A は unstable を使用 (home-manager との整合性優先)。
    # stable に切り替える場合は nixpkgs-YY.MM 形式に変更し、
    # home.stateVersion も対応バージョンに更新すること。
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-darwin,
      home-manager,
      ...
    }@inputs:
```

```
new_string:
{
  description = "gotomts macOS dotfiles via nix-darwin (Homebrew package management)";

  inputs = {
    # nixpkgs-unstable を使用（Homebrew/CLI tool の追従を優先）。
    # stable に切り替える場合は nixpkgs-YY.MM 形式に変更すること。
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-darwin,
      ...
    }@inputs:
```

- [ ] **Step 3: `nix/flake.nix` の `darwinConfigurations.default.modules` から home-manager
  wiring を削除**

```
old_string:
        modules = [
          ./darwin.nix
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            # home-manager が以前作った既存 symlink (~/.zshrc, ~/.claude/agents 等) を
            # 重複作成しようとして clobber エラーで弾かないよう、退避拡張子を指定する。
            # 初回 activation で既存ファイルは <file>.before-nix にリネームされる。
            home-manager.backupFileExtension = "before-nix";
            home-manager.users.${username} = import ./home.nix;
            home-manager.extraSpecialArgs = { inherit inputs username role; };
          }
        ];
```

```
new_string:
        modules = [
          ./darwin.nix
        ];
```

- [ ] **Step 4: `nix/darwin.nix` の imports を Homebrew のみに縮小**

```
old_string:
  imports = [
    # cask + mas + 例外 brew (S9)
    ./modules/darwin/homebrew.nix
    # SF Mono 等 (S11)。空リストで雛形のみ
    ./modules/darwin/fonts.nix
    # Touch ID for sudo (S11)
    ./modules/darwin/pam.nix
    # macOS defaults / Dock / Finder / Trackpad / Menubar etc. (S10)
    ./modules/darwin/defaults.nix
    # IME / 入力ソース。HIToolbox は array of dict 構造のため defaults import 方式
    ./modules/darwin/hitoolbox.nix
  ];
```

```
new_string:
  imports = [
    # cask + mas + brew。フォント/PAM/macOS defaults/IME/CLI tool/言語ランタイム/
    # running-config sync は Tier 3 で setup/*.zsh (Tier 1/2) へ移行済み。詳細は
    # docs/superpowers/specs/2026-08-22-restore-script-management-tier3-cutover-design.md
    ./modules/darwin/homebrew.nix
  ];
```

- [ ] **Step 5: `nix/darwin.nix` のユーザー宣言コメントを更新（home-manager 参照が消える
  ため）**

```
old_string:
  # ユーザー宣言（home-manager から参照される）
  users.users.${username} = {
```

```
new_string:
  # ユーザー宣言（nix-darwin が users.users.<name> として要求する最低限の宣言）
  users.users.${username} = {
```

- [ ] **Step 6: サンドボックスで検証（副作用なし）**

```bash
cd nix
nix flake check --impure --print-build-logs 2>&1 | tail -30
USER=ciuser nix build .#darwinConfigurations.default.system --no-link --impure --print-build-logs 2>&1 | tail -30
echo "exit: $?"
cd ..
```

Expected: 両方とも exit 0

- [ ] **Step 7: commit**

```bash
git add -A nix
git commit -m "refactor(nix): retire home-manager and Tier2-migrated darwin modules

home-manager 関連 (nix/home.nix, nix/modules/home/**) と Tier 2 で script 側へ
移植済みの nix-darwin モジュール (defaults/hitoolbox/pam/fonts.nix) を削除。
flake.nix/darwin.nix は Homebrew (homebrew.nix) のみを管理する構成に縮小。
hitoolbox.plist/inputsources.plist は setup/defaults.zsh が参照するため維持。
migrate-symlinks.zsh は対象喪失により削除。

カバレッジ監査:
docs/superpowers/specs/2026-08-21-restore-script-management-inventory.md
docs/superpowers/specs/2026-08-22-restore-script-management-tier3-cutover-design.md

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 5: `nix/README.md` を更新

**Files:**
- Modify: `nix/README.md`

**Interfaces:**
- Consumes: Task 4 で削除したファイル一覧（この節が参照していた対象の消滅を反映）

- [ ] **Step 1: 「ロールバック」節から home-manager 個別ロールバックを削除し Tier 3 への
  導線を追記**

```
old_string:
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
```

```
new_string:
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
```

- [ ] **Step 2: 「アプリ・パッケージの追加」節を Homebrew/mise のみの手順に更新**

```
old_string:
> **Tier 2 移行メモ (2026-08-22)**: `docs/superpowers/specs/2026-08-21-restore-script-management-inventory.md`
> の確定判断により、`packages.nix`/`languages.nix` の CLI tool・言語ランタイム・
> `fonts.nix` のフォントは最終的に Homebrew (`homebrew.nix`) / `setup/languages.zsh` (mise) へ
> 移行する。本 PR 時点では `homebrew.nix` に移行後の宣言（CLI tool・`mise`・3 フォント）を
> **追記のみ**しており、`packages.nix`/`languages.nix`/`fonts.nix` はまだ削除していない
> （実機切替は別途判断、`setup/README.md` 参照）。そのため下表の「配置先」は実機切替が完了する
> までの間、一時的に Homebrew と home-manager の両方に同名パッケージが宣言される状態になる
> （実害なし、redundant なだけ）。

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
```

```
new_string:
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
| Mac App Store アプリ | `nix/modules/darwin/homebrew.nix` の `masApps` | `{ "Xcode" = 497799835; }` |
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
```

- [ ] **Step 3: 「プロジェクトごとの言語バージョン管理 (devbox)」節を削除（devbox 廃止確定
  のため）**

```
old_string:
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
```

```
new_string:
## 既存 PC 移行手順 (dir-symlink → proper directory)
```

- [ ] **Step 4: 「既存 PC 移行手順 (dir-symlink → proper directory)」節を削除（対象ツール
  `nix/scripts/migrate-symlinks.zsh` を削除したため）**

```
old_string:
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
| `~/.claude/skills` | dir-symlink | home-manager が個別 skill を管理 |
| `~/.aliases` | file-symlink | home-manager が nix store 経由で再配置 |
| `~/.gitignore_global` | file-symlink | home-manager が nix store 経由で再配置 |
| `~/.grip/settings.py` | file-symlink | home-manager が nix store 経由で再配置 |
| `~/.config/cmux/config.ghostty` | file-symlink | home-manager が nix store 経由で再配置 |
| `~/.config/starship/starship.toml` | file-symlink | home-manager は `~/.config/starship.toml` に配置 |
| `~/.zshrc` | file-symlink | home-manager が nix store 経由で再配置 |
| `~/.zshenv` | file-symlink | home-manager が nix store 経由で再配置 |
| `~/.config/yazi/keymap.toml` | file-symlink | home-manager が nix store 経由で再配置 |

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
```

```
new_string:
## トラブルシューティング
```

- [ ] **Step 5: 差分を確認しファイルが壊れていないことを目視確認**

```bash
git diff nix/README.md | head -150
```

Expected: 意図した節（ロールバック/アプリ追加/devbox/dir-symlink 移行）だけが変更されている

- [ ] **Step 6: commit**

```bash
git add nix/README.md
git commit -m "docs(nix): update nix/README.md for Tier 3 (home-manager removal)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 6: `AGENTS.md`（root）を更新

**Files:**
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: Task 4 の削除結果（`nix/` の説明・棚卸ワークフローの翻訳先）

- [ ] **Step 1: 「リポジトリ構造」節の `nix/` の説明を更新**

```
old_string:
- `nix/` — nix-darwin + home-manager + flakes による環境構築定義（`darwin-rebuild` から参照される。詳細は `nix/README.md`）
```

```
new_string:
- `nix/` — nix-darwin + flakes による Homebrew パッケージ管理定義（`darwin-rebuild` から参照される。home-manager は Tier 3 で廃止済み、詳細は `nix/README.md`）
```

- [ ] **Step 2: 「重要な設計判断」節の stale な `rtk` overlay 記述を削除（`home/packages.nix`
  参照先が削除されるため。`nix/modules/overlays/` は現状のリポジトリに実在せず、記述が
  既に実態と乖離していたことを棚卸し中に確認済み）**

```
old_string:
- **`homebrew.onActivation.cleanup = "zap"`**: 宣言外パッケージは Cellar ごと削除する強い管理。宣言外のパッケージが残らないよう破壊的に同期する (`nix/modules/darwin/homebrew.nix` のコメント参照)
- **`rtk` overlay**: `flake.nix` の `rtk-src` input から `rustPlatform.buildRustPackage` でビルド。`nix/modules/overlays/rtk.nix` で `pkgs.rtk` として供給され、`home/packages.nix` から参照される
```

```
new_string:
- **`homebrew.onActivation.cleanup = "zap"`**: 宣言外パッケージは Cellar ごと削除する強い管理。宣言外のパッケージが残らないよう破壊的に同期する (`nix/modules/darwin/homebrew.nix` のコメント参照)
```

- [ ] **Step 3: 「棚卸 → triage → 翻訳ワークフロー」の翻訳先を `setup/defaults.zsh` に更新**

```
old_string:
macOS の `defaults` 値を `defaults.nix` に翻訳するための人間 in-the-loop プロセス:

1. `zsh nix/scripts/inventory.zsh` を実行 → `docs/inventory/<hostname>-<date>.md` 生成 (READ-ONLY)
2. 生成された Markdown を開き、各項目に `nix化 / 無視 / 検討` をマーク
3. triage 結果を `nix/modules/darwin/defaults.nix` に翻訳 (`nix/darwin.nix` から import)
4. `nix build` で検証 → `darwin-rebuild switch` で適用
```

```
new_string:
macOS の `defaults` 値を `setup/defaults.zsh` に翻訳するための人間 in-the-loop プロセス
（Tier 3 で `nix/modules/darwin/defaults.nix` から移行済み）:

1. `zsh nix/scripts/inventory.zsh` を実行 → `docs/inventory/<hostname>-<date>.md` 生成 (READ-ONLY)
2. 生成された Markdown を開き、各項目に `nix化 / 無視 / 検討` をマーク
3. triage 結果を `setup/defaults.zsh` に `defaults write` 行として翻訳
4. `bats setup/tests/defaults.bats` で検証 → 対象マシンで `zsh setup/defaults.zsh` を適用
```

- [ ] **Step 4: 差分を確認**

```bash
git diff AGENTS.md
```

Expected: 上記 3 箇所のみが変更されている

- [ ] **Step 5: commit**

```bash
git add AGENTS.md
git commit -m "docs: update AGENTS.md for Tier 3 (home-manager removal)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 7: root `README.md` を更新

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: Task 1〜3 で確定した Tier 1/2/3 コマンド一覧

- [ ] **Step 1: 新規マシンのセットアップ手順に Tier 1/2 の実行ステップを追記**

```
old_string:
5. Install Nix and apply
```terminal
zsh ~/.dotfiles/nix/scripts/install-nix.zsh
cd ~/.dotfiles/nix && sudo USER=$USER nix run nix-darwin -- switch --flake .#default --impure
```

See [`nix/README.md`](nix/README.md) for details.
```

```
new_string:
5. Install Nix and apply (Homebrew パッケージ層)
```terminal
zsh ~/.dotfiles/nix/scripts/install-nix.zsh
cd ~/.dotfiles/nix && sudo USER=$USER nix run nix-darwin -- switch --flake .#default --impure
```

See [`nix/README.md`](nix/README.md) for details.

6. Place dotfiles symlinks (Tier 1) and run explicit setup scripts (Tier 2)
```terminal
zsh ~/.dotfiles/setup/link.zsh
zsh ~/.dotfiles/setup/languages.zsh
zsh ~/.dotfiles/setup/defaults.zsh
zsh ~/.dotfiles/setup/pam.zsh
zsh ~/.dotfiles/setup/claude-sync.zsh
zsh ~/.dotfiles/setup/codex-sync.zsh
```

新規マシンは home-manager 状態を持たないため `setup/cutover.zsh` は不要（既存 PC を
home-manager 込みの旧構成から移行する場合のみ使う）。詳細は [`setup/README.md`](setup/README.md)
を参照。
```

- [ ] **Step 2: 差分を確認**

```bash
git diff README.md
```

- [ ] **Step 3: commit**

```bash
git add README.md
git commit -m "docs: add Tier 1/2 steps to root README setup flow

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 8: 全体のローカル検証

**Files:** なし（検証のみ）

- [ ] **Step 1: bats 全テストを実行**

```bash
bats setup/tests/*.bats | tail -30
echo "exit: $?"
```

Expected: exit 0、全 68 テスト（既存 60 + cutover 4 + rollback 4）PASS

- [ ] **Step 2: nix scripts のテストも実行（home.nix 削除の影響を受けないことを確認）**

```bash
bats nix/scripts/tests/*.bats
echo "exit: $?"
```

Expected: exit 0

- [ ] **Step 3: nix flake check / build を再確認**

```bash
cd nix
nix flake check --impure --print-build-logs 2>&1 | tail -30
echo "exit: $?"
USER=ciuser nix build .#darwinConfigurations.default.system --no-link --impure --print-build-logs 2>&1 | tail -30
echo "exit: $?"
cd ..
```

Expected: 両方とも exit 0

- [ ] **Step 4: フォーマッタ・リンタを変更ファイルのみに適用**

```bash
git diff --name-only main...HEAD
```

出力されたファイルのうち zsh ファイルは `zsh -n` 構文チェックが各 bats ファイルの先頭
テストで既にカバー済み。Nix ファイルは `nix flake check` が構文検証を兼ねる。追加の
フォーマッタが導入されていないことを確認（このリポジトリに `.nixfmt`/`shfmt` 設定は
現状ないため、対象なしで終了）。

- [ ] **Step 5: 削除漏れ・stale 参照がないことを最終確認**

```bash
grep -rn "modules/home\|home-manager" --include='*.nix' --include='*.zsh' --include='*.md' . \
  | grep -v 'docs/superpowers/specs/2026-05-02\|docs/superpowers/specs/2026-08-21\|docs/superpowers/specs/2026-08-22-restore-script-management-tier3-cutover-design\|docs/superpowers/plans/2026-08-22-restore-script-management-tier1\|docs/superpowers/plans/2026-08-22-restore-script-management-tier2\|docs/superpowers/plans/2026-08-22-restore-script-management-tier3-cutover\|docs/superpowers/main/2026-06-21'
```

Expected: 空（過去の記録用ドキュメントを除き、現行コード・現行ドキュメントに参照が残っていない）

---

## Task 9: 独立レビュー

**Files:** なし（レビュー + 指摘修正）

- [ ] **Step 1: `feature-dev:code-reviewer` エージェントに本 PR の全差分をレビューさせる**

対象: `git diff main...HEAD`（Task 1〜7 の全コミット）。観点: `cutover.zsh`/`rollback.zsh`
の安全性（sudo 規約・fail-closed ガード・stub との整合）、削除漏れ、ドキュメント間の
矛盾、`nix flake check`/`nix build` が通る状態を維持しているか。

- [ ] **Step 2: 指摘があれば修正し、該当タスクのテストを再実行**

Task 1/2 のテストファイル、または Task 4 の `nix flake check`/`nix build` を再実行して
regression がないことを確認する。

- [ ] **Step 3: 修正差分を commit**

```bash
git add -A
git commit -m "fix(setup): address Tier 3 independent review findings

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

指摘が無ければこの Task はスキップ（無変更 commit を作らない）。

---

## Task 10: push + GitHub スタック PR 作成

**Files:** なし

- [ ] **Step 1: push**

```bash
git push -u origin refactor/restore-script-management-tier3-cutover
```

- [ ] **Step 2: `gh stack link` で #54 の上にスタックする terminal PR を作成**

```bash
gh stack link
```

PR タイトル案: `feat(setup): add Tier 3 cutover/rollback + retire home-manager Nix definitions`
base は `refactor/restore-script-management-tier2`（#54）。

- [ ] **Step 3: PR body を確認・整形（やったこと/補足/動作確認方法の 3 セクション、既存
  Tier1/2 PR と同じ型）**

```bash
gh pr view --json number,url,baseRefName,headRefName,state
```

- [ ] **Step 4: CI（`setup-check.yml`/`nix-check.yml`）の完了を待って結果を確認**

```bash
gh pr checks <PR番号> --watch
```

Expected: 全 check success

- [ ] **Step 5: 実機カットオーバーは実行しない。terminal PR の URL・番号・CI 状態をユーザーに
  報告して停止する。**
