---
name: feature-team
description: Use when developing a feature that benefits from multi-agent team orchestration (parallel implementation across multiple sub-issues, multi-perspective code review). Use when a feature is too large for a single developer thread, when sub-issues are independent enough to parallelize, or when explicit security/performance/quality review separation is wanted.
argument-hint: <feature-idea>
allowed-tools:
  - Skill
  - Agent
  - Bash
  - Read
  - Write
  - AskUserQuestion
---

# Feature Team

複数のサブエージェント（developer / reviewer）をオーケストレーションして、要件出しから PR 作成までを一気通貫で進める親スキル。

このスキルを読み込んだメイン Claude セッション自身が**親（オーケストレーター）**として振る舞う。サブエージェント化はしない。

設計判断の根拠と全体像は `README.md` を参照。子エージェントへ注入する共通プロトコルは `roles/_common.md`、親の判断基準は `roles/parent.md` を参照。

## 前提

- `worktrunk`（`wt`）がインストール済みであること（`Brewfile` 既登録）
- `gh` CLI が認証済みであること
- Linear を使う場合は `linear` CLI が認証済みであること（`linear auth login`）
- `superpowers@claude-plugins-official` プラグインが有効であること（Phase 1 で `superpowers:brainstorming` を呼ぶ）
- 対象リポジトリのワーキングディレクトリにいること

## 設定ファイル: `.claude/feature-team.yml`

リポジトリごとの挙動は `.claude/feature-team.yml` で制御する。

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

### 不在時のフォールバック

Phase 2 開始時にこのファイルが存在しない場合:

1. 親が上記の雛形を `.claude/feature-team.yml` に書き出す
2. `AskUserQuestion` で「この内容でコミットするか / 内容を修正するか / 一時的に使うだけか」を確認
3. ユーザーが内容を修正したい場合は、対話で値を確定してから書き直す
4. **コミットの実行はユーザー判断に従う**。親は勝手に `git add` / `git commit` しない

## フェーズ全体図

```
Phase 1: 要件確定 (Skill: superpowers:brainstorming)
   │
   ▼
Phase 2: イシュー化 (Read: .claude/feature-team.yml → Skill: create-issue)
   │
   ▼
Phase 3: ボリューム判断 (parent.md のしきい値)
   │
   ├─ 大規模 → Phase 4-A: 並列開発（n 個の sub-issue を並列起動）
   │              │
   │              ▼
   │           Phase 5: 観点別レビュー（developer 完了ごとにストリーミング起動）
   │              │
   │              ▼
   │           Phase 6: n 個の独立 PR
   │
   └─ 小規模 → Phase 4-B: 親が直接実装（worktree 1 つ）
                  │
                  ▼
               Phase 5: 観点別レビュー（最低 quality 観点）
                  │
                  ▼
               Phase 6: 1 個の PR
```

## Phase 1: 要件確定（Brainstorming）

### 1.1 Skill 起動

```
Skill(superpowers:brainstorming)
```

ユーザーのアイデアを Socratic 対話で深掘りし、design doc を生成する。

### 1.2 Design doc の永続化

brainstorming スキルが生成した design doc を Phase 2 で `create-issue` に渡せるよう、一時ファイルに書き出す:

```bash
# 例
mkdir -p .claude/tmp
DESIGN_DOC=".claude/tmp/feature-team-design-$(date +%Y%m%d-%H%M%S).md"
# brainstorming の出力を $DESIGN_DOC に Write
```

`.claude/tmp/` は `.gitignore` 側で除外する想定（プロジェクトの `.gitignore` を確認し、なければ追加を提案）。

### 1.3 ユーザー承認

design doc の内容を提示し、Phase 2 に進んでよいかユーザーに確認する。修正が必要な場合は brainstorming に戻る。

## Phase 2: イシュー化

### 2.1 設定ファイル読込

```
Read(.claude/feature-team.yml)
```

- 存在 + `issue_tracker.type` が `github` または `linear` → そのまま続行
- 不在 → 上の「設定ファイル不在時のフォールバック」を実行
- 不正値 → `AskUserQuestion` で正しい値に修正

### 2.2 create-issue 起動

```
Skill(create-issue, args="<tracker> <design-doc-path>")
```

- `<tracker>`: `.claude/feature-team.yml` の `issue_tracker.type`
- `<design-doc-path>`: Phase 1.2 で書き出した design doc の絶対パス

`create-issue` は重複チェック → 構造化 → セルフレビュー → 登録までを自律実行する（既存 `linear-plan` / `github-plan` のような対話深掘りステップは持たない）。

### 2.3 出力の取り込み

`create-issue` は親 Issue 番号と sub-issue 番号のリストを返す。これを Phase 3 以降の入力として保持する。

## Phase 3: ボリューム判断

`roles/parent.md` の「ボリューム判断しきい値」セクションに従い、以下を決定する:

- **大規模（→ Phase 4-A 並列開発）**: sub-issue が独立して並列実装可能な場合
- **小規模（→ Phase 4-B 親直実装）**: sub-issue が 1 つのみ、または変更範囲が小さく親が直接書く方が早い場合

しきい値は `volume_thresholds` で上書き可能。デフォルト値と判定基準は `parent.md` 参照。

判定結果と理由をユーザーに提示し、必要なら手動で上書きを受け付ける。

## Phase 4-A: 並列開発（大規模）

### 4-A.1 sub-issue ごとに worktree を作成

```bash
# 各 sub-issue について順次実行
wt switch -c <branch>
# wt list で worktree パスを取得して記録
wt list
```

ブランチ命名規則: `feature/<slug>-issue-<sub-issue-番号>`（既存 `issue-dev` スキルと同じ）

> **注意:** Bash ツール経由では `wt switch -c` のシェル統合（自動 `cd`）が効かない場合がある。`wt list` の出力から worktree 絶対パスを取得し、以降の Bash コマンドはそのパス内で実行するよう Agent に明示する。

### 4-A.2 各 sub-issue の developer を選定

`roles/parent.md` の「developer 選定基準」を参照。10 種の特化版（react/nextjs/flutter/go/nodejs/hono/nestjs/rust/ruby）から該当するものを選び、該当なしなら `developer-generic` にフォールバックする。

### 4-A.3 Agent を並列起動

各 sub-issue について `run_in_background: true` で起動する。

```
Agent(
  subagent_type="developer-<lang>",
  description="<sub-issue タイトルの短縮>",
  prompt="<下記テンプレート>",
  run_in_background=true,
)
```

#### Agent プロンプトに必ず含める項目

1. `roles/_common.md` の内容を完全注入（worktrunk 運用、報告フォーマット、レビュー往復ルール、Conventional Commits、セルフレビュー必須）
2. リポジトリ情報（OWNER, REPO, DEFAULT_BRANCH）
3. Sub-issue 番号と本文（`gh issue view` または `linear issue view` で取得済みの内容）
4. **worktree の絶対パス**（このディレクトリ内で作業すること、と明示）
5. ブランチ名
6. 完了条件: 「sub-issue の受入条件をすべて満たし、テストを通し、コミットして push する。PR は作らず、親に完了通知のみ返す」

### 4-A.4 親は通常作業を続ける

`run_in_background: true` のため待たない。親は次の sub-issue の起動・既存 sub-issue 完了通知の確認を継続する。

### 4-A.5 完了通知のストリーミング処理

developer から完了通知が返ったら、即座に Phase 5（観点別レビュー）の対応する reviewer を起動する。全 developer の完了を待たない。

## Phase 4-B: 親直接実装（小規模）

### 4-B.1 worktree を 1 つ作成

```bash
wt switch -c <branch>
```

ブランチ命名規則: `feature/<slug>-issue-<親 issue 番号>`

### 4-B.2 親が直接実装

メイン Claude が `Edit` / `Write` / `Bash` ツールで直接コーディングする。worktrunk の `wt` コマンドを使った worktree 内で作業する。

### 4-B.3 Phase 5 へ

実装完了後、Phase 5 の観点別レビューを少なくとも `quality` 観点で 1 回は回す（`.claude/feature-team.yml` の `default_reviewers` に従う）。

## Phase 5: 観点別レビュー

### 5.1 観点選定

`roles/parent.md` の「観点別 reviewer 選定基準」に従い、対象 sub-issue / branch ごとに必要な観点を決定する:

- `security`: 認証・認可・入力バリデーション・秘密情報の扱い・SQL/コマンドインジェクションリスクが含まれる場合
- `performance`: ホットパス・大量データ処理・DB クエリ・N+1 リスクが含まれる場合
- `quality`: 上記以外も含めて全タスク必須（既定）

### 5.2 reviewer を並列起動

選定した観点の reviewer を `run_in_background: true` で起動する。

```
Agent(
  subagent_type="reviewer-<perspective>",
  description="<対象 branch>: <perspective> review",
  prompt="<下記テンプレート>",
  run_in_background=true,
)
```

#### Agent プロンプトに必ず含める項目

1. `roles/_common.md` の内容を完全注入
2. 対象 worktree の絶対パスとブランチ名
3. レビュー対象範囲（全コミット差分 / 特定ファイル群）
4. 観点（security / performance / quality）
5. 報告フォーマット: 重要度別（critical / major / minor）の指摘リスト + 修正不要箇所の明示

### 5.3 指摘の集約と修正依頼

reviewer 完了後、親が指摘を統合する。**子の出力をそのまま developer へ転送しない**。親が読んで critical / major のみを抽出し、矛盾する指摘は親が判断する。

その上で対応する developer に修正依頼を出す:

```
Agent(
  subagent_type="developer-<lang>",
  description="<sub-issue>: review feedback round <N>",
  prompt="<critical/major 指摘の整理 + 期待する修正方針>",
  run_in_background=true,
)
```

### 5.4 ラウンド上限

レビュー往復は `.claude/feature-team.yml` の `review_round_limit`（既定 3）を上限とする。

- 1 ラウンド目で完了 → そのまま Phase 6 へ
- 2 ラウンド目で完了 → そのまま Phase 6 へ
- 3 ラウンド目でも収束しない → **親が介入**:
  1. 親自身が差分を読み、根本原因を特定する
  2. 設計レベルの問題と判定したら `AskUserQuestion` でユーザーに escalate（選択肢: 設計やり直し / このまま PR / 中断）
  3. 実装ミスと判定したら親が直接修正する（developer をもう一周回さない）

## Phase 6: PR 作成

### 6.1 PR 単位の決定

- Phase 4-A 経由 → **n 個の独立 PR**（各 sub-issue worktree から 1 PR）
- Phase 4-B 経由 → **1 個の PR**

### 6.2 PR 作成

各 worktree で以下を実行する:

```
Skill(commit-commands:commit-push-pr)
```

PR 本文には以下を含める:
- `Resolves #<sub-issue 番号>`（Phase 4-A）または `Resolves #<親 issue 番号>`（Phase 4-B）
- レビュー結果サマリー（観点別、何ラウンドで収束したか）

### 6.3 CodeRabbit 対応

```
Skill(coderabbit-review)
```

CodeRabbit のインラインコメントへの対応を行う。

### 6.4 完了報告

```
## ✅ Feature Team 完了

**親 Issue:** #<番号>
**PR:**
- #<PR 番号> (sub-issue #<番号>): <タイトル>  | レビュー: ✅ security ✅ quality (R2)
- #<PR 番号> (sub-issue #<番号>): <タイトル>  | レビュー: ✅ quality (R1)
- ...

**Phase 5 サマリー:**
- 全 N サブタスク中、X が R1 で収束、Y が R2 で収束、Z が親介入
- escalate 件数: 0 件
```

## エスカレーション

以下のケースでは即座に `AskUserQuestion` でユーザーに判断を仰ぐ:

1. Phase 5 ラウンド上限超過かつ親介入でも収束しない
2. 設定ファイル `.claude/feature-team.yml` の値が不正で自動修復できない
3. worktrunk / gh / linear CLI のエラーが繰り返し発生する
4. sub-issue の受入条件が互いに矛盾している、または達成不能と判定された
5. ボリューム判断（Phase 3）が困難で、自動判定の信頼度が低い

エスカレーション時は、親が現状サマリーと選択肢（候補 2-3 個）を提示する。

## ハンドオフ

長時間ジョブのため、各 Phase 完了時には `Skill(handover)` で状態を保存することを推奨する（特に Phase 4 の並列開発中はコンテキスト圧縮警告が出やすい）。
