---
name: github-plan
description: アイデアを GitHub Issue として構造化する。重複チェック・サブタスク分割・Project 登録まで対話的に行う。
argument-hint: <アイデアの説明>
allowed-tools:
  - Bash
---

# GitHub Plan

曖昧なアイデアや要望を GitHub Issue として構造化し、Project に登録する。

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

### GitHub Project 検出

```bash
gh project list --owner <OWNER> --format json
```

- Project が 1 つ → 自動選択
- Project が複数 → 番号とタイトルを一覧表示し、ユーザーに選択を求める
- Project が 0 → Project 関連ステップをスキップ（Issue 作成は続行）

### Project フィールド情報（Project が見つかった場合）

```bash
gh project field-list <PROJECT_NUMBER> --owner <OWNER> --format json
```

Status フィールドを特定し、初期ステータス（「Ready」「Todo」等）に該当するオプション ID を取得する。
該当するオプションが見つからない場合、ステータス設定をスキップする。

## 処理フロー

### 1. 重複チェック

引数のアイデアからキーワードを抽出し、既存 Issue を検索する。

```bash
gh issue list --repo <OWNER>/<REPO> --search "<キーワード>" --state open --json number,title,labels
```

関連する既存 Issue があれば一覧を提示し、重複の可能性を指摘する。
重複がないことを確認してから次に進む。

### 2. 対話的な詳細化

引数があればそれをアイデアの起点とする。以下を一問ずつ確認する:

- **目的・背景**: なぜこの機能が必要か
- **受入条件**: 何をもって完了とするか（チェックリスト形式で整理）
- **影響範囲**: 既存機能への影響

ユーザーの回答が十分であれば、質問を省略して構造化に進んでよい。

### 3. 構造化提案

以下をまとめてユーザーに提示する:

- タイトル
- 説明文（目的・背景を含む）
- 受入条件（チェックリスト形式）
- ラベル
- サブタスク分割案（必要な場合。1 サブタスク = 1 Issue = 1 PR を基準）
- 他 Issue との依存関係（blocks / blocked by）

**提案フォーマット:**

```
## 提案内容

**タイトル:** コーヒー器具のカテゴリ管理機能
**ラベル:** feature

**説明:**
コーヒー器具をカテゴリごとに管理できるようにする。
現状はフラットな一覧のみで、器具が増えると探しにくい。

**受入条件:**
- [ ] カテゴリの CRUD が実装されている
- [ ] 器具にカテゴリを紐づけられる
- [ ] カテゴリでフィルタリングできる

**サブタスク:**
1. カテゴリ API の実装
2. カテゴリ選択 UI の実装
3. フィルタリング機能の実装

**依存関係:** なし
```

### 4. ユーザー承認

提案内容を確認してもらう。修正があれば反映する。
**承認なしに GitHub Issue の作成を行わない。**

### 5. GitHub Issue 作成

```bash
gh issue create --repo <OWNER>/<REPO> --title "<タイトル>" --body "<body>" --label "<ラベル>"
```

サブタスクがある場合:
1. 親 Issue を作成（body にサブタスクをタスクリスト形式で含める）
2. 各サブタスクを個別の Issue として作成
3. 親 Issue の body を更新し、タスクリストの項目を Issue 参照（`#番号`）に置換

タスクリスト形式の例:
```markdown
## サブタスク
- [ ] #749 カテゴリ API の実装
- [ ] #750 カテゴリ選択 UI の実装
- [ ] #751 フィルタリング機能の実装
```

### 6. GitHub Project に追加（Project が検出された場合）

```bash
# Issue を Project に追加
gh project item-add <PROJECT_NUMBER> --owner <OWNER> --url <Issue URL>

# 追加されたアイテムの ID を取得
ITEM_ID=$(gh project item-list <PROJECT_NUMBER> --owner <OWNER> --format json | jq -r '.items[] | select(.content.url == "<Issue URL>") | .id')

# Status を設定（Ready/Todo 等）
gh project item-edit --project-id <PROJECT_ID> --id $ITEM_ID --field-id <STATUS_FIELD_ID> --single-select-option-id <READY_OPTION_ID>
```

サブタスクの Issue も同様に Project に追加する。

### 7. 完了報告

作成した Issue の一覧を表示する:

```
Issue 作成完了:
- #748 - コーヒー器具のカテゴリ管理機能
  - #749 - カテゴリ API の実装 (Sub-task)
  - #750 - カテゴリ選択 UI の実装 (Sub-task)
  - #751 - フィルタリング機能の実装 (Sub-task)
```

次のステップとして `/issue-dev <Issue番号>` で開発を開始できることを案内する。
