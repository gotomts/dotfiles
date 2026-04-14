# Worktrunk 統合設計

## 概要

issue-dev スキルの開発フローを worktrunk (`wt`) ベースの worktree 運用に切り替える。加えて、マージ済み PR の worktree を一括クリーンアップする `wt-cleanup` スキルを新規作成する。

## 背景

- worktrunk を Brewfile + zshrc に導入済み（`189fb6e`）
- issue-dev は現在 `git checkout -b` で通常ブランチを作成しているが、worktree で作業することで main ブランチの作業状態を汚さずに開発できる
- 並列実行（フェーズ S）では Agent の `isolation: "worktree"` を使っているが、worktrunk 管理外のため `wt list` に表示されない

## 設計判断

| 判断項目 | 決定 | 理由 |
|---------|------|------|
| worktree 利用 | 常に worktree（オプションなし） | worktrunk 導入の目的そのもの |
| 並列実行の worktree 管理 | `wt switch -c` で事前作成 | `wt list` で一元管理するため |
| PR 作成後のクリーンアップ | しない（別スキルに委譲） | レビュー修正の可能性があるため |
| クリーンアップ方式 | マージ済み一覧表示 → ユーザー確認 → 一括削除 | 安全性と手軽さのバランス |

## 変更 1: issue-dev スキル修正

### フェーズ A ステップ 2: worktree 作成

**変更前:**

```bash
git checkout <DEFAULT_BRANCH>
git pull origin <DEFAULT_BRANCH>
git checkout -b <ブランチ名>
```

**変更後:**

```bash
wt switch -c <ブランチ名>
```

`wt switch -c` は内部で以下を実行する:
- DEFAULT_BRANCH の最新を取得
- worktree ディレクトリを作成
- シェルのカレントディレクトリを worktree に移動

> **実装上の注意:** Bash ツール経由では `wt switch -c` のシェル統合（自動 `cd`）が効かない可能性がある。その場合は `wt switch -c <ブランチ名>` 実行後、`wt list` の出力から worktree パスを取得し、以降の Bash コマンドをそのパス内で実行する。

ブランチ命名規則は変更なし: `{type}/{slug}-issue-{number}`

### フェーズ A ステップ 4: 開発コンテキスト出力

完了報告に worktree パスを追加:

```
**Worktree:** <worktree パス>
```

### フェーズ S4: 並列実行

**変更前:**

```
Agent(isolation: "worktree") × N 並列起動
```

**変更後:**

```
1. 各サブ issue のブランチ名を生成
2. wt switch -c <ブランチ名1> → worktree パスを記録
   wt switch -c <ブランチ名2> → worktree パスを記録
   ...（メインプロセスで順次作成）
3. 各 Agent を対応する worktree パスで並列起動（isolation なし）
   - Agent プロンプトに worktree パスを含め、cd してから作業させる
```

Agent プロンプトに含めるコンテキストは既存と同じ（リポジトリ情報、Project 情報、設計ドキュメント等）に加え、worktree の絶対パスを追加。

### フェーズ B5: 完了報告

worktree パスを報告に追加:

```
PR 作成完了:
- PR: <PR URL>
- Worktree: <worktree パス>
- CI: ✅ All checks passed / ...
- ...
```

### 変更しない箇所

- フェーズ A ステップ 1（Issue 読み込み）: 変更なし
- フェーズ A ステップ 3（Project ステータス更新）: 変更なし
- フェーズ B1〜B4: PR 作成・CI チェック・CodeRabbit・ステータス更新のロジックは変更なし
- フェーズ C: 開発フェーズのロジックは変更なし
- ブランチ命名規則: 変更なし

## 変更 2: wt-cleanup スキル新規作成

### スキル定義

- **名前:** `wt-cleanup`
- **説明:** マージ済み PR の worktree を検出し、一括クリーンアップする
- **引数:** なし
- **allowed-tools:** `Bash`

### 前提

- `wt` CLI がインストール済みであること
- `gh` CLI が認証済みであること

### 実行フロー

```
1. wt list で全 worktree を取得（メインを除く）
2. 各 worktree のブランチに対応する PR を検索
   gh pr list --state merged --head <branch> --repo <OWNER>/<REPO> --json number,title,mergedAt
3. 結果を分類:
   - マージ済み: 削除対象
   - 未マージ（open / closed）: 保持
   - PR なし: 保持（手動管理ブランチの可能性）
4. マージ済み worktree の一覧を表示
5. ユーザー確認（Y/n）
6. 確認後、wt remove <branch> で一括削除
7. 結果報告
```

### 出力フォーマット

**削除対象がある場合:**

```
## 🧹 Worktree クリーンアップ

### マージ済み（削除対象）
| ブランチ | PR | マージ日 |
|---------|-----|---------|
| feature/foo-issue-123 | #200 | 2026-04-14 |
| hotfix/bar-issue-456 | #201 | 2026-04-15 |

### 未マージ（保持）
| ブランチ | PR | 状態 |
|---------|-----|------|
| feature/baz-issue-789 | #202 | open |

削除しますか？ (Y/n)
```

確認後:
```
✅ 2 worktree を削除しました
- feature/foo-issue-123
- hotfix/bar-issue-456
```

**削除対象がない場合:**

```
クリーンアップ対象の worktree はありません。

### 現在の worktree
| ブランチ | PR | 状態 |
|---------|-----|------|
| feature/baz-issue-789 | #202 | open |
```
