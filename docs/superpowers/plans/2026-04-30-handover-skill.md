# handover Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Claude Code セッションのコンパクト前後で文脈が失われる事故を防ぐ `handover` スキルを、シェルスクリプト群と 3 種のフックの組み合わせで実装する。

**Architecture:** `/handover` スキル本体（`claude/skills/handover/SKILL.md`）が `scripts/` 配下のシェルスクリプトを呼び出してメモを作成・破棄・列挙する。3 種のフック（`PreCompact` / `SessionStart` / `UserPromptSubmit`）が同じスクリプト群を再利用しつつ、コンパクトのブロックや次セッションへの引き継ぎ通知を行う。`state.json`（機械可読）と `handover.md`（人間可読・自動生成）の二重ファイルで保存先 `~/.claude/handover/{project-hash}/{branch}/{fingerprint}/` に格納する。

**Tech Stack:** zsh / bash, jq, bats-core, Claude Code Skills, Claude Code Hooks

**仕様書:** [docs/superpowers/specs/2026-04-30-handover-skill-design.md](../specs/2026-04-30-handover-skill-design.md)

---

## ファイル構造マップ

```
.dotfiles/
├ Brewfile                                            # MODIFY: bats-core 追加
├ CLAUDE.md                                           # MODIFY: リポジトリ構造に claude/hooks/ 追加 + Claude Code 設定の説明追加
├ claude/
│  ├ settings.json                                    # MODIFY: hooks に PreCompact / SessionStart / UserPromptSubmit を登録
│  ├ hooks/                                            # CREATE: フックスクリプト集約ディレクトリ
│  │  ├ pre-compact.sh                                # CREATE: 未 handover 時にコンパクトをブロック
│  │  ├ session-start.sh                              # CREATE: 起動時に未消費メモ通知
│  │  └ user-prompt-submit.sh                         # CREATE: コンパクト後の同セッション通知（重複抑止付き）
│  └ skills/handover/                                  # CREATE: 新規スキル
│     ├ SKILL.md                                      # CREATE: /handover [clear | status]
│     ├ references/
│     │  ├ state-schema.md                            # CREATE: state.json スキーマ詳解
│     │  └ handover-md-format.md                      # CREATE: handover.md フォーマット仕様
│     ├ scripts/
│     │  ├ resolve-path.sh                            # CREATE: project-hash / branch / fingerprint 解決
│     │  ├ consume.sh                                 # CREATE: consumed フラグ立て
│     │  ├ cleanup.sh                                 # CREATE: TTL 7 日 + ALL_COMPLETE の自動削除
│     │  ├ render-md.sh                               # CREATE: state.json → handover.md 生成
│     │  └ list-active.sh                             # CREATE: 未消費・READY・TTL 内のメモ列挙
│     └ tests/
│        ├ helpers.bash                               # CREATE: bats 共通セットアップ
│        ├ resolve-path.bats                          # CREATE
│        ├ consume.bats                               # CREATE
│        ├ cleanup.bats                               # CREATE
│        ├ render-md.bats                             # CREATE
│        ├ list-active.bats                           # CREATE
│        ├ pre-compact.bats                           # CREATE
│        ├ session-start.bats                         # CREATE
│        ├ user-prompt-submit.bats                    # CREATE
│        └ scenarios.md                               # CREATE: 手動シナリオテスト 9 件
```

### 各ファイルの責務

| ファイル | 責務 |
|---|---|
| `scripts/resolve-path.sh` | CWD と git コマンドから `PROJECT_PATH` / `PROJECT_HASH` / `BRANCH` / `FINGERPRINT` / `HANDOVER_DIR` を環境変数形式で出力 |
| `scripts/consume.sh` | 引数の state.json に `consumed=true`, `updated_at` 更新を施す（jq でアトミック書き換え） |
| `scripts/cleanup.sh` | `~/.claude/handover/` 配下を走査し、`status=ALL_COMPLETE` かつ `created_at` が 7 日以上前のディレクトリを削除 |
| `scripts/render-md.sh` | state.json から jq テンプレートで handover.md を生成（決定的・冪等） |
| `scripts/list-active.sh` | 引数なし or `(project_hash, branch, [session_id])` で未消費・READY・TTL 内のメモを JSON 配列で列挙 |
| `hooks/pre-compact.sh` | 同 `$CLAUDE_SESSION_ID` の state.json 不在時に `{"decision": "block", "reason": ...}` を返す |
| `hooks/session-start.sh` | 起動時、未消費メモがあれば `additionalContext` で Claude に通知し、マーカーを作成 |
| `hooks/user-prompt-submit.sh` | マーカー未作成のときのみ session-start.sh と同等の通知を行う（hookEventName のみ差し替え） |
| `SKILL.md` | 引数 `[clear \| status]` で動作分岐。Claude が呼ぶ Bash 手順を記述 |

---

## 実装順序の考え方

下層（pure shell scripts、副作用が `~/.claude/handover/` 配下に閉じる）から TDD で実装し、上層（フック・スキル本体）に進む。フックは内部で `scripts/list-active.sh` を呼び出すため、スクリプトが揃ってから着手する。

依存関係:

```
Task 1 (準備)
   ↓
Task 2 (resolve-path) ← 全スクリプトが PATH 計算で利用
   ↓
Task 3 (consume) ─┐
Task 4 (cleanup) ─┤  互いに独立、並列実装可能だが順次が無難
Task 5 (render-md)─┤
Task 6 (list-active) ← resolve-path に依存
   ↓
Task 7 (references)
   ↓
Task 8 (SKILL.md)
   ↓
Task 9 (pre-compact hook)
Task 10 (session-start hook) ← list-active に依存
Task 11 (user-prompt-submit hook)
   ↓
Task 12 (settings.json 登録)
   ↓
Task 13 (Brewfile / CLAUDE.md 更新)
   ↓
Task 14 (手動シナリオテスト)
```

---

## Task 1: 前提準備とディレクトリスケルトン作成

**Files:**
- Modify: `Brewfile`（`# Utilities` セクションに `brew "bats-core"` を追加）
- Create: `claude/skills/handover/.gitkeep`
- Create: `claude/skills/handover/references/.gitkeep`
- Create: `claude/skills/handover/scripts/.gitkeep`
- Create: `claude/skills/handover/tests/helpers.bash`
- Create: `claude/hooks/.gitkeep`

- [ ] **Step 1.1: Brewfile に bats-core を追加**

`Brewfile` の `# Utilities` セクションに 1 行追加する。`brew 'jq'` の直下に挿入:

```ruby
# Utilities
brew 'autoconf'
brew 'automake'
brew 'bison'
brew 'freetype'
brew 'gd'
brew 'gettext'
brew 'gmp'
brew 'jq'
brew 'bats-core'
brew 'libyaml'
brew 'openssl@3'
brew 'pkg-config'
brew 're2c'
brew 'zlib'
brew 'pwgen'
```

- [ ] **Step 1.2: bats をインストール**

Run: `brew bundle --file=/Users/goto/.dotfiles/Brewfile`
Expected: `bats-core` の `Installing` または `Already installed` メッセージ

- [ ] **Step 1.3: bats が利用可能か確認**

Run: `bats --version`
Expected: `Bats 1.x.x` のような出力

- [ ] **Step 1.4: ディレクトリスケルトン作成**

Run:
```bash
mkdir -p /Users/goto/.dotfiles/claude/skills/handover/{references,scripts,tests}
mkdir -p /Users/goto/.dotfiles/claude/hooks
touch /Users/goto/.dotfiles/claude/skills/handover/{references,scripts}/.gitkeep
touch /Users/goto/.dotfiles/claude/hooks/.gitkeep
```

- [ ] **Step 1.5: bats 共通ヘルパーを作成**

Create `claude/skills/handover/tests/helpers.bash`:

```bash
#!/usr/bin/env bash
# bats 共通ヘルパー
# 各テストファイルから `load helpers` で読み込む。

# 一時 HOME を設定し、テスト後に削除する setup/teardown
setup_handover_env() {
  TEST_TMP_HOME="$(mktemp -d)"
  export HOME="${TEST_TMP_HOME}"
  export TMPDIR="${TEST_TMP_HOME}/tmp"
  mkdir -p "${TMPDIR}"
  mkdir -p "${HOME}/.claude/handover"
  # スクリプト群への絶対パス
  SCRIPTS_DIR="${BATS_TEST_DIRNAME}/../scripts"
  HOOKS_DIR="${BATS_TEST_DIRNAME}/../../../hooks"
  export SCRIPTS_DIR HOOKS_DIR
}

teardown_handover_env() {
  if [ -n "${TEST_TMP_HOME:-}" ] && [ -d "${TEST_TMP_HOME}" ]; then
    rm -rf "${TEST_TMP_HOME}"
  fi
}

# 与えた条件の state.json を作る簡易関数
# Usage: write_state <dir> <session_id> <status> <created_at> [consumed]
write_state() {
  local dir="$1" sid="$2" status="$3" created="$4" consumed="${5:-false}"
  mkdir -p "${dir}"
  cat > "${dir}/state.json" <<EOF
{
  "version": 1,
  "session_id": "${sid}",
  "created_at": "${created}",
  "updated_at": "${created}",
  "consumed": ${consumed},
  "status": "${status}",
  "project": {
    "path": "/tmp/test-project",
    "hash": "test-12345678",
    "branch": "main"
  },
  "session_summary": "test summary",
  "tasks": [],
  "decisions": [],
  "blockers": []
}
EOF
}

# 7 日前 ISO8601 を返す（macOS / Linux 両対応）
iso_days_ago() {
  local days="$1"
  if date -v -1d >/dev/null 2>&1; then
    date -v "-${days}d" -Iseconds
  else
    date -d "${days} days ago" -Iseconds
  fi
}
```

- [ ] **Step 1.6: コミット**

```bash
cd /Users/goto/.dotfiles
git add Brewfile claude/skills/handover claude/hooks
git commit -m "$(cat <<'EOF'
chore: handover スキルのディレクトリスケルトンと bats を追加

Brewfile に bats-core を追加し、claude/skills/handover/ 配下に
scripts / references / tests のサブディレクトリを作成する。
TDD のための共通ヘルパー tests/helpers.bash も用意する。
EOF
)"
```

---

## Task 2: scripts/resolve-path.sh の TDD 実装

**Files:**
- Create: `claude/skills/handover/scripts/resolve-path.sh`
- Create: `claude/skills/handover/tests/resolve-path.bats`

- [ ] **Step 2.1: bats テストを書く（失敗する状態）**

Create `claude/skills/handover/tests/resolve-path.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() {
  setup_handover_env
  WORK_DIR="$(mktemp -d)"
  cd "${WORK_DIR}"
}

teardown() {
  cd /
  rm -rf "${WORK_DIR}"
  teardown_handover_env
}

@test "git リポジトリで PROJECT_HASH と BRANCH を出力する" {
  git init -q -b main "${WORK_DIR}"
  git -C "${WORK_DIR}" -c user.email=a@a -c user.name=a commit --allow-empty -q -m init

  run "${SCRIPTS_DIR}/resolve-path.sh"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"PROJECT_PATH=${WORK_DIR}"* ]]
  [[ "${output}" == *"BRANCH=main"* ]]
  [[ "${output}" == *"PROJECT_HASH=$(basename "${WORK_DIR}")-"* ]]
  [[ "${output}" == *"FINGERPRINT="* ]]
  [[ "${output}" == *"HANDOVER_DIR="* ]]
}

@test "ブランチ名の / と : と空白を - にサニタイズする" {
  git init -q "${WORK_DIR}"
  git -C "${WORK_DIR}" -c user.email=a@a -c user.name=a commit --allow-empty -q -m init
  git -C "${WORK_DIR}" checkout -q -b "feat/foo bar:baz"

  run "${SCRIPTS_DIR}/resolve-path.sh"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"BRANCH=feat-foo-bar-baz"* ]]
}

@test "detached HEAD で detached-{sha7} を出力する" {
  git init -q -b main "${WORK_DIR}"
  git -C "${WORK_DIR}" -c user.email=a@a -c user.name=a commit --allow-empty -q -m init
  sha="$(git -C "${WORK_DIR}" rev-parse --short=7 HEAD)"
  git -C "${WORK_DIR}" checkout -q --detach

  run "${SCRIPTS_DIR}/resolve-path.sh"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"BRANCH=detached-${sha}"* ]]
}

@test "非 git ディレクトリで BRANCH=nogit を出力する" {
  run "${SCRIPTS_DIR}/resolve-path.sh"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"BRANCH=nogit"* ]]
}

@test "FINGERPRINT は YYYYMMDD-HHMMSS 形式" {
  run "${SCRIPTS_DIR}/resolve-path.sh"
  [[ "${output}" =~ FINGERPRINT=[0-9]{8}-[0-9]{6} ]]
}
```

- [ ] **Step 2.2: テストを実行して失敗を確認**

Run: `bats /Users/goto/.dotfiles/claude/skills/handover/tests/resolve-path.bats`
Expected: 全テストが FAIL（スクリプトが存在しないため）

- [ ] **Step 2.3: scripts/resolve-path.sh を実装**

Create `claude/skills/handover/scripts/resolve-path.sh`:

```sh
#!/bin/zsh
# CWD と git コマンドから handover の保存先解決に必要な値を環境変数形式で出力する。
# 出力例:
#   PROJECT_PATH=/Users/goto/.dotfiles
#   PROJECT_HASH=dotfiles-a1b2c3d4
#   BRANCH=main
#   FINGERPRINT=20260430-153000
#   HANDOVER_DIR=/Users/goto/.claude/handover/dotfiles-a1b2c3d4/main
set -eu

if repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  :
else
  repo_root="${PWD}"
fi

project_basename="$(basename "${repo_root}")"
project_sha="$(printf '%s' "${repo_root}" | shasum -a 1 | cut -c1-8)"
project_hash="${project_basename}-${project_sha}"

if branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"; then
  if [ "${branch}" = "HEAD" ]; then
    branch="detached-$(git rev-parse --short=7 HEAD)"
  fi
else
  branch="nogit"
fi
branch="$(printf '%s' "${branch}" | sed 's|[/:[:space:]]|-|g')"

fingerprint="$(date +%Y%m%d-%H%M%S)"

handover_dir="${HOME}/.claude/handover/${project_hash}/${branch}"

cat <<EOF
PROJECT_PATH=${repo_root}
PROJECT_HASH=${project_hash}
BRANCH=${branch}
FINGERPRINT=${fingerprint}
HANDOVER_DIR=${handover_dir}
EOF
```

Run: `chmod +x /Users/goto/.dotfiles/claude/skills/handover/scripts/resolve-path.sh`

- [ ] **Step 2.4: テストを実行して合格を確認**

Run: `bats /Users/goto/.dotfiles/claude/skills/handover/tests/resolve-path.bats`
Expected: `5 tests, 0 failures`

- [ ] **Step 2.5: コミット**

```bash
cd /Users/goto/.dotfiles
git add claude/skills/handover/scripts/resolve-path.sh \
        claude/skills/handover/tests/resolve-path.bats
git commit -m "feat: handover の resolve-path.sh を追加"
```

---

## Task 3: scripts/consume.sh の TDD 実装

**Files:**
- Create: `claude/skills/handover/scripts/consume.sh`
- Create: `claude/skills/handover/tests/consume.bats`

- [ ] **Step 3.1: bats テストを書く**

Create `claude/skills/handover/tests/consume.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() {
  setup_handover_env
  STATE_DIR="${HOME}/.claude/handover/test/main/20260430-100000"
  write_state "${STATE_DIR}" "sess-1" "READY" "2026-04-30T10:00:00+09:00" "false"
  STATE_FILE="${STATE_DIR}/state.json"
}

teardown() {
  teardown_handover_env
}

@test "consumed=false → true に更新する" {
  run "${SCRIPTS_DIR}/consume.sh" "${STATE_FILE}"
  [ "${status}" -eq 0 ]
  consumed="$(jq -r '.consumed' "${STATE_FILE}")"
  [ "${consumed}" = "true" ]
}

@test "updated_at が変わる" {
  before="$(jq -r '.updated_at' "${STATE_FILE}")"
  sleep 1
  run "${SCRIPTS_DIR}/consume.sh" "${STATE_FILE}"
  [ "${status}" -eq 0 ]
  after="$(jq -r '.updated_at' "${STATE_FILE}")"
  [ "${before}" != "${after}" ]
}

@test "既に consumed=true でも冪等" {
  jq '.consumed = true' "${STATE_FILE}" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "${STATE_FILE}"
  run "${SCRIPTS_DIR}/consume.sh" "${STATE_FILE}"
  [ "${status}" -eq 0 ]
  consumed="$(jq -r '.consumed' "${STATE_FILE}")"
  [ "${consumed}" = "true" ]
}

@test "存在しないファイルは exit 1" {
  run "${SCRIPTS_DIR}/consume.sh" "${HOME}/nonexistent.json"
  [ "${status}" -ne 0 ]
}

@test "不正な JSON は exit 1" {
  echo "not json" > "${STATE_FILE}"
  run "${SCRIPTS_DIR}/consume.sh" "${STATE_FILE}"
  [ "${status}" -ne 0 ]
}

@test "引数なしは Usage を表示して exit 1" {
  run "${SCRIPTS_DIR}/consume.sh"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Usage"* ]]
}
```

- [ ] **Step 3.2: テスト実行して失敗確認**

Run: `bats /Users/goto/.dotfiles/claude/skills/handover/tests/consume.bats`
Expected: 全テストが FAIL

- [ ] **Step 3.3: scripts/consume.sh を実装**

Create `claude/skills/handover/scripts/consume.sh`:

```sh
#!/bin/zsh
# 指定された state.json に consumed=true, updated_at=現在時刻 を反映する。
# 用途: 自動読込でメモを「消費した」状態にする、または /handover clear で一括破棄する。
set -eu

if [ "$#" -ne 1 ]; then
  printf 'Usage: consume.sh <state.json path>\n' >&2
  exit 1
fi

state_file="$1"

if [ ! -f "${state_file}" ]; then
  printf 'Error: %s not found\n' "${state_file}" >&2
  exit 1
fi

if ! jq empty "${state_file}" >/dev/null 2>&1; then
  printf 'Error: %s is not valid JSON\n' "${state_file}" >&2
  exit 1
fi

now="$(date -Iseconds)"
tmp_file="$(mktemp)"
trap 'rm -f "${tmp_file}"' EXIT

jq --arg now "${now}" '.consumed = true | .updated_at = $now' "${state_file}" > "${tmp_file}"
mv "${tmp_file}" "${state_file}"
```

Run: `chmod +x /Users/goto/.dotfiles/claude/skills/handover/scripts/consume.sh`

- [ ] **Step 3.4: テスト合格を確認**

Run: `bats /Users/goto/.dotfiles/claude/skills/handover/tests/consume.bats`
Expected: `6 tests, 0 failures`

- [ ] **Step 3.5: コミット**

```bash
cd /Users/goto/.dotfiles
git add claude/skills/handover/scripts/consume.sh \
        claude/skills/handover/tests/consume.bats
git commit -m "feat: handover の consume.sh を追加"
```

---

## Task 4: scripts/cleanup.sh の TDD 実装

**Files:**
- Create: `claude/skills/handover/scripts/cleanup.sh`
- Create: `claude/skills/handover/tests/cleanup.bats`

- [ ] **Step 4.1: bats テストを書く**

Create `claude/skills/handover/tests/cleanup.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() {
  setup_handover_env
  ROOT="${HOME}/.claude/handover/test-proj/main"
}

teardown() {
  teardown_handover_env
}

@test "7日超 + ALL_COMPLETE は削除される" {
  old_dir="${ROOT}/20260101-000000"
  write_state "${old_dir}" "s1" "ALL_COMPLETE" "$(iso_days_ago 10)"
  run "${SCRIPTS_DIR}/cleanup.sh"
  [ "${status}" -eq 0 ]
  [ ! -d "${old_dir}" ]
}

@test "7日超でも READY なら残る" {
  old_dir="${ROOT}/20260101-000001"
  write_state "${old_dir}" "s2" "READY" "$(iso_days_ago 10)"
  run "${SCRIPTS_DIR}/cleanup.sh"
  [ "${status}" -eq 0 ]
  [ -d "${old_dir}" ]
}

@test "7日以内の ALL_COMPLETE は残る" {
  recent_dir="${ROOT}/20260425-000000"
  write_state "${recent_dir}" "s3" "ALL_COMPLETE" "$(iso_days_ago 3)"
  run "${SCRIPTS_DIR}/cleanup.sh"
  [ "${status}" -eq 0 ]
  [ -d "${recent_dir}" ]
}

@test "handover ルート未存在でも exit 0" {
  rm -rf "${HOME}/.claude/handover"
  run "${SCRIPTS_DIR}/cleanup.sh"
  [ "${status}" -eq 0 ]
}

@test "複数プロジェクト・複数ブランチを横断して走査する" {
  d1="${HOME}/.claude/handover/proj-a/main/20260101-000000"
  d2="${HOME}/.claude/handover/proj-b/feature-x/20260101-000000"
  write_state "${d1}" "x1" "ALL_COMPLETE" "$(iso_days_ago 10)"
  write_state "${d2}" "x2" "ALL_COMPLETE" "$(iso_days_ago 10)"
  run "${SCRIPTS_DIR}/cleanup.sh"
  [ ! -d "${d1}" ]
  [ ! -d "${d2}" ]
}
```

- [ ] **Step 4.2: テスト失敗確認**

Run: `bats /Users/goto/.dotfiles/claude/skills/handover/tests/cleanup.bats`
Expected: 全テストが FAIL

- [ ] **Step 4.3: scripts/cleanup.sh を実装**

Create `claude/skills/handover/scripts/cleanup.sh`:

```sh
#!/bin/zsh
# ~/.claude/handover/ 配下を走査し、status=ALL_COMPLETE かつ created_at が
# 7 日以上前のディレクトリを丸ごと削除する。
# /handover 実行のたびに呼ばれて、ストレージを綺麗に保つ。
set -eu

handover_root="${HOME}/.claude/handover"
[ ! -d "${handover_root}" ] && exit 0

threshold_seconds=$((7 * 24 * 60 * 60))
now_epoch="$(date +%s)"

# project_hash/branch/fingerprint/state.json の階層 = 4 段
find "${handover_root}" -mindepth 4 -maxdepth 4 -name state.json -type f 2>/dev/null | while IFS= read -r state_file; do
  if ! status="$(jq -r '.status // ""' "${state_file}" 2>/dev/null)"; then
    continue
  fi
  [ "${status}" != "ALL_COMPLETE" ] && continue

  created="$(jq -r '.created_at // ""' "${state_file}" 2>/dev/null)"
  [ -z "${created}" ] && continue

  # macOS の date は -j -f 形式、GNU date は -d。両対応。
  if created_epoch="$(date -j -f '%Y-%m-%dT%H:%M:%S%z' "${created}" +%s 2>/dev/null)"; then
    :
  elif created_epoch="$(date -d "${created}" +%s 2>/dev/null)"; then
    :
  else
    continue
  fi

  age=$((now_epoch - created_epoch))
  if [ "${age}" -gt "${threshold_seconds}" ]; then
    target_dir="$(dirname "${state_file}")"
    rm -rf "${target_dir}"
    printf 'cleanup: removed %s (age: %d days)\n' "${target_dir}" $((age / 86400)) >&2
  fi
done
```

Run: `chmod +x /Users/goto/.dotfiles/claude/skills/handover/scripts/cleanup.sh`

- [ ] **Step 4.4: テスト合格を確認**

Run: `bats /Users/goto/.dotfiles/claude/skills/handover/tests/cleanup.bats`
Expected: `5 tests, 0 failures`

- [ ] **Step 4.5: コミット**

```bash
cd /Users/goto/.dotfiles
git add claude/skills/handover/scripts/cleanup.sh \
        claude/skills/handover/tests/cleanup.bats
git commit -m "feat: handover の cleanup.sh を追加"
```

---

## Task 5: scripts/render-md.sh の TDD 実装

**Files:**
- Create: `claude/skills/handover/scripts/render-md.sh`
- Create: `claude/skills/handover/tests/render-md.bats`

- [ ] **Step 5.1: bats テスト（ゴールデン）を書く**

Create `claude/skills/handover/tests/render-md.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() {
  setup_handover_env
  TARGET_DIR="${HOME}/.claude/handover/test/main/20260430-100000"
  mkdir -p "${TARGET_DIR}"
}

teardown() {
  teardown_handover_env
}

@test "標準 state.json から想定 Markdown を生成する" {
  cat > "${TARGET_DIR}/state.json" <<'JSON'
{
  "version": 1,
  "session_id": "abc",
  "created_at": "2026-04-30T15:30:00+09:00",
  "updated_at": "2026-04-30T15:30:00+09:00",
  "consumed": false,
  "status": "READY",
  "project": {
    "path": "/Users/goto/.dotfiles",
    "hash": "dotfiles-a1b2c3d4",
    "branch": "main"
  },
  "session_summary": "handover の設計を進行中",
  "tasks": [
    {
      "id": "T1",
      "description": "実装する",
      "status": "in_progress",
      "next_action": "SKILL.md を書く"
    }
  ],
  "decisions": [
    {
      "topic": "保存先",
      "chosen": "~/.claude/handover/",
      "rejected": [".agents/"],
      "rationale": "プロジェクト側を汚さない"
    }
  ],
  "blockers": ["jq インストール待ち"]
}
JSON

  run "${SCRIPTS_DIR}/render-md.sh" "${TARGET_DIR}/state.json"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"# Handover: 2026-04-30 15:30"* ]]
  [[ "${output}" == *"**Project**: /Users/goto/.dotfiles"* ]]
  [[ "${output}" == *"**Branch**: main"* ]]
  [[ "${output}" == *"**Status**: READY"* ]]
  [[ "${output}" == *"**Session**: abc"* ]]
  [[ "${output}" == *"## Session Summary"* ]]
  [[ "${output}" == *"handover の設計を進行中"* ]]
  [[ "${output}" == *"T1: 実装する (in_progress)"* ]]
  [[ "${output}" == *"Next: SKILL.md を書く"* ]]
  [[ "${output}" == *"**保存先**: ~/.claude/handover/"* ]]
  [[ "${output}" == *"却下: .agents/"* ]]
  [[ "${output}" == *"理由: プロジェクト側を汚さない"* ]]
  [[ "${output}" == *"jq インストール待ち"* ]]
}

@test "tasks 空配列で 「なし」 表示" {
  cat > "${TARGET_DIR}/state.json" <<'JSON'
{
  "version": 1, "session_id": "x", "created_at": "2026-04-30T10:00:00+09:00",
  "updated_at": "2026-04-30T10:00:00+09:00", "consumed": false, "status": "ALL_COMPLETE",
  "project": {"path": "/p", "hash": "p-1", "branch": "main"},
  "session_summary": "done", "tasks": [], "decisions": [], "blockers": []
}
JSON
  run "${SCRIPTS_DIR}/render-md.sh" "${TARGET_DIR}/state.json"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"## Tasks"* ]]
  [[ "${output}" == *"なし"* ]]
}

@test "存在しないファイルで exit 1" {
  run "${SCRIPTS_DIR}/render-md.sh" "${HOME}/nonexistent.json"
  [ "${status}" -ne 0 ]
}
```

- [ ] **Step 5.2: テスト失敗確認**

Run: `bats /Users/goto/.dotfiles/claude/skills/handover/tests/render-md.bats`
Expected: 全テスト FAIL

- [ ] **Step 5.3: scripts/render-md.sh を実装**

Create `claude/skills/handover/scripts/render-md.sh`:

```sh
#!/bin/zsh
# state.json から人間可読な handover.md を生成して stdout に出力する。
# state.json は唯一の真実、handover.md はそのビュー（直接編集禁止）。
set -eu

if [ "$#" -ne 1 ]; then
  printf 'Usage: render-md.sh <state.json path>\n' >&2
  exit 1
fi

state_file="$1"

if [ ! -f "${state_file}" ]; then
  printf 'Error: %s not found\n' "${state_file}" >&2
  exit 1
fi

jq -r '
  def task_line:
    "- [\(if .status == "completed" then "x" else " " end)] \(.id): \(.description) (\(.status))" +
    (if .next_action and .next_action != "" then "\n  - Next: \(.next_action)" else "" end);

  def decision_block:
    "- **\(.topic)**: \(.chosen)" +
    (if (.rejected // []) | length > 0 then "\n  - 却下: \(.rejected | join(", "))" else "" end) +
    "\n  - 理由: \(.rationale)";

  def header_time:
    .created_at | sub("T"; " ") | sub(":[0-9]+(\\.[0-9]+)?(\\+|Z|-).*$"; "");

  "# Handover: \(header_time)\n" +
  "\n**Project**: \(.project.path)\n" +
  "**Branch**: \(.project.branch)\n" +
  "**Status**: \(.status)\n" +
  "**Session**: \(.session_id)\n" +
  "\n## Session Summary\n\(.session_summary)\n" +
  "\n## Tasks\n" +
  (if (.tasks | length) > 0 then ([.tasks[] | task_line] | join("\n")) else "なし" end) +
  "\n\n## Decisions\n" +
  (if (.decisions | length) > 0 then ([.decisions[] | decision_block] | join("\n")) else "なし" end) +
  "\n\n## Blockers\n" +
  (if (.blockers | length) > 0 then ([.blockers[] | "- \(.)"] | join("\n")) else "なし" end)
' "${state_file}"
```

Run: `chmod +x /Users/goto/.dotfiles/claude/skills/handover/scripts/render-md.sh`

- [ ] **Step 5.4: テスト合格を確認**

Run: `bats /Users/goto/.dotfiles/claude/skills/handover/tests/render-md.bats`
Expected: `3 tests, 0 failures`

- [ ] **Step 5.5: コミット**

```bash
cd /Users/goto/.dotfiles
git add claude/skills/handover/scripts/render-md.sh \
        claude/skills/handover/tests/render-md.bats
git commit -m "feat: handover の render-md.sh を追加"
```

---

## Task 6: scripts/list-active.sh の TDD 実装

**Files:**
- Create: `claude/skills/handover/scripts/list-active.sh`
- Create: `claude/skills/handover/tests/list-active.bats`

- [ ] **Step 6.1: bats テストを書く**

Create `claude/skills/handover/tests/list-active.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() {
  setup_handover_env
  ROOT="${HOME}/.claude/handover/proj/main"
}

teardown() {
  teardown_handover_env
}

@test "未消費・READY・TTL 内のメモを返す" {
  d="${ROOT}/20260430-100000"
  write_state "${d}" "s1" "READY" "$(iso_days_ago 1)" "false"
  run "${SCRIPTS_DIR}/list-active.sh" "proj" "main"
  [ "${status}" -eq 0 ]
  count="$(printf '%s' "${output}" | jq 'length')"
  [ "${count}" = "1" ]
  fp="$(printf '%s' "${output}" | jq -r '.[0].fingerprint')"
  [ "${fp}" = "20260430-100000" ]
}

@test "consumed=true は除外" {
  d="${ROOT}/20260430-100000"
  write_state "${d}" "s1" "READY" "$(iso_days_ago 1)" "true"
  run "${SCRIPTS_DIR}/list-active.sh" "proj" "main"
  [ "${status}" -eq 0 ]
  [ "${output}" = "[]" ]
}

@test "ALL_COMPLETE は除外" {
  d="${ROOT}/20260430-100000"
  write_state "${d}" "s1" "ALL_COMPLETE" "$(iso_days_ago 1)" "false"
  run "${SCRIPTS_DIR}/list-active.sh" "proj" "main"
  [ "${status}" -eq 0 ]
  [ "${output}" = "[]" ]
}

@test "TTL 7 日超は除外" {
  d="${ROOT}/20260101-000000"
  write_state "${d}" "s1" "READY" "$(iso_days_ago 10)" "false"
  run "${SCRIPTS_DIR}/list-active.sh" "proj" "main"
  [ "${status}" -eq 0 ]
  [ "${output}" = "[]" ]
}

@test "session_id フィルタが効く" {
  d1="${ROOT}/20260430-100000"
  d2="${ROOT}/20260430-110000"
  write_state "${d1}" "sess-a" "READY" "$(iso_days_ago 1)" "false"
  write_state "${d2}" "sess-b" "READY" "$(iso_days_ago 1)" "false"
  run "${SCRIPTS_DIR}/list-active.sh" "proj" "main" "sess-a"
  [ "${status}" -eq 0 ]
  count="$(printf '%s' "${output}" | jq 'length')"
  [ "${count}" = "1" ]
  sid="$(printf '%s' "${output}" | jq -r '.[0].session_id')"
  [ "${sid}" = "sess-a" ]
}

@test "保存先ディレクトリ未存在で空配列" {
  run "${SCRIPTS_DIR}/list-active.sh" "nonexistent" "main"
  [ "${status}" -eq 0 ]
  [ "${output}" = "[]" ]
}

@test "引数なしなら CWD から自動解決して列挙" {
  d="${HOME}/.claude/handover/auto-test-$(printf '%s' "$(pwd)" | shasum -a 1 | cut -c1-8)/nogit/20260430-100000"
  # 上記の自動解決パスに合わせ、auto-test- は固定ではないので、CWD ベースで write
  cd "$(mktemp -d)"
  eval "$("${SCRIPTS_DIR}/resolve-path.sh")"
  write_state "${HANDOVER_DIR}/${FINGERPRINT}" "auto-sess" "READY" "$(iso_days_ago 1)" "false"
  run "${SCRIPTS_DIR}/list-active.sh"
  [ "${status}" -eq 0 ]
  count="$(printf '%s' "${output}" | jq 'length')"
  [ "${count}" -ge 1 ]
}
```

- [ ] **Step 6.2: テスト失敗確認**

Run: `bats /Users/goto/.dotfiles/claude/skills/handover/tests/list-active.bats`
Expected: 全テスト FAIL

- [ ] **Step 6.3: scripts/list-active.sh を実装**

Create `claude/skills/handover/scripts/list-active.sh`:

```sh
#!/bin/zsh
# 未消費・READY・TTL(7日)内の handover メモを JSON 配列で返す。
# Usage:
#   list-active.sh                              # CWD から自動解決
#   list-active.sh <project_hash> <branch>      # 明示指定
#   list-active.sh <project_hash> <branch> <session_id>  # session_id でフィルタ
set -eu

project_hash="${1:-}"
branch="${2:-}"
session_filter="${3:-}"

if [ -z "${project_hash}" ] || [ -z "${branch}" ]; then
  eval "$("${0:A:h}/resolve-path.sh")"
  project_hash="${PROJECT_HASH}"
  branch="${BRANCH}"
fi

scope_dir="${HOME}/.claude/handover/${project_hash}/${branch}"
if [ ! -d "${scope_dir}" ]; then
  printf '[]\n'
  exit 0
fi

threshold_seconds=$((7 * 24 * 60 * 60))
now_epoch="$(date +%s)"

results='[]'
setopt NULL_GLOB
for state_file in "${scope_dir}"/*/state.json; do
  [ ! -f "${state_file}" ] && continue
  if ! jq empty "${state_file}" >/dev/null 2>&1; then
    printf 'warn: skip invalid JSON %s\n' "${state_file}" >&2
    continue
  fi

  consumed="$(jq -r '.consumed // false' "${state_file}")"
  status="$(jq -r '.status // ""' "${state_file}")"
  created="$(jq -r '.created_at // ""' "${state_file}")"
  session_id="$(jq -r '.session_id // ""' "${state_file}")"
  summary="$(jq -r '.session_summary // ""' "${state_file}")"

  [ "${consumed}" = "true" ] && continue
  [ "${status}" != "READY" ] && continue
  [ -z "${created}" ] && continue

  if created_epoch="$(date -j -f '%Y-%m-%dT%H:%M:%S%z' "${created}" +%s 2>/dev/null)"; then
    :
  elif created_epoch="$(date -d "${created}" +%s 2>/dev/null)"; then
    :
  else
    continue
  fi

  age=$((now_epoch - created_epoch))
  [ "${age}" -gt "${threshold_seconds}" ] && continue

  if [ -n "${session_filter}" ] && [ "${session_id}" != "${session_filter}" ]; then
    continue
  fi

  fingerprint="$(basename "$(dirname "${state_file}")")"
  abs_path="$(dirname "${state_file}")"

  results="$(printf '%s' "${results}" | jq \
    --arg fp "${fingerprint}" \
    --arg sm "${summary}" \
    --arg ca "${created}" \
    --arg ap "${abs_path}" \
    --arg sid "${session_id}" \
    '. + [{fingerprint: $fp, summary: $sm, created_at: $ca, abs_path: $ap, session_id: $sid}]')"
done

printf '%s\n' "${results}"
```

Run: `chmod +x /Users/goto/.dotfiles/claude/skills/handover/scripts/list-active.sh`

- [ ] **Step 6.4: テスト合格を確認**

Run: `bats /Users/goto/.dotfiles/claude/skills/handover/tests/list-active.bats`
Expected: `7 tests, 0 failures`

- [ ] **Step 6.5: コミット**

```bash
cd /Users/goto/.dotfiles
git add claude/skills/handover/scripts/list-active.sh \
        claude/skills/handover/tests/list-active.bats
git commit -m "feat: handover の list-active.sh を追加"
```

---

## Task 7: references/ ドキュメント作成

**Files:**
- Create: `claude/skills/handover/references/state-schema.md`
- Create: `claude/skills/handover/references/handover-md-format.md`

- [ ] **Step 7.1: state-schema.md を作成**

Create `claude/skills/handover/references/state-schema.md`:

````markdown
# state.json スキーマ

handover メモの真実を保持する機械可読ファイル。`render-md.sh` がこれを `handover.md` に変換する。

## サンプル

```json
{
  "version": 1,
  "session_id": "abc123-def456",
  "created_at": "2026-04-30T15:30:00+09:00",
  "updated_at": "2026-04-30T15:45:00+09:00",
  "consumed": false,
  "status": "READY",
  "project": {
    "path": "/Users/goto/.dotfiles",
    "hash": "dotfiles-a1b2c3d4",
    "branch": "main"
  },
  "session_summary": "handover スキルの設計を進行中",
  "tasks": [
    {
      "id": "T1",
      "description": "handover スキル本体を実装",
      "status": "in_progress",
      "next_action": "SKILL.md を docs/superpowers/specs/ から起こす"
    }
  ],
  "decisions": [
    {
      "topic": "保存先",
      "chosen": "~/.claude/handover/{project-hash}/{branch}/",
      "rejected": ["{repo-root}/.agents/", "{cwd}/.handover.md"],
      "rationale": "プロジェクト側を汚さず、複数プロジェクト横断で集約管理できる"
    }
  ],
  "blockers": []
}
```

## フィールド定義

| フィールド | 型 | 必須 | 説明 |
|---|---|:---:|---|
| `version` | int | ✅ | スキーマバージョン。現状 `1` 固定 |
| `session_id` | string | ✅ | `$CLAUDE_SESSION_ID` の値 |
| `created_at` | ISO 8601 string | ✅ | 初回作成時刻 |
| `updated_at` | ISO 8601 string | ✅ | 最終更新時刻 |
| `consumed` | bool | ✅ | 読込で消費済みなら `true` |
| `status` | enum | ✅ | `READY` または `ALL_COMPLETE` |
| `project.path` | string | ✅ | リポジトリルート絶対パス |
| `project.hash` | string | ✅ | `{basename}-{sha1[0:8]}` 形式 |
| `project.branch` | string | ✅ | サニタイズ済みブランチ名 |
| `session_summary` | string | ✅ | 1〜2 行のセッション要約 |
| `tasks` | array | ✅ | タスク配列。空配列も可 |
| `decisions` | array | ✅ | 決定事項配列。空配列も可 |
| `blockers` | array of string | ✅ | ブロッカー配列。空配列も可 |

### tasks[] 要素

| フィールド | 型 | 必須 | 説明 |
|---|---|:---:|---|
| `id` | string | ✅ | `T1`, `T2`, ... |
| `description` | string | ✅ | タスク内容 |
| `status` | enum | ✅ | `in_progress` / `blocked` / `completed` |
| `next_action` | string | 任意 | 次の一歩 |

### decisions[] 要素

| フィールド | 型 | 必須 | 説明 |
|---|---|:---:|---|
| `topic` | string | ✅ | 決定対象 |
| `chosen` | string | ✅ | 採用したアプローチ |
| `rejected` | array of string | 任意 | 却下選択肢 |
| `rationale` | string | ✅ | 採用理由 |

## status 自動判定ルール

`/handover` 実行時に `tasks[]` を走査して再計算する:

- `tasks` が空、または全要素が `status == "completed"` → `ALL_COMPLETE`
- `tasks` に `in_progress` または `blocked` を 1 件でも含む → `READY`
````

- [ ] **Step 7.2: handover-md-format.md を作成**

Create `claude/skills/handover/references/handover-md-format.md`:

````markdown
# handover.md フォーマット

`state.json` から `render-md.sh` で自動生成される人間可読ビュー。直接編集禁止。

## サンプル出力

```markdown
# Handover: 2026-04-30 15:30

**Project**: /Users/goto/.dotfiles
**Branch**: main
**Status**: READY
**Session**: abc123-def456

## Session Summary
handover スキルの設計を進行中

## Tasks
- [ ] T1: handover スキル本体を実装 (in_progress)
  - Next: SKILL.md を docs/superpowers/specs/ から起こす

## Decisions
- **保存先**: `~/.claude/handover/{project-hash}/{branch}/` を採用
  - 却下: `.agents/`, `.handover.md`
  - 理由: プロジェクト側を汚さず、複数プロジェクト横断で集約管理できる

## Blockers
なし
```

## ルール

- ヘッダ時刻は `created_at` を `YYYY-MM-DD HH:MM` まで切り詰めて表示
- `tasks` が空配列なら `## Tasks` 直下に `なし`
- `decisions` が空配列なら `## Decisions` 直下に `なし`
- `blockers` が空配列なら `## Blockers` 直下に `なし`
- 完了タスクは `- [x]`、未完了は `- [ ]`
- `next_action` フィールドが存在するタスクのみ `- Next:` 行を追加
- `rejected` 配列が非空のときのみ `- 却下:` 行を追加
````

- [ ] **Step 7.3: コミット**

```bash
cd /Users/goto/.dotfiles
git add claude/skills/handover/references/
git commit -m "docs: handover の references を追加"
```

---

## Task 8: SKILL.md 作成（書込・破棄・状態確認）

**Files:**
- Create: `claude/skills/handover/SKILL.md`

- [ ] **Step 8.1: SKILL.md を作成**

Create `claude/skills/handover/SKILL.md`:

````markdown
---
name: handover
description: セッションの引き継ぎメモを作成・破棄・確認する。コンパクト前後で文脈が失われる事故を防ぐ。
argument-hint: "[clear | status]"
allowed-tools:
  - Bash
  - Read
  - Write
---

# Handover

セッションのタスク状態と決定事項を `~/.claude/handover/{project-hash}/{branch}/{fingerprint}/` 配下に記録し、次セッションで自動引き継ぎを可能にする。

## アクション判定

- 引数なし → 書込（メモ作成・更新）
- `clear` → 当該プロジェクト・ブランチの未消費メモを一括 consumed
- `status` → 現在の未消費メモ一覧を表示

## 書込（引数なし）

### 1. パス解決

Bash で `~/.claude/skills/handover/scripts/resolve-path.sh` を実行し、出力を `eval` で取り込む:

```sh
eval "$(${HOME}/.claude/skills/handover/scripts/resolve-path.sh)"
```

これにより以下が利用可能になる:
- `${PROJECT_PATH}` `${PROJECT_HASH}` `${BRANCH}` `${FINGERPRINT}` `${HANDOVER_DIR}`

### 2. 既存セッション再利用判定

Bash で:

```sh
${HOME}/.claude/skills/handover/scripts/list-active.sh "${PROJECT_HASH}" "${BRANCH}" "${CLAUDE_SESSION_ID}"
```

戻り値の JSON 配列が:
- 空 → 新規 fingerprint で作成: `target_dir="${HANDOVER_DIR}/${FINGERPRINT}"`
- 1 件以上 → 最初の要素の `abs_path` を再利用: `target_dir="$(jq -r '.[0].abs_path' <<< ...)"` 既存 state.json をマージベースで更新

### 3. state.json の構築

このセッションで観測したタスク・決定事項・ブロッカーを整理し、以下のスキーマで JSON を構築する。スキーマ詳細は `references/state-schema.md` を参照。

含めるべき内容（仕様書に基づく）:

- **tasks**: 残タスク・進行中タスク（最低限 `id` `description` `status` を埋める。`next_action` は明確なら埋める）
- **decisions**: このセッションで採用したアプローチ。却下した選択肢・採用理由を含める
- **blockers**: 着手を止めている事象（あれば）
- **session_summary**: 1〜2 行の要約

### 4. status 自動判定

`tasks[]` を走査:
- 全要素 `completed` または空 → `status = "ALL_COMPLETE"`
- それ以外 → `status = "READY"`

### 5. 書き出し

`${target_dir}/state.json` を Write ツールで書き出す。

### 6. handover.md を再生成

```sh
${HOME}/.claude/skills/handover/scripts/render-md.sh "${target_dir}/state.json" > "${target_dir}/handover.md"
```

### 7. cleanup 実行

```sh
${HOME}/.claude/skills/handover/scripts/cleanup.sh
```

### 8. ユーザーに報告

書き込み先の絶対パスとハイライト（タスク数、status）を表示する。

## 破棄（`/handover clear`）

### 1. パス解決

```sh
eval "$(${HOME}/.claude/skills/handover/scripts/resolve-path.sh)"
```

### 2. 当該ブランチの全 state.json を消費済みに

```sh
for f in "${HANDOVER_DIR}"/*/state.json(N); do
  ${HOME}/.claude/skills/handover/scripts/consume.sh "${f}"
done
```

zsh の `(N)` は null glob オプション（マッチがゼロでもエラーにしない）。

### 3. 現セッションのマーカーを削除

このセッションでも自動読込通知が再発火しないよう:

```sh
rm -f "${TMPDIR:-/tmp}/claude-handover-checked-${CLAUDE_SESSION_ID}"
```

代わりに作成:

```sh
touch "${TMPDIR:-/tmp}/claude-handover-checked-${CLAUDE_SESSION_ID}"
```

これで通知済み扱いとなり、UserPromptSubmit で再通知されない。

### 4. ユーザーに報告

何件の state.json を consumed したかを表示する。

## 状態確認（`/handover status`）

### 1. パス解決と列挙

```sh
eval "$(${HOME}/.claude/skills/handover/scripts/resolve-path.sh)"
${HOME}/.claude/skills/handover/scripts/list-active.sh "${PROJECT_HASH}" "${BRANCH}"
```

### 2. 結果表示

JSON 配列を読み解いて、以下の形式で表示:

```
Project: {project_hash}
Branch:  {branch}

Active handovers:
- {fingerprint}: {summary}
    created: {created_at}
    session: {session_id}
    path:    {abs_path}/handover.md
```

該当なしなら `No active handovers.` と表示。

## 不明な引数

`Unknown subcommand: {arg}. Use one of: (none) / clear / status` を表示し、何もせず終了する。

## 制約

- `state.json` の編集は `consume.sh` 経由 or Write ツールで行うこと（直接 sed しない）
- `handover.md` は `render-md.sh` でしか書かないこと（直接編集禁止）
- このセッションで実際に観測した事実のみ書く。推測や補足は含めない
````

- [ ] **Step 8.2: コミット**

```bash
cd /Users/goto/.dotfiles
git add claude/skills/handover/SKILL.md
git commit -m "feat: handover の SKILL.md を追加"
```

---

## Task 9: hooks/pre-compact.sh の TDD 実装

**Files:**
- Create: `claude/hooks/pre-compact.sh`
- Create: `claude/skills/handover/tests/pre-compact.bats`

- [ ] **Step 9.1: bats テストを書く**

Create `claude/skills/handover/tests/pre-compact.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() {
  setup_handover_env
  export CLAUDE_SESSION_ID="test-session-123"
}

teardown() {
  teardown_handover_env
}

@test "同 session_id の state.json があれば exit 0 + stdout 空" {
  d="${HOME}/.claude/handover/proj/main/20260430-100000"
  write_state "${d}" "${CLAUDE_SESSION_ID}" "READY" "$(iso_days_ago 0)"

  run "${HOOKS_DIR}/pre-compact.sh"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "session_id 一致なし → block JSON を出力" {
  d="${HOME}/.claude/handover/proj/main/20260430-100000"
  write_state "${d}" "other-session" "READY" "$(iso_days_ago 0)"

  run "${HOOKS_DIR}/pre-compact.sh"
  [ "${status}" -eq 0 ]
  decision="$(printf '%s' "${output}" | jq -r '.decision')"
  [ "${decision}" = "block" ]
  reason="$(printf '%s' "${output}" | jq -r '.reason')"
  [[ "${reason}" == *"/handover"* ]]
}

@test "handover ルート未存在 → block JSON" {
  rm -rf "${HOME}/.claude/handover"

  run "${HOOKS_DIR}/pre-compact.sh"
  [ "${status}" -eq 0 ]
  decision="$(printf '%s' "${output}" | jq -r '.decision')"
  [ "${decision}" = "block" ]
}

@test "CLAUDE_SESSION_ID 未設定 → exit 0 で何もしない" {
  unset CLAUDE_SESSION_ID

  run "${HOOKS_DIR}/pre-compact.sh"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "不正な JSON ファイルが混在しても他はチェックされる" {
  bad_dir="${HOME}/.claude/handover/proj/main/20260101-000000"
  good_dir="${HOME}/.claude/handover/proj/main/20260430-100000"
  mkdir -p "${bad_dir}"
  echo "not json" > "${bad_dir}/state.json"
  write_state "${good_dir}" "${CLAUDE_SESSION_ID}" "READY" "$(iso_days_ago 0)"

  run "${HOOKS_DIR}/pre-compact.sh"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}
```

- [ ] **Step 9.2: テスト失敗確認**

Run: `bats /Users/goto/.dotfiles/claude/skills/handover/tests/pre-compact.bats`
Expected: 全テスト FAIL

- [ ] **Step 9.3: hooks/pre-compact.sh を実装**

Create `claude/hooks/pre-compact.sh`:

```sh
#!/bin/zsh
# Claude Code の PreCompact フック。
# 現セッション ID で書かれた handover が存在しない時、コンパクトをブロックして
# ユーザーに /handover 実行を促す。
set -eu

session_id="${CLAUDE_SESSION_ID:-}"
[ -z "${session_id}" ] && exit 0

handover_root="${HOME}/.claude/handover"

found="false"
if [ -d "${handover_root}" ]; then
  setopt NULL_GLOB
  for state_file in "${handover_root}"/*/*/*/state.json; do
    [ ! -f "${state_file}" ] && continue
    if ! jq empty "${state_file}" >/dev/null 2>&1; then
      continue
    fi
    sid="$(jq -r '.session_id // ""' "${state_file}")"
    if [ "${sid}" = "${session_id}" ]; then
      found="true"
      break
    fi
  done
fi

if [ "${found}" = "true" ]; then
  exit 0
fi

cat <<'EOF'
{
  "decision": "block",
  "reason": "セッション開始後に /handover を実行してから再度コンパクトしてください。"
}
EOF
exit 0
```

Run: `chmod +x /Users/goto/.dotfiles/claude/hooks/pre-compact.sh`

- [ ] **Step 9.4: テスト合格確認**

Run: `bats /Users/goto/.dotfiles/claude/skills/handover/tests/pre-compact.bats`
Expected: `5 tests, 0 failures`

- [ ] **Step 9.5: コミット**

```bash
cd /Users/goto/.dotfiles
git add claude/hooks/pre-compact.sh \
        claude/skills/handover/tests/pre-compact.bats
git commit -m "feat: PreCompact フックで未 handover 時をブロック"
```

---

## Task 10: hooks/session-start.sh の TDD 実装

**Files:**
- Create: `claude/hooks/session-start.sh`
- Create: `claude/skills/handover/tests/session-start.bats`

- [ ] **Step 10.1: bats テストを書く**

Create `claude/skills/handover/tests/session-start.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() {
  setup_handover_env
  export CLAUDE_SESSION_ID="sess-start-test"
  WORK_DIR="$(mktemp -d)"
  cd "${WORK_DIR}"
  git init -q -b main
  git -c user.email=a@a -c user.name=a commit --allow-empty -q -m init
  # CWD ベースで HANDOVER_DIR を計算
  eval "$("${SCRIPTS_DIR}/resolve-path.sh")"
}

teardown() {
  cd /
  rm -rf "${WORK_DIR}"
  teardown_handover_env
}

@test "未消費メモあり → additionalContext 出力 + マーカー作成" {
  d="${HANDOVER_DIR}/20260430-100000"
  write_state "${d}" "old-session" "READY" "$(iso_days_ago 1)" "false"

  run "${HOOKS_DIR}/session-start.sh"
  [ "${status}" -eq 0 ]
  ctx="$(printf '%s' "${output}" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "${ctx}" == *"HANDOVER NOTICE"* ]]
  [[ "${ctx}" == *"20260430-100000"* ]]
  [ -f "${TMPDIR}/claude-handover-checked-${CLAUDE_SESSION_ID}" ]
}

@test "未消費メモなし → 何も出力しない、マーカーも作らない" {
  run "${HOOKS_DIR}/session-start.sh"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ ! -f "${TMPDIR}/claude-handover-checked-${CLAUDE_SESSION_ID}" ]
}

@test "consumed=true は通知対象外" {
  d="${HANDOVER_DIR}/20260430-100000"
  write_state "${d}" "old-session" "READY" "$(iso_days_ago 1)" "true"
  run "${HOOKS_DIR}/session-start.sh"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "ALL_COMPLETE は通知対象外" {
  d="${HANDOVER_DIR}/20260430-100000"
  write_state "${d}" "old-session" "ALL_COMPLETE" "$(iso_days_ago 1)" "false"
  run "${HOOKS_DIR}/session-start.sh"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "TTL 7日超は通知対象外" {
  d="${HANDOVER_DIR}/20260101-000000"
  write_state "${d}" "old-session" "READY" "$(iso_days_ago 10)" "false"
  run "${HOOKS_DIR}/session-start.sh"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "CLAUDE_SESSION_ID 未設定 → exit 0、何もしない" {
  unset CLAUDE_SESSION_ID
  run "${HOOKS_DIR}/session-start.sh"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "出力 JSON の hookEventName は SessionStart" {
  d="${HANDOVER_DIR}/20260430-100000"
  write_state "${d}" "old-session" "READY" "$(iso_days_ago 1)" "false"
  run "${HOOKS_DIR}/session-start.sh"
  name="$(printf '%s' "${output}" | jq -r '.hookSpecificOutput.hookEventName')"
  [ "${name}" = "SessionStart" ]
}
```

- [ ] **Step 10.2: テスト失敗確認**

Run: `bats /Users/goto/.dotfiles/claude/skills/handover/tests/session-start.bats`
Expected: 全テスト FAIL

- [ ] **Step 10.3: hooks/session-start.sh を実装**

Create `claude/hooks/session-start.sh`:

```sh
#!/bin/zsh
# Claude Code の SessionStart フック。
# 当該プロジェクト・ブランチの未消費メモを検出し、引き継ぎ確認を Claude に注入する。
set -eu

session_id="${CLAUDE_SESSION_ID:-}"
[ -z "${session_id}" ] && exit 0

marker_dir="${TMPDIR:-/tmp}"
marker="${marker_dir}/claude-handover-checked-${session_id}"
[ -f "${marker}" ] && exit 0

scripts_dir="${HOME}/.claude/skills/handover/scripts"
[ ! -d "${scripts_dir}" ] && exit 0

active_json="$("${scripts_dir}/list-active.sh" 2>/dev/null || printf '[]')"
count="$(printf '%s' "${active_json}" | jq 'length' 2>/dev/null || printf '0')"
[ "${count}" = "0" ] && exit 0

ctx="$(printf '%s' "${active_json}" | jq -r '
  "[HANDOVER NOTICE]\n未消費の handover が見つかりました:\n" +
  ([.[] | "- \(.fingerprint): \(.summary) (\(.created_at))\n  パス: \(.abs_path)/handover.md"] | join("\n")) +
  "\n\nユーザーに「引き継ぎますか？それとも新規会話にしますか？」を確認してください。\n - 引き継ぐ → 上記 handover.md の内容を Read で読み込み、~/.claude/skills/handover/scripts/consume.sh <abs_path>/state.json を Bash で実行\n - 新規 → consume.sh のみ実行（読込はしない）"
')"

jq -n --arg ctx "${ctx}" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'

mkdir -p "${marker_dir}"
touch "${marker}"
```

Run: `chmod +x /Users/goto/.dotfiles/claude/hooks/session-start.sh`

- [ ] **Step 10.4: テスト合格確認**

Run: `bats /Users/goto/.dotfiles/claude/skills/handover/tests/session-start.bats`
Expected: `7 tests, 0 failures`

- [ ] **Step 10.5: コミット**

```bash
cd /Users/goto/.dotfiles
git add claude/hooks/session-start.sh \
        claude/skills/handover/tests/session-start.bats
git commit -m "feat: SessionStart フックで未消費 handover を通知"
```

---

## Task 11: hooks/user-prompt-submit.sh の TDD 実装

**Files:**
- Create: `claude/hooks/user-prompt-submit.sh`
- Create: `claude/skills/handover/tests/user-prompt-submit.bats`

- [ ] **Step 11.1: bats テストを書く**

Create `claude/skills/handover/tests/user-prompt-submit.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() {
  setup_handover_env
  export CLAUDE_SESSION_ID="sess-ups-test"
  WORK_DIR="$(mktemp -d)"
  cd "${WORK_DIR}"
  git init -q -b main
  git -c user.email=a@a -c user.name=a commit --allow-empty -q -m init
  eval "$("${SCRIPTS_DIR}/resolve-path.sh")"
}

teardown() {
  cd /
  rm -rf "${WORK_DIR}"
  teardown_handover_env
}

@test "マーカーなし + 未消費メモあり → 通知 + マーカー作成" {
  d="${HANDOVER_DIR}/20260430-100000"
  write_state "${d}" "old" "READY" "$(iso_days_ago 1)" "false"
  run "${HOOKS_DIR}/user-prompt-submit.sh"
  [ "${status}" -eq 0 ]
  name="$(printf '%s' "${output}" | jq -r '.hookSpecificOutput.hookEventName')"
  [ "${name}" = "UserPromptSubmit" ]
  [ -f "${TMPDIR}/claude-handover-checked-${CLAUDE_SESSION_ID}" ]
}

@test "マーカーあり → 何もしない（重複抑止）" {
  touch "${TMPDIR}/claude-handover-checked-${CLAUDE_SESSION_ID}"
  d="${HANDOVER_DIR}/20260430-100000"
  write_state "${d}" "old" "READY" "$(iso_days_ago 1)" "false"
  run "${HOOKS_DIR}/user-prompt-submit.sh"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "未消費メモなし → 何もしない、マーカーも作らない" {
  run "${HOOKS_DIR}/user-prompt-submit.sh"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ ! -f "${TMPDIR}/claude-handover-checked-${CLAUDE_SESSION_ID}" ]
}

@test "CLAUDE_SESSION_ID 未設定 → 何もしない" {
  unset CLAUDE_SESSION_ID
  run "${HOOKS_DIR}/user-prompt-submit.sh"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}
```

- [ ] **Step 11.2: テスト失敗確認**

Run: `bats /Users/goto/.dotfiles/claude/skills/handover/tests/user-prompt-submit.bats`
Expected: 全テスト FAIL

- [ ] **Step 11.3: hooks/user-prompt-submit.sh を実装**

Create `claude/hooks/user-prompt-submit.sh`:

```sh
#!/bin/zsh
# Claude Code の UserPromptSubmit フック。
# session-start.sh と同等のロジックだが、マーカーで重複抑止し、
# hookEventName を UserPromptSubmit にする。
set -eu

session_id="${CLAUDE_SESSION_ID:-}"
[ -z "${session_id}" ] && exit 0

marker_dir="${TMPDIR:-/tmp}"
marker="${marker_dir}/claude-handover-checked-${session_id}"
[ -f "${marker}" ] && exit 0

scripts_dir="${HOME}/.claude/skills/handover/scripts"
[ ! -d "${scripts_dir}" ] && exit 0

active_json="$("${scripts_dir}/list-active.sh" 2>/dev/null || printf '[]')"
count="$(printf '%s' "${active_json}" | jq 'length' 2>/dev/null || printf '0')"
[ "${count}" = "0" ] && exit 0

ctx="$(printf '%s' "${active_json}" | jq -r '
  "[HANDOVER NOTICE]\n未消費の handover が見つかりました:\n" +
  ([.[] | "- \(.fingerprint): \(.summary) (\(.created_at))\n  パス: \(.abs_path)/handover.md"] | join("\n")) +
  "\n\nユーザーに「引き継ぎますか？それとも新規会話にしますか？」を確認してください。\n - 引き継ぐ → 上記 handover.md の内容を Read で読み込み、~/.claude/skills/handover/scripts/consume.sh <abs_path>/state.json を Bash で実行\n - 新規 → consume.sh のみ実行（読込はしない）"
')"

jq -n --arg ctx "${ctx}" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'

mkdir -p "${marker_dir}"
touch "${marker}"
```

Run: `chmod +x /Users/goto/.dotfiles/claude/hooks/user-prompt-submit.sh`

- [ ] **Step 11.4: テスト合格確認**

Run: `bats /Users/goto/.dotfiles/claude/skills/handover/tests/user-prompt-submit.bats`
Expected: `4 tests, 0 failures`

- [ ] **Step 11.5: コミット**

```bash
cd /Users/goto/.dotfiles
git add claude/hooks/user-prompt-submit.sh \
        claude/skills/handover/tests/user-prompt-submit.bats
git commit -m "feat: UserPromptSubmit フックでコンパクト後の未消費 handover を通知"
```

---

## Task 12: claude/settings.json への hook 登録

**Files:**
- Modify: `claude/settings.json`

- [ ] **Step 12.1: 既存の hooks セクションを読む**

Run: `jq '.hooks' /Users/goto/.dotfiles/claude/settings.json`
Expected: 既存の `PreToolUse` / `PostToolUse` 配列が表示される

- [ ] **Step 12.2: hooks セクションを更新**

`claude/settings.json` の `hooks` キーを以下に置き換える（既存の PreToolUse / PostToolUse は維持）:

```json
"hooks": {
  "PreToolUse": [
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "if printf '%s\\n' \"$CLAUDE_TOOL_INPUT\" | jq -r '.command' 2>/dev/null | grep -qE '(rm\\s+-rf\\s+(/|~|\\$HOME|/usr|/etc|/var|/opt|/System)|>\\s*/dev/sd|mkfs|dd\\s+if=|git\\s+push\\s+.*--force|git\\s+push\\s+.*-f\\b|git\\s+reset\\s+--hard|git\\s+clean\\s+-fd)'; then echo 'BLOCK: Destructive command detected' >&2; exit 2; fi"
        }
      ]
    }
  ],
  "PostToolUse": [
    {
      "matcher": "Edit|Write",
      "hooks": [
        {
          "type": "command",
          "command": "npx tsc --noEmit --pretty 2>&1 | head -20"
        }
      ]
    }
  ],
  "PreCompact": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "${HOME}/.claude/hooks/pre-compact.sh"
        }
      ]
    }
  ],
  "SessionStart": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "${HOME}/.claude/hooks/session-start.sh"
        }
      ]
    }
  ],
  "UserPromptSubmit": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "${HOME}/.claude/hooks/user-prompt-submit.sh"
        }
      ]
    }
  ]
}
```

- [ ] **Step 12.3: settings.json が valid JSON か検証**

Run: `jq empty /Users/goto/.dotfiles/claude/settings.json && echo OK`
Expected: `OK`

- [ ] **Step 12.4: 反映確認（シンボリックリンク経由）**

Run:
```bash
ls -la ${HOME}/.claude/hooks/pre-compact.sh
ls -la ${HOME}/.claude/hooks/session-start.sh
ls -la ${HOME}/.claude/hooks/user-prompt-submit.sh
```
Expected: 3 ファイルとも存在し、`/Users/goto/.dotfiles/claude/hooks/...` を指すシンボリックリンク

もしリンクが張られていない場合、`/Users/goto/.dotfiles/setup/setup.zsh` のロジックを確認する。`claude/` ディレクトリ全体が `~/.claude/` にリンクされているか、サブディレクトリが反映されているかを検証する。

- [ ] **Step 12.5: コミット**

```bash
cd /Users/goto/.dotfiles
git add claude/settings.json
git commit -m "feat: handover フックを settings.json に登録"
```

---

## Task 13: Brewfile / CLAUDE.md / setup.zsh の整合確認と更新

**Files:**
- Modify: `CLAUDE.md`（リポジトリ構造に `claude/hooks/` を追加 + handover の説明）
- Verify: `setup/setup.zsh`（`claude/hooks/` のシンボリックリンクが既存ロジックでカバーされるか）

- [ ] **Step 13.1: setup.zsh の挙動を確認**

Run: `cat /Users/goto/.dotfiles/setup/setup.zsh | head -100`

`claude/` ディレクトリ全体（サブディレクトリ含む）が `~/.claude/` にシンボリックリンクされているなら追加対応不要。`claude/skills/` と `claude/hooks/` が個別ループで処理されているなら `hooks/` 用のループ追加が必要。

→ もし対応が必要なら、setup.zsh を修正してから本タスクを進める。

- [ ] **Step 13.2: CLAUDE.md のリポジトリ構造を更新**

`/Users/goto/.dotfiles/CLAUDE.md` の「リポジトリ構造」セクションに以下を追加:

```markdown
- `claude/hooks/` — Claude Code フックスクリプト群（PreCompact / SessionStart / UserPromptSubmit）
```

挿入位置は既存の `claude/` の説明の直下が妥当。

- [ ] **Step 13.3: CLAUDE.md の「Claude Code 設定」セクションに handover の説明を追加**

「Claude Code 設定」セクションに以下を追記:

```markdown
- `claude/skills/handover/` は引き継ぎメモ管理スキル。`/handover` 実行で `~/.claude/handover/{project-hash}/{branch}/{fingerprint}/` 配下に `state.json` と `handover.md` を生成する
- `claude/hooks/` 配下のフックスクリプトは PreCompact で未 handover 時のコンパクトをブロックし、SessionStart / UserPromptSubmit で未消費メモを Claude に通知する
```

- [ ] **Step 13.4: コミット**

```bash
cd /Users/goto/.dotfiles
git add CLAUDE.md
# setup.zsh も修正したなら add
if git diff --cached --name-only | grep -q setup.zsh; then :; else
  if ! git diff --quiet setup/setup.zsh; then
    git add setup/setup.zsh
  fi
fi
git commit -m "docs: CLAUDE.md に handover とフックの説明を追加"
```

---

## Task 14: 手動シナリオテストとドキュメント

**Files:**
- Create: `claude/skills/handover/tests/scenarios.md`

- [ ] **Step 14.1: scenarios.md にチェックリストを書き出す**

Create `claude/skills/handover/tests/scenarios.md`:

```markdown
# 手動シナリオテスト

bats では検証できない統合動作（Claude が実際に SKILL.md を解釈して動くこと、
フックが Claude Code から実際に発火すること）を手動で検証する。

実行は実装完了後、最低 1 周通すこと。

## A. 基本サイクル: 書込 → 別セッション起動 → 引き継ぎ

1. 任意の git リポジトリで `claude` を起動
2. `/handover` を実行
3. `~/.claude/handover/{hash}/{branch}/{fingerprint}/state.json` と `handover.md` が作られていることを確認
4. `claude` を終了
5. 同じディレクトリで再度 `claude` を起動
6. **期待**: 起動直後に「未消費の handover があります、引き継ぎますか？」の確認が出る
7. 「引き継ぐ」と答え、内容が会話に反映されることを確認
8. `state.json` の `consumed: true` を確認

## B. ALL_COMPLETE は通知対象外

1. 全タスク完了状態（または tasks 空）で `/handover` 実行
2. `state.json` の `status` が `ALL_COMPLETE` であることを確認
3. 別セッションで起動
4. **期待**: 通知が出ない

## C. TTL 7日超は通知対象外

1. 過去のテスト用 state.json を `created_at: 10 日前` で配置
2. `claude` 起動
3. **期待**: 通知が出ない
4. `~/.claude/skills/handover/scripts/cleanup.sh` 実行で削除されることを確認（status=ALL_COMPLETE のとき）

## D. /handover clear で破棄

1. `/handover` で未消費メモを作る
2. `/handover clear` を実行
3. 別セッション起動
4. **期待**: 通知が出ない
5. `state.json` の `consumed: true` を確認

## E. 手動 /compact は事前に /handover が必要

1. 新規セッション起動（`/handover` 履歴なし）
2. `/compact` を実行
3. **期待**: コンパクトがブロックされ「セッション開始後に /handover を実行してから...」reason が表示される
4. `/handover` を実行
5. 再度 `/compact`
6. **期待**: 今度は通る

## F. 自動コンパクトでもブロック

1. コンテキストを大量に消費する作業を行い、自動コンパクトが発火する状態にする
2. `/handover` を打たずに継続
3. **期待**: 自動コンパクト発火時にブロックされる
4. `/handover` を実行 → 自動コンパクトが進む

## G. 同セッション続行: コンパクト後の重複通知抑止

1. `/handover` → `/compact`（成功）
2. コンパクト後に何かプロンプトを送る
3. **期待**: UserPromptSubmit で通知が出るのは最大 1 回のみ
4. もう一度プロンプトを送る
5. **期待**: 既にマーカーがあるので通知は出ない

## H. 別ブランチに切り替えると通知対象外

1. `feature/x` ブランチで `/handover`
2. `git checkout main` で別ブランチへ
3. 同セッションで `claude` を再起動
4. **期待**: `feature/x` の handover は通知対象外（プロジェクトハッシュ + ブランチ単位の分離が機能）

## I. /handover status

1. `/handover` でメモを作る
2. `/handover status` を実行
3. **期待**: 該当ブランチの未消費メモ一覧が表示される
4. `/handover clear` 後に `/handover status`
5. **期待**: `No active handovers.` 表示

## 結果記録

各シナリオ実行後、PR 説明欄に成否を記録すること:

| シナリオ | 結果 |
|---|---|
| A. 基本サイクル | □ |
| B. ALL_COMPLETE | □ |
| C. TTL 7 日超 | □ |
| D. /handover clear | □ |
| E. 手動 /compact ブロック | □ |
| F. 自動コンパクトブロック | □ |
| G. 重複通知抑止 | □ |
| H. ブランチ分離 | □ |
| I. /handover status | □ |
```

- [ ] **Step 14.2: 手動シナリオを実行**

scenarios.md の各シナリオ A〜I を 1 つずつ実行し、結果を記録する。
失敗があった場合、原因を特定して修正コミットを追加する。

- [ ] **Step 14.3: コミット**

```bash
cd /Users/goto/.dotfiles
git add claude/skills/handover/tests/scenarios.md
git commit -m "docs: handover の手動シナリオテストを追加"
```

- [ ] **Step 14.4: 全 bats テストを最終実行**

Run: `bats /Users/goto/.dotfiles/claude/skills/handover/tests/*.bats`
Expected: 全テスト合格

- [ ] **Step 14.5: PR 作成（commit-push-pr スキル経由）**

Run: 設計書の主要ポイント（コンパクト前後の引き継ぎ、PreCompact ブロック、ブランチ分離、TTL 7 日）を要約した PR 本文を作成する。手動シナリオテストの結果（A〜I の成否）も PR 本文に含める。
