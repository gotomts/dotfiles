# Worktree Cleanup — 設計ドキュメント（保守者向け）

このファイルは **保守者向けの設計ガイド** です。責務範囲・他スキルとの連携・安全機構の根拠・改修注意点を集約します。

スキル本体の使い方は `SKILL.md` を参照してください。

## TL;DR

`SKILL.md` は Claude が読んで Bash で実行する指示書。本ファイルは **保守者向けの設計ガイド** であり、責務範囲・他スキルとの連携・安全機構の根拠・改修注意点を集約する。

スキル本体の使い方は `SKILL.md` を、対話的な実行例は親プロジェクトの `claude/CLAUDE.md` を参照。

---

## 1. 責務範囲

**担当する範囲:**

- PR 作成済み or マージ済みの worktree 検出
- ユーザー確認後の `wt remove` 実行
- uncommitted / 未 push 検出による fail-safe 保護

**スコープ外:**

- worktree の **作成** (これは `feature-team` 親 / 手動 `wt switch -c` の責務)
- PR マージ前の早期クリーンアップ (PR ライフサイクル管理は GitHub / `pr-publisher` の責務)
- merge 戦略の検討 (merged モードと with-pr モードのみ対応、`older-than` 等の時間フィルタは YAGNI)

---

## 2. feature-team との連携（双方向参照）

`feature-team/roles/parent.md` §7「親が **やってはいけない** こと」に以下が明記されている:

> worktree を勝手に `wt remove` する（PR マージ後の cleanup は別途 `wt-cleanup` スキル）

これにより責務境界が確定する:

| 主体 | 責務 |
|------|------|
| `feature-team` 親オーケストレーター | sub-issue 単位で `wt switch -c` で worktree を **作成** する。作成後は触らない |
| `pr-publisher` サブエージェント | PR 作成 + push のみ。worktree は触らない |
| `wt-cleanup` スキル（本スキル） | PR マージ後の worktree **削除** を、user 確認 + 保護判定付きで実行 |

`parent.md` §7 は **無改修を基本** とし、本 README が wt-cleanup 側からの参照点となる（双方向参照は wt-cleanup 側に集約することで、feature-team 側の文書負荷を増やさない）。

---

## 3. 安全機構

3 段階の safety net:

### 3.1 確認プロンプト（既存）

削除実行前に `AskUserQuestion` で「N 件削除しますか?」確認。N で即時終了。

### 3.2 保護カテゴリ — uncommitted / 未 push 検出（新規）

各 worktree について `git status --porcelain`（uncommitted）と `git rev-list @{u}..HEAD --count`（未 push commits）を検査し、いずれか非空・正値なら「保護カテゴリ」へ分類。**既定では削除対象から除外**（fail-safe）。

エラーハンドリング方針:
- `git status` が失敗した場合 → そのブランチを保護扱い（fail-safe）
- `@{u}` 未設定の場合 → `UNPUSHED=0` 扱い（削除対象は PR 経由なので upstream 設定済みが前提）

### 3.3 force 引数によるガード解除 + 追加確認（新規）

`/wt-cleanup force` を実行すると保護対象も削除候補に統合し、最終確認プロンプト「**保護対象 N 件を削除します。ローカル変更が失われます。続行しますか?**」を経て削除する。

---

## 4. 引数モデル — 独立修飾子

3 種の独立修飾子を 0〜3 個、順序不問・空白区切りで受ける:

| 修飾子 | 意味 | 既定 |
|--------|------|------|
| `with-pr` | PR 作成済み全件（状態問わず）を削除対象 | `merged`（マージ済みのみ） |
| `dry-run` | 実削除フェーズをスキップ | 実削除する |
| `force` | uncommitted / 未 push 検出による保護を解除 | ガード有効 |

全 8 通りの組み合わせ:

| 引数 | 動作 |
|------|------|
| （なし） | merged + 実削除 + ガード有効 |
| `with-pr` | with-pr + 実削除 + ガード有効 |
| `dry-run` | merged + dry-run + ガード有効 |
| `with-pr dry-run` | with-pr + dry-run + ガード有効 |
| `force` | merged + 実削除 + ガード解除 |
| `with-pr force` | with-pr + 実削除 + ガード解除 |
| `dry-run force` | merged + dry-run + ガード解除（force 効果プレビュー） |
| `with-pr dry-run force` | with-pr + dry-run + ガード解除 |

未知引数は **明示エラー + exit 1** で silent ignore しない。`dry-rum` のような typo を silent ignore すると、ユーザーは「dry-run 動作中」と誤認して実削除に進むリスクがある。

---

## 5. 改修するときの注意点

### 5.1 SKILL.md 変更前に

- 既存の 6 ステップフロー（リポ取得 → PR + 保護検出 → 4 カテゴリ表示 → dry-run 判定 → 削除実行 → 報告）を保持しているか確認
- 引数パーサの case 文に新規修飾子を追加する場合、本 README §4 の表も更新する（両方が同期している必要）
- 検出ロジック（`git status --porcelain` / `git rev-list @{u}..HEAD --count`）のエラー時挙動を変更する場合、§3.2 の fail-safe 原則を維持する

### 5.2 README.md 変更前に

- §1 責務範囲を変える場合は `feature-team/roles/parent.md` §7 との整合を確認（新責務が parent.md と矛盾しないか）
- §2 連携テーブルの主体を増やす場合は、その主体側のドキュメントにも本 README への参照を追加（双方向）
- §4 引数モデル表を変える場合は SKILL.md の引数パーサ実装と必ず同期

### 5.3 parent.md §7 と整合確認

`feature-team` 側のリファクタで §7 の文言が変わった場合、本 README §2 の引用も更新する。引用ずれを検出するため、変更時は両ファイルを並べて diff 確認すること。

### 5.4 引数組み合わせ追加時の影響範囲

新修飾子を追加する場合、以下を全て更新:

1. SKILL.md — 引数パーサ（case 文に追加）
2. SKILL.md — 使用例
3. 本 README §4 表（8 通り → 16 通り等）
4. 本 README §6 手動テストシナリオ（新シナリオ追加）
5. spec の AC 追加検討

---

## 6. 手動テスト シナリオ

zsh script 自動テスト基盤（bats-core 等）はスコープ外。各シナリオは worktree を準備し、`/wt-cleanup [引数]` を実行して期待出力を目視確認する:

- **S1**: merged モード基本動作 — マージ済み worktree のみ削除候補として表示・実削除
- **S2**: with-pr モード基本動作 — PR 作成済み全件（open/closed/merged）が削除候補
- **S3**: dry-run — 削除候補表示は通常と同じ、削除フェーズで「dry-run のため削除をスキップしました」表示・実削除なし
- **S4**: ガード uncommitted — 1 worktree で `touch new-file.tmp` し、保護カテゴリに「⚠️ uncommitted: 1 files」表示
- **S5**: ガード 未 push — 1 worktree で `git commit --allow-empty -m wip` し、保護カテゴリに「⚠️ 未 push: 1 commits」表示
- **S6**: force — 保護対象を含むケースで `/wt-cleanup force` 実行 → 統合表示 → 追加確認プロンプト「保護対象 N 件を削除します。ローカル変更が失われます。続行しますか?」→ Y で削除実行
- **S7**: dry-run + force — `/wt-cleanup dry-run force` で保護解除済み削除候補が表示、追加確認なし、実削除なし
- **S8**: 修飾子順序自由 — `with-pr force dry-run` と `dry-run with-pr force` で同等動作
- **S9**: 全件保護 — 全 worktree が保護対象になる状況で「クリーンアップ対象なし」表示
- **S10**: ネットワーク断 — `gh pr list` を失敗させ（例: `unset GH_TOKEN` で認証失効）、エラー表示後も処理継続を確認

将来の自動化候補: bats-core での S1〜S10 ゴールデンテスト化を検討（現状は YAGNI でスコープ外）。
