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

| モード | 削除対象 | 判定条件 |
|--------|---------|---------|
| **merged**（デフォルト） | マージ済み PR の worktree | `gh pr list --state merged` が 1件以上 |
| **with-pr** | PR 作成済みの worktree（状態問わず） | `gh pr list --state all` が 1件以上 |

## 実行フロー

### 0. 引数の解釈

ユーザーが `/wt-cleanup` に渡した引数を 3 種の独立修飾子としてパースする。順序不問、空白区切り。

```bash
MODE=merged
DRY_RUN=false
FORCE=false

for arg in "$@"; do
  case "$arg" in
    with-pr) MODE=with-pr ;;
    dry-run) DRY_RUN=true ;;
    force)   FORCE=true ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: /wt-cleanup [with-pr] [dry-run] [force]" >&2
      exit 1
      ;;
  esac
done

echo "Mode: $MODE / Dry-run: $DRY_RUN / Force: $FORCE"
```

未知引数は明示エラー + `exit 1`。silent ignore は禁止（typo 誤認による予期せぬ削除を防ぐ）。

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

### 4. dry-run 判定

`DRY_RUN=true` の場合、削除フェーズをスキップして終了する:

```bash
if [ "$DRY_RUN" = true ]; then
  echo ""
  echo "🔍 **dry-run のため削除をスキップしました**"
  echo "実削除するには \`dry-run\` 引数を外して再実行してください"
  exit 0
fi
```

`DRY_RUN=false` ならそのまま次のステップへ進む。

### 5. ユーザー確認後、一括削除

> **前提:** ステップ 4 で `DRY_RUN=true` ならここに到達しない（即時終了済み）。
> このステップは実削除モードでのみ実行される。

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

### 6. 結果報告

```
✅ <N> worktree を削除しました
- <ブランチ名1>
- <ブランチ名2>
```
