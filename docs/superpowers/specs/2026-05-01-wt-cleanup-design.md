---
title: wt-cleanup スキル改修設計 (P2: A+B+D)
date: 2026-05-01
status: draft
---

# wt-cleanup スキル改修設計 (P2: A+B+D)

## 1. 目的

既存の wt-cleanup スキルが抱える 3 つの課題を解消する:

1. **安全性**: 無条件で `wt remove` するため未 push のローカル変更を破壊するリスク
2. **UX**: 事前確認モード（dry-run）が確認プロンプト Y/n 以外に明示的なフォームで存在しない
3. **設計ドキュメント**: feature-team の親が **やってはいけない** こと §7（worktree を勝手に `wt remove` しない）との連携が wt-cleanup 側に書かれておらず、責務分離が双方向で文書化されていない

P2 = サブタスク 3 件:

- (A) dry-run モード追加
- (B) uncommitted/未 push ガード強化
- (D) parent.md §7 連携の文書化

## 2. 要件

### 2.1 A: dry-run モード

- ユーザーが `/wt-cleanup dry-run`（または `with-pr dry-run`）と打つと、既存フローの「結果分類と表示」までは通常通り実行し、削除フェーズ（`wt remove`）をスキップして「dry-run のため削除をスキップしました」を表示して終了できる
- dry-run は merged / with-pr モードのいずれにも併用可能（フラグ方式）
- dry-run と他の修飾子（force）の組み合わせも許容する（独立修飾子モデル）

### 2.2 B: uncommitted/未 push ガード

- 各非 main worktree について `git status --porcelain`（uncommitted 検出）と `git rev-list @{u}..HEAD --count`（未 push commits 検出）を実行する
- いずれかが非空・正の値の場合、そのブランチを「保護カテゴリ」として分類する
- 既定では保護カテゴリのブランチは削除対象から自動除外する（fail-safe）
- `/wt-cleanup force` と打つことで保護カテゴリも削除対象に統合し、追加の確認プロンプトを経て削除できる
- 保護カテゴリは結果表示テーブルに常時表示され、保護理由（`uncommitted: N files` / `未 push: N commits`）を明示する

### 2.3 D: parent.md §7 連携の文書化

- `claude/skills/wt-cleanup/README.md` を新規作成する（feature-team の SKILL.md + README.md 二層パターンに揃える）
- README.md は保守者向けで、責務範囲・feature-team との連携（双方向参照）・安全機構・引数モデル・改修注意点・手動テストシナリオを記述する
- parent.md §7 の引用を README.md に明記し、wt-cleanup 側からの双方向参照を確立する
- parent.md §7 自体は無改修もしくは最小追記（責務分離の主体は wt-cleanup 側に置く）

## 3. 非要件（YAGNI で削る）

以下は今回の設計に含めない:

- bats-core 等による zsh スクリプトの自動テスト基盤の構築
- 新規モード追加（merged-only / older-than 等の時間フィルタ）
- `gh pr list` 以外の PR 状態取得経路（GitHub Enterprise API 等）
- 削除前の worktree バックアップ機構
- 保護理由の優先順位制御（uncommitted と 未 push 両方ある場合は両方表示で十分）
- 既存 SKILL.md の構造的書き換え（5 ステップ → 6 ステップ拡張のみ、責務範囲は変えない）

これらは将来必要になった時に独立タスクとして追加できる。

## 4. 調査結果（設計前提）

- 既存 `wt-cleanup/SKILL.md` は 135 行、`allowed-tools: Bash + AskUserQuestion`、5 ステップフロー
- ステップ 4 は `wt remove "$b"` を while ループで実行するのみで、ブランチごとの保護検証はない
- `wt remove`（=worktrunk）の uncommitted 拒否挙動は worktrunk 実装依存で不確実
- `feature-team/roles/parent.md` §7 に「worktree を勝手に `wt remove` しない（PR マージ後の cleanup は別途 `wt-cleanup` スキル）」と明記されているが、wt-cleanup 側からの参照は存在しない
- wt-cleanup スキルは **自然言語の指示書**（Claude が SKILL.md を読んで Bash で実行する設計）であり、`--dry-run` のような POSIX CLI フラグではなく、ユーザーが `/wt-cleanup` の引数として意図を伝える設計

## 5. アーキテクチャ

### 5.1 二層構造への移行

```
claude/skills/wt-cleanup/
├ SKILL.md     (改修): 実行指示書 — Claude が読んで Bash で実行する自然言語フロー
└ README.md    (新規): 保守者向け設計ドキュメント — 責務分離・連携・改修ガイド
```

feature-team の二層パターンに揃える。SKILL.md を実行用に軽量に保ち、メタ情報（外部スキルとの連携、改修ガイド、テストシナリオ）を README.md に分離する。

### 5.2 引数モデル — 独立修飾子

ユーザーが `/wt-cleanup` に渡せる引数は **3 種の独立修飾子**を 0〜3 個、順序不問・空白区切り:

| 修飾子 | 意味 | 既定 |
|--------|------|------|
| **モード**: `with-pr` | PR 作成済み全件（状態問わず）を削除対象 | `merged`（マージ済みのみ） |
| **削除**: `dry-run` | 実削除フェーズをスキップ | 実削除する |
| **ガード**: `force` | uncommitted/未 push 検出による保護を解除 | ガード有効 |

全 8 通りの組み合わせ:

| 引数 | 動作 |
|------|------|
| (なし) | merged + 実削除 + ガード有効 |
| `with-pr` | with-pr + 実削除 + ガード有効 |
| `dry-run` | merged + dry-run + ガード有効 |
| `with-pr dry-run` | with-pr + dry-run + ガード有効 |
| `force` | merged + 実削除 + ガード解除 |
| `with-pr force` | with-pr + 実削除 + ガード解除 |
| `dry-run force` | merged + dry-run + ガード解除（force 効果プレビュー） |
| `with-pr dry-run force` | with-pr + dry-run + ガード解除 |

**「ガード解除」命名選定**: `force` を採用（git/GUI/CLI 慣習）。代替案として `unsafe` / `override-guard` / `delete-anyway` を検討したが、簡潔さと既知性を優先。安全性は `AskUserQuestion` の最終確認プロンプト（「force 指定により N 件のローカル変更を破壊します。続行しますか？」）で担保する。

#### 5.2.1 引数パーサ実装方針

独立修飾子モデルは、引数を for ループで全スキャンしフラグ変数を立てる pattern を採用する。固定 case 文（`if [ "$1" = "with-pr" ]`）では順序依存になり、修飾子の独立性が崩れるため避ける:

```bash
MODE=merged; DRY_RUN=false; FORCE=false
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
```

**未知引数は明示エラー** で即時終了する（silent ignore しない）。`dry-rum` のような typo を silent ignore すると、ユーザーは「dry-run 動作中」と誤認して実削除フェーズに突入するリスクがある。明示エラーが「予期せぬ削除」を防ぐ最後の防衛線。

### 5.3 サブタスク間の依存関係

3 サブタスクの改修対象ファイルと並列性:

| サブタスク | 改修対象ファイル | 並列性 |
|-----------|-----------------|-------|
| A (dry-run) | `SKILL.md` (ステップ 4 新規挿入 + 引数パーサに `dry-run` フラグ追加 + ステップ 5 dry-run 分岐) | B と同一ファイル — rebase 想定 |
| B (ガード) | `SKILL.md` (ステップ 2 検出ロジック追加 + ステップ 3 保護カテゴリ追加 + 引数パーサに `force` フラグ追加 + ステップ 5 force 分岐) | A と同一ファイル — rebase 想定 |
| D (README) | `README.md` (新規作成) | 完全独立 |

**引数パーサ (5.2.1) は A/B 共通基盤**。骨組み（for ループ + case 文 + 既存 `with-pr` フラグ + 未知引数エラー）は A/B のうち先に Phase 5 を通った側が実装し、後続側はフラグを 1 つ追加するだけで済む。

**Phase 4-A 並列起動時の推奨順序**: D 先行起動（独立 worktree、衝突なし）→ A/B を並列起動。A/B のうち先に Phase 5 を通った側を baseline とし、後続側は rebase で吸収する。

writing-plans (Phase 1.2) は本マトリクスを参照し、A/B のステップ順序を「ステップ 5.2.1 引数パーサ → A の dry-run 分岐 → B のガード分岐 → 統合確認」のように直列化することで rebase コストを抑える選択肢もある（最終判断は plan 側）。

## 6. データフロー — 6 ステップ

既存 5 ステップに新規ステップ 4「dry-run 判定」を挿入し、ステップ 2/3/5 を改修する。

```
1. リポジトリ情報取得 + worktree 一覧 (既存)
2. PR ステータス + 保護状態の一括検出 (改修)
   ├ 既存: gh pr list で PR 状態取得 (per branch)
   └ 追加: 各 worktree で git status --porcelain と git rev-list @{u}..HEAD --count
3. 結果の 4 カテゴリ分類と表示 (改修)
   ├ 削除対象 (マージ済み or PR 作成済み・モード依存)
   ├ 🛡️ 保護 (uncommitted or 未 push)
   ├ 未マージ (PR open/closed)
   └ PR なし
4. dry-run 判定 (新規)
   └ dry-run なら結果表示後に「dry-run のため削除をスキップしました」を出力して終了
5. ユーザー確認後、削除実行 (既存改修)
   ├ force なし: 削除対象カテゴリのみ削除
   └ force あり: 削除対象 + 保護カテゴリ両方削除（追加確認プロンプト必須）
6. 結果報告 (既存)
```

## 7. 検出ロジック詳細

### 7.1 各 worktree への保護判定

```bash
WT_PATH=<wt list --format=json から取得した path>
BRANCH=<同 branch>

# uncommitted 検出（status --porcelain が非空）
UNCOMMITTED=$(git -C "$WT_PATH" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

# 未 push commits 検出（先に upstream の有無を判定）
if git -C "$WT_PATH" rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
  UPSTREAM_SET=true
  UNPUSHED=$(git -C "$WT_PATH" rev-list @{u}..HEAD --count 2>/dev/null)
  [ -z "$UNPUSHED" ] && UNPUSHED=0
else
  UPSTREAM_SET=false
  UNPUSHED=0
fi

if [ "$UNCOMMITTED" -gt 0 ] || [ "$UNPUSHED" -gt 0 ] || [ "$UPSTREAM_SET" = "false" ]; then
  PROTECTED=true
fi
```

### 7.2 エッジケース

| ケース | 挙動 | 根拠 |
|-------|------|------|
| `git status` がエラー | 保護扱い (PROTECTED=true) | fail-safe（破壊リスクを避ける） |
| `@{u}` 未設定 | 保護扱い (PROTECTED=true)、理由「upstream 未設定 (未 push)」 | remote にコミットが存在しないため、削除すると差分を失う可能性がある |
| detached HEAD | uncommitted のみ判定 | 想定外、保護扱いで安全側 |
| ネットワーク非接続 (`gh pr list` 失敗) | 既存挙動踏襲 | スコープ外 |

## 8. 表示フォーマット

### 8.1 通常モード（merged の例）

```
## 🧹 Worktree クリーンアップ（merged モード）

### ✅ 削除対象（マージ済み）
| ブランチ | PR | マージ日 |
|---------|-----|---------|
| feature/foo-issue-123 | #200 | 2026-04-14 |

### 🛡️ 保護（uncommitted or 未 push）
| ブランチ | PR | マージ日 | 保護理由 |
|---------|-----|---------|---------|
| feature/bar-issue-456 | #201 | 2026-04-15 | ⚠️ 未 push: 3 commits |
| feature/baz-issue-789 | #203 | 2026-04-16 | ⚠️ uncommitted: 5 files |

### ⏳ 未マージ（保持）
| ブランチ | PR | 状態 |
|---------|-----|------|
| feature/qux-issue-901 | #202 | open |

### 📦 PR なし（保持）
| ブランチ |
|---------|
| experiment/local-only |

### 操作
- 削除対象 1 件を削除しますか？ (Y/n)
- 🛡️ 保護対象 2 件を削除するには `/wt-cleanup force` を再実行してください
```

### 8.2 dry-run モード

通常モードの表示の最後に「**dry-run のため削除をスキップしました**」を出力して終了。ステップ 5（ユーザー確認後の削除）は実行しない。

### 8.3 force モード

「削除対象」と「保護」を統合した 1 テーブルに警告マーク付きで再表示し、`AskUserQuestion` で「**🛡️ 保護対象 N 件を削除します。ローカル変更が失われます。続行しますか？**」を最終確認。

## 9. エラーハンドリング

| 事象 | 既定挙動 | 中断条件 |
|------|---------|---------|
| `gh pr list` 失敗（ネットワーク等） | 既存挙動踏襲（エラー出力 + 該当ブランチを「PR なし」扱い） | 全 worktree について `gh pr list` が失敗した場合は中断 |
| `git status` 失敗 | 該当ブランチを保護扱い、ログ出力 | 中断しない |
| `wt remove` 失敗（force でも失敗） | エラー出力、残り処理は継続 | 中断しない |
| ユーザーが N で確認拒否 | 即時終了、何もせず | — |

## 10. テスト戦略

zsh スクリプトの自動テスト基盤（bats-core 等）の構築は **スコープ外**。SKILL.md は自然言語ベースで Claude が実行するため、再現性のあるテストは別途設計が必要。

代替として README.md に手動テストシナリオを **チェックリスト** として記述する:

- S1: merged モード基本動作 — マージ済み worktree のみ削除されること
- S2: with-pr モード基本動作 — PR 作成済み全件が削除候補になること
- S3: dry-run — 削除されないこと、結果表示は通常と同じであること
- S4: ガード uncommitted — `git status --porcelain` 非空で保護カテゴリ表示
- S5: ガード 未 push — `git rev-list @{u}..HEAD` で N>0 で保護カテゴリ表示
- S6: force — 保護対象も削除候補に統合され、追加確認後に削除されること
- S7: dry-run + force — 保護解除済みの削除候補が表示され、削除されないこと
- S8: 修飾子順序自由 — `with-pr force dry-run` も `dry-run with-pr force` も同等動作
- S9: 全件保護 — 削除候補が 0 になり「クリーンアップ対象なし」表示
- S10: ネットワーク断 — エラー処理が中断せず継続すること

将来的な自動化候補は README.md の「改修するときの注意点」に「将来 bats-core 化検討」として記述する。

## 11. README.md の構造（新規）

```markdown
# Worktree Cleanup — 設計ドキュメント（保守者向け）

## TL;DR
SKILL.md は実行指示書、本ファイルは保守者向け設計ガイド。

## 1. 責務範囲
担当: PR 作成済み or マージ済みの worktree 検出 + 削除（要 user 確認）
スコープ外: worktree 作成、PR マージ前のクリーンアップ

## 2. feature-team との連携（双方向参照）
parent.md §7 「親が やってはいけない こと」:
> worktree を勝手に `wt remove` する（PR マージ後の cleanup は別途 `wt-cleanup` スキル）

責務分離テーブル:
| 主体 | 責務 |
| feature-team の親 | sub-issue 単位で worktree を `wt switch -c` 作成 |
| pr-publisher | PR 作成 + push（worktree は触らない） |
| wt-cleanup スキル | PR マージ後の worktree 削除（safety guard 付き） |

## 3. 安全機構
3.1 確認プロンプト（既存）
3.2 保護カテゴリ — uncommitted / 未 push 検出
3.3 force 引数によるガード解除 + 追加確認

## 4. 引数モデル — 独立修飾子
[Section 5.2 の表]

## 5. 改修するときの注意点
5.1 SKILL.md 変更前に
5.2 README.md 変更前に
5.3 parent.md §7 と整合確認
5.4 引数組み合わせ追加時の影響範囲

## 6. 手動テスト シナリオ
[Section 10 のチェックリスト]
```

## 12. 受入条件

- [ ] **AC-1 (A)**: `/wt-cleanup dry-run` が実削除をスキップして対象一覧のみ表示できる
- [ ] **AC-2 (A)**: `/wt-cleanup with-pr dry-run` も動作する（修飾子の独立性）
- [ ] **AC-3 (B)**: `git status --porcelain` 非空のブランチが保護カテゴリに表示される
- [ ] **AC-4 (B)**: `git rev-list @{u}..HEAD --count` > 0 のブランチが保護カテゴリに表示される
- [ ] **AC-5 (B)**: `force` 修飾子で保護対象を削除候補に統合し、追加確認後に削除できる
- [ ] **AC-6 (B)**: 既定では保護対象が削除されないこと（fail-safe）
- [ ] **AC-7 (D)**: `claude/skills/wt-cleanup/README.md` が新規作成され、parent.md §7 との双方向参照が成立する
- [ ] **AC-8 (D)**: README.md に責務分離テーブル・安全機構・引数モデル・改修注意点・手動テストシナリオが含まれる
- [ ] **AC-9 (D)**: parent.md §7 から wt-cleanup README.md への参照は **wt-cleanup 側** が記述。parent.md §7 は **無改修を基本** とし、必要な場合でも「`wt-cleanup スキル README` を参照」程度の 1 行リンク追加に留める（責務分離の主体は wt-cleanup 側に置く）
- [ ] **AC-10 (横断)**: 修飾子順序が結果に影響しないこと（独立修飾子モデルの確認）。**統合確認は最終 merge 後に手動 S8 シナリオで実施**（A/B 各 sub-issue の developer は自分のスコープ内のみ確認、横断確認は親オーケストレーター責任）

## 13. リポジトリ内ファイル配置

```
.dotfiles/
├ claude/
│  └ skills/
│     └ wt-cleanup/
│        ├ SKILL.md   (改修)
│        └ README.md  (新規)
└ docs/
   └ superpowers/
      ├ specs/
      │  └ 2026-05-01-wt-cleanup-design.md  (本ファイル)
      └ plans/
         └ 2026-05-01-wt-cleanup.md  (Phase 1.2 で writing-plans が生成)
```

## 14. 次のフェーズ

本 spec 承認後、`superpowers:writing-plans` スキルで implementation plan を `docs/superpowers/plans/2026-05-01-wt-cleanup.md` に書き出す。plan は AC-1〜10 を満たすための具体的な実装ステップ（A/B/D の sub-issue 分割含む）を順序付きで記述する。
