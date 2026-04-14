---
name: wt-cleanup
description: マージ済み PR の worktree を検出し、一括クリーンアップする
allowed-tools:
  - Bash
---

# Worktree Cleanup

マージ済み PR に対応する worktree を検出し、ユーザー確認のうえ一括削除する。

## 前提

- `wt`（worktrunk）がインストール済みであること
- `gh` CLI が認証済みであること
- 対象リポジトリのワーキングディレクトリにいること

## 実行フロー

### 1. リポジトリ情報取得

```bash
gh repo view --json owner,name -q '{owner: .owner.login, repo: .name}'
```

### 2. Worktree 一覧取得

```bash
wt list
```

メインの worktree（デフォルトブランチ）を除く全 worktree のブランチ名とパスを取得する。

### 3. マージ済み PR の検出

各 worktree のブランチに対応する PR を検索する:

```bash
gh pr list --state merged --head <ブランチ名> --repo <OWNER>/<REPO> --json number,title,mergedAt
```

結果を以下の3カテゴリに分類する:
- **マージ済み**: PR が merged 状態 → 削除対象
- **未マージ**: PR が open または closed（未マージ）状態 → 保持
- **PR なし**: 対応する PR が存在しない → 保持（手動管理ブランチの可能性）

### 4. 結果表示

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

**削除対象がない場合:**

```
クリーンアップ対象の worktree はありません。

### 現在の worktree
| ブランチ | PR | 状態 |
|---------|-----|------|
| feature/baz-issue-789 | #202 | open |
```

worktree が 1 つもない場合（メインのみ）:

```
worktree はありません。
```

### 5. ユーザー確認・削除実行

ユーザーが承認した場合、マージ済み worktree を `wt remove` で削除する:

```bash
wt remove <ブランチ名>
```

### 6. 結果報告

```
✅ <N> worktree を削除しました
- <ブランチ名1>
- <ブランチ名2>
```
