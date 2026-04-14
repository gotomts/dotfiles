---
name: coderabbit-review
description: PR の CodeRabbit インラインコメントを確認し、指摘への対応・リプライを行う。
argument-hint: <PR番号 or PR URL>
allowed-tools:
  - Bash
---

# CodeRabbit Review

PR に対する CodeRabbit のインラインコメントを確認し、指摘への修正・リプライを実行する。

## 前提

- `gh` CLI が認証済みであること
- 対象リポジトリのワーキングディレクトリにいること

## コンテキスト検出

```bash
gh repo view --json owner,name -q '{owner: .owner.login, repo: .name}'
```

取得する値:
- `OWNER`: リポジトリオーナー
- `REPO`: リポジトリ名

引数が PR 番号の場合はそのまま使用。PR URL の場合は番号を抽出する。

## 実行フロー

```
PR 指定
  │
  ├─ コメント待機（ポーリング）
  │     │
  │     ├─ タイムアウト → CodeRabbit 未設定、スキップ
  │     └─ レビュー検出 → インラインコメント取得
  │           │
  │           ├─ 0 件 → 完了（指摘なし）
  │           └─ あり → 対応サイクル
  │                 │
  │                 ├─ 修正 → リプライ → プッシュ → 再確認
  │                 │     │
  │                 │     ├─ 新規コメントなし → 完了
  │                 │     └─ 新規コメントあり（2 回目）→ ユーザー確認
  │                 │
  │                 └─ 修正不要と判断 → リプライのみ
  │
  └─ 完了報告
```

## 1. コメント待機

CodeRabbit のレビューが投稿されるまでポーリングする（30 秒間隔、最大 5 分）。

```bash
# CodeRabbit のレビューが投稿されたか確認
gh pr view <PR_NUMBER> --json reviews --jq '.reviews[] | select(.author.login == "coderabbitai")'
```

- レビューが投稿されない（タイムアウト）→ CodeRabbit 未設定と判断し、その旨を通知して終了
- レビューが投稿された → インラインコメントを取得する

## 2. インラインコメント取得

```bash
gh api repos/<OWNER>/<REPO>/pulls/<PR_NUMBER>/comments --jq '[.[] | select(.user.login == "coderabbitai") | {id: .id, path: .path, line: .line, body: .body}]'
```

- インラインコメントが 0 件 → 指摘なしとして完了報告
- インラインコメントあり → 対応サイクルに入る

## 3. 対応サイクル

1 回自動修正を試み、2 回目の失敗でユーザーに判断を仰ぐ。

### 3-1. コメント分析・修正

各インラインコメントの指摘内容を分析し、修正を実施する。

修正不要と判断した場合（意図的な設計判断、誤検知等）は、修正せずリプライで理由を説明する。

### 3-2. 対応内容をリプライ

修正した各コメントに対し、対応内容を返信する。

```bash
# 各コメントに対応内容をリプライ
gh api repos/<OWNER>/<REPO>/pulls/<PR_NUMBER>/comments/<COMMENT_ID>/replies -f body="@coderabbitai <対応内容の説明>

---
🤖 *via Claude Code*"
```

対応内容は簡潔に、何をどう修正したかを記載する（例: 「`nil` チェックを追加しました」「未使用の変数を削除しました」）。
修正しなかった場合は理由を記載する（例: 「意図的な設計です。`XXX` の理由で現状を維持します」）。
末尾に `🤖 *via Claude Code*` を付与し、自動対応であることを明示する。

### 3-3. 再プッシュ・再確認

修正がある場合、コミット・プッシュし、CodeRabbit の再レビューを待機する。

```bash
git add <修正ファイル>
git commit -m "fix: CodeRabbit の指摘を修正"
git push
```

再度ポーリングし、新しいインラインコメントを確認する。

- 新規コメントなし → 完了報告へ
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
2. ⏩ 指摘を残したまま続行
3. 🛑 中断する
```

## 4. 完了報告

```
CodeRabbit レビュー対応完了:
- PR: <PR URL>
- 結果: ✅ No issues / 🔧 Fixed (<N>件修正) / ⚠️ Issues remaining / ⏭️ Not configured
- リプライ済みコメント: <N> 件
```
