---
name: wt-cleanup
description: PR 作成済みまたはマージ済みの worktree を検出し、一括クリーンアップする
allowed-tools:
  - Bash
  - AskUserQuestion
---

# Worktree Cleanup

PR に対応する worktree を検出し、ユーザー確認のうえ一括削除する。

## 前提

- `wt`（worktrunk）がインストール済みであること
- `gh` CLI が認証済みであること
- 対象リポジトリのワーキングディレクトリにいること

## 削除モード

ユーザーの意図に応じて削除対象を切り替える:

| モード | 削除対象 | 判定条件 |
|--------|---------|---------|
| **merged**（デフォルト） | マージ済み PR の worktree | `gh pr list --state merged` が 1件以上 |
| **with-pr** | PR 作成済みの worktree（状態問わず） | `gh pr list --state all` が 1件以上 |

- 明示的な指定がなければ **merged** モード
- 「PR作成済みを削除」「PR があるものを消したい」等の指示があれば **with-pr** モード

## 実行フロー

### 1. リポジトリ情報取得 + Worktree 一覧取得

```bash
REPO=$(gh repo view --json owner,name -q '.owner.login + "/" + .name')
wt list --format=json
```

worktree が main のみ（1件）の場合は「worktree はありません。」と表示して終了。

### 2. PR ステータスの一括検出

全ブランチの PR 状態を1コマンドで取得する:

```bash
wt list --format=json | jq -r '.[] | select(.is_main == false) | .branch' | while read b; do
  pr=$(gh pr list --state all --head "$b" --repo "$REPO" --json number,title,state,mergedAt --jq '.[0] // empty')
  if [ -n "$pr" ]; then
    echo "$b|$(echo "$pr" | jq -r '[.number, .title, .state, (.mergedAt // "")] | join("|")')"
  else
    echo "$b|none"
  fi
done
```

### 3. 結果の分類と表示

ステップ2の出力を以下の3カテゴリに分類して表示する:
- **マージ済み**: `state == "MERGED"` → merged モードで削除対象
- **未マージ（PR あり）**: `state == "OPEN"` or `state == "CLOSED"` → with-pr モードで削除対象
- **PR なし**: `none` → 常に保持

**表示例（merged モード）:**

```
## 🧹 Worktree クリーンアップ（merged モード）

### マージ済み（削除対象）
| ブランチ | PR | マージ日 |
|---------|-----|---------|
| feature/foo-issue-123 | #200 | 2026-04-14 |

### 未マージ（保持）
| ブランチ | PR | 状態 |
|---------|-----|------|
| feature/baz-issue-789 | #202 | open |

### PR なし（保持）
| ブランチ |
|---------|
| experiment/local-only |

削除しますか？ (Y/n)
```

**表示例（with-pr モード）:**

```
## 🧹 Worktree クリーンアップ（with-pr モード）

### PR 作成済み（削除対象）
| ブランチ | PR | 状態 |
|---------|-----|------|
| feature/foo-issue-123 | #200 | merged |
| feature/baz-issue-789 | #202 | open |

### PR なし（保持）
| ブランチ |
|---------|
| experiment/local-only |

削除しますか？ (Y/n)
```

削除対象がない場合は「クリーンアップ対象の worktree はありません。」と現在の worktree 一覧を表示して終了。

### 4. ユーザー確認後、一括削除

ユーザーが承認した場合、対象ブランチを1コマンドで削除する。

**merged モード:**

```bash
wt list --format=json | jq -r '.[] | select(.is_main == false) | .branch' | while read b; do
  [ "$(gh pr list --state merged --head "$b" --repo "$REPO" --json number --jq 'length')" -gt 0 ] && wt remove "$b"
done
```

**with-pr モード:**

```bash
wt list --format=json | jq -r '.[] | select(.is_main == false) | .branch' | while read b; do
  [ "$(gh pr list --state all --head "$b" --repo "$REPO" --json number --jq 'length')" -gt 0 ] && wt remove "$b"
done
```

### 5. 結果報告

```
✅ <N> worktree を削除しました
- <ブランチ名1>
- <ブランチ名2>
```
