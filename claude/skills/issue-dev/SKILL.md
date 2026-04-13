---
name: issue-dev
description: GitHub Issue を起点にブランチ作成・Project ステータス更新・PR 作成までのフルサイクル開発を管理する。
argument-hint: <Issue番号> [--type hotfix|feature|refactor] [--finish]
allowed-tools:
  - Bash
---

# Issue Dev

GitHub Issue を起点に、ブランチ作成から PR 作成・ステータス更新までを実行する。

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
- `--finish`: フェーズ B を実行（PR 作成・ステータス更新）

## ブランチタイプ推定ルール

1. `--type` 指定あり → そのまま使用
2. Issue ラベルに `bug` を含む → `hotfix`
3. Issue ラベルに `refactor` を含む → `refactor`
4. それ以外 → `feature`

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

**フェーズ A 完了後、フェーズ C（開発）に進む。**

## フェーズ B: 開発完了（`--finish` フラグ付きで再起動）

`/issue-dev <番号> --finish` で起動する。

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

### B2. GitHub Project ステータス更新（Project が検出された場合）

Status を「Review」に変更する。

```bash
ITEM_ID=$(gh project item-list <PROJECT_NUMBER> --owner <OWNER> --format json | jq -r '.items[] | select(.content.number == <番号> and .content.repository == "<OWNER>/<REPO>") | .id')

gh project item-edit --project-id <PROJECT_ID> --id $ITEM_ID --field-id <STATUS_FIELD_ID> --single-select-option-id <REVIEW_OPTION_ID>
```

### B3. 完了報告

```
PR 作成完了:
- PR: <PR URL>
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

### C6. 完了

1. すべての Todo を完了にする
2. 実装サマリーを出力:
   - 何を実装したか
   - 主要な設計判断
   - 変更したファイル一覧
3. `/issue-dev <番号> --finish` で PR 作成に進めることを案内する
