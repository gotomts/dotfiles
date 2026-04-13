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

## フェーズ A: 開発開始（スキル起動時）

### 1. Issue 読み込み

```bash
gh issue view <番号> --repo <OWNER>/<REPO> --json title,body,labels,number
```

Issue の内容を取得し、以下を把握する:
- タイトル
- 受入条件（body 内のチェックリスト）
- ラベル（ブランチタイプ推定に使用）
- 関連 Issue

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

---
ここからは通常の開発を行ってください。
開発が完了したら `/issue-dev <番号> --finish` で PR 作成とステータス更新を行います。
```

**フェーズ A はここで終了する。**

## フェーズ B: 開発完了（`--finish` フラグ付きで再起動）

`/issue-dev <番号> --finish` で起動する。

### 5. PR 作成

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

### 6. GitHub Project ステータス更新（Project が検出された場合）

Status を「Review」に変更する。

```bash
ITEM_ID=$(gh project item-list <PROJECT_NUMBER> --owner <OWNER> --format json | jq -r '.items[] | select(.content.number == <番号> and .content.repository == "<OWNER>/<REPO>") | .id')

gh project item-edit --project-id <PROJECT_ID> --id $ITEM_ID --field-id <STATUS_FIELD_ID> --single-select-option-id <REVIEW_OPTION_ID>
```

### 7. 完了報告

```
PR 作成完了:
- PR: <PR URL>
- Issue: #<番号> → Project Status: Review
```
