---
title: claude/AGENTS.md トークン削減 — 設計
date: 2026-06-21
status: draft
slug: agents-md-token-reduction
---

# claude/AGENTS.md トークン削減 — 設計

## 1. 背景

`claude/AGENTS.md`（user global メモリ）は **全プロジェクトで毎セッション auto-load** される。`/context` で確認した時点の占有は **3.3k tokens（9,410 chars / 114 行）**。同じ user global の `CLAUDE.md` 31 tokens、AutoMem 91 tokens と比較して突出している。

メモリは prompt cache に乗るため 1 セッション内の追加コストは低いが、`/clear`・セッション切替・cache miss のたびに再送が発生する。**全プロジェクト × 全セッション**にかかる固定コストなので、削減の限界費用は他のメモリ削減より高い。

## 2. 目的

- `claude/AGENTS.md` の規模を **3.3k → ~2.3k tokens（約 -29%, ~-950 tokens）** に削減する。char/token 比約 2.85（9,410 chars / 3.3k tokens）、char 削減 ~2,745 を token 換算した推定値。
- ルールの実効性を維持する（削除はトークン投資対効果が薄い項目に限る。Claude default で最低限カバーされる範囲、またはユーザー判断で許容される差分のみ）。
- 詳細仕様・仕組み説明は別ファイルに分離して **read-on-demand** とし、メモリ常駐を回避する。

## 3. 方針（3 軸）

| 軸 | 概要 |
|---|---|
| **削除** | Claude default 挙動と重複するルール、または効果に対してトークンコストが見合わないルールを除去する |
| **外部化** | 詳細な実装仕様・仕組み説明を独立ファイルに切り出し、AGENTS.md にはファイルパスへの参照のみ残す。外部ファイルは `@import` で auto-load せず、必要時にエージェントが Read する |
| **統合・圧縮** | 単独セクション化されている小項目を関連セクションに併合、各項目の冗長な言い回しを引き締める |

## 4. アーキテクチャ

### ファイル構成

```
~/.claude/CLAUDE.md  (dotfiles の claude/CLAUDE.md への symlink)
  ↓ @AGENTS.md
~/.dotfiles/claude/AGENTS.md         (削減対象。9,410 → ~6,665 chars)
  ↓ @CLAUDE.local.md
~/.claude/CLAUDE.local.md             (PC ローカル。変更なし)

[新規・read-on-demand]
~/.dotfiles/claude/handoff-policy.md  (handoff の PC ローカル運用規約)
~/.dotfiles/docs/memory-loading.md    (memory load の仕組み解説)
```

### load 機構の不変条件

- `CLAUDE.md → @AGENTS.md → @CLAUDE.local.md` の auto-import チェーンは変更しない。
- 外部化ファイルは **`@import` を使わない**。AGENTS.md 内には**パス参照のみ**残し、エージェントが必要時に Read する。
- これによって外部化ファイルの内容は auto-load 対象外となり、token 占有が発生しない。

## 5. セクション別処理マップ

| # | セクション | 処理 | 削減 chars |
|---|---|---|---:|
| 1 | Git Commit Rules | ✂ squash 系 2 項目を統合 | ~80 |
| 2 | Worktree Workflow | ✂ `wt --help` 注記削除 | ~30 |
| 3 | Configuration Scope | ✂ 対象例を本文に統合 | ~80 |
| 4 | コミュニケーション方針 | ✂ 一問一答 2 項目を統合、括弧書き短縮 | ~200 |
| 5 | 出力方針 | ⊕ #4 末尾に統合し独立セクション削除 | ~25 |
| 6 | コードレビュー | ◎ セクション全削除（Claude default が最低限カバーする範囲のため） | ~270 |
| 7 | セキュリティ | ✂ L40 (OWASP) / L41 (積極提案) 削除、L42 (secrets) のみ残す | ~240 |
| 8 | 実装規律 | ✂ 文言圧縮 | ~60 |
| 9 | テスト | ✂ L54 削除、L55+L56 統合 | ~120 |
| 10 | コミットメッセージ | ✂ 2 項目を 1 項目に統合 | ~50 |
| 11 | マルチエージェント | ✂ 文言圧縮 | ~80 |
| 12 | セッション管理 | ⇨ handoff 詳細を `claude/handoff-policy.md` に外部化 | ~600 |
| 13 | 実装前検証 | ✂ 文言圧縮 | ~30 |
| 14 | フォーマッタ・リンタ | = 維持 | 0 |
| 15 | Document Dependency Check | ✂ 仕組み説明を短縮、規約のみ残す | ~100 |
| 16 | Knowledge Capture | ✂ 対象/除外リストを 1 行化 | ~80 |
| 17 | Local Overrides | ⇨ import 経路の解説を `docs/memory-loading.md` に外部化 | ~700 |

**合計**: ~2,745 chars 削減（token 換算 ~960 tokens, char/token 比 2.85 換算）

## 6. 外部化ファイル設計

### 6.1 `claude/handoff-policy.md`（新規）

**位置付け**: `handoff` skill が upstream（mattpocock/skills）同期されている制約下で、PC 固有のパス命名規約・解決ロジックを独立ファイル化する。

**ロード方式**: read-on-demand（auto-load しない）。AGENTS.md 内の参照記述からエージェントが必要時に Read する。

**含める内容**:

- 保存先パスの命名規約（`$TMPDIR/handoff-<repo-slug>-<branch-slug>.md`）
- `<repo-slug>` の解決ロジック（main git working dir basename / worktree からの解決 / git 外の挙動）
- `<branch-slug>` の解決ロジック（sanitize / detached HEAD / git 外の `nobranch`）
- `$TMPDIR` の OS 差分（macOS / Linux）
- 旧形式 `handoff-<repo-slug>.md` の過渡対応
- skill 本体との関係（upstream 同期で触らない / 本ポリシーが skill 指示より優先）

### 6.2 `docs/memory-loading.md`（新規、dotfiles リポジトリ内）

**位置付け**: `@import` 解決の仕組み・優先順位・デバッグ手順を独立ドキュメント化する。

**ロード方式**: read-on-demand。トラブルシュート時に Read する。

**含める内容**:

- 優先順位（User CLAUDE.local.md > AGENTS.md > Claude default）
- import 解決の経路（3 段階）
- `/memory` コマンドによる検証手順
- `CLAUDE.local.md` が無い PC での挙動（skip）

## 7. AGENTS.md 残存記述（圧縮後）

外部化対象セクションの AGENTS.md 内残存記述は以下の通り。

### 7.1 セッション管理（残存）

```
# セッション管理
- 完了タスクの要約・整理はユーザーに指摘される前に行うこと
- コンテキスト圧縮警告 / ツール呼び出し増加時は作業状態の保存を提案
- handoff skill の保存先・命名規約は `~/.dotfiles/claude/handoff-policy.md` に従う。「ハンドオフから再開」と言われたら同ファイルの規則で Read してから応答すること
```

### 7.2 Local Overrides（残存）

```
# Local Overrides
- 優先順位: User CLAUDE.local.md > AGENTS.md（global）> Claude Code 既定挙動
- CLAUDE.local.md は PC 固有の設定・制約を記述するファイル。AGENTS.md の内容を上書きする
- 読み込みの仕組み・デバッグ手順は `~/.dotfiles/docs/memory-loading.md` 参照
```

## 8. リスクと後方互換

| リスク | 対策 |
|---|---|
| 外部化先ファイルを Read し忘れる | AGENTS.md 残存記述に**明示的にファイルパス**を書き込む |
| `#6 コードレビュー` 削除でレビュー品質が下がる | Claude default の "OWASP top 10... immediately fix" が最低限カバー。実害が出たら CLAUDE.local.md 側で個別追加可能（ロールバック容易） |
| `#7 L40 OWASP` 削除で security 軽視 | Claude default に OWASP top 10 記述がそのまま含まれる |
| 外部化ファイルが symlink で配布されない | `nix/modules/home/claude.nix` で `claude/` 配下は既に symlink 展開済み。`docs/` は dotfiles リポジトリ内なので追加対応不要 |
| 別 PC で `CLAUDE.local.md` が無い | 既存挙動と同じく `@import` で skip されるだけ。本変更で挙動変化なし |

## 9. 検証方法

| # | 検証項目 | 検証手段 |
|---|---|---|
| V1 | AGENTS.md が ~6,665 chars に縮小 | `wc -c claude/AGENTS.md` |
| V2 | AGENTS.md token 数が ~2.3k に減少（許容幅 2.1k〜2.5k） | Claude Code 上で `/context` |
| V3 | 外部化先ファイルが存在し抜けがない | `ls claude/handoff-policy.md docs/memory-loading.md` と内容確認 |
| V4 | AGENTS.md に外部ファイル参照が残る | `grep -E "handoff-policy.md\|memory-loading.md" claude/AGENTS.md` |
| V5 | nix build が成功 | `USER=ciuser nix build .#darwinConfigurations.default.system --no-link --impure` |
| V6 | symlink 展開が機能 | `darwin-rebuild switch` 後に `ls -la ~/.claude/handoff-policy.md` |

## 10. スコープ外

- `claude/AGENTS.md` 以外のメモリファイル（project AGENTS.md 5.2k tokens 等）の削減。別タスクとして検討する。
- `handoff` skill 本体の改変。upstream 同期方針を維持する。
- nix 設定の構造変更。`claude/handoff-policy.md` は既存 symlink 設定の対象範囲内で配布される。
- AGENTS.md の文体・トーンの統一作業。今回は内容削減に集中する。

## 11. ロールバック方針

すべての変更は `git revert` で元に戻る。外部化ファイル（`claude/handoff-policy.md` / `docs/memory-loading.md`）の追加と AGENTS.md の編集は同一コミットまたは関連する複数コミットにまとめ、revert 時に整合が崩れないようにする。
