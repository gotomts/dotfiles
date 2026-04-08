---
name: issue-dev
description: GitHub Issue を起点にブランチ作成・Project ステータス更新・PR 作成までのフルサイクル開発を管理する。
argument-hint: <Issue番号> [--type hotfix|feature|refactor]
allowed-tools:
  - Bash
---

# Issue Dev

GitHub Issue を起点に、ブランチ作成から PR 作成・ステータス更新までを実行する。

## 前提

- `gh` CLI で `gotomts/socialcoffeenote` リポジトリにアクセスできること
- GitHub Project のスコープ権限があること
- 対象リポジトリのワーキングディレクトリにいること

## 定数

- リポジトリ: `gotomts/socialcoffeenote`
- Project ID: `PVT_kwHOAxAVd84ACA3Q`
- Project Number: `4`
- Project Owner: `gotomts`
- Status フィールド ID: `PVTSSF_lAHOAxAVd84ACA3QzgBKlac`
- Status Option ID:
  - In Progress: `47fc9ee4`
  - Review: `52fe9807`

## 引数の解析

- 第1引数: GitHub Issue 番号（必須）
- `--type`: ブランチプレフィックス（`hotfix`, `feature`, `refactor`）。省略時は Issue のラベルから推定

## ブランチタイプ推定ルール

1. `--type` 指定あり → そのまま使用
2. Issue ラベルに `bug` を含む → `hotfix`
3. Issue ラベルに `refactor` を含む → `refactor`
4. それ以外 → `feature`

## フェーズ A: 開発開始（スキル起動時）

### 1. Issue 読み込み

```bash
gh issue view <番号> --repo gotomts/socialcoffeenote --json title,body,labels,number
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
- 30文字以内に収める

例:
- Issue「コーヒー器具のカテゴリ管理機能」→ `feature/coffee-equipment-category-issue-748`
- Issue「焙煎日にnullと表示されている」→ `hotfix/roast-date-null-display-issue-742`

```bash
git checkout main
git pull origin main
git checkout -b <ブランチ名>
```

### 3. GitHub Project ステータス更新

Status を「In Progress」に変更する。

```bash
# Issue の Item ID を取得
ITEM_ID=$(gh project item-list 4 --owner gotomts --format json | jq -r '.items[] | select(.content.number == <番号> and .content.repository == "gotomts/socialcoffeenote") | .id')

# Status を In Progress に設定
gh project item-edit --project-id PVT_kwHOAxAVd84ACA3Q --id $ITEM_ID --field-id PVTSSF_lAHOAxAVd84ACA3QzgBKlac --single-select-option-id 47fc9ee4
```

### 4. 開発コンテキストの出力

Issue の受入条件をチェックリストとして出力し、開発の指針を示す。

出力例:
```
## 開発コンテキスト

**Issue:** #748 - コーヒー器具のカテゴリ管理機能
**ブランチ:** feature/coffee-equipment-category-issue-748
**Project Status:** 🚲In Progress

### 受入条件
- [ ] カテゴリの CRUD が実装されている
- [ ] 器具にカテゴリを紐づけられる
- [ ] カテゴリでフィルタリングできる

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
gh pr create --repo gotomts/socialcoffeenote --title "<タイトル>" --body "<body>"
```

### 6. GitHub Project ステータス更新

Status を「Review」に変更する。

```bash
ITEM_ID=$(gh project item-list 4 --owner gotomts --format json | jq -r '.items[] | select(.content.number == <番号> and .content.repository == "gotomts/socialcoffeenote") | .id')

gh project item-edit --project-id PVT_kwHOAxAVd84ACA3Q --id $ITEM_ID --field-id PVTSSF_lAHOAxAVd84ACA3QzgBKlac --single-select-option-id 52fe9807
```

### 7. 完了報告

```
PR 作成完了:
- PR: https://github.com/gotomts/socialcoffeenote/pull/<番号>
- Issue: #<番号> → Project Status: Review
```
