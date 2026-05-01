# linear-plan / github-plan 廃止 + project.yml 設定統合 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `linear-plan` / `github-plan` の 2 スキルを廃止し、`.claude/feature-team.yml` を `.claude/project.yml` に統合、`create-issue` の `<tracker>` 引数を廃止して config 自己解決に変更する。

**Architecture:** ドキュメント・設定ファイル中心の改修。各タスクは「ファイル編集 → grep 検証 → commit」を 1 サイクルとし、独立した commit として積む。物理ファイルマイグレーション（`.yml` の置換）は単一 commit で完結させ、中間状態を残さない。

**Tech Stack:** Markdown（SKILL.md, README.md, CLAUDE.md, auto memory）/ YAML（`.claude/project.yml`）/ シェル（grep, ls, rm, git）

**Spec:** `docs/superpowers/specs/2026-05-01-deprecate-linear-github-plan-design.md`

---

## 実行順序の考え方

1. **Task 1**: 設定ファイル物理マイグレーション（基盤）
2. **Task 2**: `create-issue` 改修（最も独立性が高い。新 config を参照する側の主体）
3. **Task 3**: `feature-team/SKILL.md` 改修（create-issue を呼び出す側）
4. **Task 4**: `feature-team/README.md` 改修
5. **Task 5**: `feature-team/roles/{_common,parent}.md` 改修
6. **Task 6**: トップレベル `CLAUDE.md` 改修
7. **Task 7**: `linear-plan` / `github-plan` ディレクトリ削除 + symlink 残骸の cleanup
8. **Task 8**: auto memory `project_feature_team_skill.md` 更新
9. **Task 9**: 最終検証（受入条件チェック）

---

## Task 1: `.claude/project.yml` 新設 + `.claude/feature-team.yml` 削除

**Files:**
- Create: `/Users/goto/.dotfiles/.claude/project.yml`
- Delete: `/Users/goto/.dotfiles/.claude/feature-team.yml`

- [ ] **Step 1.1: 既存 `.claude/feature-team.yml` の値を確認**

```bash
cat /Users/goto/.dotfiles/.claude/feature-team.yml
```

期待される内容（移行元）:
```yaml
issue_tracker:
  type: linear
  team: KISSA
  # project_id: bbe50233861e

default_reviewers:
  - quality

review_round_limit: 3

volume_thresholds:
  small:
    max_sub_issues: 1
    max_files: 5
    max_lines: 200
  large:
    min_sub_issues: 2
    min_files: 6
    min_lines: 201
```

- [ ] **Step 1.2: `.claude/project.yml` を新スキーマで作成**

`/Users/goto/.dotfiles/.claude/project.yml` に以下の内容で `Write` ツールを使う:

```yaml
# .claude/project.yml — このプロジェクトに関する Claude スキル / ワークフロー設定
#
# tracker: create-issue が参照（Issue tracker 設定）
# review:  feature-team Phase 5 が参照
# volume_thresholds: feature-team Phase 3 が参照（roles/parent.md のしきい値上書き）

tracker:
  type: linear
  linear:
    team: KISSA
    project_id: bbe50233861e
  # github を使う場合は上記 linear セクションを削除し、以下をアンコメント:
  # github:
  #   project_number: 1

review:
  default_reviewers:
    - quality
    # security / performance は roles/parent.md の起動条件で動的判断
  round_limit: 3

volume_thresholds:
  small:
    max_sub_issues: 1
    max_files: 5
    max_lines: 200
  large:
    min_sub_issues: 2
    min_files: 6
    min_lines: 201
```

注意点: 旧 `.claude/feature-team.yml` の `project_id` はコメントアウトされていたが、spec で「`project_id` も入れたい」と決定済みのため、新ファイルでは有効値として書く。

- [ ] **Step 1.3: 旧 `.claude/feature-team.yml` を削除**

```bash
rm /Users/goto/.dotfiles/.claude/feature-team.yml
ls -la /Users/goto/.dotfiles/.claude/
```

期待: `feature-team.yml` が存在せず、`project.yml` のみ存在する。

- [ ] **Step 1.4: 移行内容を git diff で確認**

```bash
cd /Users/goto/.dotfiles && git status --short
```

期待出力:
```
 D .claude/feature-team.yml
?? .claude/project.yml
```

- [ ] **Step 1.5: 1 commit で完結**

```bash
cd /Users/goto/.dotfiles
git add .claude/project.yml .claude/feature-team.yml
git commit -m "$(cat <<'EOF'
refactor(config): .claude/feature-team.yml を .claude/project.yml に置換

tracker / review / volume_thresholds の 3 セクションに再構成。
スキル名に依存しない汎用名（project.yml）に統一する。
EOF
)"
```

期待: 1 file deleted, 1 file created の 1 commit。

---

## Task 2: `create-issue` SKILL.md 改修

**Files:**
- Modify: `/Users/goto/.dotfiles/claude/skills/create-issue/SKILL.md`

- [ ] **Step 2.1: frontmatter の `argument-hint` を更新**

`Edit` ツールで以下を置換:

old_string:
```
argument-hint: <tracker> <spec-path> <plan-path>
```

new_string:
```
argument-hint: <spec-path> <plan-path>
```

- [ ] **Step 2.2: frontmatter の `description` から linear-plan/github-plan 言及を削除**

old_string:
```
description: Spec / plan を入力に、Linear または GitHub の親 Issue + sub-issue 群を自律的に登録する。対話深掘りステップは持たず、`feature-team` Phase 2 から呼ばれることを想定した design-doc 駆動パイプライン。既存の `linear-plan` / `github-plan`（対話起点の単発用途）とは棲み分ける。
```

new_string:
```
description: Spec / plan を入力に、Linear または GitHub の親 Issue + sub-issue 群を自律的に登録する。対話深掘りステップは持たず、`feature-team` Phase 2 から呼ばれることを想定した design-doc 駆動パイプライン。tracker は `.claude/project.yml` の `tracker.type` から自己解決する。
```

- [ ] **Step 2.3: 引数セクション（L17-26 相当）を書き換え**

old_string:
````
## 引数

```
/create-issue <tracker> <spec-path> <plan-path>
```

- `<tracker>`: `linear` | `github`
- `<spec-path>`: spec ファイルへの絶対 or 相対パス（例: `docs/superpowers/specs/2026-05-01-feature-x-design.md`）
- `<plan-path>`: plan ファイルへの絶対 or 相対パス（例: `docs/superpowers/plans/2026-05-01-feature-x.md`）

引数が不足している、もしくはパスが存在しない場合は即座にエラーで停止する。**この時点でユーザー対話には戻らない**（呼び元の `feature-team` 親が再投入する想定）。
````

new_string:
````
## 引数

```
/create-issue <spec-path> <plan-path>
```

- `<spec-path>`: spec ファイルへの絶対 or 相対パス（例: `docs/superpowers/specs/2026-05-01-feature-x-design.md`）
- `<plan-path>`: plan ファイルへの絶対 or 相対パス（例: `docs/superpowers/plans/2026-05-01-feature-x.md`）

tracker は `.claude/project.yml` の `tracker.type` から自己解決する（引数では受け取らない）。

引数が不足している、パスが存在しない、もしくは `.claude/project.yml` が存在しない / `tracker.type` 未定義の場合は即座にエラーで停止する。**この時点でユーザー対話には戻らない**（呼び元の `feature-team` 親が再投入する想定）。
````

- [ ] **Step 2.4: 「このスキルがしないこと」L38 を更新**

old_string:
```
- 対話によるアイデア深掘り（`linear-plan` / `github-plan` の役割）
```

new_string:
```
- 対話によるアイデア深掘り（`superpowers:brainstorming` の役割）
```

- [ ] **Step 2.5: §1 引数検証ブロックを書き換え**

old_string:
````
## 1. 引数検証

```bash
# tracker
[[ "$1" == "linear" || "$1" == "github" ]] || abort "tracker must be 'linear' or 'github'"
# パス存在
[[ -f "$2" ]] || abort "spec not found: $2"
[[ -f "$3" ]] || abort "plan not found: $3"
```
````

new_string:
````
## 1. 引数検証

```bash
# パス存在
[[ -f "$1" ]] || abort "spec not found: $1"
[[ -f "$2" ]] || abort "plan not found: $2"

# 設定ファイル存在
[[ -f .claude/project.yml ]] || abort ".claude/project.yml not found. Define tracker.type before running create-issue."

# tracker.type 取得（yq があれば yq、なければ grep ベースの簡易抽出）
TRACKER_TYPE=$(yq -r '.tracker.type' .claude/project.yml 2>/dev/null || grep -E '^[[:space:]]+type:' .claude/project.yml | head -1 | awk '{print $2}')
[[ "$TRACKER_TYPE" == "linear" || "$TRACKER_TYPE" == "github" ]] || abort "tracker.type must be 'linear' or 'github' in .claude/project.yml"
```

`<tracker>` は引数で受け取らず、`.claude/project.yml` の `tracker.type` を必ず参照する。
````

- [ ] **Step 2.6: §3-Linear のチーム情報取得を新スキーマに書き換え**

old_string:
```
複数チームがある場合、spec / plan のフロントマターか `.claude/feature-team.yml` にチームキー指定があれば優先する。なければエラー停止して呼び元に「チーム指定が必要」と報告する（自律スキルなので推測しない）。
```

new_string:
```
複数チームがある場合、`.claude/project.yml` の `tracker.linear.team` を必ず参照する。指定がなければエラー停止して呼び元に「`.claude/project.yml` に `tracker.linear.team` が必要」と報告する（自律スキルなので推測しない）。

`tracker.linear.project_id` が指定されている場合、Issue 作成時に `--project` フラグ相当で関連付ける（linear-cli の対応状況に応じて運用）。
```

- [ ] **Step 2.7: §3-GitHub の Project 参照を新スキーマに書き換え**

old_string:
```
- 2 個以上 → `.claude/feature-team.yml` の `issue_tracker.project_number` を参照。指定がなければエラー停止
```

new_string:
```
- 2 個以上 → `.claude/project.yml` の `tracker.github.project_number` を参照。指定がなければエラー停止
```

- [ ] **Step 2.8: §7-GitHub 内の「github-plan で確立されたパターン」括弧書きを削除**

old_string:
```
`item-list` の `--limit` は Project の既存アイテム数以上に設定する（既存の `github-plan` で確立されたパターン）。
```

new_string:
```
`item-list` の `--limit` は Project の既存アイテム数以上に設定する。
```

- [ ] **Step 2.9: 末尾「既存スキルとの棲み分け」表 + 段落（L323-331 相当）を全削除**

old_string:
````
## 既存スキルとの棲み分け

| スキル | 起点 | 対話 | 入力 |
|--------|------|------|------|
| `linear-plan` | アイデア（口頭） | あり（Socratic） | アイデア文字列 |
| `github-plan` | アイデア（口頭） | あり（深掘り） | アイデア文字列 |
| **`create-issue`（このスキル）** | **spec/plan ファイル** | **なし** | **spec-path + plan-path** |

`linear-plan` / `github-plan` は無改修で温存する。単発で対話的に Issue を立てたい場合はそちらを使う。`feature-team` は **brainstorming + writing-plans の標準フロー** を経たうえでこのスキルを呼ぶ。
````

new_string:
````
## 呼び出し元

このスキルは以下のパターンで呼ばれる:

- `feature-team` Phase 2 — brainstorming + writing-plans が生成した spec / plan を入力に自律登録
- 単独実行 — spec / plan が手元にあるとき `/create-issue <spec> <plan>` で直接登録

いずれの場合も tracker は `.claude/project.yml` から自己解決するため、呼び出し側は tracker を引数で渡さない。
````

- [ ] **Step 2.10: 完了報告テンプレ（§8）の Tracker 行を確認・更新**

`Read` で `/Users/goto/.dotfiles/claude/skills/create-issue/SKILL.md` の §8 完了報告セクションを確認し、`**Tracker:** linear / github` 行があれば「.claude/project.yml の tracker.type で解決」と注記を追加。

old_string:
```
**Tracker:** linear / github
```

new_string:
```
**Tracker:** linear / github（`.claude/project.yml` の `tracker.type` で解決）
```

- [ ] **Step 2.11: grep 検証**

```bash
cd /Users/goto/.dotfiles
grep -nE 'linear-plan|github-plan|feature-team\.yml|<tracker>|issue_tracker' claude/skills/create-issue/SKILL.md
```

期待: 何もマッチしない（exit code 1）。

- [ ] **Step 2.12: commit**

```bash
cd /Users/goto/.dotfiles
git add claude/skills/create-issue/SKILL.md
git commit -m "$(cat <<'EOF'
refactor(create-issue): tracker 引数を廃止し .claude/project.yml から自己解決する

引数を <spec-path> <plan-path> の 2 つに簡略化。tracker.type / tracker.linear.* / tracker.github.* を .claude/project.yml から読む。linear-plan / github-plan の言及を削除。
EOF
)"
```

---

## Task 3: `feature-team/SKILL.md` 改修

**Files:**
- Modify: `/Users/goto/.dotfiles/claude/skills/feature-team/SKILL.md`

- [ ] **Step 3.1: 設定ファイルセクション見出し + 本文（L29-31）を更新**

old_string:
```
## 設定ファイル: `.claude/feature-team.yml`

リポジトリごとの挙動は `.claude/feature-team.yml` で制御する。
```

new_string:
```
## 設定ファイル: `.claude/project.yml`

リポジトリごとの挙動は `.claude/project.yml` で制御する。`feature-team` が読むセクションは `review.*` と `volume_thresholds.*` のみで、`tracker.*` は `create-issue` が直接参照する（Phase 2 では `feature-team` は tracker を読まない）。
```

- [ ] **Step 3.2: スキーマ定義（L33-55）を新スキーマに全面書き換え**

old_string:
````
### スキーマ

```yaml
# Phase 2: イシュー化先
issue_tracker:
  type: github          # github | linear
  # type: linear の場合のみ有効
  # team: SCN

# Phase 5: 既定で起動するレビュー観点（タスク内容に応じて増減する）
default_reviewers:
  - quality
  # - security
  # - performance

# Phase 5: レビュー往復上限（既定 3）
review_round_limit: 3

# Phase 3: ボリューム判断のしきい値上書き（任意）
# volume_thresholds:
#   small_max_subtasks: 1
#   small_max_files: 5
```
````

new_string:
````
### スキーマ

```yaml
# tracker: create-issue が参照（feature-team は読まない）
tracker:
  type: linear              # linear | github
  linear:
    team: KISSA
    project_id: bbe50233861e
  # github を使う場合:
  # github:
  #   project_number: 1

# review: feature-team Phase 5 で参照
review:
  default_reviewers:
    - quality
    # - security
    # - performance
  round_limit: 3            # レビュー往復上限（既定 3）

# volume_thresholds: feature-team Phase 3（roles/parent.md のしきい値）で参照
volume_thresholds:
  small:
    max_sub_issues: 1
    max_files: 5
    max_lines: 200
  large:
    min_sub_issues: 2
    min_files: 6
    min_lines: 201
```
````

- [ ] **Step 3.3: 不在時フォールバック（L57-64）を新スキーマで書き換え**

old_string:
```
### 不在時のフォールバック

Phase 2 開始時にこのファイルが存在しない場合:

1. 親が上記の雛形を `.claude/feature-team.yml` に書き出す
2. `AskUserQuestion` で「この内容でコミットするか / 内容を修正するか / 一時的に使うだけか」を確認
3. ユーザーが内容を修正したい場合は、対話で値を確定してから書き直す
4. **コミットの実行はユーザー判断に従う**。親は勝手に `git add` / `git commit` しない
```

new_string:
```
### 不在時のフォールバック

Phase 2 開始時に `.claude/project.yml` が存在しない場合:

1. 親が上記の雛形を `.claude/project.yml` に書き出す（`tracker.type` はユーザーに `linear` / `github` を選んでもらう）
2. `AskUserQuestion` で「この内容でコミットするか / 内容を修正するか / 一時的に使うだけか」を確認
3. ユーザーが内容を修正したい場合は、対話で値を確定してから書き直す
4. **コミットの実行はユーザー判断に従う**。親は勝手に `git add` / `git commit` しない
```

- [ ] **Step 3.4: フェーズ全体図の Phase 2 行（L75）を更新**

old_string:
```
Phase 2: イシュー化 (Read: .claude/feature-team.yml → Skill: create-issue)
```

new_string:
```
Phase 2: イシュー化 (Skill: create-issue → 内部で .claude/project.yml を読む)
```

- [ ] **Step 3.5: Phase 2 §2.1 設定ファイル読込ブロック（L135-143）を簡略化**

old_string:
````
### 2.1 設定ファイル読込

```
Read(.claude/feature-team.yml)
```

- 存在 + `issue_tracker.type` が `github` または `linear` → そのまま続行
- 不在 → 上の「設定ファイル不在時のフォールバック」を実行
- 不正値 → `AskUserQuestion` で正しい値に修正
````

new_string:
````
### 2.1 設定ファイル前提確認

`.claude/project.yml` の `tracker.type` を `create-issue` が参照するため、起動前に存在を確認する:

```
Read(.claude/project.yml)
```

- 存在 + `tracker.type` が `github` または `linear` → そのまま続行
- 不在 → 上の「設定ファイル不在時のフォールバック」を実行
- 不正値 → `AskUserQuestion` で正しい値に修正

`feature-team` 自身は `tracker.*` の値を使わない。確認後すぐ `create-issue` を起動する。
````

- [ ] **Step 3.6: §2.2 create-issue 起動ブロック（L145-153）を `<tracker>` 引数なしに更新**

old_string:
````
### 2.2 create-issue 起動

```
Skill(create-issue, args="<tracker> <spec-path> <plan-path>")
```

- `<tracker>`: `.claude/feature-team.yml` の `issue_tracker.type`
- `<spec-path>`: Phase 1.1 の brainstorming が書き出した spec の絶対パス（`docs/superpowers/specs/...md`）
- `<plan-path>`: Phase 1.2 の writing-plans が書き出した plan の絶対パス（`docs/superpowers/plans/...md`）
````

new_string:
````
### 2.2 create-issue 起動

```
Skill(create-issue, args="<spec-path> <plan-path>")
```

- `<spec-path>`: Phase 1.1 の brainstorming が書き出した spec の絶対パス（`docs/superpowers/specs/...md`）
- `<plan-path>`: Phase 1.2 の writing-plans が書き出した plan の絶対パス（`docs/superpowers/plans/...md`）

tracker は `create-issue` が `.claude/project.yml` から自己解決するため、`feature-team` は引数で渡さない。
````

- [ ] **Step 3.7: §2.2 末尾の linear-plan/github-plan 言及（L155）を削除**

old_string:
```
`create-issue` は spec / plan を読み、重複チェック → 構造化（plan のステップを sub-issue に変換）→ セルフレビュー → 登録までを自律実行する（既存 `linear-plan` / `github-plan` のような対話深掘りステップは持たない）。
```

new_string:
```
`create-issue` は spec / plan を読み、重複チェック → 構造化（plan のステップを sub-issue に変換）→ セルフレビュー → 登録までを自律実行する（対話深掘りステップは持たない）。
```

- [ ] **Step 3.8: Phase 4-B.3（L237）の `default_reviewers` 参照を新キー名に**

old_string:
```
実装完了後、Phase 5 の観点別レビューを少なくとも `quality` 観点で 1 回は回す（`.claude/feature-team.yml` の `default_reviewers` に従う）。
```

new_string:
```
実装完了後、Phase 5 の観点別レビューを少なくとも `quality` 観点で 1 回は回す（`.claude/project.yml` の `review.default_reviewers` に従う）。
```

- [ ] **Step 3.9: §5.4（L287）の `review_round_limit` 参照を新キー名に**

old_string:
```
レビュー往復は `.claude/feature-team.yml` の `review_round_limit`（既定 3）を上限とする。
```

new_string:
```
レビュー往復は `.claude/project.yml` の `review.round_limit`（既定 3）を上限とする。
```

- [ ] **Step 3.10: エスカレーション（L362）のパス更新**

old_string:
```
2. 設定ファイル `.claude/feature-team.yml` の値が不正で自動修復できない
```

new_string:
```
2. 設定ファイル `.claude/project.yml` の値が不正で自動修復できない
```

- [ ] **Step 3.11: grep 検証**

```bash
cd /Users/goto/.dotfiles
grep -nE 'linear-plan|github-plan|feature-team\.yml|issue_tracker\.|<tracker>|review_round_limit' claude/skills/feature-team/SKILL.md
```

期待: 何もマッチしない（exit code 1）。`default_reviewers` 単独は `review.default_reviewers` の一部なのでマッチしてよい。

```bash
grep -nE '\.claude/project\.yml' claude/skills/feature-team/SKILL.md | wc -l
```

期待: 4 以上（複数箇所で参照）。

- [ ] **Step 3.12: commit**

```bash
cd /Users/goto/.dotfiles
git add claude/skills/feature-team/SKILL.md
git commit -m "$(cat <<'EOF'
refactor(feature-team): SKILL.md を .claude/project.yml ベースに更新

設定ファイルパス・キー名を新スキーマに合わせて変更。Phase 2 では feature-team が tracker を読まず create-issue に丸投げする責務分離に修正。
EOF
)"
```

---

## Task 4: `feature-team/README.md` 改修

**Files:**
- Modify: `/Users/goto/.dotfiles/claude/skills/feature-team/README.md`

- [ ] **Step 4.1: L23 設定ファイルパス**

old_string:
```
- **設定は `.claude/feature-team.yml`**（リポジトリ単位）
```

new_string:
```
- **設定は `.claude/project.yml`**（リポジトリ単位）
```

- [ ] **Step 4.2: L33 USER 説明**

old_string:
```
│  - Phase 2 で Linear/GitHub どちらか口頭指定（または .claude/feature-team.yml）│
```

new_string:
```
│  - Phase 2 で Linear/GitHub どちらか口頭指定（または .claude/project.yml）   │
```

注: 罫線の文字数調整に注意（修正前後でセル幅を一致させるため、空白パディングで揃える）。

- [ ] **Step 4.3: L113-117 Phase 2 図ブロックを書き換え**

old_string:
````
│ Phase 2: イシュー化                                                      │
│  PARENT → Read(.claude/feature-team.yml) で tracker 取得                 │
│         → Skill(create-issue,                                            │
│             args="<tracker> <spec-path> <plan-path>")                   │
│  成果物: 親 issue + sub-issues (n 個)                                    │
````

new_string:
````
│ Phase 2: イシュー化                                                      │
│  PARENT → Skill(create-issue,                                            │
│             args="<spec-path> <plan-path>")                              │
│         （create-issue が .claude/project.yml の tracker を自己解決）    │
│  成果物: 親 issue + sub-issues (n 個)                                    │
````

注: 罫線揃えに注意。

- [ ] **Step 4.4: L256 表 E パス更新**

old_string:
```
| E | レビュー往復上限 | 3 ラウンド（`.claude/feature-team.yml` で上書き可）|
```

new_string:
```
| E | レビュー往復上限 | 3 ラウンド（`.claude/project.yml` の `review.round_limit` で上書き可）|
```

- [ ] **Step 4.5: L261 表 J を新スキーマで書き換え**

old_string:
```
| J | Phase 2 の tracker 選択 | `.claude/feature-team.yml` の `issue_tracker.type` を参照。不在時は雛形書出 + ユーザー判断でコミット |
```

new_string:
```
| J | Phase 2 の tracker 選択 | `create-issue` が `.claude/project.yml` の `tracker.type` を直接参照。`feature-team` は読まない。不在時は親が雛形書出 + ユーザー判断でコミット |
```

- [ ] **Step 4.6: L264 表 M の引数仕様更新**

old_string:
```
| M | Phase 2 のイシュー化スキル | `create-issue`（引数 `<tracker> <spec-path> <plan-path>`） |
```

new_string:
```
| M | Phase 2 のイシュー化スキル | `create-issue`（引数 `<spec-path> <plan-path>`、tracker は config 自己解決） |
```

- [ ] **Step 4.7: L265 表 N（linear-plan/github-plan 行）を削除**

old_string:
```
| N | 既存 `linear-plan` / `github-plan` | 対話起点の単発用途として温存・無改修 |
```

new_string:
```
```

注: 行を完全に削除する（空白行ではなく行ごと消す）。

確認のため、削除後 `grep -nE '^\| [N-Z] \|' claude/skills/feature-team/README.md` で N 行が消え、O 行が残っていることを確認する。

- [ ] **Step 4.8: L297-301 「なぜ create-issue は引数で linear/github を切替えるのか」セクション全体を書き換え**

old_string:
```
### なぜ create-issue は引数で linear/github を切替えるのか

- 共通フェーズ（重複チェック・構造化・セルフレビュー）を一元化できる
- 既存 `linear-plan` / `github-plan` を改修せず温存しているので、対話起点の単発用途と棲み分け可能
- 内部で tracker 別に分岐するため、フェーズ単位の差異（GitHub Project / Linear Sub-issue）は明示的に扱える
```

new_string:
```
### なぜ create-issue は config から tracker を自己解決するのか

- 共通フェーズ（重複チェック・構造化・セルフレビュー）を一元化しつつ、tracker 設定はリポジトリ単位で固定するのが自然
- `feature-team` 親が tracker 設定を読む必要がなくなり、責務分離が明確になる
- 内部で tracker 別に分岐するため、フェーズ単位の差異（GitHub Project / Linear Sub-issue）は明示的に扱える
```

- [ ] **Step 4.9: L335 「しきい値変更」セクションのパス更新**

old_string:
```
`.claude/feature-team.yml` の `volume_thresholds` で**リポジトリ単位で上書き**するのが第一選択。`parent.md` の既定値は最後の砦として残しておく。
```

new_string:
```
`.claude/project.yml` の `volume_thresholds` で**リポジトリ単位で上書き**するのが第一選択。`parent.md` の既定値は最後の砦として残しておく。
```

- [ ] **Step 4.10: grep 検証**

```bash
cd /Users/goto/.dotfiles
grep -nE 'linear-plan|github-plan|feature-team\.yml|issue_tracker\.|<tracker>|review_round_limit' claude/skills/feature-team/README.md
```

期待: 何もマッチしない。

- [ ] **Step 4.11: commit**

```bash
cd /Users/goto/.dotfiles
git add claude/skills/feature-team/README.md
git commit -m "$(cat <<'EOF'
docs(feature-team): README を .claude/project.yml ベースに更新

設定ファイルパス・引数仕様・棲み分け説明を新設計に合わせて更新。linear-plan / github-plan 行を削除。
EOF
)"
```

---

## Task 5: `feature-team/roles/{_common,parent}.md` 改修

**Files:**
- Modify: `/Users/goto/.dotfiles/claude/skills/feature-team/roles/_common.md`
- Modify: `/Users/goto/.dotfiles/claude/skills/feature-team/roles/parent.md`

- [ ] **Step 5.1: `_common.md` L177 review_round_limit 参照更新**

old_string:
```
- **レビュー往復は最大 3 ラウンド**まで（親側の `.claude/feature-team.yml` で上書きされている場合あり）
```

new_string:
```
- **レビュー往復は最大 3 ラウンド**まで（親側の `.claude/project.yml` の `review.round_limit` で上書きされている場合あり）
```

- [ ] **Step 5.2: `parent.md` L20 volume_thresholds 参照更新**

old_string:
```
これらは `.claude/feature-team.yml` の `volume_thresholds` で上書きされている場合があるので、設定ファイル値を優先する。
```

new_string:
```
これらは `.claude/project.yml` の `volume_thresholds` で上書きされている場合があるので、設定ファイル値を優先する。
```

- [ ] **Step 5.3: `parent.md` L87 default_reviewers 参照を新キー名に**

old_string:
```
`.claude/feature-team.yml` の `default_reviewers` を起点に、各 sub-issue / branch ごとに以下を加味して観点を決める:
```

new_string:
```
`.claude/project.yml` の `review.default_reviewers` を起点に、各 sub-issue / branch ごとに以下を加味して観点を決める:
```

- [ ] **Step 5.4: `parent.md` L211 設定ファイル commit 注意のパス更新**

old_string:
```
- 設定ファイル `.claude/feature-team.yml` を勝手に commit する（書き出しまで、コミットはユーザー判断）
```

new_string:
```
- 設定ファイル `.claude/project.yml` を勝手に commit する（書き出しまで、コミットはユーザー判断）
```

- [ ] **Step 5.5: `parent.md` L213 review_round_limit 参照を新キー名に**

old_string:
```
- ラウンド上限を勝手に伸ばす（ユーザー承認なしで `review_round_limit` を上書きしない）
```

new_string:
```
- ラウンド上限を勝手に伸ばす（ユーザー承認なしで `review.round_limit` を上書きしない）
```

- [ ] **Step 5.6: grep 検証**

```bash
cd /Users/goto/.dotfiles
grep -nE 'linear-plan|github-plan|feature-team\.yml|issue_tracker\.|review_round_limit' claude/skills/feature-team/roles/_common.md claude/skills/feature-team/roles/parent.md
```

期待: 何もマッチしない（`default_reviewers` 単独は `review.default_reviewers` 内の一部なのでマッチしてよい）。

```bash
grep -nE '\.claude/project\.yml' claude/skills/feature-team/roles/_common.md claude/skills/feature-team/roles/parent.md | wc -l
```

期待: 4 以上。

- [ ] **Step 5.7: commit**

```bash
cd /Users/goto/.dotfiles
git add claude/skills/feature-team/roles/_common.md claude/skills/feature-team/roles/parent.md
git commit -m "$(cat <<'EOF'
refactor(feature-team): roles/*.md を .claude/project.yml ベースに更新

review_round_limit → review.round_limit、default_reviewers → review.default_reviewers のキー名変更を反映。
EOF
)"
```

---

## Task 6: トップレベル `CLAUDE.md` 改修

**Files:**
- Modify: `/Users/goto/.dotfiles/CLAUDE.md`

- [ ] **Step 6.1: create-issue 説明（L53）を更新**

old_string:
```
- `claude/skills/create-issue/` は spec/plan を入力に Linear / GitHub の親 Issue + sub-issue を自律登録するスキル。引数 `<tracker> <spec-path> <plan-path>` で tracker を切替。`feature-team` Phase 2 から呼ばれる前提で、対話起点の `linear-plan` / `github-plan` とは棲み分け
```

new_string:
```
- `claude/skills/create-issue/` は spec/plan を入力に Linear / GitHub の親 Issue + sub-issue を自律登録するスキル。引数 `<spec-path> <plan-path>` で受け取り、tracker は `.claude/project.yml` の `tracker.type` から自己解決する。`feature-team` Phase 2 から呼ばれる前提
```

- [ ] **Step 6.2: grep 検証**

```bash
cd /Users/goto/.dotfiles
grep -nE 'linear-plan|github-plan|feature-team\.yml' CLAUDE.md
```

期待: 何もマッチしない。

- [ ] **Step 6.3: commit**

```bash
cd /Users/goto/.dotfiles
git add CLAUDE.md
git commit -m "$(cat <<'EOF'
docs(claude): create-issue 説明を新引数仕様に更新

linear-plan / github-plan 言及を削除し、tracker 自己解決の挙動を明記。
EOF
)"
```

---

## Task 7: `linear-plan` / `github-plan` ディレクトリ削除 + symlink cleanup

**Files:**
- Delete: `/Users/goto/.dotfiles/claude/skills/linear-plan/` (ディレクトリごと)
- Delete: `/Users/goto/.dotfiles/claude/skills/github-plan/` (ディレクトリごと)
- Delete: `/Users/goto/.claude/skills/linear-plan/` (symlink 残骸の親ディレクトリ)
- Delete: `/Users/goto/.claude/skills/github-plan/` (symlink 残骸の親ディレクトリ)

- [ ] **Step 7.1: 削除前の状態を確認**

```bash
ls -la /Users/goto/.dotfiles/claude/skills/linear-plan/ /Users/goto/.dotfiles/claude/skills/github-plan/
ls -la /Users/goto/.claude/skills/linear-plan/ /Users/goto/.claude/skills/github-plan/
```

期待: それぞれ `SKILL.md` が存在し、`~/.claude/skills/{linear-plan,github-plan}/SKILL.md` は dotfiles 配下への symlink になっている。

- [ ] **Step 7.2: dotfiles 側のソースディレクトリを git で削除**

```bash
cd /Users/goto/.dotfiles
git rm -r claude/skills/linear-plan claude/skills/github-plan
```

期待: `claude/skills/linear-plan/SKILL.md` と `claude/skills/github-plan/SKILL.md` がステージングされ、ローカルからも削除される。

- [ ] **Step 7.3: ホーム側 symlink 残骸を削除**

```bash
# symlink された SKILL.md を削除し、空の親ディレクトリを rmdir
rm -f /Users/goto/.claude/skills/linear-plan/SKILL.md /Users/goto/.claude/skills/github-plan/SKILL.md
rmdir /Users/goto/.claude/skills/linear-plan /Users/goto/.claude/skills/github-plan
```

期待: 両ディレクトリが完全に消える。`rmdir` が失敗する場合は中身を確認してから手動で対処（ユーザー判断）。

- [ ] **Step 7.4: 削除後の状態を確認**

```bash
ls -la /Users/goto/.dotfiles/claude/skills/ | grep -E 'linear-plan|github-plan'
ls -la /Users/goto/.claude/skills/ | grep -E 'linear-plan|github-plan'
```

期待: いずれも何も出力されない（exit code 1 でも可）。

- [ ] **Step 7.5: commit**

```bash
cd /Users/goto/.dotfiles
git status --short
git commit -m "$(cat <<'EOF'
chore(skills): linear-plan / github-plan スキルを削除

create-issue + superpowers:brainstorming + superpowers:writing-plans のチェーンで役割が完全に置き換わったため廃止。
EOF
)"
```

期待: 2 つの SKILL.md 削除のみが含まれる commit になる。

---

## Task 8: auto memory `project_feature_team_skill.md` 更新

**Files:**
- Modify: `/Users/goto/.claude/projects/-Users-goto--dotfiles/memory/project_feature_team_skill.md`

注意: このファイルは dotfiles リポジトリ管理外（auto memory）のため、git 管理されない。`Edit` ツールで直接編集する。

- [ ] **Step 8.1: L15 の linear-plan/github-plan 言及を削除し、project.yml への参照を追加**

old_string:
```
- 既存 `linear-plan` / `github-plan` は無改修で温存。design-doc 駆動の自動化用途は `create-issue`（引数 `<tracker> <spec-path> <plan-path>`）が担う
```

new_string:
```
- design-doc 駆動の自動化は `create-issue`（引数 `<spec-path> <plan-path>`）が担い、tracker は `.claude/project.yml` の `tracker.type` から自己解決する
```

- [ ] **Step 8.2: grep 検証**

```bash
grep -nE 'linear-plan|github-plan' /Users/goto/.claude/projects/-Users-goto--dotfiles/memory/project_feature_team_skill.md
```

期待: 何もマッチしない。

注: auto memory はリポジトリ管理外なので commit 不要。

---

## Task 9: 最終検証（受入条件チェック）

- [ ] **Step 9.1: スキルディレクトリの不在を確認**

```bash
test ! -d /Users/goto/.dotfiles/claude/skills/linear-plan && echo "OK: dotfiles linear-plan absent" || echo "NG"
test ! -d /Users/goto/.dotfiles/claude/skills/github-plan && echo "OK: dotfiles github-plan absent" || echo "NG"
test ! -e /Users/goto/.claude/skills/linear-plan && echo "OK: home linear-plan absent" || echo "NG"
test ! -e /Users/goto/.claude/skills/github-plan && echo "OK: home github-plan absent" || echo "NG"
```

期待: 4 つすべて `OK`。

- [ ] **Step 9.2: 設定ファイル状態を確認**

```bash
test ! -f /Users/goto/.dotfiles/.claude/feature-team.yml && echo "OK: feature-team.yml absent" || echo "NG"
test -f /Users/goto/.dotfiles/.claude/project.yml && echo "OK: project.yml present" || echo "NG"
```

期待: 2 つとも `OK`。

- [ ] **Step 9.3: project.yml のスキーマ確認**

```bash
cat /Users/goto/.dotfiles/.claude/project.yml | grep -E '^(tracker|review|volume_thresholds):'
```

期待出力（順序は問わない）:
```
tracker:
review:
volume_thresholds:
```

- [ ] **Step 9.4: 旧キー名・旧ファイル名の網羅 grep**

```bash
cd /Users/goto/.dotfiles
git grep -nE 'linear-plan|github-plan|feature-team\.yml|issue_tracker\.|review_round_limit' \
  -- ':(exclude)docs/superpowers/specs/2026-04-08-linear-github-workflow-design.md' \
     ':(exclude)docs/superpowers/plans/2026-04-08-linear-github-workflow.md' \
     ':(exclude)docs/superpowers/specs/2026-05-01-deprecate-linear-github-plan-design.md' \
     ':(exclude)docs/superpowers/plans/2026-05-01-deprecate-linear-github-plan.md'
```

期待: 何もマッチしない（exit code 1）。

- [ ] **Step 9.5: create-issue argument-hint 確認**

```bash
grep -E '^argument-hint:' /Users/goto/.dotfiles/claude/skills/create-issue/SKILL.md
```

期待出力:
```
argument-hint: <spec-path> <plan-path>
```

- [ ] **Step 9.6: feature-team Phase 2 が tracker を引数渡ししていないことを確認**

```bash
grep -nE 'create-issue.*<tracker>' /Users/goto/.dotfiles/claude/skills/feature-team/SKILL.md /Users/goto/.dotfiles/claude/skills/feature-team/README.md
```

期待: 何もマッチしない。

- [ ] **Step 9.7: auto memory の確認**

```bash
grep -nE 'linear-plan|github-plan' /Users/goto/.claude/projects/-Users-goto--dotfiles/memory/project_feature_team_skill.md
```

期待: 何もマッチしない。

- [ ] **Step 9.8: setup.zsh 再実行で残骸が再生成されないことを確認**

```bash
cd /Users/goto/.dotfiles
zsh setup/setup.zsh 2>&1 | grep -iE 'linear-plan|github-plan|error'
ls -la /Users/goto/.claude/skills/ | grep -E 'linear-plan|github-plan'
```

期待: setup.zsh の出力に `linear-plan` / `github-plan` が出ず、`~/.claude/skills/` にも該当ディレクトリがない。

- [ ] **Step 9.9: feature-team / create-issue の動作確認（実機検証）**

実コマンドでスキル起動を試して、エラーなく config 読み取りまで進むか確認:

```bash
# Skill ツールで /create-issue を呼び出す（実 Issue 作成は不要、引数検証段階で停止すればよい）
# 例: 存在しないファイルを渡してエラーで停止することを確認
/create-issue /nonexistent/spec.md /nonexistent/plan.md
```

期待: `spec not found: /nonexistent/spec.md` などのエラーで停止し、config 読み取りロジック自体は動いている形跡がある。

注: この検証は手動で実行する。失敗した場合、create-issue SKILL.md の §1 引数検証ロジックを再点検。

- [ ] **Step 9.10: コミットログ確認**

```bash
cd /Users/goto/.dotfiles
git log --oneline -10
```

期待: 直近 7 commits（Task 1〜7）が独立してログに残っており、squash されていないこと。
