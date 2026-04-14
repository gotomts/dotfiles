---
name: issue-dev
description: GitHub Issue を起点にブランチ作成・Project ステータス更新・PR 作成・CI チェックまでのフルサイクル開発を管理する。サブ issue を検出した場合は依存関係を分析し、直列/並列実行の戦略を提案する。
argument-hint: <Issue番号> [--type hotfix|feature|refactor] [--finish]
allowed-tools:
  - Bash
---

# Issue Dev

GitHub Issue を起点に、ブランチ作成から PR 作成・ステータス更新までを実行する。

## 実行フロー概要

```
Issue 読み込み
    │
    ├─ サブ issue あり（2件以上） → フェーズ S（実行戦略）
    │       │
    │       ├─ 🔗 直列: 1つずつ A→C→B → PR マージ待ち → 次の issue-dev 起動
    │       ├─ ⚡ 並列: worktree で同時に A→C→B → 全 PR 作成
    │       └─ 🔀 混合: 直列 + 並列の組み合わせ
    │
    ├─ サブ issue なし → フェーズ A → C → B（一気通貫で PR 作成まで）
    │
    └─ --finish 指定 → フェーズ B のみ（PR 作成）
```

## 前提

- `gh` CLI が認証済みであること
- 対象リポジトリのワーキングディレクトリにいること
- GitHub Project を操作する場合、スコープ権限が必要（`gh auth refresh -s project`）

## コンテキスト検出

スキル起動時に以下を自動検出する。検出に失敗した場合はエラーメッセージとともに停止する。

### リポジトリ情報

```bash
gh repo view --json owner,name,defaultBranchRef -q '{owner: .owner.login, repo: .name, defaultBranch: .defaultBranchRef.name}'
```

取得する値:
- `OWNER`: リポジトリオーナー（ユーザーまたは Organization）
- `REPO`: リポジトリ名
- `DEFAULT_BRANCH`: デフォルトブランチ名

### GitHub Project 検出

```bash
gh project list --owner <OWNER> --format json
```

- Project が 1 つ → 自動選択
- Project が複数 → 番号とタイトルを一覧表示し、ユーザーに選択を求める
- Project が 0 → Project 関連ステップをスキップし、その旨を通知

### Project フィールド情報（Project が見つかった場合）

```bash
gh project field-list <PROJECT_NUMBER> --owner <OWNER> --format json
```

Status フィールドを特定し、以下のオプション ID を取得する:
- **In Progress** に該当するオプション（名前に "progress" を含むもの）
- **Review** に該当するオプション（名前に "review" を含むもの）

該当するオプションが見つからない場合、ステータス更新をスキップする。

## 引数の解析

- 第 1 引数: GitHub Issue 番号（必須）
- `--type`: ブランチプレフィックス（`hotfix`, `feature`, `refactor`）。省略時は Issue のラベルから推定
- `--finish`: フェーズ B のみを実行（既に実装済みのブランチで PR だけ作りたい場合）。省略時はフェーズ A → C → B を一気通貫で実行する

## ブランチタイプ推定ルール

1. `--type` 指定あり → そのまま使用
2. Issue ラベルに `bug` を含む → `hotfix`
3. Issue ラベルに `refactor` を含む → `refactor`
4. それ以外 → `feature`

## サブ issue 検出

コンテキスト検出・引数解析の後、まず Issue を読み込む（フェーズ A 手順 1 の `gh issue view` を実行）。
取得した body 内のサブタスクリストをパースする。

### 検出パターン

body 内の以下のパターンにマッチする行を抽出する:

```
- [ ] #<番号> ...
- [x] #<番号> ...
```

マッチが **2 件以上** ある場合、親 issue と判定し**フェーズ S** に進む。
マッチがない、または 1 件のみの場合は通常の**フェーズ A** に進む。

## フェーズ S: 実行戦略（親 issue の場合）

親 issue と判定された場合、フェーズ A〜C の代わりにこのフェーズを実行する。
`--finish` フラグは親 issue では無視する。

### S1. サブ issue 情報収集

検出した全サブ issue の情報を取得する:

```bash
# 各サブ issue に対して実行
gh issue view <番号> --repo <OWNER>/<REPO> --json title,body,labels,number,state
```

また、親 issue のコメントから**設計ドキュメント**と**実装プラン**を取得する（フェーズ A 手順 1 と同様）。
実装プラン内のステップ番号順序は、依存関係分析の最も重要な入力となる。

### S2. 依存関係分析

以下のシグナルを**優先度順**に評価し、依存グラフを構築する:

1. **実装プランの順序**（最優先）: 親 issue コメントの実装プランでステップが番号付きで記述されている場合、その順序を依存関係として採用する
2. **明示的依存マーカー**: サブ issue の body 内の「#XXX の完了後」「depends on」「requires」「前提」等のキーワード
3. **構造パターン**:
   - 「基盤」「setup」「規約」「初期」を含むタイトル → 先頭（他に依存しない）
   - 「クリーンアップ」「cleanup」「削除」「最終」を含むタイトル → 末尾（全サブ issue に依存）
   - 「パイロット」「pilot」「検証」を含むタイトル → 基盤タスクの直後
4. **変更スコープの重複**: 複数のサブ issue が同じディレクトリ・ファイル群を変更する記述がある → 直列推奨

判定に確信が持てない場合は**直列をデフォルト**とする（安全側に倒す）。

### S3. 戦略提案

依存グラフから実行戦略を判定し、以下の形式で出力する:

**戦略の種類:**

| 戦略 | 条件 |
|------|------|
| 🔗 直列 | 全サブ issue が線形依存 / 変更範囲が重複 |
| ⚡ 並列 | 全サブ issue が互いに独立 |
| 🔀 混合 | 一部に依存関係あり + 独立グループあり |

**出力フォーマット:**

```
## 🗺️ 実行戦略

### サブ issue 一覧
| # | タイトル | 状態 | 依存先 |
|---|---------|------|--------|
| #750 | 基盤構築 | open | - |
| #751 | record パイロット | open | #750 |
| ... | ... | ... | ... |

### 依存グラフ
#750 → #751 → [#752, #753, #754] → #759
                    （並列可能）

### 推奨: 🔗 直列 / ⚡ 並列 / 🔀 混合
**理由:** ...

### 実行計画
Phase 1: #XXX → 実行 → PR 作成
Phase 2: #YYY → 実行 → PR 作成
...
```

**ユーザーの承認を得てから S4 に進む。** 戦略の修正・上書きも受け付ける。

### S4. 実行

承認された戦略に基づきサブ issue を実行する。各サブ issue は**フェーズ A → C → B（PR 作成まで）** を一気通貫で実行する。

#### 直列実行モード 🔗

1. 未完了（`state: open`）のサブ issue のうち、依存先が全て完了済みの先頭を特定する
2. そのサブ issue に対して**フェーズ A → C → B** を実行する
3. PR 作成完了後、進捗サマリーを出力する:

```
## 📋 直列実行の進捗

✅ #750 基盤構築 → PR #XXX
🚲 次: #751 record パイロット
⏳ #752 shop 移行
⏳ #753 coffeebeans 移行
...

**次のステップ:** PR をレビュー・マージ後、`/issue-dev <親issue番号>` で次のサブ issue を開始します。
```

#### 並列実行モード ⚡

並列可能な全サブ issue に対して、Agent ツールを `isolation: "worktree"` で**同時起動**する。

各エージェントのプロンプトに含めるコンテキスト:
- リポジトリ情報（OWNER, REPO, DEFAULT_BRANCH）
- GitHub Project 情報（検出済みの場合）
- サブ issue 番号
- 親 issue の設計ドキュメント・実装プラン
- **指示: 「このサブ issue に対してフェーズ A → C → B を実行し、PR を作成せよ」**

全エージェント完了後、結果を集約して報告する:

```
## 📋 並列実行の結果

✅ #752 shop 移行 → PR #XXX (worktree: /path/to/worktree)
✅ #753 coffeebeans 移行 → PR #YYY (worktree: /path/to/worktree)
❌ #754 coffee_equipment 移行 → エラー: ...
...
```

#### 混合実行モード 🔀

直列フェーズと並列フェーズを順番に処理する。

1. 依存グラフの直列部分を先に実行（1 サブ issue ずつ、PR マージ待ち）
2. 並列可能なフェーズに到達したら並列実行モードで起動
3. 並列フェーズ完了後、残りの直列部分を実行

各フェーズの切り替わりで進捗サマリーを出力する。

## フェーズ A: 開発開始（セットアップ）

### 1. Issue 読み込み

```bash
# Issue 本文
gh issue view <番号> --repo <OWNER>/<REPO> --json title,body,labels,number

# Issue コメント（設計ドキュメント・実装プランが含まれている場合がある）
gh issue view <番号> --repo <OWNER>/<REPO> --comments --json comments
```

Issue の内容を取得し、以下を把握する:
- タイトル
- 受入条件（body 内のチェックリスト）
- ラベル（ブランチタイプ推定に使用）
- 関連 Issue
- **設計ドキュメント**（コメントに含まれている場合）
- **実装プラン**（コメントに含まれている場合）

### 2. ブランチ作成

命名規則: `{type}/{slug}-issue-{number}`

slug は Issue タイトルから生成する:
- 日本語はローマ字化せず、英単語に要約する
- スペースをハイフンに置換
- 小文字に統一
- 30 文字以内に収める

例:
- Issue「コーヒー器具のカテゴリ管理機能」→ `feature/coffee-equipment-category-issue-748`
- Issue「焙煎日に null と表示されている」→ `hotfix/roast-date-null-display-issue-742`

```bash
git checkout <DEFAULT_BRANCH>
git pull origin <DEFAULT_BRANCH>
git checkout -b <ブランチ名>
```

### 3. GitHub Project ステータス更新（Project が検出された場合）

Status を「In Progress」に変更する。

```bash
# Issue の Item ID を取得
ITEM_ID=$(gh project item-list <PROJECT_NUMBER> --owner <OWNER> --format json | jq -r '.items[] | select(.content.number == <番号> and .content.repository == "<OWNER>/<REPO>") | .id')

# Status を In Progress に設定
gh project item-edit --project-id <PROJECT_ID> --id $ITEM_ID --field-id <STATUS_FIELD_ID> --single-select-option-id <IN_PROGRESS_OPTION_ID>
```

Item ID が見つからない場合（Issue が Project に未追加）:
1. `gh project item-add` で Issue を Project に追加
2. 追加後に Item ID を取得してステータスを設定

### 4. 開発コンテキストの出力

```
## 開発コンテキスト

**Issue:** #<番号> - <タイトル>
**リポジトリ:** <OWNER>/<REPO>
**ブランチ:** <ブランチ名>
**Project Status:** 🚲 In Progress

### 受入条件
- [ ] 条件1
- [ ] 条件2

### 設計ドキュメント（Issue コメントより）
<設計コメントがあればここに要約>

### 実装プラン（Issue コメントより）
<実装プランコメントがあればここに要約>
```

**フェーズ A 完了後、フェーズ C（開発）に進む。** フェーズ C 完了後、自動的にフェーズ B（PR 作成）に進む。

## フェーズ B: PR 作成・CI チェック・ステータス更新

通常はフェーズ C 完了後に自動実行される。
`--finish` フラグ付きで起動した場合は、フェーズ A・C をスキップしてこのフェーズのみ実行する（既に実装済みのブランチで PR だけ作りたい場合）。

### B1. PR 作成

Issue の情報から PR を作成する。

**タイトル:** Conventional Commits 形式。Issue のラベルとタイトルから推定する:
- `bug` ラベル → `fix: <要約>`
- `refactor` ラベル → `refactor: <要約>`
- それ以外 → `feat: <要約>`

**Body:**
```markdown


## Issue
Resolves #<番号>
```

```bash
gh pr create --repo <OWNER>/<REPO> --title "<タイトル>" --body "<body>"
```

### B2. CI チェック・自動修正

PR 作成後、CI の完了を待機し結果を確認する。

#### チェック待機

```bash
gh pr checks <PR_URL> --watch
```

- チェックが 0 件（CI 未設定）→ スキップして B3 へ
- 全チェック pass → B3 へ
- チェック fail → エラー解析・修正サイクルに入る
- 10 分以内に完了しない → 現在のステータスを報告し、ユーザーに待機/続行を確認する

#### エラー解析・修正サイクル

CI が fail した場合、原因を解析し自動修正を試みる。2 回目の失敗でユーザーに判断を仰ぐ。

**1. エラーログ取得**

```bash
# 最新の workflow run ID を取得
gh run list --branch <BRANCH> --limit 1 --json databaseId,conclusion -q '.[0].databaseId'

# 失敗ログを確認
gh run view <RUN_ID> --log-failed
```

**2. 原因分析・修正**: エラーログを解析し、原因を特定して修正を実施する。

**3. 再プッシュ・再チェック**: 修正をコミット・プッシュし、CI を再トリガーする。

```bash
git add <修正ファイル>
git commit -m "fix: CI エラーを修正"
git push
gh pr checks <PR_URL> --watch
```

- pass → B3 へ
- 再度 fail（2 回目の失敗）→ ユーザーに報告し判断を仰ぐ:

```
## ⚠️ CI チェック失敗（2 回目）

### 失敗したチェック
- <チェック名>: <エラー概要>

### 試行した修正
1. 1 回目: <修正内容と結果>
2. 2 回目: <修正内容と結果>

### 選択肢
1. 🔧 修正を続行（手動で調査・修正）
2. ⏩ CI 失敗のまま Review に進む
3. 🛑 中断する
```

### B3. CodeRabbit レビュー確認・対応

PR 作成後、CodeRabbit のインラインコメントを待機し対応する。

#### コメント待機

CodeRabbit のレビューが投稿されるまでポーリングする（30 秒間隔、最大 5 分）。

```bash
# CodeRabbit のレビューが投稿されたか確認
gh pr view <PR_NUMBER> --json reviews --jq '.reviews[] | select(.author.login == "coderabbitai")'
```

- レビューが投稿されない（タイムアウト）→ CodeRabbit 未設定と判断しスキップして B4 へ
- レビューが投稿された → インラインコメントを取得する

#### インラインコメント取得

```bash
gh api repos/<OWNER>/<REPO>/pulls/<PR_NUMBER>/comments --jq '[.[] | select(.user.login == "coderabbitai") | {path: .path, line: .line, body: .body}]'
```

- インラインコメントが 0 件 → B4 へ
- インラインコメントあり → 対応サイクルに入る

#### 対応サイクル

CI チェックと同様、1 回自動修正を試み、2 回目の失敗でユーザーに判断を仰ぐ。

**1. コメント分析**: 各インラインコメントの指摘内容を分析し、修正を実施する。

**2. 再プッシュ・再確認**: 修正をコミット・プッシュし、CodeRabbit の再レビューを待機する。

```bash
git add <修正ファイル>
git commit -m "fix: CodeRabbit の指摘を修正"
git push
```

再度ポーリングし、新しいインラインコメントを確認する。

- 新規コメントなし → B4 へ
- 新規コメントあり（2 回目）→ ユーザーに報告し判断を仰ぐ:

```
## ⚠️ CodeRabbit レビュー指摘（2 回目）

### 残存するインラインコメント
- <ファイルパス>:<行番号> — <指摘内容>
- ...

### 試行した修正
1. 1 回目: <修正内容と結果>
2. 2 回目: <修正内容と結果>

### 選択肢
1. 🔧 修正を続行
2. ⏩ 指摘を残したまま Review に進む
3. 🛑 中断する
```

### B4. GitHub Project ステータス更新（Project が検出された場合）

Status を「Review」に変更する。

```bash
ITEM_ID=$(gh project item-list <PROJECT_NUMBER> --owner <OWNER> --format json | jq -r '.items[] | select(.content.number == <番号> and .content.repository == "<OWNER>/<REPO>") | .id')

gh project item-edit --project-id <PROJECT_ID> --id $ITEM_ID --field-id <STATUS_FIELD_ID> --single-select-option-id <REVIEW_OPTION_ID>
```

### B5. 完了報告

```
PR 作成完了:
- PR: <PR URL>
- CI: ✅ All checks passed / ⚠️ Failed (continued) / ⏭️ No CI
- CodeRabbit: ✅ No issues / 🔧 Fixed / ⚠️ Issues remaining / ⏭️ Not configured
- Issue: #<番号> → Project Status: Review
```

## フェーズ C: 開発（feature-dev 手法）

フェーズ A 完了後に自動的に開始する。
feature-dev スキルの構造的な開発プロセスを Issue コンテキストに適応して実行する。

### C1. コードベース探索

feature-dev の code-explorer エージェントを用いて、関連コードを深く理解する。

2-3 の code-explorer エージェントを**並列起動**する。各エージェントは:
- Issue の受入条件・設計ドキュメントに関連するコードを包括的にトレースする
- それぞれ異なる観点を担当する（類似機能、アーキテクチャ、影響範囲など）
- 読むべき重要ファイル 5-10 件のリストを返す

エージェント完了後、**返されたファイルをすべて読み**、深い理解を構築する。

### C2. 明確化の質問

Issue の受入条件・設計ドキュメント・コードベース探索の結果を照合し、曖昧な点を洗い出す。

- **設計/実装プランコメントがある場合**: 内容とコードベースの現状に矛盾がないか確認。矛盾や不明点があればユーザーに質問する
- **設計/実装プランコメントがない場合**: エッジケース、エラーハンドリング、統合ポイント、スコープ境界について質問を整理し、ユーザーに提示する

**すべての質問への回答を得てから次に進む。**

### C3. 設計判断（設計コメントがない場合のみ）

Issue コメントに設計ドキュメントがない場合、feature-dev の code-architect エージェントを用いて設計する。

2-3 の code-architect エージェントを**並列起動**し、異なるアプローチを設計させる:
- 最小変更（既存コード最大活用）
- クリーンアーキテクチャ（保守性重視）
- プラグマティック（速度と品質のバランス）

各アプローチのトレードオフと推奨案を提示し、**ユーザーに選択してもらう。**

設計コメントがある場合はこのステップをスキップし、その設計に従う。

### C4. 実装

**ユーザーの承認を得てから開始する。**

1. 前フェーズで特定したファイルをすべて読む
2. 選択されたアーキテクチャ / 設計ドキュメントに従い実装
3. コードベースの既存規約に厳密に従う
4. TodoWrite で進捗を追跡する

### C5. 品質レビュー

feature-dev の code-reviewer エージェントを用いて品質を検証する。

3 つの code-reviewer エージェントを**並列起動**し、異なる観点でレビューする:
- シンプルさ・DRY・可読性
- バグ・機能的正確性
- プロジェクト規約・抽象化の整合性

結果を統合し、重要度の高い指摘をユーザーに提示する。
**ユーザーの判断を仰ぐ**（今すぐ修正 / 後で修正 / このまま進行）。

### C6. 完了 → フェーズ B へ

1. すべての Todo を完了にする
2. 実装サマリーを出力:
   - 何を実装したか
   - 主要な設計判断
   - 変更したファイル一覧
3. **自動的にフェーズ B（PR 作成・ステータス更新）に進む**
