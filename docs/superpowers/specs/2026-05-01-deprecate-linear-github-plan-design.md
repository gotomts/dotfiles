---
title: linear-plan / github-plan 廃止 + project.yml 設定統合設計
date: 2026-05-01
status: draft
---

# linear-plan / github-plan 廃止 + project.yml 設定統合設計

## 1. 目的

以下 3 件を 1 つの設計として統合する:

1. `linear-plan` / `github-plan` の 2 スキルを廃止する
2. `.claude/feature-team.yml` を `.claude/project.yml` に置き換え、tracker 設定を集約する
3. `create-issue` の責務を整理する（引数 `<tracker>` を廃止し、自身が `.claude/project.yml` を読む）

## 2. 背景

### 2.1 linear-plan / github-plan の重複

`create-issue`（spec / plan 入力で Linear / GitHub の親 + sub-issue を自律登録）と `superpowers:brainstorming` / `superpowers:writing-plans` のチェーンで、`linear-plan` / `github-plan` の役割は完全に置き換え可能。`feature-team` も Phase 1-2 で同じチェーンを内包している。

### 2.2 設定ファイルの責務違反

現状 `.claude/feature-team.yml` は 6 項目を抱え、用途が混在している:

| 設定項目 | 使用元スキル |
|---|---|
| `issue_tracker.type` | feature-team Phase 2 経由で create-issue に渡す |
| `issue_tracker.team` | create-issue（Linear 複数チーム時の選択）|
| `default_reviewers` | feature-team（Phase 5）|
| `review_round_limit` | feature-team（Phase 5）|
| `volume_thresholds` | feature-team（Phase 3）|

create-issue は単独でも使えるスキルなのに、feature-team の名前を冠した設定に依存している。

### 2.3 引数仕様の歪み

create-issue の `<tracker>` 引数は、feature-team から呼ばれる場合は `.claude/feature-team.yml` から読まれた値を渡される。create-issue は config を直接読む手段を持たないので、単独実行時はユーザーが手動で tracker を指定する必要がある（DRY 違反）。

## 3. スコープ

### 3.1 削除

- `claude/skills/linear-plan/` ディレクトリ（`SKILL.md` 含む）
- `claude/skills/github-plan/` ディレクトリ（`SKILL.md` 含む）

### 3.2 物理ファイルマイグレーション

- `.claude/feature-team.yml` を削除し、`.claude/project.yml` を新規作成（既存値を新スキーマで移行）
- 同一 commit で完結させ、中間状態（両方が存在する状態）を残さない

### 3.3 削除後の標準経路

| ユースケース | 経路 |
|---|---|
| 思いつき → Issue（実装はまだ） | `superpowers:brainstorming` → `superpowers:writing-plans` → `/create-issue <spec> <plan>` |
| Issue → 実装・レビュー・PR まで一気通貫 | `/feature-team` |
| spec / plan が既にある状態で Issue だけ登録 | `/create-issue <spec> <plan>` |

`<tracker>` 引数は廃止。`.claude/project.yml` の `tracker.type` から create-issue が自己解決する。

## 4. `.claude/project.yml` のスキーマ

### 4.1 全体構造

```yaml
# .claude/project.yml — このプロジェクトに関する Claude スキル / ワークフロー設定

tracker:
  type: linear              # linear | github
  linear:
    team: KISSA
    project_id: bbe50233861e
  # github を使う場合は上記 linear セクションを削除し、以下をアンコメント:
  # github:
  #   project_number: 1

review:
  default_reviewers: [quality]
  round_limit: 3

volume_thresholds:
  small: { max_sub_issues: 1, max_files: 5, max_lines: 200 }
  large: { min_sub_issues: 2, min_files: 6, min_lines: 201 }
```

### 4.2 セクション規約

- `tracker.type` の値（`linear` / `github`）と一致するサブセクション（`tracker.linear` / `tracker.github`）のみ書く。他は記述しない（discriminator パターン）
- `review` / `volume_thresholds` は feature-team Phase 3 / 5 専用
- ファイル不在時の挙動は §6.4 に記述

### 4.3 セクションごとの読み手

| セクション | 読むスキル |
|---|---|
| `tracker.*` | **create-issue のみ** |
| `review.*` | feature-team |
| `volume_thresholds.*` | feature-team（roles/parent.md のしきい値計算）|

## 5. アーキテクチャ

### 5.1 標準パイプライン

```
[アイデア]
   |
   v
[superpowers:brainstorming]
   |  spec を docs/superpowers/specs/YYYY-MM-DD-*.md に書き出し
   v
[superpowers:writing-plans]
   |  plan を docs/superpowers/plans/YYYY-MM-DD-*.md に書き出し
   v
[/create-issue <spec> <plan>]
   |  .claude/project.yml の tracker.type を参照し、Linear or GitHub に自律登録
   v
[Issue 登録完了]
   |
   v (実装まで進める場合)
[/feature-team] が Phase 1-6 を回す（または手動で /issue-dev <番号>）
```

### 5.2 feature-team Phase 2 の責務分離

- 旧: `Read(.claude/feature-team.yml) → Skill(create-issue, args="<tracker> <spec> <plan>")`
- 新: `Skill(create-issue, args="<spec> <plan>")` （feature-team は tracker 設定を読まない）

create-issue が起動時に `.claude/project.yml` を `Read` し、`tracker.type` で動作分岐する。

### 5.3 create-issue 単独実行

- 引数: `/create-issue <spec> <plan>`
- 内部で `.claude/project.yml` を `Read`
- `tracker.type` 未定義 / ファイル不在 → エラー停止し、`.claude/project.yml` の必要性をユーザーに案内

## 6. 変更対象詳細

### 6.1 削除対象

- `claude/skills/linear-plan/` ディレクトリ（`SKILL.md` 含む）
- `claude/skills/github-plan/` ディレクトリ（`SKILL.md` 含む）

### 6.2 create-issue 改修（`claude/skills/create-issue/SKILL.md`）

| 変更箇所 | 内容 |
|---|---|
| frontmatter `argument-hint` | `<tracker> <spec-path> <plan-path>` → `<spec-path> <plan-path>` |
| frontmatter `description` | `linear-plan / github-plan とは棲み分け` 文言を削除 |
| §引数（L18-26 相当）| `<tracker>` を削除し、`.claude/project.yml` 必須に書き換え |
| §「このスキルがしないこと」L38 | `linear-plan / github-plan の役割` → `superpowers:brainstorming の役割` |
| §1 引数検証 | `tracker` 引数バリデーションを削除し、`.claude/project.yml` 存在 + `tracker.type` 検証に置換 |
| §3-Linear / §3-GitHub | チーム / Project 参照先を `.claude/feature-team.yml` → `.claude/project.yml` の `tracker.linear.team` / `tracker.github.project_number` に変更 |
| §3-Linear（spec/plan フロントマターへのフォールバック） | 廃止（config 必須化で揃える）|
| L284 「github-plan で確立されたパターン」括弧書き | 削除（パターン自体は残す）|
| L323-331 「既存スキルとの棲み分け」表 + 段落 | 全削除 |
| 完了報告のテンプレ | `<tracker>` 関連の表記を削除（`Tracker:` 行は config 由来であることを明示）|

### 6.3 feature-team 改修

#### 6.3.1 `claude/skills/feature-team/SKILL.md`

| 変更箇所 | 内容 |
|---|---|
| L29 セクション見出し | `## 設定ファイル: .claude/feature-team.yml` → `## 設定ファイル: .claude/project.yml` |
| L31 本文 | パス参照を `.claude/project.yml` に変更 |
| L33-55 スキーマ定義 | 新スキーマ（§4.1）に全面書き換え。ただし feature-team から見えるのは `review.*` / `volume_thresholds.*` のみで、`tracker.*` は「create-issue が読むセクション」と注記 |
| L57-64 不在時フォールバック | パス・スキーマを新形式に書き換え。雛形は §4.1 に準拠 |
| L75 図 | `Phase 2: イシュー化 (Read: .claude/feature-team.yml → Skill: create-issue)` → `Phase 2: イシュー化 (Skill: create-issue)` （feature-team が config を読まなくなる）|
| L138 `Read(.claude/feature-team.yml)` | 削除。Phase 2 の手順から「config を読む」ステップを除去 |
| L151 `<tracker>: .claude/feature-team.yml の issue_tracker.type` | 削除。引数定義から `<tracker>` 自体を除去し、`<spec-path>` / `<plan-path>` のみに |
| L237 `default_reviewers` | パス更新 + キー名 `review.default_reviewers` に変更 |
| L287 `review_round_limit` | パス更新 + キー名 `review.round_limit` に変更 |
| L362 escalation 条件 | `.claude/feature-team.yml` → `.claude/project.yml` |

#### 6.3.2 `claude/skills/feature-team/README.md`

| 変更箇所 | 内容 |
|---|---|
| L23 概要 | `.claude/feature-team.yml` → `.claude/project.yml` |
| L33 USER 説明 | `.claude/feature-team.yml` → `.claude/project.yml` |
| L114 Phase 2 図 | `Read(.claude/feature-team.yml) で tracker 取得 → Skill(create-issue, "<tracker> ...")` を `Skill(create-issue, "<spec-path> <plan-path>")` のみに簡略化 |
| L256 表 E | `review_round_limit` → `review.round_limit`、パス更新 |
| L261 表 J | `issue_tracker.type` 参照を「create-issue が `.claude/project.yml` の `tracker.type` を読む」に書き換え |
| L264-265 表 N | `既存 linear-plan / github-plan` 行を削除 |
| L300 bullet | `既存 linear-plan / github-plan を改修せず温存` を削除 |
| L335 「しきい値変更」| `.claude/feature-team.yml` → `.claude/project.yml`、キー名は `volume_thresholds` 維持 |

#### 6.3.3 `claude/skills/feature-team/roles/_common.md`

| 変更箇所 | 内容 |
|---|---|
| L177 review 往復 | `.claude/feature-team.yml で上書き` → `.claude/project.yml の review.round_limit で上書き` |

#### 6.3.4 `claude/skills/feature-team/roles/parent.md`

| 変更箇所 | 内容 |
|---|---|
| L20 volume_thresholds | パス更新 |
| L87 default_reviewers | パス・キー名更新（`review.default_reviewers`）|
| L211 設定ファイル commit | パス更新 |

### 6.4 物理ファイルマイグレーション

- `.claude/feature-team.yml` を削除
- `.claude/project.yml` を新規作成。既存値を新スキーマで移行:
  ```yaml
  tracker:
    type: linear
    linear:
      team: KISSA
      project_id: bbe50233861e

  review:
    default_reviewers:
      - quality
    round_limit: 3

  volume_thresholds:
    small: { max_sub_issues: 1, max_files: 5, max_lines: 200 }
    large: { min_sub_issues: 2, min_files: 6, min_lines: 201 }
  ```
- 削除と作成を 1 commit にまとめる

### 6.5 トップレベル `CLAUDE.md`

| 変更箇所 | 内容 |
|---|---|
| L53 create-issue 説明 | `対話起点の linear-plan / github-plan とは棲み分け` を削除し、引数仕様 `<tracker> <spec-path> <plan-path>` を `<spec-path> <plan-path>` に更新 |

※ `feature-team` 説明（L52）には `.claude/feature-team.yml` の直接言及はないため変更不要（grep 確認済み）

### 6.6 auto memory 更新

| ファイル | 内容 |
|---|---|
| `~/.claude/projects/-Users-goto--dotfiles/memory/project_feature_team_skill.md` (L15) | `既存 linear-plan / github-plan は無改修で温存` を削除し、必要なら `.claude/project.yml` の構造を追記 |

### 6.7 残すもの（履歴的ドキュメント）

- `docs/superpowers/specs/2026-04-08-linear-github-workflow-design.md`
- `docs/superpowers/plans/2026-04-08-linear-github-workflow.md`

→ 2026-04-08 時点の設計・実装記録として温存。当時のスナップショットを書き換えると履歴の整合性が崩れる。`depends-on` フロントマターは未宣言なので CLAUDE.md の「Document Dependency Check」にも抵触しない。

## 7. 検証観点

### 7.1 事前検証（spec 段階で確認済み）

- ✅ `aliases` / `functions/` / `claude/settings.json` / `claude/hooks/` に `linear-plan` / `github-plan` の参照なし（grep 確認済み）
- ✅ `.claude/feature-team.yml` は dotfiles リポジトリ内の単一ファイル（git 管理済み、`fb7529c`）
- ✅ feature-team の config 参照は 26 箇所（grep 確認済み）

### 7.2 実装後検証

- 削除対象ディレクトリ（`linear-plan/` / `github-plan/`）が存在しない
- `.claude/feature-team.yml` が存在せず、`.claude/project.yml` が存在し新スキーマに準拠している
- `~/.claude/skills/linear-plan` / `~/.claude/skills/github-plan` の symlink が存在しない
- `git grep -E 'linear-plan|github-plan'` の結果が、履歴 docs（`2026-04-08-linear-github-workflow-*.md`）と本 spec / 後続 plan のみ
- `git grep -E 'feature-team\.yml'` の結果が、履歴 docs と本 spec / 後続 plan のみ
- `git grep -E 'issue_tracker\.|default_reviewers|review_round_limit'`（旧キー名）の結果がゼロ（履歴 docs を除く）
- create-issue を `<spec> <plan>` の 2 引数で起動できる（実機検証）
- feature-team を Phase 2 まで進めて、create-issue が `.claude/project.yml` から tracker を自己解決できる（実機検証）

## 8. スコープ外（今回やらない）

- `feature-team` への "Issue 作成だけで停止" モード追加 — 廃止後は手動 3 段チェーンで対応可能。必要が出たら別 spec
- `create-issue` の機能追加（Linear project 自動付与の正式実装など、auto memory にある既知課題は別タスク。ただし本 spec の `tracker.linear.project_id` フィールドを用意したことで実装の前提は整う）
- `superpowers:brainstorming` / `superpowers:writing-plans` の改変 — 標準スキルなので触らない
- 旧形式設定ファイル（`.claude/feature-team.yml`）の互換読み込み — 単一リポジトリ対象なので不要

## 9. 受入条件

- [ ] `claude/skills/linear-plan/` / `claude/skills/github-plan/` ディレクトリが存在しない
- [ ] `~/.claude/skills/linear-plan` / `~/.claude/skills/github-plan` の symlink が存在しない
- [ ] `.claude/feature-team.yml` が存在しない
- [ ] `.claude/project.yml` が存在し、§4.1 のスキーマに準拠している
- [ ] `create-issue` の `argument-hint` が `<spec-path> <plan-path>`
- [ ] `create-issue` 単独実行で `.claude/project.yml` から tracker を解決できる
- [ ] `feature-team` Phase 2 が `<tracker>` を引数として渡さなくなっている
- [ ] `git grep -E 'linear-plan|github-plan|feature-team\.yml|issue_tracker\.|review_round_limit'` の結果が履歴 docs と本 spec / 後続 plan のみ
- [ ] auto memory `project_feature_team_skill.md` から `linear-plan` / `github-plan` への言及が消えていること
