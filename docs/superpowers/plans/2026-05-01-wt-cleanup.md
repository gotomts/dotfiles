---
title: wt-cleanup スキル改修 (P2: A+B+D) Implementation Plan
date: 2026-05-01
status: draft
spec: docs/superpowers/specs/2026-05-01-wt-cleanup-design.md
---

# wt-cleanup スキル改修 (P2: A+B+D) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **For feature-team parent orchestrator:** This plan is consumed by Phase 2 (`create-issue`) which converts each Task into 1 sub-issue. Phase 4-A then dispatches `developer-generic` per sub-issue in parallel worktrees.

**Goal:** wt-cleanup スキルに dry-run モードと uncommitted/未push ガードを追加し、feature-team との責務分離を README で双方向参照する。

**Architecture:** SKILL.md (実行指示書) と README.md (保守者向け設計ドキュメント) の二層構造に移行。SKILL.md は引数を独立修飾子モデル (順序不問の `with-pr` / `dry-run` / `force` フラグ) で受け、6 ステップフローで実行する。検出ロジックは git CLI ベース (`status --porcelain` / `rev-list @{u}..HEAD --count`)、安全機構は fail-safe デフォルト + 明示的 `force` 解除 + 追加確認プロンプト。

**Tech Stack:** zsh shell コマンド (Claude が Markdown SKILL.md を読み Bash ツールで実行)、git CLI、gh CLI、worktrunk (`wt`) CLI、`AskUserQuestion` ツール。

**Spec:** [`docs/superpowers/specs/2026-05-01-wt-cleanup-design.md`](../specs/2026-05-01-wt-cleanup-design.md)

---

## File Structure

```
claude/skills/wt-cleanup/
├ SKILL.md      (改修: Task A + Task B が共同で触る)
└ README.md     (新規: Task D が単独作成)
```

**ファイルごとの責務:**

| パス | 責務 | 範囲外 |
|------|------|------|
| `SKILL.md` | Claude が読んで Bash で実行する自然言語フロー。引数パース → リポジトリ情報取得 → PR + 保護状態検出 → 4 カテゴリ分類表示 → dry-run 判定 → 削除実行 → 報告 の 6 ステップ | 設計判断の根拠、改修ガイド、テスト計画 |
| `README.md` | 保守者向け。TL;DR / 責務範囲 / feature-team 連携 (parent.md §7 双方向参照) / 安全機構 / 引数モデル 8 通り / 改修注意点 / 手動テストシナリオ S1〜S10 | 実行手順そのもの |

**サブタスク間の共有とコンフリクト管理:**

- A と B は同じ `SKILL.md` を編集する。Phase 4-A 並列開発では別 worktree なので並列起動は安全だが、merge 後の rebase が発生する
- 引数パーサ (3 フラグ全部) は **A/B 両方が同じコードを書く** ことで rebase 時の conflict を `with-pr` / `dry-run` / `force` の case 文整合チェックのみに限定
- 削除フェーズの分岐 (Step 5) は **A の dry-run 分岐と B の force 分岐が同じ if 文ツリーに入る** ため、merge 順序により conflict 発生。後続 merge 側は spec §6 のフロー図に従って統合

---

## Tasks

タスクは feature-team Phase 4-A で 1 sub-issue = 1 worktree に対応する単位で分割。実行順序の推奨は **D → A/B 並列**（D は独立で衝突なし、A/B は SKILL.md 共有のため後続 rebase）。

---

### Task D: README.md 新規作成 (D サブタスク)

**対応 AC:** AC-7, AC-8, AC-9
**Spec 参照:** §2.3, §11

**Files:**
- Create: `claude/skills/wt-cleanup/README.md`

- [ ] **Step D-1: 既存 README サンプル (feature-team) を参照して構造を把握**

Run:
```bash
ls -la /Users/goto/.dotfiles/claude/skills/feature-team/
cat /Users/goto/.dotfiles/claude/skills/feature-team/README.md | head -50
```
Expected: feature-team の README.md が `# Feature Team` 見出しで始まり、SKILL.md の保守者向け補完情報を持つことを確認。これを wt-cleanup README の構造ベースとする。

- [ ] **Step D-2: README.md を新規作成**

Create `claude/skills/wt-cleanup/README.md` with:

```markdown
# Worktree Cleanup — 設計ドキュメント (保守者向け)

## TL;DR

`SKILL.md` は Claude が読んで Bash で実行する指示書。本ファイルは **保守者向けの設計ガイド** であり、責務範囲・他スキルとの連携・安全機構の根拠・改修注意点を集約する。

スキル本体の使い方は `SKILL.md` を、対話的な実行例は親プロジェクトの `claude/CLAUDE.md` を参照。

## 1. 責務範囲

**担当する範囲:**

- PR 作成済み or マージ済みの worktree 検出
- ユーザー確認後の `wt remove` 実行
- uncommitted / 未 push 検出による fail-safe 保護

**スコープ外:**

- worktree の **作成** (これは `feature-team` 親 / `issue-dev` スキル / 手動 `wt switch -c` の責務)
- PR マージ前の早期クリーンアップ (PR ライフサイクル管理は GitHub / `pr-publisher` の責務)
- merge 戦略の検討 (merged モードと with-pr モードのみ対応、`older-than` 等の時間フィルタは YAGNI)

## 2. feature-team との連携 (双方向参照)

`feature-team/roles/parent.md` §7「親が **やってはいけない** こと」 に以下が明記されている:

> worktree を勝手に `wt remove` する (PR マージ後の cleanup は別途 `wt-cleanup` スキル)

これにより責務境界が確定する:

| 主体 | 責務 |
|------|------|
| `feature-team` 親オーケストレーター | sub-issue 単位で `wt switch -c` で worktree を **作成** する。作成後は触らない |
| `pr-publisher` サブエージェント | PR 作成 + push のみ。worktree は触らない |
| `wt-cleanup` スキル (本スキル) | PR マージ後の worktree **削除** を、user 確認 + 保護判定付きで実行 |

`parent.md` §7 は **無改修を基本** とし、本 README が wt-cleanup 側からの参照点となる (双方向参照は wt-cleanup 側に集約することで、feature-team 側の文書負荷を増やさない)。

## 3. 安全機構

3 段階の safety net:

**3.1 確認プロンプト (既存)**
削除実行前に `AskUserQuestion` で「N 件削除しますか?」確認。N で即時終了。

**3.2 保護カテゴリ — uncommitted / 未 push 検出 (新規)**
各 worktree について `git status --porcelain` (uncommitted) と `git rev-list @{u}..HEAD --count` (未 push commits) を検査し、いずれか非空・正値なら「保護カテゴリ」へ分類。**既定では削除対象から除外** (fail-safe)。

**3.3 force 引数によるガード解除 + 追加確認 (新規)**
`/wt-cleanup force` を実行すると保護対象も削除候補に統合し、最終確認プロンプト「**保護対象 N 件を削除します。ローカル変更が失われます。続行しますか?**」を経て削除する。

## 4. 引数モデル — 独立修飾子

3 種の独立修飾子を 0〜3 個、順序不問・空白区切りで受ける:

| 修飾子 | 意味 | 既定 |
|--------|------|------|
| `with-pr` | PR 作成済み全件 (状態問わず) を削除対象 | `merged` (マージ済みのみ) |
| `dry-run` | 実削除フェーズをスキップ | 実削除する |
| `force` | uncommitted / 未 push 検出による保護を解除 | ガード有効 |

全 8 通り組み合わせ:

| 引数 | 動作 |
|------|------|
| (なし) | merged + 実削除 + ガード有効 |
| `with-pr` | with-pr + 実削除 + ガード有効 |
| `dry-run` | merged + dry-run + ガード有効 |
| `with-pr dry-run` | with-pr + dry-run + ガード有効 |
| `force` | merged + 実削除 + ガード解除 |
| `with-pr force` | with-pr + 実削除 + ガード解除 |
| `dry-run force` | merged + dry-run + ガード解除 (force 効果プレビュー) |
| `with-pr dry-run force` | with-pr + dry-run + ガード解除 |

未知引数は **明示エラー + exit 1** で silent ignore しない。`dry-rum` のような typo を silent ignore すると、ユーザーは「dry-run 動作中」と誤認して実削除に進むリスクがある。

## 5. 改修するときの注意点

### 5.1 SKILL.md 変更前に

- 既存の 6 ステップフロー (リポ取得 → PR + 保護検出 → 4 カテゴリ表示 → dry-run 判定 → 削除実行 → 報告) を保持しているか確認
- 引数パーサ (5.2.1) の case 文に新規修飾子を追加する場合、本 README §4 の表も更新する (両方が同期している必要)
- 検出ロジック (`git status --porcelain` / `git rev-list @{u}..HEAD --count`) のエラー時挙動を変更する場合、§3.2 の fail-safe 原則を維持する

### 5.2 README.md 変更前に

- §1 責務範囲を変える場合は `feature-team/roles/parent.md` §7 との整合を確認 (新責務が parent.md と矛盾しないか)
- §2 連携テーブルの主体を増やす場合は、その主体側のドキュメントにも本 README への参照を追加 (双方向)
- §4 引数モデル表を変える場合は SKILL.md の引数パーサ実装と必ず同期

### 5.3 parent.md §7 と整合確認

`feature-team` 側のリファクタで §7 の文言が変わった場合、本 README §2 の引用も更新する。引用ずれを検出するため、変更時は両ファイルを並べて diff 確認すること。

### 5.4 引数組み合わせ追加時の影響範囲

新修飾子を追加する場合、以下を全て更新:

1. SKILL.md §引数パーサ (case 文に追加)
2. SKILL.md §使用例
3. 本 README §4 表 (8 通り → 16 通り 等)
4. 本 README §6 手動テストシナリオ (新シナリオ追加)
5. spec の AC 追加検討

## 6. 手動テスト シナリオ

zsh script 自動テスト基盤 (bats-core 等) はスコープ外。各シナリオは worktree を準備し、`/wt-cleanup [引数]` を実行して期待出力を目視確認する:

- **S1**: merged モード基本動作 — マージ済み worktree のみ削除候補として表示・実削除
- **S2**: with-pr モード基本動作 — PR 作成済み全件 (open/closed/merged) が削除候補
- **S3**: dry-run — 削除候補表示は通常と同じ、削除フェーズで「dry-run のため削除をスキップしました」表示・実削除なし
- **S4**: ガード uncommitted — 1 worktree で `touch new-file.tmp` し、保護カテゴリに「⚠️ uncommitted: 1 files」表示
- **S5**: ガード 未 push — 1 worktree で `git commit --allow-empty -m wip` し、保護カテゴリに「⚠️ 未 push: 1 commits」表示
- **S6**: force — 保護対象を含むケースで `/wt-cleanup force` 実行 → 統合表示 → 追加確認プロンプト「保護対象 N 件を削除します。ローカル変更が失われます。続行しますか?」→ Y で削除実行
- **S7**: dry-run + force — `/wt-cleanup dry-run force` で保護解除済み削除候補が表示、追加確認なし、実削除なし
- **S8**: 修飾子順序自由 — `with-pr force dry-run` と `dry-run with-pr force` で同等動作
- **S9**: 全件保護 — 全 worktree が保護対象になる状況で「クリーンアップ対象なし」表示
- **S10**: ネットワーク断 — `gh pr list` を失敗させ (例: `unset GH_TOKEN` で認証失効)、エラー表示後も処理継続を確認

将来の自動化候補: bats-core での S1〜S10 ゴールデンテスト化を検討 (現状は YAGNI でスコープ外)。
```

- [ ] **Step D-3: README 内部整合性をセルフレビュー**

Run:
```bash
# §4 引数表が 8 通りすべて含むか確認
grep -c "^|" claude/skills/wt-cleanup/README.md
# §6 シナリオが S1〜S10 すべて含むか確認
grep -c "^- \*\*S[0-9]" claude/skills/wt-cleanup/README.md
```
Expected:
- §4 表行数 ≥ 16 行 (修飾子表 4 行 + 引数組み合わせ表 9 行 + その他)
- §6 シナリオ 10 件 (S1〜S10)

差分があれば README.md を Edit で修正してから次へ進む。

- [ ] **Step D-4: 双方向参照の整合確認**

Run:
```bash
grep -n "wt-cleanup" /Users/goto/.dotfiles/claude/skills/feature-team/roles/parent.md
grep -n "parent.md" claude/skills/wt-cleanup/README.md
```
Expected:
- parent.md §7 に `wt-cleanup` への参照が存在する (既存)
- README.md §2 に `parent.md §7` への参照が存在する (Step D-2 で記述)

参照が成立していることを確認 (AC-7 達成)。`parent.md` 側は無改修 (AC-9: 「無改修を基本とし、必要な場合でも 1 行リンク追加に留める」)。

- [ ] **Step D-5: コミット**

```bash
git add claude/skills/wt-cleanup/README.md
git commit -m "feat(wt-cleanup): 保守者向け README.md を新規作成

feature-team parent.md §7 との責務分離・双方向参照を明示。
- §1 責務範囲 (PR マージ後 cleanup のみ、worktree 作成は範囲外)
- §2 feature-team / pr-publisher との連携テーブル
- §3 安全機構 3 段階 (確認 / 保護カテゴリ / force 追加確認)
- §4 独立修飾子モデル 8 通り
- §5 改修注意点 (4 ファイル同期ルール)
- §6 手動テストシナリオ S1〜S10"
```

---

### Task A: dry-run モード追加 (A サブタスク)

**対応 AC:** AC-1, AC-2, AC-10 (部分)
**Spec 参照:** §2.1, §5.2, §5.2.1, §6 (新規ステップ 4), §8.2

**Files:**
- Modify: `claude/skills/wt-cleanup/SKILL.md`

- [ ] **Step A-1: 現状の SKILL.md を読み込み引数パース箇所を特定**

Run:
```bash
cat /Users/goto/.dotfiles/claude/skills/wt-cleanup/SKILL.md | head -60
grep -n "with-pr" /Users/goto/.dotfiles/claude/skills/wt-cleanup/SKILL.md
```
Expected: 既存の引数判定箇所 (例えば「`with-pr` モード判定」のセクション or 該当 bash 行) を特定。現状は固定 case 文 or 単純 `if` で `with-pr` を扱っているはず。

- [ ] **Step A-2: 期待挙動を確認 (現状で dry-run なしであることを実演)**

Run (現状の baseline):
```bash
# main 以外の worktree が 1 個以上ある状態で
/wt-cleanup
```
Expected: `dry-run` 引数を渡せない (受け付けても無視される or エラー)、削除候補が表示されたら実削除フェーズへ進む。

これにより「dry-run なし」の現状挙動を確認する (TDD 代替: 現状の fail を実演)。

- [ ] **Step A-3: SKILL.md の引数パース箇所を独立修飾子モデルへ書き換え (3 フラグ全部実装)**

SKILL.md の冒頭 (リポジトリ情報取得の前) に以下のステップを **新規ステップ 0** または **既存ステップ 1 の前段** として挿入:

````markdown
## 0. 引数の解釈

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

未知引数は明示エラー + `exit 1`。silent ignore は禁止 (typo 誤認による予期せぬ削除を防ぐ)。
````

> **Note:** 既存 SKILL.md に `with-pr` 判定の固定コードがある場合は、それを上記の for ループに統合して置き換える (重複を残さない)。

- [ ] **Step A-4: SKILL.md にステップ 4「dry-run 判定」を新規挿入**

既存の「結果分類と表示」ステップ (= 新ステップ 3) の後、削除実行ステップ (= 新ステップ 5) の前に以下を挿入:

````markdown
## 4. dry-run 判定

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
````

- [ ] **Step A-5: SKILL.md ステップ 5 (削除実行) は dry-run 分岐済み前提に整理**

ステップ 5 冒頭に以下を明記:

```markdown
> **前提:** ステップ 4 で `DRY_RUN=true` ならここに到達しない (即時終了済み)。
> このステップは実削除モードでのみ実行される。
```

既存の `wt remove "$b"` ループは変更しない (force 分岐は Task B で追加されるが、本タスクは触らない)。

- [ ] **Step A-6: 動作確認 — dry-run 単独**

Run (worktree 内で SKILL.md を Bash 直接実行):
```bash
# 既存ステップを順次実行する形で
zsh -c '
MODE=merged
DRY_RUN=false
FORCE=false

for arg in dry-run; do
  case "$arg" in
    with-pr) MODE=with-pr ;;
    dry-run) DRY_RUN=true ;;
    force)   FORCE=true ;;
    *) echo "Unknown: $arg" >&2; exit 1 ;;
  esac
done

echo "Mode: $MODE / Dry-run: $DRY_RUN / Force: $FORCE"

if [ "$DRY_RUN" = true ]; then
  echo "skip delete"
fi
'
```
Expected output:
```
Mode: merged / Dry-run: true / Force: false
skip delete
```

- [ ] **Step A-7: 動作確認 — 修飾子順序不問**

Run:
```bash
zsh -c '
for args in "with-pr dry-run" "dry-run with-pr" "dry-run force with-pr" "force dry-run with-pr"; do
  MODE=merged; DRY_RUN=false; FORCE=false
  for arg in $(echo $args); do
    case "$arg" in
      with-pr) MODE=with-pr ;;
      dry-run) DRY_RUN=true ;;
      force)   FORCE=true ;;
      *) echo "Unknown: $arg" >&2; exit 1 ;;
    esac
  done
  echo "[$args] => Mode=$MODE Dry=$DRY_RUN Force=$FORCE"
done
'
```
Expected: 4 つの順序すべてで `Mode=with-pr Dry=true Force=true` (3 番目以降) または期待状態 (1, 2 番目)。AC-10 部分達成 (developer 自スコープ内確認)。

- [ ] **Step A-8: 動作確認 — 未知引数で明示エラー**

Run:
```bash
zsh -c '
MODE=merged; DRY_RUN=false; FORCE=false
for arg in dry-rum; do
  case "$arg" in
    with-pr) MODE=with-pr ;;
    dry-run) DRY_RUN=true ;;
    force)   FORCE=true ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done
echo "should not reach here"
'
echo "exit code: $?"
```
Expected:
```
Unknown argument: dry-rum
exit code: 1
```
"should not reach here" は出力されない。typo silent ignore がないことを確認。

- [ ] **Step A-9: コミット**

```bash
git add claude/skills/wt-cleanup/SKILL.md
git commit -m "feat(wt-cleanup): dry-run モードを追加

独立修飾子モデルの引数パーサ (with-pr / dry-run / force 全 3 フラグ) と
ステップ 4 dry-run 判定を新規実装。実削除フェーズ前に DRY_RUN=true なら
即時終了。未知引数は silent ignore せず明示エラー + exit 1。

force フラグは引数として受けるが本タスクでは何もしない (Task B で実装)。"
```

---

### Task B: uncommitted / 未 push ガード強化 (B サブタスク)

**対応 AC:** AC-3, AC-4, AC-5, AC-6, AC-10 (部分)
**Spec 参照:** §2.2, §5.2, §5.2.1, §6 (ステップ 2 / 3 / 5 改修), §7, §8.1, §8.3, §9

**Files:**
- Modify: `claude/skills/wt-cleanup/SKILL.md`

- [ ] **Step B-1: 現状の SKILL.md を読み込み既存検出 / 削除箇所を特定**

Run:
```bash
cat /Users/goto/.dotfiles/claude/skills/wt-cleanup/SKILL.md | head -150
grep -n "wt remove" /Users/goto/.dotfiles/claude/skills/wt-cleanup/SKILL.md
grep -n "gh pr list" /Users/goto/.dotfiles/claude/skills/wt-cleanup/SKILL.md
```
Expected: 既存の PR 検出箇所 (`gh pr list`) と削除箇所 (`wt remove`) を特定。現状は無条件 `wt remove "$b"` for ループ。

- [ ] **Step B-2: 現状で uncommitted を破壊することを実演 (TDD 代替: fail 確認)**

Run (実害を出さないため使い捨て worktree で):
```bash
# 安全のため別場所で再現
cd /tmp
mkdir wt-test && cd wt-test
git init -q && git commit --allow-empty -m init -q
wt switch -c experiment/uncommitted-loss
echo "important work" > unsaved.txt
# uncommitted 状態。現状の wt remove は確認なしで削除する
# 注: ここでは実削除せず、想定挙動のみ確認
echo "現状: wt remove $(pwd) を実行すると unsaved.txt が失われる (検出ロジックなし)"
```
これにより「現状: 検出ロジックなし → 破壊リスクあり」を確認する (TDD 代替)。

- [ ] **Step B-3: 引数パース箇所を独立修飾子モデルへ書き換え (3 フラグ全部実装、Task A と同コード)**

> **Note:** Task A と **同じ for ループパターン** で 3 フラグ (`with-pr` / `dry-run` / `force`) すべての case を実装する。これにより Phase 4-A の merge 順序によらず単独動作可能、後続側は rebase で `git checkout --theirs` 等で簡単解決できる。

SKILL.md 冒頭 (リポジトリ情報取得の前) に以下を新規ステップ 0 として挿入:

````markdown
## 0. 引数の解釈

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
````

> **本タスクで使うのは `MODE` と `FORCE`**。`DRY_RUN` は引数として受けるが本タスクでは何もしない (Task A で実装)。

- [ ] **Step B-4: SKILL.md ステップ 2 に保護状態検出ロジックを追加**

既存「PR ステータス取得」ステップに、各 worktree への保護判定を追加。spec §7.1 の bash コードを直接組み込む:

````markdown
## 2. PR ステータス + 保護状態の一括検出

各非 main worktree について以下を実行:

```bash
# wt list の出力を per-line で解析
# 例: "feature/foo /path/to/wt feature/foo HEAD"
while IFS= read -r line; do
  WT_PATH=$(echo "$line" | awk '{print $2}')
  BRANCH=$(echo "$line" | awk '{print $3}')

  # main は除外
  [ "$BRANCH" = "main" ] && continue

  # 保護判定 (uncommitted)
  UNCOMMITTED=$(git -C "$WT_PATH" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  STATUS_RC=$?

  # git status 失敗時は fail-safe で保護扱い (spec §9)
  if [ "$STATUS_RC" -ne 0 ]; then
    PROTECTED_REASON[$BRANCH]="git status 失敗 (fail-safe)"
    continue
  fi

  # 保護判定 (未 push commits)
  UNPUSHED=$(git -C "$WT_PATH" rev-list @{u}..HEAD --count 2>/dev/null)
  if [ -z "$UNPUSHED" ]; then
    UNPUSHED=0   # @{u} 未設定の場合
  fi

  # 保護理由を蓄積
  REASONS=""
  if [ "$UNCOMMITTED" -gt 0 ]; then
    REASONS="uncommitted: $UNCOMMITTED files"
  fi
  if [ "$UNPUSHED" -gt 0 ]; then
    [ -n "$REASONS" ] && REASONS="$REASONS / "
    REASONS="${REASONS}未 push: $UNPUSHED commits"
  fi

  if [ -n "$REASONS" ]; then
    PROTECTED_REASON[$BRANCH]="$REASONS"
  fi
done < <(wt list --format=plain | tail -n +2)
```

> **エラーハンドリング** (spec §9):
> - `git status` が失敗 → そのブランチを保護扱い (PROTECTED_REASON にマーク)、処理は継続
> - `@{u}` 未設定 → `UNPUSHED=0` 扱い (削除対象は PR 経由なので upstream 設定済みが前提)
> - `gh pr list` 失敗 → 既存挙動踏襲 (該当ブランチを「PR なし」扱い、処理継続)。**全 worktree について `gh pr list` が失敗した場合のみ中断**
````

> **Note:** 既存 SKILL.md の PR 取得ループに上記の保護判定を統合する。重複ループを残さないよう注意。

- [ ] **Step B-5: SKILL.md ステップ 3 に「保護」カテゴリを追加**

既存の 3 カテゴリ表示 (削除対象 / 未マージ / PR なし) に **🛡️ 保護** カテゴリを追加。spec §8.1 の表示フォーマットに従う:

````markdown
## 3. 結果の 4 カテゴリ分類と表示

```
## 🧹 Worktree クリーンアップ (${MODE} モード)

### ✅ 削除対象 (マージ済み or PR 作成済み)
| ブランチ | PR | マージ日 |
| ... |

### 🛡️ 保護 (uncommitted or 未 push)
| ブランチ | PR | マージ日 | 保護理由 |
| feature/bar-issue-456 | #201 | 2026-04-15 | ⚠️ 未 push: 3 commits |
| feature/baz-issue-789 | #203 | 2026-04-16 | ⚠️ uncommitted: 5 files |

### ⏳ 未マージ (保持)
| ... |

### 📦 PR なし (保持)
| ... |
```

実装:

```bash
echo "## 🧹 Worktree クリーンアップ ($MODE モード)"
echo ""

# 削除対象カテゴリ (既存)
echo "### ✅ 削除対象"
# ... 既存ループ ...

# 保護カテゴリ (新規)
echo ""
echo "### 🛡️ 保護 (uncommitted or 未 push)"
echo "| ブランチ | PR | マージ日 | 保護理由 |"
echo "|---------|-----|---------|---------|"
for branch in "${!PROTECTED_REASON[@]}"; do
  reason="${PROTECTED_REASON[$branch]}"
  pr="${PR_NUMBER[$branch]:--}"
  merged="${MERGED_DATE[$branch]:--}"
  echo "| $branch | $pr | $merged | ⚠️ $reason |"
done

# 未マージ / PR なしカテゴリ (既存)
# ...

# 操作案内
DELETE_COUNT=${#TARGET_BRANCHES[@]}
PROTECT_COUNT=${#PROTECTED_REASON[@]}
echo ""
echo "### 操作"
echo "- 削除対象 $DELETE_COUNT 件を削除しますか? (Y/n)"
if [ "$PROTECT_COUNT" -gt 0 ] && [ "$FORCE" != true ]; then
  echo "- 🛡️ 保護対象 $PROTECT_COUNT 件を削除するには \`/wt-cleanup force\` を再実行してください"
fi
```
````

- [ ] **Step B-6: SKILL.md ステップ 5 (削除実行) に force 分岐を追加**

force=true のときに保護対象を削除候補に統合し、追加確認後に削除する。spec §8.3 のプロンプトに従う:

````markdown
## 5. ユーザー確認後、削除実行

> **前提:** ステップ 4 で `DRY_RUN=true` ならここに到達しない (Task A で実装)。

```bash
# force=true なら保護対象を削除候補に統合
if [ "$FORCE" = true ] && [ ${#PROTECTED_REASON[@]} -gt 0 ]; then
  echo ""
  echo "## ⚠️ force モード: 保護対象を削除候補に統合"
  echo "| ブランチ | 保護理由 |"
  echo "|---------|---------|"
  for branch in "${!PROTECTED_REASON[@]}"; do
    echo "| $branch | ⚠️ ${PROTECTED_REASON[$branch]} |"
    TARGET_BRANCHES+=("$branch")
  done

  # 追加確認 (AskUserQuestion ツール使用)
  # 親 Claude が AskUserQuestion で
  # 「🛡️ 保護対象 ${#PROTECTED_REASON[@]} 件を削除します。ローカル変更が失われます。続行しますか?」
  # を表示し、Y を確認してから次へ
fi

# 削除実行
for b in "${TARGET_BRANCHES[@]}"; do
  if wt remove "$b"; then
    echo "✅ removed: $b"
  else
    echo "❌ failed: $b" >&2
    # 失敗しても残り処理は継続 (spec §9)
  fi
done
```

> **`wt remove` が失敗した場合** (spec §9): エラー出力して残り worktree の処理を継続する。中断しない。
````

- [ ] **Step B-7: 動作確認 — 保護検出 (uncommitted)**

Run (使い捨て git repo で):
```bash
cd /tmp
rm -rf wt-cleanup-test
mkdir wt-cleanup-test && cd wt-cleanup-test
git init -q && git commit --allow-empty -m init -q

# uncommitted を作る
echo "wip" > new.txt

# 検出ロジックを直接実行
UNCOMMITTED=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
echo "uncommitted: $UNCOMMITTED files"
```
Expected:
```
uncommitted: 1 files
```

- [ ] **Step B-8: 動作確認 — 保護検出 (未 push)**

Run:
```bash
cd /tmp/wt-cleanup-test
git add new.txt && git commit -m wip -q

# 未 push 検出 (upstream 未設定なら 0 扱い)
UNPUSHED=$(git rev-list @{u}..HEAD --count 2>/dev/null)
[ -z "$UNPUSHED" ] && UNPUSHED=0
echo "unpushed: $UNPUSHED commits"
```
Expected:
```
unpushed: 0 commits
```
(upstream 未設定なので 0、これは想定通り。実 worktree では upstream 設定済み前提で N>0 になる)

- [ ] **Step B-9: 動作確認 — fail-safe (git status エラー)**

Run:
```bash
# git ではないディレクトリで status 失敗を再現
cd /tmp
mkdir not-a-repo && cd not-a-repo

UNCOMMITTED=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
STATUS_RC=$?
echo "rc: $STATUS_RC, uncommitted: $UNCOMMITTED"
if [ "$STATUS_RC" -ne 0 ]; then
  echo "→ 保護扱い (fail-safe)"
fi
```
Expected:
```
rc: 128, uncommitted: 0
→ 保護扱い (fail-safe)
```
git status 失敗時に保護扱いになることを確認 (AC-6 fail-safe 達成)。

- [ ] **Step B-10: 動作確認 — force 分岐 (dry-run + force で安全確認)**

Run:
```bash
zsh -c '
MODE=merged; DRY_RUN=true; FORCE=true
declare -A PROTECTED_REASON
PROTECTED_REASON[feature/test]="uncommitted: 2 files"

if [ "$FORCE" = true ] && [ ${#PROTECTED_REASON[@]} -gt 0 ]; then
  echo "## ⚠️ force モード: 保護対象を削除候補に統合"
  for branch in "${!PROTECTED_REASON[@]}"; do
    echo "| $branch | ⚠️ ${PROTECTED_REASON[$branch]} |"
  done
fi
'
```
Expected:
```
## ⚠️ force モード: 保護対象を削除候補に統合
| feature/test | ⚠️ uncommitted: 2 files |
```

- [ ] **Step B-11: コミット**

```bash
git add claude/skills/wt-cleanup/SKILL.md
git commit -m "feat(wt-cleanup): uncommitted/未push ガード強化 (保護カテゴリ + force)

各非 main worktree で git status --porcelain と git rev-list @{u}..HEAD --count
を実行し、いずれか非空・正値なら『保護カテゴリ』として 4 カテゴリ表示に追加。
既定では削除対象から除外 (fail-safe)。force 引数で保護対象を削除候補に統合し、
追加確認プロンプト『保護対象 N 件を削除します。ローカル変更が失われます』を経て削除。

エラーハンドリング (spec §9):
- git status 失敗 → 該当ブランチを保護扱い (fail-safe)
- @{u} 未設定 → UNPUSHED=0 扱い
- wt remove 失敗 → 残り処理を継続 (中断しない)

dry-run フラグは引数として受けるが本タスクでは何もしない (Task A で実装)。"
```

---

## Self-Review

### Spec Coverage

| Spec 要素 | 担当タスク | 担当 Step |
|----------|-----------|-----------|
| §2.1 dry-run モード | Task A | A-3 (引数パーサ), A-4 (ステップ 4 挿入), A-5 (ステップ 5 整理) |
| §2.2 uncommitted/未 push ガード | Task B | B-3 (引数パーサ), B-4 (検出), B-5 (表示), B-6 (force 分岐) |
| §2.3 parent.md §7 連携文書化 | Task D | D-2 (README 作成), D-4 (双方向参照確認) |
| §5.1 二層構造 | Task D | D-2 (README 新規) |
| §5.2 引数モデル 8 通り | Task A + B | A-3 / B-3 (3 フラグ実装) |
| §5.2.1 引数パーサ実装方針 | Task A + B | A-3 / B-3 (for ループ + 未知引数 exit 1) |
| §6 データフロー 6 ステップ | Task A + B | A-4 (ステップ 4), B-4 (ステップ 2 改修), B-5 (ステップ 3 改修), B-6 (ステップ 5 改修) |
| §7 検出ロジック | Task B | B-4 (git status / rev-list) |
| §8.1 通常モード表示 | Task B | B-5 (4 カテゴリ表示) |
| §8.2 dry-run モード表示 | Task A | A-4 (「dry-run のため削除をスキップ」) |
| §8.3 force モード表示 | Task B | B-6 (force 統合 + 追加確認) |
| §9 エラーハンドリング | Task B | B-4 (git status fail-safe), B-6 (wt remove 継続) |
| §10 テスト戦略 | Task D | D-2 (README §6 シナリオ S1〜S10) |
| §11 README 構造 | Task D | D-2 |
| AC-1 (A) | Task A | A-6 |
| AC-2 (A) | Task A | A-7 |
| AC-3 (B) | Task B | B-7 |
| AC-4 (B) | Task B | B-8 |
| AC-5 (B) | Task B | B-10 + 親による S6 統合確認 |
| AC-6 (B) | Task B | B-9 |
| AC-7 (D) | Task D | D-4 |
| AC-8 (D) | Task D | D-2 (README に必須セクション全部) |
| AC-9 (D) | Task D | D-4 (parent.md 無改修確認) |
| AC-10 (横断) | A + B + 親 | A-7 / B-10 部分 + Phase 6 後の親による S8 統合確認 |

**カバレッジ判定:** spec の全 14 セクション + AC-1〜10 すべてに担当タスク・ステップが対応している。Gap なし。

### Placeholder Scan

検査対象: 「TBD」「TODO」「implement later」「Add appropriate error handling」「Similar to Task N」「Write tests for the above」

```bash
grep -n -E "TBD|TODO|implement later|fill in details|appropriate error handling|Similar to Task" docs/superpowers/plans/2026-05-01-wt-cleanup.md
```
Expected: 0 件マッチ

すべてのステップに具体的な code block / command / expected output が含まれている。

### Type / Method 一貫性

`MODE` / `DRY_RUN` / `FORCE` / `PROTECTED_REASON` / `TARGET_BRANCHES` の変数名・型は Task A / Task B で完全一致。`PROTECTED_REASON` は連想配列 (`declare -A`) を前提とし zsh / bash 4+ で動作する。

`wt list --format=plain | tail -n +2` の出力フィールド数 (4 列: branch / path / sha / additional) は worktrunk のドキュメントを Phase 4-A の developer agent が `wt list --help` で確認すること (Step B-4 内で実行可能)。

### Phase 4-A 並列実行への適性

- D は完全独立 → 単独 worktree で動く
- A と B は SKILL.md 共有 → merge 順序により後続側は rebase 必要 (spec §5.3 で明示済み)
- 引数パーサは A/B で完全同コード → rebase conflict が `with-pr` / `dry-run` / `force` の case 文整合チェックのみに限定
- 削除フェーズの dry-run 分岐 (A) と force 分岐 (B) は同じ if 文ツリーに入る → spec §6 のフロー図に従い親が rebase 統合判断

---

## 次のフェーズ

本 plan を Phase 2 (`Skill(create-issue, args="linear <spec-path> <plan-path>")`) に渡す。create-issue が以下を生成する想定:

- 親 Issue: P2 改修パッケージ (spec / plan へのリンク)
- Sub-issue × 3: Task D (README), Task A (dry-run), Task B (ガード強化)
- 各 sub-issue の本文に、対応する AC チェックリストを転記

その後 Phase 3 (ボリューム判定) → Phase 4-A (並列開発) → Phase 5 (レビュー、Task B は security 加算) → Phase 6 (pr-publisher 並列起動 → 3 PR + CodeRabbit) と進む。
