# Linear + GitHub Projects 連携ワークフロー 実装プラン

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Linear を企画層、GitHub Projects を実行層とする二層タスク管理ワークフローを、3つの Claude Code スキルとインフラ設定で実現する

**Architecture:** Brewfile に linear CLI を追加し、`claude/settings.json` でパーミッションとプラグインを設定する。3つのスキル（`linear-plan`, `issue-sync`, `issue-dev`）を `claude/skills/` 配下に SKILL.md として配置する。各スキルは疎結合で独立して使用可能。

**Tech Stack:** linear-cli (schpet/tap/linear), gh CLI, Claude Code Skills (SKILL.md), Brewfile, zsh

---

## ファイルマップ

- 変更: `Brewfile` — linear CLI の tap と brew を追加
- 変更: `claude/settings.json` — `Bash(linear:*)` パーミッションと `linear-cli` プラグインを追加
- 変更: `setup/setup.zsh:13` — `docs` を除外条件に追加
- 新規: `claude/skills/linear-plan/SKILL.md` — 企画構造化スキル
- 新規: `claude/skills/issue-sync/SKILL.md` — Linear → GitHub 同期スキル
- 新規: `claude/skills/issue-dev/SKILL.md` — フルサイクル開発スキル
- 変更: `CLAUDE.md` — リポジトリ構造セクションに `docs/` を追加

---

### Task 1: Brewfile に linear CLI を追加

**Files:**
- Modify: `Brewfile:1-3`（tap セクション）
- Modify: `Brewfile:45-46`（Other セクションの前）

- [ ] **Step 1: tap を追加**

`Brewfile` の tap セクション（3行目の後）に追加:

```ruby
tap 'schpet/tap'
```

- [ ] **Step 2: brew パッケージを追加**

`# Network & API` セクションと `# Other` セクションの間に新しいセクションを追加:

```ruby
# Task Management
brew 'schpet/tap/linear'
```

- [ ] **Step 3: コミット**

```bash
git add Brewfile
git commit -m "add: Brewfile に linear CLI (schpet/tap/linear) を追加"
```

---

### Task 2: claude/settings.json にパーミッションとプラグインを追加

**Files:**
- Modify: `claude/settings.json`

- [ ] **Step 1: `Bash(linear:*)` パーミッションを追加**

`claude/settings.json` の `permissions.allow` 配列に、`"Bash(shellcheck:*)"` の後（121行目付近）に追加:

```json
"Bash(linear:*)",
```

- [ ] **Step 2: `linear-cli` プラグインを有効化**

`claude/settings.json` の `enabledPlugins` オブジェクトに追加:

```json
"linear-cli@linear-cli": true
```

- [ ] **Step 3: 変更後の settings.json が有効な JSON であることを確認**

```bash
jq . claude/settings.json > /dev/null
```

期待結果: エラーなし（exit code 0）

- [ ] **Step 4: コミット**

```bash
git add claude/settings.json
git commit -m "add: settings.json に linear CLI パーミッションとプラグインを追加"
```

---

### Task 3: setup.zsh の除外条件に docs を追加

**Files:**
- Modify: `setup/setup.zsh:13`

- [ ] **Step 1: docs を除外条件に追加**

`setup/setup.zsh` の13行目を以下のように変更する:

```zsh
# 変更前
    if [[ ${name} != 'setup' ]] && [[ ${name} != 'README.md' ]] && [[ ${name} != 'ssh' ]] && [[ ${name} != 'claude' ]] && [[ ${name} != 'CLAUDE.md' ]]; then

# 変更後
    if [[ ${name} != 'setup' ]] && [[ ${name} != 'README.md' ]] && [[ ${name} != 'ssh' ]] && [[ ${name} != 'claude' ]] && [[ ${name} != 'CLAUDE.md' ]] && [[ ${name} != 'docs' ]]; then
```

- [ ] **Step 2: setup.zsh を実行して除外が機能することを確認**

```bash
cd ${HOME}/.dotfiles && zsh setup/setup.zsh
```

確認ポイント: `~/.docs` が作成されていないこと。

```bash
ls -la ~/.docs
```

期待結果: `No such file or directory`

- [ ] **Step 3: コミット**

```bash
git add setup/setup.zsh
git commit -m "fix: setup.zsh の除外条件に docs を追加"
```

---

### Task 4: linear-plan スキルを作成

**Files:**
- Create: `claude/skills/linear-plan/SKILL.md`

- [ ] **Step 1: ディレクトリを作成**

```bash
mkdir -p claude/skills/linear-plan
```

- [ ] **Step 2: SKILL.md を作成**

`claude/skills/linear-plan/SKILL.md` を以下の内容で作成する:

```markdown
---
name: linear-plan
description: アイデアを Linear Issue として構造化する。重複チェック・サブタスク分割・依存関係設定まで対話的に行う。
argument-hint: <アイデアの説明>
allowed-tools:
  - Bash
---

# Linear Plan

曖昧なアイデアや要望を Linear Issue として構造化する。

## 前提

- `linear` CLI が認証済みであること（`linear auth login`）
- 対象チームが設定済みであること（`linear config`）

## 処理フロー

### 1. コンテキスト収集

既存 Issue との重複を確認する。

```bash
linear issue list --json
```

関連する既存 Issue があれば一覧を提示し、重複の可能性を指摘する。

### 2. 対話的な詳細化

引数があればそれをアイデアの起点とする。以下を一問ずつ確認する:

- **目的・背景**: なぜこの機能が必要か
- **受入条件**: 何をもって完了とするか（チェックリスト形式で整理）
- **影響範囲**: 既存機能への影響

### 3. 構造化提案

以下をまとめてユーザーに提示する:

- タイトル
- 説明文（目的・背景を含む）
- 受入条件（チェックリスト形式）
- 優先度（Urgent / High / Medium / Low / No priority）
- ラベル
- サブタスク分割案（必要な場合。1サブタスク = 1 GitHub Issue = 1 PR を基準とする）
- 他 Issue との依存関係（blocks / blocked by）

**提案フォーマット例:**

```
## 提案内容

**タイトル:** コーヒー器具のカテゴリ管理機能
**優先度:** Medium
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
**承認なしに Linear への登録を行わない。**

### 5. Linear に登録

承認後、`linear issue create` で Issue を作成する。

サブタスクがある場合:
1. 親 Issue を作成
2. 各サブタスクを Sub-issue として作成
3. 依存関係がある場合は設定

作成完了後、作成した Issue の一覧（ID とタイトル）を表示する。

次のステップとして `/issue-sync <Issue ID>` で GitHub に同期できることを案内する。
```

- [ ] **Step 3: コミット**

```bash
git add claude/skills/linear-plan/SKILL.md
git commit -m "add: linear-plan スキルを追加"
```

---

### Task 5: issue-sync スキルを作成

**Files:**
- Create: `claude/skills/issue-sync/SKILL.md`

- [ ] **Step 1: ディレクトリを作成**

```bash
mkdir -p claude/skills/issue-sync
```

- [ ] **Step 2: SKILL.md を作成**

`claude/skills/issue-sync/SKILL.md` を以下の内容で作成する:

```markdown
---
name: issue-sync
description: Linear Issue を GitHub Issue に変換し、GitHub Project に登録する。逆リンクと Sub-issue の再帰処理にも対応。
argument-hint: <Linear Issue ID（複数可）>
allowed-tools:
  - Bash
---

# Issue Sync

Linear Issue の内容を GitHub Issue に変換し、GitHub Project に登録する。

## 前提

- `linear` CLI が認証済みであること
- `gh` CLI で `gotomts/socialcoffeenote` リポジトリにアクセスできること
- GitHub Project の読み書き権限があること（`gh auth refresh -s project` 済み）

## 定数

- リポジトリ: `gotomts/socialcoffeenote`
- Project ID: `PVT_kwHOAxAVd84ACA3Q`
- Project Number: `4`
- Project Owner: `gotomts`
- Status フィールド ID: `PVTSSF_lAHOAxAVd84ACA3QzgBKlac`
- Status Option ID（Ready）: `a3fe5591`

## 処理フロー

### 1. 引数の解析

引数として渡された Linear Issue ID を解析する。複数の ID が渡された場合は順に処理する。

### 2. Linear Issue 読み込み

```bash
linear issue show <Issue ID> --json
```

取得する情報:
- タイトル
- 説明文
- 優先度
- ラベル
- Sub-issue 一覧
- 依存関係（blocked by / blocks）

### 3. 重複チェック

Linear Issue のコメントに GitHub Issue の URL が既に記録されている場合、その Issue はスキップする。

```bash
linear issue show <Issue ID> --json
```

コメント欄に `github.com/gotomts/socialcoffeenote/issues/` を含む URL があればスキップし、その旨を報告する。

### 4. GitHub Issue body を生成

以下のフォーマットで GitHub Issue の body を組み立てる:

```markdown
## 概要
（Linear Issue の説明文をそのまま記載）

## 受入条件
- [ ] 条件1
- [ ] 条件2
（Linear Issue の説明文からチェックリスト部分を抽出。なければ省略）

## 関連
- Linear: <Issue ID>
（依存関係がある場合）
- Blocked by: #<GitHub Issue番号>
- Blocks: #<GitHub Issue番号>
```

### 5. ユーザー承認

生成した GitHub Issue の内容（タイトル + body）をユーザーに提示し、承認を得る。
**承認なしに GitHub Issue の作成を行わない。**

### 6. GitHub Issue 作成

```bash
gh issue create --repo gotomts/socialcoffeenote --title "<タイトル>" --body "<body>" --label "<ラベル>"
```

作成された Issue 番号を記録する。

### 7. GitHub Project に追加

Issue を Project #4 に追加し、Status を「Ready」に設定する。

```bash
# Issue の URL から Item ID を取得して Project に追加
gh project item-add 4 --owner gotomts --url <Issue URL>

# 追加されたアイテムの ID を取得
ITEM_ID=$(gh project item-list 4 --owner gotomts --format json | jq -r '.items[] | select(.content.url == "<Issue URL>") | .id')

# Status を Ready に設定
gh project item-edit --project-id PVT_kwHOAxAVd84ACA3Q --id $ITEM_ID --field-id PVTSSF_lAHOAxAVd84ACA3QzgBKlac --single-select-option-id a3fe5591
```

### 8. Linear に逆リンク

Linear Issue のコメントに GitHub Issue の URL を記録する。

```bash
linear issue comment <Issue ID> "GitHub Issue: https://github.com/gotomts/socialcoffeenote/issues/<番号>"
```

### 9. Sub-issue の処理

Linear Issue に Sub-issue がある場合、各 Sub-issue に対してステップ 2〜8 を再帰的に実行する。

GitHub 側では Parent issue フィールドを設定して階層を再現する。

### 10. 完了報告

作成した GitHub Issue の一覧を表示する:

```
同期完了:
- SCN-42 → #748 (https://github.com/gotomts/socialcoffeenote/issues/748)
- SCN-43 → #749 (Sub-issue of #748)
```

次のステップとして `/issue-dev <Issue番号>` で開発を開始できることを案内する。
```

- [ ] **Step 3: コミット**

```bash
git add claude/skills/issue-sync/SKILL.md
git commit -m "add: issue-sync スキルを追加"
```

---

### Task 6: issue-dev スキルを作成

**Files:**
- Create: `claude/skills/issue-dev/SKILL.md`

- [ ] **Step 1: ディレクトリを作成**

```bash
mkdir -p claude/skills/issue-dev
```

- [ ] **Step 2: SKILL.md を作成**

`claude/skills/issue-dev/SKILL.md` を以下の内容で作成する:

```markdown
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
```

- [ ] **Step 3: コミット**

```bash
git add claude/skills/issue-dev/SKILL.md
git commit -m "add: issue-dev スキルを追加"
```

---

### Task 7: CLAUDE.md のリポジトリ構造を更新

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: リポジトリ構造セクションに docs/ を追加**

`CLAUDE.md` の「リポジトリ構造」セクションに、`config/` の後に以下を追加:

```markdown
- `docs/` — 設計ドキュメント・実装プラン（シンボリックリンク対象外）
```

- [ ] **Step 2: シンボリックリンク管理セクションの除外リストを更新**

除外リストに `docs` を追加:

```markdown
- 以下はシンボリックリンク対象外として除外されている: `setup`, `README.md`, `ssh`, `claude`, `CLAUDE.md`, `docs`
```

- [ ] **Step 3: コミット**

```bash
git add CLAUDE.md
git commit -m "docs: CLAUDE.md のリポジトリ構造に docs/ を追加"
```

---

### Task 8: linear CLI のインストールと認証

**Files:** なし（手動操作）

- [ ] **Step 1: Homebrew でインストール**

```bash
brew tap schpet/tap
brew install schpet/tap/linear
```

- [ ] **Step 2: インストール確認**

```bash
linear --version
```

期待結果: バージョン番号が表示される

- [ ] **Step 3: GitHub Project の書き込みスコープを追加**

```bash
gh auth refresh -s project
```

ブラウザで認証フローを完了する。

- [ ] **Step 4: Linear API キーを作成**

ブラウザで https://linear.app/settings/account/security を開き、API キーを作成する。

- [ ] **Step 5: CLI で認証**

```bash
linear auth login
```

プロンプトに従い API キーを入力する。

- [ ] **Step 6: socialcoffeenote リポジトリで設定**

socialcoffeenote リポジトリのディレクトリに移動して Linear チームを設定する:

```bash
cd <socialcoffeenote のパス>
linear config
```

プロンプトでチームを選択する。

- [ ] **Step 7: 認証確認**

```bash
linear team list
```

期待結果: チーム一覧が表示される

---

### Task 9: スキルの動作確認

**Files:** なし（手動検証）

- [ ] **Step 1: linear-plan スキルの確認**

Claude Code で以下を実行し、対話フローが正しく動作することを確認する:

```
/linear-plan テスト用の機能
```

確認ポイント:
- 既存 Issue の重複チェックが行われる
- 対話的に詳細化が進む
- 構造化された提案が表示される
- 承認前に Linear に登録されない
- 承認後に Issue が作成される

- [ ] **Step 2: issue-sync スキルの確認**

Step 1 で作成した Linear Issue ID を使って確認:

```
/issue-sync <Linear Issue ID>
```

確認ポイント:
- Linear Issue の内容が正しく取得される
- GitHub Issue body が正しいフォーマットで生成される
- 承認前に GitHub Issue が作成されない
- GitHub Project に追加され Status が Ready になる
- Linear にコメントで GitHub Issue URL が記録される

- [ ] **Step 3: issue-dev スキルの確認**

Step 2 で作成した GitHub Issue 番号を使って確認:

```
/issue-dev <Issue番号>
```

確認ポイント:
- Issue の内容が正しく取得される
- ブランチが正しい命名規則で作成される
- GitHub Project の Status が In Progress に変更される
- 開発コンテキストが出力される

- [ ] **Step 4: issue-dev --finish の確認**

```
/issue-dev <Issue番号> --finish
```

確認ポイント:
- PR が Conventional Commits 形式のタイトルで作成される
- PR body に `Resolves #<番号>` が含まれる
- GitHub Project の Status が Review に変更される

- [ ] **Step 5: テスト用 Issue のクリーンアップ**

テストで作成した Linear Issue、GitHub Issue、PR、ブランチを削除する。
