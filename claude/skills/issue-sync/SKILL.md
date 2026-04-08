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
