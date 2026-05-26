---
name: feature-team
description: 実装専任のチーム展開スキル。実装対象 (issue 番号/ID または spec/plan パス) を引数で受け取り、developer 並列起動 → reviewer 観点別 → pr-publisher で PR まで自走する。要件定義 (brainstorming/grill-me/grill-with-docs) や issue 作成 (create-issue) は外部スキルの責務でこのスキルではやらない。
allowed-tools:
  - Skill
  - Agent
  - Bash
  - Read
  - Write
  - AskUserQuestion
---

# Feature Team

実装専任のオーケストレーター。**実装対象を引数で受け取り**、developer / reviewer / pr-publisher を展開して PR 作成まで一気通貫で進める。

このスキルを読み込んだメイン Claude セッション自身が**親 (オーケストレーター)** として振る舞う。サブエージェント化はしない。

設計判断の根拠と全体像は `README.md` を参照。子エージェントへ注入する共通プロトコルは `roles/_common.md`、親の判断基準は `roles/parent.md` を参照。

## このスキルがしないこと

- 要件定義 (`grill-me` / `superpowers:brainstorming` / `grill-with-docs` の責務)
- 実装計画作成 (`superpowers:writing-plans` の責務)
- Issue 作成 (`create-issue` の責務)
- 対象が曖昧なときの肩代わり (Phase 0 で交通整理して停止する)

これらは前段の独立スキルに任せる。`feature-team` は実装対象が明示的に渡された後の「実装〜PR」フェーズだけを担う。

## 前段スキルとの組み合わせ

```
要件詰め (任意選択)            計画化            issue 化           実装〜PR
─────────────────         ──────────────    ──────────────    ──────────────
brainstorming             writing-plans     create-issue      feature-team
grill-me                                                          ↑
grill-with-docs                                              <issue-番号|ID>
pick-next (一括)                                                  または
手動 (UI から登録)                                          --spec <path> [--plan <path>]
```

代表的な経路:

- `Skill(pick-next)` で既存 active issue 選定 or 新規テーマで `create-issue` 起動 → `/feature-team <番号>`
- `Skill(superpowers:brainstorming)` → `Skill(superpowers:writing-plans)` → `Skill(create-issue, args="<spec> <plan>")` → `/feature-team <番号>`
- `Skill(grill-me)` または `Skill(grill-with-docs)` で対話深掘り → ユーザーが spec/plan を書き出す → `Skill(create-issue, args="<spec> <plan>")` → `/feature-team <番号>`
- GitHub / Linear UI で issue を手動作成 → `/feature-team <番号>`
- spec/plan を手書きで用意 → `/feature-team --spec <path> [--plan <path>]` (issue 化を経由せず直接実装)

## 前提

- `worktrunk` (`wt`) がインストール済みであること
- `gh` CLI が認証済みであること
- Linear を使う場合は `linear` CLI が認証済みであること (`linear auth login`)
- 対象リポジトリのワーキングディレクトリにいること

## 設定ファイル: `.claude/project.yml`

`feature-team` が読むセクションは `review.*` と `volume_thresholds.*` のみ。

### スキーマ

```yaml
review:
  default_reviewers:
    - quality
    # - security
    # - performance
  round_limit: 3            # レビュー往復上限 (既定 3)

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

`tracker.*` セクションは `create-issue` 専用なので、ここでは説明しない (`feature-team` は issue を作らないため tracker 情報を必要としない)。

### 不在時の挙動

`review.*` / `volume_thresholds.*` が不在の場合、既定値で動作する。雛形書き出しはしない (実装対象を引数で受け取る設計なので、Phase 1 のしきい値さえ既定値で決まれば動く)。

## フェーズ全体図

```
Phase 0: 起動 (実装対象の受領と妥当性確認)
   ├─ 対象あり (issue 番号 or spec+plan パス) → Phase 1 へ
   └─ 対象なし or 薄い → 4 択案内して停止 (要件詰めは外部スキルへ)
   │
   ▼
Phase 1: ボリューム判断 (parent.md のしきい値)
   │
   ├─ 大規模 → Phase 2-A: 並列開発 (n 個の sub-issue を並列起動)
   │              │
   │              ▼
   │           Phase 3: 観点別レビュー (developer 完了ごとにストリーミング起動)
   │              │             ※ quality は全実装で必須
   │              │             ※ CONTEXT.md / docs/adr/ 存在時は候補スクリーニングも
   │              ▼
   │           Phase 4: pr-publisher を n 個並列起動 → n 個の独立 PR
   │
   └─ 小規模 → Phase 2-B: 親が直接実装 (worktree 1 つ)
                  │
                  ▼
               Phase 3: 観点別レビュー (最低 quality 観点必須)
                  │
                  ▼
               Phase 4: pr-publisher を 1 個起動 → 1 個の PR
```

## Phase 0: 起動

### 0.1 起動引数

```
/feature-team <issue-番号|ID>
  例: /feature-team 123          (GitHub Issue 番号)
       /feature-team KISSA-72   (Linear Issue ID)

/feature-team --spec <path> [--plan <path>]
  例: /feature-team --spec docs/superpowers/specs/2026-05-27-foo-design.md
       /feature-team --spec ...md --plan ...md

/feature-team                   (引数なし → 4 択案内して停止)
```

実装対象を起動時に明示することが、「実装してよい」というゴーサインを兼ねる。事前ラベル付け等のマーキングは使わない。

### 0.2 引数あり時の対象取得と妥当性確認

#### Issue 番号で起動された場合

```bash
# GitHub
gh issue view <番号> --json title,body,labels,state,number

# Linear
linear issue view <ID>
```

- 実在しない → エラー停止 (引数を直して再投入してもらう)
- state が closed → `AskUserQuestion` で「クローズ済み issue です。再オープンして進める / 別 issue を指定する」を確認
- sub-issue があれば一覧取得 (Phase 1 のボリューム判断と Phase 2-A の並列起動に使う)
- 本文をユーザーに見せて「この内容で進めて良いか」を 1 回確認する (本文が古い/方針と乖離している可能性に備える)

#### spec/plan パスで起動された場合

```
Read(<spec-path>)
Read(<plan-path>)   # 省略可
```

- ファイルが存在しない → エラー停止
- 標準セクション (目的・背景・受入条件・サブタスク) を簡易判定
  - 揃っている → 続行
  - 揃っていない → `AskUserQuestion` で「情報が不足しています。要件詰めに戻る / それでも進める」を確認

### 0.3 「薄い」判定

以下のいずれかに該当 → 薄いと判定 → `AskUserQuestion` で「考慮漏れが発生しやすい状態です。要件詰めに戻る / このまま進める」を確認:

- 受入条件が無い、または 1 行のみ
- 変更対象 (ファイル / モジュール / 機能) が不明
- 主要な依存関係・スコープが不明

判定基準の詳細は `roles/parent.md` の「9. Phase 0 の対象判定基準」参照。

### 0.4 引数なし時の交通整理

`feature-team` は要件定義を肩代わりしない。`AskUserQuestion` で 4 択を提示して停止する:

- **(a) 要件詰めに戻る**: 「`Skill(grill-me)` または `Skill(superpowers:brainstorming)` で要件を詰めてください。終了後 spec/plan を書き出し → `Skill(create-issue, args="<spec> <plan>")` → `/feature-team <作成された番号>` で再起動」と案内して停止
- **(b) 既存 issue で実装する**: 「`/feature-team <issue-番号|ID>` で再起動してください」と案内して停止
- **(c) 既に spec/plan を書いてある**: 「`/feature-team --spec <path> [--plan <path>]` で再起動してください」と案内して停止
- **(d) 簡単な内容を対話で詰めてここで実装する**: 親が**最小限の対話** (受入条件・変更対象・主要依存) を聞き取り、ad-hoc spec として親メモリ上に保持して Phase 1 へ進む。spec/plan のファイル化はユーザー希望時のみ

**(d) ルートでの制約 (必須):**

- 親は要件定義を肩代わりしない。聞くのは「実装可能になる最小限」のみ
- 設計判断・代替案検討・前提整理・ドメイン探求は行わない (それらは grill-me / brainstorming の責務)
- **質問が 3 つ目に到達したら、(d) を中断して (a) へ案内し直す**

### 0.5 確認後 Phase 1 へ

取得した対象 (issue 本文 + sub-issue / spec / plan / ad-hoc spec) を Phase 1 のボリューム判断に渡す。

## Phase 1: ボリューム判断

`roles/parent.md` の「1. ボリューム判断しきい値」セクションに従い、以下を決定する:

- **大規模 (→ Phase 2-A 並列開発)**: sub-issue が独立して並列実装可能な場合
- **小規模 (→ Phase 2-B 親直実装)**: sub-issue が 1 つのみ、または変更範囲が小さく親が直接書く方が早い場合

しきい値は `volume_thresholds` で上書き可能。判定結果と理由をユーザーに提示し、必要なら手動で上書きを受け付ける。

ad-hoc spec (Phase 0.4 (d) ルート) の場合、sub-issue 構造を持たないため通常は Phase 2-B 直行になる。

## Phase 2-A: 並列開発 (大規模)

### 2-A.1 sub-issue ごとに worktree を作成

```bash
wt switch -c <branch>
wt list
```

ブランチ命名規則: `feature/<slug>-issue-<sub-issue-番号>` (既存 `issue-dev` スキルと同じ)

> **注意:** Bash ツール経由では `wt switch -c` のシェル統合 (自動 `cd`) が効かない場合がある。`wt list` の出力から worktree 絶対パスを取得し、以降の Bash コマンドはそのパス内で実行するよう Agent に明示する。

### 2-A.2 各 sub-issue の developer を選定

`roles/parent.md` の「2. Developer 選定基準」を参照。10 種の特化版 (react/nextjs/flutter/go/nodejs/hono/nestjs/rust/ruby) から該当するものを選び、該当なしなら `developer-generic` にフォールバックする。

### 2-A.3 Agent を並列起動

各 sub-issue について `run_in_background: true` で起動する:

```
Agent(
  subagent_type="developer-<lang>",
  description="<sub-issue タイトルの短縮>",
  prompt="<下記テンプレート>",
  run_in_background=true,
)
```

#### Agent プロンプトに必ず含める項目

1. `roles/_common.md` の内容を完全注入
2. リポジトリ情報 (OWNER, REPO, DEFAULT_BRANCH)
3. Sub-issue 番号と本文 (Phase 0 で取得済みのものを渡す or `gh issue view` / `linear issue view` で再取得)
4. **worktree の絶対パス** (このディレクトリ内で作業すること、と明示)
5. ブランチ名
6. 完了条件: 「sub-issue の受入条件をすべて満たし、テストを通し、コミットして push する。PR は作らず、親に完了通知のみ返す」

### 2-A.4 親は通常作業を続ける

`run_in_background: true` のため待たない。親は次の sub-issue の起動・既存 sub-issue 完了通知の確認を継続する。

### 2-A.5 完了通知のストリーミング処理

developer から完了通知が返ったら、即座に Phase 3 (観点別レビュー) の対応する reviewer を起動する。全 developer の完了を待たない。

## Phase 2-B: 親直接実装 (小規模)

### 2-B.1 worktree を 1 つ作成

```bash
wt switch -c <branch>
```

ブランチ命名規則: `feature/<slug>-issue-<親 issue 番号>` (ad-hoc spec の場合は `feature/<slug>` で省略可)

### 2-B.2 親が直接実装

メイン Claude が `Edit` / `Write` / `Bash` ツールで直接コーディングする。worktrunk の `wt` コマンドを使った worktree 内で作業する。

### 2-B.3 Phase 3 へ

実装完了後、Phase 3 の観点別レビューを少なくとも `quality` 観点で 1 回は回す (必須)。

## Phase 3: 観点別レビュー

### 3.1 観点選定

`roles/parent.md` の「3. Reviewer 観点選定」に従い、対象 sub-issue / branch ごとに必要な観点を決定する:

- `quality`: **全実装で必須**。省略不可 (規約違反・バグ・テスト不足の検出ハブ)
- `security`: 認証・認可・入力バリデーション・秘密情報の扱い・SQL/コマンドインジェクションリスクが含まれる場合
- `performance`: ホットパス・大量データ処理・DB クエリ・N+1 リスクが含まれる場合

### 3.2 reviewer を並列起動

選定した観点の reviewer を `run_in_background: true` で起動する。

```
Agent(
  subagent_type="reviewer-<perspective>",
  description="<対象 branch>: <perspective> review",
  prompt="<下記テンプレート>",
  run_in_background=true,
)
```

#### Agent プロンプトに必ず含める項目 (全 reviewer 共通)

1. `roles/_common.md` の内容を完全注入
2. 対象 worktree の絶対パスとブランチ名
3. レビュー対象範囲 (全コミット差分 / 特定ファイル群)
4. 観点 (security / performance / quality)
5. 報告フォーマット: 重要度別 (critical / major / minor) の指摘リスト + 修正不要箇所の明示

#### reviewer-quality 専用追加指示: CONTEXT.md / ADR 候補スクリーニング

reviewer-quality 起動時のみ、以下を追加する:

```
リポジトリに CONTEXT.md または docs/adr/ が存在する場合のみ、追加の観点として以下を含めること:

1. 判定基準の参照:
   - ~/.claude/skills/grill-with-docs/SKILL.md の "Update CONTEXT.md inline" / "Offer ADRs sparingly" セクション
   - ~/.claude/skills/grill-with-docs/CONTEXT-FORMAT.md
   - ~/.claude/skills/grill-with-docs/ADR-FORMAT.md
   を Read で参照する。

2. 実装差分から以下を抽出し、候補として列挙する (最終的な 3 条件判定は親側で grill-with-docs が行うため、ここでは判定しない):
   - 既存 CONTEXT.md と矛盾 or 未掲載の新用語 → Minor 指摘 (CONTEXT.md 追記候補)
   - 重要な設計決定 → Major 指摘 (ADR 化候補)

3. CONTEXT.md / docs/adr/ が存在しないリポジトリではこの観点をスキップする (静かに退避)

reviewer 側で 3 条件 (Hard to reverse / Surprising without context / Real trade-off) を最終判定しないこと。
親が必要に応じて grill-with-docs スキルを起動して対話判定する。
```

### 3.3 指摘の集約と修正依頼

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

### 3.4 ラウンド上限

レビュー往復は `.claude/project.yml` の `review.round_limit` (既定 3) を上限とする。

- 1〜2 ラウンド目で完了 → そのまま Phase 4 へ
- 3 ラウンド目でも収束しない → **親が介入** (`parent.md` 「4. ラウンド超過時介入手順」参照)

### 3.5 CONTEXT.md / ADR 連携 (該当時のみ)

reviewer-quality からの候補列挙を受けて:

- **CONTEXT.md 追記候補がある場合 (Minor 指摘)**:
  - 親が直接 `Edit` で追記する。フォーマットは `~/.claude/skills/grill-with-docs/CONTEXT-FORMAT.md` に従う
  - 実装コミットと混ぜず、別コミット (`docs: add <term> to CONTEXT.md` 等) に分ける
  - grill-with-docs スキルの起動は不要 (用語追記は軽量判断)

- **ADR 化候補がある場合 (Major 指摘)**:
  - 親が `AskUserQuestion` で 3 択を提示:
    - (i) 今すぐ `Skill(grill-with-docs)` で対話判定する
    - (ii) PR を先に出してから別途検討する (Phase 4 に進む、ADR は後日)
    - (iii) ADR 化しない (スキップ)
  - (i) が選ばれたら `Skill(grill-with-docs)` を起動する。grill-with-docs が 3 条件を対話判定し、すべて満たすときのみ `docs/adr/` に書き出す (1 つでも欠ければスキップ)
  - 判定基準と書き出しは grill-with-docs に委譲。このスキルでは判定基準を再定義しない

詳細は `parent.md` 「8. CONTEXT.md / ADR 連携」参照。

## Phase 4: PR 作成

### 4.1 PR 単位の決定

- Phase 2-A 経由 → **n 個の独立 PR** (各 sub-issue worktree から 1 PR)
- Phase 2-B 経由 → **1 個の PR**

### 4.2 pr-publisher を並列起動

各 worktree について `pr-publisher` を `run_in_background: true` で起動する。Phase 3 がレビュー OK で完了している sub-issue / branch のみが対象 (critical 指摘が残っているものは起動しない)。

```
Agent(
  subagent_type="pr-publisher",
  description="<sub-issue タイトル>: PR publish",
  prompt="<下記テンプレート>",
  run_in_background=true,
)
```

#### Agent プロンプトに必ず含める項目

1. `roles/_common.md` の内容を完全注入
2. リポジトリ情報 (OWNER, REPO, DEFAULT_BRANCH)
3. **Worktree の絶対パス** (このディレクトリ内で作業すること、と明示)
4. ブランチ名
5. Issue 番号 (Phase 2-A は sub-issue 番号、Phase 2-B は親 issue 番号、ad-hoc spec の場合は無し)
6. 対応する spec / plan のパス (PR 本文の参照リンクに使う、ad-hoc spec の場合は省略)
7. レビュー結果サマリー (観点別、何ラウンドで収束したか、CONTEXT/ADR 更新の有無)
8. 期待される処理:
   - コミット整理 (必要に応じて)
   - `git push`
   - `gh pr create` で PR 作成 (Issue 番号があれば本文に `Resolves #<番号>` を含める)
   - `Skill(coderabbit-review)` で CodeRabbit インラインコメント対応
   - 結果を親に通知

### 4.3 完了報告

全 `pr-publisher` の完了を待ち、結果を集約して報告:

```
## ✅ Feature Team 完了

**実装対象:** #<番号> または <spec-path> または ad-hoc spec
**Spec:** <spec-path or ad-hoc>
**Plan:** <plan-path or 省略>

**PR:**
- #<PR 番号> (sub-issue #<番号>): <タイトル>  | レビュー: ✅ security ✅ quality (R2)
- #<PR 番号> (sub-issue #<番号>): <タイトル>  | レビュー: ✅ quality (R1)
- ...

**Phase 3 サマリー:**
- 全 N サブタスク中、X が R1 で収束、Y が R2 で収束、Z が親介入
- escalate 件数: 0 件
- CONTEXT.md 追記: <件数> / ADR 作成: <件数> (該当ファイル列挙)

**Phase 4 サマリー:**
- 全 N PR 作成 / CI: ✅ all passed / ⚠️ N failed
- CodeRabbit: ✅ no issues / 🔧 fixed N items / ⚠️ N items remaining
```

## エスカレーション

以下のケースでは即座に `AskUserQuestion` でユーザーに判断を仰ぐ:

1. Phase 0 で対象が「薄い」と判定された (続行 / 要件詰めに戻るの確認)
2. Phase 0 で issue が closed 状態 (再オープン / 別 issue 指定の確認)
3. Phase 3 ラウンド上限超過かつ親介入でも収束しない
4. Phase 3.5 で ADR 化候補が見つかった (3 択)
5. 設定ファイル `.claude/project.yml` の値が不正で自動修復できない
6. worktrunk / gh / linear CLI のエラーが繰り返し発生する
7. sub-issue の受入条件が互いに矛盾している、または達成不能と判定された
8. ボリューム判断 (Phase 1) が困難で、自動判定の信頼度が低い

エスカレーション時は、親が現状サマリーと選択肢 (候補 2-3 個) を提示する。

## ハンドオフ

長時間ジョブのため、各 Phase 完了時には `Skill(handoff)` で状態を保存することを推奨する (特に Phase 2-A の並列開発中はコンテキスト圧縮警告が出やすい)。

## 呼び出し元

このスキルは以下のパターンで呼ばれる:

- **ユーザー直接起動**:
  - `/feature-team <issue-番号|ID>` — 既存 issue で実装
  - `/feature-team --spec <path> [--plan <path>]` — spec/plan で直接実装 (issue 化なし)
  - `/feature-team` — 引数なしで 4 択案内 → 該当する経路へ
- **`pick-next` 連携**: `pick-next` が `Skill(create-issue)` で issue を作成した後、ユーザーが `/feature-team <作成された番号>` を手動起動
- **`issue-dev` 連携**: `issue-dev` が複数 sub-issue 並列実装を要するケースで `/feature-team <番号>` を案内 (issue-dev 側の挙動次第)

このスキルは要件定義や issue 作成を**しない**。これらは前段の独立スキル (`grill-me` / `superpowers:brainstorming` / `superpowers:writing-plans` / `create-issue` / `pick-next`) に任せる。
