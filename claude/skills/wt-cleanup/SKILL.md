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
- **shell は zsh であること**（`typeset -A`、連想配列キー展開 `${(k)assoc[@]}` など zsh 固有構文を使用するため、bash では動作しない）

## 削除モード

ユーザーの意図に応じて削除対象を切り替える:

| モード | 削除対象 | 判定条件 |
|--------|---------|---------|
| **merged**（デフォルト） | マージ済み PR の worktree | `gh pr list --state merged` が 1件以上 |
| **with-pr** | PR 作成済みの worktree（状態問わず） | `gh pr list --state all` が 1件以上 |

- 明示的な指定がなければ **merged** モード
- 「PR作成済みを削除」「PR があるものを消したい」等の指示があれば **with-pr** モード

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

### 2. PR ステータス + 保護状態の一括検出

各非 main worktree について PR 状態と保護状態を検出する。

まず保護判定用の連想配列を初期化する:

```bash
typeset -A PROTECTED_REASON
typeset -A PR_NUMBER
typeset -A MERGED_DATE
typeset -a TARGET_BRANCHES
typeset -a UNMERGED_BRANCHES
typeset -a NO_PR_BRANCHES
```

各ブランチのループ処理:

```bash
while IFS=$'\t' read -r BRANCH WT_PATH; do

  # ---- 保護判定 (uncommitted) ----
  PORCELAIN=$(git -C "$WT_PATH" status --porcelain 2>/dev/null)
  STATUS_RC=$?

  # git status 失敗時は fail-safe で保護扱い（spec §9）
  if [ "$STATUS_RC" -ne 0 ]; then
    PROTECTED_REASON[$BRANCH]="git status 失敗 (fail-safe)"
    continue
  fi

  # uncommitted ファイル数（空文字列ならゼロ）
  if [ -z "$PORCELAIN" ]; then
    UNCOMMITTED=0
  else
    UNCOMMITTED=$(echo "$PORCELAIN" | wc -l | tr -d ' ')
  fi

  # ---- 保護判定 (upstream 未設定 / 未 push commits) ----
  # 先に upstream の有無を判定する。未設定の場合は「未push」として保護扱いにする
  # （まだ remote に存在しないコミットを失わないため）
  if git -C "$WT_PATH" rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
    UPSTREAM_SET=true
    UNPUSHED=$(git -C "$WT_PATH" rev-list @{u}..HEAD --count 2>/dev/null)
    [ -z "$UNPUSHED" ] && UNPUSHED=0
  else
    UPSTREAM_SET=false
    UNPUSHED=0
  fi

  # ---- 保護理由を蓄積 ----
  REASONS=""
  if [ "$UNCOMMITTED" -gt 0 ]; then
    REASONS="uncommitted: ${UNCOMMITTED} files"
  fi
  if [ "$UPSTREAM_SET" = "false" ]; then
    [ -n "$REASONS" ] && REASONS="${REASONS} / "
    REASONS="${REASONS}upstream 未設定 (未 push)"
  elif [ "$UNPUSHED" -gt 0 ]; then
    [ -n "$REASONS" ] && REASONS="${REASONS} / "
    REASONS="${REASONS}未 push: ${UNPUSHED} commits"
  fi

  if [ -n "$REASONS" ]; then
    PROTECTED_REASON[$BRANCH]="$REASONS"
    # 保護対象は削除候補から除外（後続で force 判定）
    continue
  fi

  # ---- PR ステータス取得 ----
  pr=$(gh pr list --state all --head "$BRANCH" --repo "$REPO" --json number,title,state,mergedAt --jq '.[0] // empty')
  if [ -n "$pr" ]; then
    PR_NUM=$(echo "$pr" | jq -r '.number')
    PR_STATE=$(echo "$pr" | jq -r '.state')
    MERGED_AT=$(echo "$pr" | jq -r '.mergedAt // ""')

    PR_NUMBER[$BRANCH]="#${PR_NUM}"
    [ -n "$MERGED_AT" ] && MERGED_DATE[$BRANCH]="${MERGED_AT:0:10}"

    if [ "$PR_STATE" = "MERGED" ]; then
      # merged モードの削除対象
      TARGET_BRANCHES+=("$BRANCH")
    elif [ "$MODE" = "with-pr" ]; then
      # with-pr モードなら open/closed も削除対象
      TARGET_BRANCHES+=("$BRANCH")
    else
      UNMERGED_BRANCHES+=("$BRANCH")
    fi
  else
    NO_PR_BRANCHES+=("$BRANCH")
  fi
done < <(wt list --format=json | jq -r '.[] | select(.is_main == false) | [.branch, .path] | @tsv')
```

> **エラーハンドリング**（spec §9）:
> - `git status` が失敗 → そのブランチを保護扱い（PROTECTED_REASON にマーク）、処理は継続
> - `@{u}` 未設定 → 「upstream 未設定 (未 push)」として保護扱い（remote にコミットが存在しないため、削除すると差分を失う可能性がある）
> - `gh pr list` 失敗 → 既存挙動踏襲（該当ブランチを「PR なし」扱い、処理継続）。**全 worktree について `gh pr list` が失敗した場合のみ中断**

### 3. 結果の 4 カテゴリ分類と表示

ステップ 2 の出力を以下の 4 カテゴリに分類して表示する:
- **削除対象**: `state == "MERGED"`（merged モード）または PR あり（with-pr モード）
- **保護**: uncommitted or 未 push → 既定では削除しない
- **未マージ（保持）**: `state == "OPEN"` or `state == "CLOSED"`（merged モード時）
- **PR なし（保持）**: PR が存在しない

```bash
echo "## 🧹 Worktree クリーンアップ（${MODE} モード）"
echo ""

# 削除対象カテゴリ
echo "### ✅ 削除対象"
if [ ${#TARGET_BRANCHES[@]} -eq 0 ]; then
  echo "（なし）"
else
  echo "| ブランチ | PR | マージ日 |"
  echo "|---------|-----|---------|"
  for branch in "${TARGET_BRANCHES[@]}"; do
    pr="${PR_NUMBER[$branch]:--}"
    merged="${MERGED_DATE[$branch]:--}"
    echo "| $branch | $pr | $merged |"
  done
fi

# 保護カテゴリ（新規）
echo ""
echo "### 🛡️ 保護（uncommitted or 未 push）"
if [ ${#PROTECTED_REASON[@]} -eq 0 ]; then
  echo "（なし）"
else
  echo "| ブランチ | PR | マージ日 | 保護理由 |"
  echo "|----------|----|----------|----------|"
  for branch in "${(k)PROTECTED_REASON[@]}"; do
    pr_display="${PR_NUMBER[$branch]:--}"
    date_display="${MERGED_DATE[$branch]:--}"
    reason="${PROTECTED_REASON[$branch]}"
    echo "| $branch | $pr_display | $date_display | ⚠️ $reason |"
  done
fi

# 未マージカテゴリ（merged モード時のみ表示）
if [ "$MODE" = "merged" ] && [ ${#UNMERGED_BRANCHES[@]} -gt 0 ]; then
  echo ""
  echo "### ⏳ 未マージ（保持）"
  echo "| ブランチ | PR | 状態 |"
  echo "|---------|-----|------|"
  for branch in "${UNMERGED_BRANCHES[@]}"; do
    pr="${PR_NUMBER[$branch]:--}"
    echo "| $branch | $pr | open/closed |"
  done
fi

# PR なしカテゴリ
if [ ${#NO_PR_BRANCHES[@]} -gt 0 ]; then
  echo ""
  echo "### 📦 PR なし（保持）"
  echo "| ブランチ |"
  echo "|---------|"
  for branch in "${NO_PR_BRANCHES[@]}"; do
    echo "| $branch |"
  done
fi

# 操作案内 + 早期終了判定
DELETE_COUNT=${#TARGET_BRANCHES[@]}
PROTECT_COUNT=${#PROTECTED_REASON[@]}
echo ""
echo "### 操作"

if [ "$DELETE_COUNT" -eq 0 ]; then
  if [ "$FORCE" = "true" ] && [ "$PROTECT_COUNT" -gt 0 ]; then
    # force モードでは Step 5 で保護対象を削除候補に統合するため、ここでは終了しない
    echo "- ⚠️ 通常削除対象 0 件 / 保護対象 ${PROTECT_COUNT} 件 → force により Step 5 で削除候補へ統合します"
  else
    echo "クリーンアップ対象の worktree はありません。"
    if [ "$PROTECT_COUNT" -gt 0 ]; then
      echo "- 🛡️ 保護対象 ${PROTECT_COUNT} 件を削除するには \`/wt-cleanup force\` を再実行してください"
    fi
    # 削除対象が無く force でも保護を取り込まないため、dry-run の有無に関わらず即時終了
    exit 0
  fi
elif [ "$PROTECT_COUNT" -gt 0 ] && [ "$FORCE" != "true" ]; then
  echo "- 🛡️ 保護対象 ${PROTECT_COUNT} 件を削除するには \`/wt-cleanup force\` を再実行してください"
fi
```

削除対象が 0 件かつ force で保護を取り込まないケースは、dry-run の有無に関わらずこの時点で `exit 0` する。
これにより「削除対象なし」と「dry-run のためスキップ」が同時に表示される冗長を避ける。

### 4. dry-run 判定

`DRY_RUN=true` の場合、削除フェーズをスキップして終了する:

```bash
if [ "$DRY_RUN" = "true" ]; then
  echo ""
  echo "🔍 **dry-run のため削除をスキップしました**"
  echo "実削除するには \`dry-run\` 引数を外して再実行してください"
  exit 0
fi
```

`DRY_RUN=false` ならそのまま次のステップへ進む。

### 5. ユーザー確認後、削除実行

> **前提:** ステップ 4 で `DRY_RUN=true` ならここに到達しない（即時終了済み）。
> このステップは実削除モードでのみ実行される。

#### 確認プロンプトのフロー

通常モード（force なし）: 確認は **1 段階**
1. 削除対象 N 件の最終確認 (`AskUserQuestion`) → 「はい」で削除実行

force モード（保護対象あり）: 確認は **2 段階**
1. **1 段階目**: 保護対象を削除候補に統合する旨を表示し、「保護対象を削除候補に加えてよいか」を `AskUserQuestion` で確認
2. **2 段階目**: 統合後の全削除対象 N 件について最終確認を `AskUserQuestion` で再度取得

破壊的操作（uncommitted な変更や未 push commit を失う）は force 時にのみ発生するため、確認を 2 段階に分けることで「うっかり Y を押した」事故を防ぐ。

#### 実装

```bash
# ---- force=true: 1 段階目の確認 ----
# 保護対象を削除候補に統合する前に、保護内容の詳細とともに 1 段階目の確認を取る
if [ "$FORCE" = "true" ] && [ "${#PROTECTED_REASON[@]}" -gt 0 ]; then
  echo ""
  echo "## ⚠️ force モード: 保護対象を削除候補に統合します"
  echo "以下の worktree は uncommitted な変更 / 未 push commit を含みます。削除すると **これらの変更は失われます**。"
  echo ""
  echo "| ブランチ | 保護理由 |"
  echo "|---------|---------|"
  for branch in "${(k)PROTECTED_REASON[@]}"; do
    echo "| $branch | ⚠️ ${PROTECTED_REASON[$branch]} |"
  done

  # Claude へ: AskUserQuestion ツールで 1 段階目の確認を取る:
  #   質問文: 「⚠️ 保護対象 ${#PROTECTED_REASON[@]} 件を削除候補に統合します。これらの worktree のローカル変更・未 push commit は失われます。続行しますか?」
  #   選択肢: ["はい (削除候補に統合)", "いいえ (中断)"]
  # 「はい」が選ばれた場合のみ次の TARGET_BRANCHES への統合へ進む。
  # 「いいえ」または不明な選択: `echo "削除を中断しました"` を出力して `exit 0`。

  # 1 段階目の確認 OK の場合のみ削除候補に統合
  for branch in "${(k)PROTECTED_REASON[@]}"; do
    TARGET_BRANCHES+=("$branch")
  done
fi

# ---- 削除対象がゼロなら終了（防御的チェック） ----
# Step 3 の早期終了で通常はここに到達しないが、防御として残す
if [ ${#TARGET_BRANCHES[@]} -eq 0 ]; then
  echo "削除対象がありません。終了します。"
  exit 0
fi

# ---- 最終確認（force / 通常モード共通の最後の確認） ----
# Claude へ: AskUserQuestion ツールで最終確認を取る:
#   質問文: 「削除対象 ${#TARGET_BRANCHES[@]} 件を削除します。続行しますか?」
#   選択肢: ["はい (削除実行)", "いいえ (中断)"]
# 「はい」が選ばれた場合のみ削除ループへ進む。
# 「いいえ」または不明な選択: `echo "削除を中断しました"` を出力して `exit 0`。

# ---- 削除実行 ----
REMOVED=()
for b in "${TARGET_BRANCHES[@]}"; do
  if wt remove "$b"; then
    REMOVED+=("$b")
  else
    echo "❌ failed: $b" >&2
    # 失敗しても残り処理は継続（spec §9）
  fi
done
```

> **`wt remove` が失敗した場合**（spec §9）: エラー出力して残り worktree の処理を継続する。中断しない。

### 6. 結果報告

```
✅ <N> worktree を削除しました
- <ブランチ名1>
- <ブランチ名2>
```

```bash
echo ""
echo "✅ ${#REMOVED[@]} worktree を削除しました"
for b in "${REMOVED[@]}"; do
  echo "- $b"
done
```
