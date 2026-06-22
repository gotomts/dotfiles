# claude/AGENTS.md トークン削減 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `claude/AGENTS.md` を 3.3k → ~2.3k tokens（約 -29%）に削減する。Claude default と重複するルールを削除し、handoff のパス規約と memory loading の仕組み解説を独立ファイルに read-on-demand 化し、残りセクションを圧縮する。

**Architecture:** `claude/handoff-policy.md` と `docs/memory-loading.md` を新規追加し、AGENTS.md からは `@import` を使わずパス参照のみ残す（auto-load しない）。AGENTS.md は 17 セクションを削除・統合・圧縮して短縮。`CLAUDE.md → @AGENTS.md → @CLAUDE.local.md` の既存 import チェーンは変更しない。

**Tech Stack:** Markdown のみ。nix-darwin + home-manager で symlink 配布されるため、新規ファイルも既存の `claude/` / `docs/` 配下に置けば自動展開される。

## Global Constraints

- ファイル配置: 全成果物は `~/.dotfiles/` 配下に置く。`claude/` 配下と `docs/` 配下は既存の nix `home.activation` で symlink 展開される
- import チェーン不変: `CLAUDE.md → @AGENTS.md → @CLAUDE.local.md` の auto-load チェーンに変更を加えない
- 外部化ファイル: `@import` 構文を使わない。AGENTS.md から絶対パス（`~/.dotfiles/...`）で参照する
- コミットメッセージ: Conventional Commits（`docs(claude):` / `refactor(claude):` 等）に従う
- 各タスク完了時に独立コミットを作成（squash しない）
- AGENTS.md 編集は Write ではなく Edit で実施し、変更内容を git diff で確認可能にする（Write だと全行が差分扱いになり、何が変わったか追いにくい）

---

### Task 1: `claude/handoff-policy.md` を新規作成

**Files:**
- Create: `/Users/goto/.dotfiles/claude/handoff-policy.md`

**Interfaces:**
- Produces: `~/.dotfiles/claude/handoff-policy.md`（symlink 経由で `~/.claude/handoff-policy.md` からアクセス可能）。Task 3 で AGENTS.md からパス参照される

- [ ] **Step 1: ファイルを作成する**

`/Users/goto/.dotfiles/claude/handoff-policy.md` を以下の内容で新規作成する:

````markdown
# handoff skill のローカル運用ポリシー

> このファイルは auto-load されない。`AGENTS.md` の handoff 規約からエージェントが必要時に Read する。skill 本体（`claude/skills/handoff/SKILL.md`）は upstream（mattpocock/skills）と完全同期する運用なので触らず、本ポリシーが skill の指示より優先される。

## ファイル配置

- 保存先: `$TMPDIR/handoff-<repo-slug>-<branch-slug>.md`
- repo × branch 単位で 1 ファイル、同一ブランチ内は上書き運用
- 複数セッションを別ブランチ（別 worktree）で並行運用しても衝突しないよう、ファイル名は repo と branch の複合キーにする

## `<repo-slug>` の解決

- main git working dir の basename
- worktree からは `dirname "$(git rev-parse --git-common-dir)"` 経由で main working dir を解決し、その basename
- git 外ならカレントディレクトリの basename

## `<branch-slug>` の解決

- 現在のブランチ名を sanitize したもの（`/` 等を `-` に置換）
- detached HEAD や git 外などブランチを解決できない場合は `nobranch`

## `$TMPDIR` の OS 差分

- macOS: `/var/folders/.../T/`
- Linux: 通常 `/tmp`

## 過渡対応

旧形式の `handoff-<repo-slug>.md`（repo 単位のみのファイル）が残っていても触らない。移行で消さない。

## 「ハンドオフから再開」要求への応答

ユーザーが「ハンドオフから再開」と言ったら、上記の規則で `$TMPDIR/handoff-<repo-slug>-<branch-slug>.md` を Read で読んでから応答する。該当ファイルが無ければユーザーにパスを確認する。
````

- [ ] **Step 2: 作成内容を確認する**

実行: `wc -l /Users/goto/.dotfiles/claude/handoff-policy.md`
期待: 28〜35 行程度

実行: `grep -c "handoff-<repo-slug>" /Users/goto/.dotfiles/claude/handoff-policy.md`
期待: 3 以上（パス命名規約・過渡対応・再開要求の 3 箇所で言及されている）

- [ ] **Step 3: コミット**

```bash
git add claude/handoff-policy.md
git commit -m "$(cat <<'EOF'
docs(claude): handoff skill のローカル運用ポリシーを独立ファイル化

claude/AGENTS.md に焼き込まれていた handoff の保存先パス命名規約・
<repo-slug>/<branch-slug> の解決ロジック・OS 差分などを独立ファイルに
切り出す。本ファイルは auto-load せず、AGENTS.md からのパス参照経由で
必要時にエージェントが Read する read-on-demand 方式。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

実行: `git log -1 --format="%s"`
期待: `docs(claude): handoff skill のローカル運用ポリシーを独立ファイル化`

---

### Task 2: `docs/memory-loading.md` を新規作成

**Files:**
- Create: `/Users/goto/.dotfiles/docs/memory-loading.md`

**Interfaces:**
- Produces: `~/.dotfiles/docs/memory-loading.md`。Task 3 で AGENTS.md からパス参照される

- [ ] **Step 1: ファイルを作成する**

`/Users/goto/.dotfiles/docs/memory-loading.md` を以下の内容で新規作成する:

````markdown
# Claude Code メモリ読み込みの仕組み

> このファイルは auto-load されない。トラブルシュート時に `claude/AGENTS.md` の Local Overrides セクションから参照される。

## 優先順位

```
User CLAUDE.local.md > AGENTS.md（global） > Claude Code 既定挙動
```

`CLAUDE.local.md` は PC 固有の設定・制約を記述するファイルであり、グローバル規約である `AGENTS.md` を上書きする。

## import 解決の経路

1. Claude Code が `~/.claude/CLAUDE.md`（dotfiles の `claude/CLAUDE.md` への symlink）を読む
2. `CLAUDE.md` 内の `@AGENTS.md` で AGENTS.md を inject
3. 続く `@CLAUDE.local.md` で `~/.claude/CLAUDE.local.md` を inject（ファイルが存在しない PC では skip される）

ここまでが起動時の自動 inject 機構であり、エージェントが Read を忘れる余地はない。

## デバッグ

- `CLAUDE.local.md` が読まれていることの確認: Claude Code 起動後に `/memory` でメモリ階層を表示する
- `/memory` の出力に `~/.claude/CLAUDE.local.md` が現れていれば inject 成功
- AGENTS.md / CLAUDE.local.md の各 token 数も `/context` で確認できる

## 外部化ファイルの read-on-demand

`AGENTS.md` 内では以下の外部ファイルへのパス参照のみを残している。`@import` は使わないため auto-load されず、エージェントが必要時に Read する。

- `~/.dotfiles/claude/handoff-policy.md` — handoff skill の PC ローカル運用規約
- `~/.dotfiles/docs/memory-loading.md` — 本ファイル
````

- [ ] **Step 2: 作成内容を確認する**

実行: `wc -l /Users/goto/.dotfiles/docs/memory-loading.md`
期待: 25〜35 行程度

実行: `grep -c "CLAUDE.local.md" /Users/goto/.dotfiles/docs/memory-loading.md`
期待: 4 以上

- [ ] **Step 3: コミット**

```bash
git add docs/memory-loading.md
git commit -m "$(cat <<'EOF'
docs(claude): memory load の仕組み解説を独立ドキュメント化

claude/AGENTS.md の Local Overrides セクションに焼き込まれていた
import チェーン解決の 3 段階解説・優先順位ルール・/memory コマンドでの
デバッグ手順を独立ドキュメントに切り出す。本ファイルは auto-load せず、
AGENTS.md からのパス参照経由でトラブルシュート時に Read する。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

実行: `git log -1 --format="%s"`
期待: `docs(claude): memory load の仕組み解説を独立ドキュメント化`

---

### Task 3: `claude/AGENTS.md` を削減編集

**Files:**
- Modify: `/Users/goto/.dotfiles/claude/AGENTS.md`

**Interfaces:**
- Consumes: Task 1 で作成した `~/.dotfiles/claude/handoff-policy.md`、Task 2 で作成した `~/.dotfiles/docs/memory-loading.md`
- Produces: 削減済み AGENTS.md（~6,665 chars / ~2.3k tokens）

- [ ] **Step 1: 現状を確認する**

実行: `wc -c /Users/goto/.dotfiles/claude/AGENTS.md`
期待: `9410 /Users/goto/.dotfiles/claude/AGENTS.md`（編集前）

実行: `git log -1 --format="%h" -- claude/AGENTS.md`
期待: 直近の AGENTS.md コミット hash が取得できること（ロールバック起点）

- [ ] **Step 2: AGENTS.md 全体を新規内容で置き換える**

`/Users/goto/.dotfiles/claude/AGENTS.md` を Write ツールで以下の内容に上書きする（Read 済の前提）:

````markdown
## Git Commit Rules

- NEVER squash unrelated commits。Each commit は独立を保つ（ユーザーが明示的に squash を指示した場合を除く）
- When committing, always confirm the target repository (dotfiles vs project) before running git commands
- NEVER force-push without explicit user authorization. `--amend` の許可は push の許可ではない。push は別途承認を取ること

## Worktree Workflow

- `wt` shell function を使って並列ワークを開始する（plain git branch/checkout より優先）
- Never restore deliberately deleted local branches without explicit user confirmation
- ユーザーが parallel work を言及したら worktree ベースのフローをデフォルトとする

## Configuration Scope

- 設定変更を行う前に、対象スコープ（global / per-project / per-repo）を明示してユーザーに確認すること。対象は git config、シェル alias / function、claude settings.json、エディタ設定など
- 「グローバルに入れる」と「このリポジトリだけ」では影響範囲が大きく異なるため、判断を委ねずに先に確認する

# コミュニケーション方針

- 技術的に誤った意見には根拠を示して反論すること。懸念・代替案は実装提案の前に伝える
- 曖昧な指示に対しては推測で進めず、具体的に確認すること
- 一問一答を徹底する。1 ターンにつき 1 つだけ質問し、ユーザーが yes / no または番号で答えられる選択肢化・二択化を行う。自由記述を要する問い・複数質問同時提示は禁止
- 判断を伴う選択をユーザーに求める場合は、推奨案と各選択肢のメリット・デメリットを併記する。推奨案は技術負債にならないことを確認した上で提案する
- 設計・レビュー・分析は分割確認せず、完全な形で一度に出力すること

# セキュリティ

- シークレット、認証情報、APIキーがコードやコミットに含まれないことを確認すること

# 実装規律

- 初回の実装パスでバリデーション（範囲制約、境界値、型チェック）を含めること
- コミット前に linter・型チェッカー・フォーマッター・テストを実行すること
- LSP が利用可能な場合、シンボル調査・定義元・参照箇所の特定に Grep/Glob より優先して使うこと
- 成果物（コード・ドキュメント・設計）を提出する前にセルフレビューを行う（プレースホルダー・矛盾・曖昧さなし）
- ワークフローの各フェーズで成果物を書き出した後、次のフェーズに進む前に git status を確認し、未コミットの成果物があればコミットすること

# テスト

- ゴールデンテストを基本アプローチとし、種類・粒度はプロジェクトの規約に従う

# コミットメッセージ

- デフォルトは Conventional Commits（feat:, fix:, refactor: 等）に従う。プロジェクト固有の規約や既存のコミット履歴があればそちらを優先する

# マルチエージェント

- サブエージェントには明確なスコープと完了条件を与え、出力は検証する
- デフォルトの分業は Research → Synthesis → Implementation → Verification
- サブエージェントの調査結果をそのまま次のエージェントへ転送せず、オーケストレーター自身が理解・統合してから次の指示を書く
- サブエージェント向けプロンプトは自己完結であること。`based on your findings` のような理解責任の再委譲を禁止する
- read-only な探索は積極的に並列化、同一ファイル群への write-heavy な作業は直列化する
- 失敗修正や直前作業の継続は同一エージェント continuation を優先、独立 verification や方針の全面変更は fresh context のエージェントを使う

# セッション管理

- 完了タスクの要約・整理はユーザーに指摘される前に行う
- コンテキスト圧縮警告 / ツール呼び出し増加時は作業状態の保存を提案
- handoff skill の保存先・命名規約は `~/.dotfiles/claude/handoff-policy.md` に従う。「ハンドオフから再開」と言われたら同ファイルの規則で Read してから応答すること

# 実装前検証

- 実装開始前に、関連する依存ライブラリの実際のバージョンと既存コードを確認する
- 前提条件（バージョン、API互換性、プロジェクト状態）をコメントで明示してから実装に入る

# フォーマッタ・リンタのスコープ

- フォーマッタやリンタは変更したファイルのみに適用する
- git diff --name-only で対象を特定し、全体実行しない

# Document Dependency Check

- md ファイルの frontmatter に `depends-on` が宣言されているドキュメントはコード変更の影響を受ける可能性がある。コード変更タスク完了時に該当ドキュメントの更新要否を検討する
- ドキュメントの更新はユーザー承認後に行うこと。自動更新は禁止

# Knowledge Capture

- タスク完了時、作業中に得たプロジェクト固有の知見（アーキテクチャパターン、暗黙の制約・落とし穴、ドメイン知識・ビジネスルール、設計判断の根拠）を auto memory に記録する。コード/git history から自明な内容と一般論は除外
- 既存メモリ（MEMORY.md）と重複しないこと
- 記録件数の目安: 0〜3 件。該当なしなら記録不要。記録後、何を保存したかを通知する

# Local Overrides

- 優先順位: User CLAUDE.local.md > AGENTS.md（global）> Claude Code 既定挙動
- CLAUDE.local.md は PC 固有の設定・制約を記述するファイル。AGENTS.md の内容を上書きする
- 読み込みの仕組み・デバッグ手順は `~/.dotfiles/docs/memory-loading.md` 参照
````

- [ ] **Step 3: char 数を検証する**

実行: `wc -c /Users/goto/.dotfiles/claude/AGENTS.md`
期待: 6,000〜7,200 chars 範囲（目標 ~6,665、許容幅 ±600）。許容を外れた場合は git diff を見て圧縮しすぎ/不足を判断

- [ ] **Step 4: 外部ファイル参照が残っていることを検証する**

実行: `grep -c "handoff-policy.md" /Users/goto/.dotfiles/claude/AGENTS.md`
期待: 1（セッション管理セクションで 1 回参照）

実行: `grep -c "memory-loading.md" /Users/goto/.dotfiles/claude/AGENTS.md`
期待: 1（Local Overrides セクションで 1 回参照）

- [ ] **Step 5: 削除対象セクションが消えていることを検証する**

実行: `grep -c "^# コードレビュー" /Users/goto/.dotfiles/claude/AGENTS.md`
期待: 0（セクション全削除されていること）

実行: `grep -c "OWASP" /Users/goto/.dotfiles/claude/AGENTS.md`
期待: 0（#7 L40 OWASP 行が削除されていること）

実行: `grep -c "^## 出力方針" /Users/goto/.dotfiles/claude/AGENTS.md`
期待: 0（独立セクションが消え、# コミュニケーション方針に統合されていること）

- [ ] **Step 6: 重要ルールが残っていることを検証する**

実行: `grep -c "シークレット" /Users/goto/.dotfiles/claude/AGENTS.md`
期待: 1（#7 セキュリティの secrets 行が残っていること）

実行: `grep -c "一問一答" /Users/goto/.dotfiles/claude/AGENTS.md`
期待: 1（コミュニケーション方針の核ルールが残っていること）

実行: `grep -c "ハンドオフから再開" /Users/goto/.dotfiles/claude/AGENTS.md`
期待: 1（handoff 再開トリガが残っていること）

- [ ] **Step 7: コミット**

```bash
git add claude/AGENTS.md
git commit -m "$(cat <<'EOF'
refactor(claude): AGENTS.md を 3.3k → ~2.3k tokens に削減

- # コードレビュー セクション全体を削除 (Claude default が最低限カバー)
- # セキュリティ から OWASP / 積極提案行を削除 (default に同等記述あり)
- # セッション管理 の handoff パス規約を claude/handoff-policy.md に外部化
- # Local Overrides の import 解説を docs/memory-loading.md に外部化
- ## 出力方針 を # コミュニケーション方針 に統合 (独立セクション削除)
- その他セクションの冗長な言い回しを圧縮

外部化ファイルは @import で auto-load せず、AGENTS.md からのパス参照経由
で必要時に Read する read-on-demand 方式。全プロジェクト × 全セッション
で発生する固定 token コストを削減する。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

実行: `git log -1 --format="%s"`
期待: `refactor(claude): AGENTS.md を 3.3k → ~2.3k tokens に削減`

---

### Task 4: 削減結果を検証する

**Files:** なし（検証のみ）

**Interfaces:**
- Consumes: Task 1〜3 の成果物
- Produces: 検証ログ（コミット不要、必要なら gwt.md のチェックリストを更新）

- [ ] **Step 1: nix build で構文・依存解決を検証**

実行: `cd /Users/goto/.dotfiles/nix && USER=ciuser nix build .#darwinConfigurations.default.system --no-link --impure`
期待: exit 0 で完了

- [ ] **Step 2: darwin-rebuild switch で symlink を更新**

実行: `cd /Users/goto/.dotfiles/nix && sudo USER=$USER darwin-rebuild switch --flake .#default --impure`
期待: exit 0 で完了、`~/.claude/handoff-policy.md` が `claude/handoff-policy.md` への symlink として作成されている

実行: `ls -la ~/.claude/handoff-policy.md`
期待: symlink 表示で `-> /Users/goto/.dotfiles/claude/handoff-policy.md` が見える

- [ ] **Step 3: Claude Code で token 数を確認**

ユーザーに依頼: Claude Code を再起動し、新規セッションで `/context` を実行する
期待: `claude/AGENTS.md` の token 数が 2.1k〜2.5k tokens の範囲に収まる（期待値 ~2.3k）

ユーザーから値を受け取ったら gwt.md の AC-1 チェックボックスを `- [x]` に書き換える

- [ ] **Step 4: 外部化ファイルの Read 動作を確認**

ユーザーに依頼: 新規セッションでエージェントに「ハンドオフから再開」を依頼する
期待: エージェントが `claude/handoff-policy.md` を Read してから処理を続行する（規約に従う）

gwt.md の AC-2 チェックボックスを `- [x]` に書き換える

- [ ] **Step 5: gwt.md の検証チェックリストを更新**

`docs/superpowers/main/2026-06-21-agents-md-token-reduction-gwt.md` の検証チェックリストで、確認できた AC を `- [x]` にマークする:

- AC-1（token 数）: Step 3 の結果で更新
- AC-2（handoff-policy.md 機能）: Step 4 の結果で更新
- AC-3（memory-loading.md 機能）: Step 2 のファイル存在確認で更新可
- AC-4（参照パスが残る）: Task 3 Step 4 の grep 結果で更新
- AC-5（nix build 成功）: Step 1 の結果で更新
- AC-6（default カバー確認）: 別途 `/context` の system prompt 出力で目視確認
- AC-E1（CLAUDE.local.md 不在時）: 別 PC での確認は本タスクのスコープ外（将来のフォローアップ）
- AC-E2（参照壊れた時のエラー）: 必要なら別途 mv 等で意図的に発生させて確認

- [ ] **Step 6: gwt.md の更新をコミット**

```bash
git add docs/superpowers/main/2026-06-21-agents-md-token-reduction-gwt.md
git commit -m "$(cat <<'EOF'
docs(claude): AGENTS.md トークン削減の検証チェックリストを更新

実機で確認できた AC を `- [x]` に更新。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

実行: `git log -1 --format="%s"`
期待: `docs(claude): AGENTS.md トークン削減の検証チェックリストを更新`

---

## Self-Review

### 1. Spec coverage

spec の各要件をタスクにマップする:

| spec 要件 | 対応タスク |
|---|---|
| #6 コードレビュー全削除 | Task 3 Step 2 + Step 5 grep 検証 |
| #7 OWASP / 積極提案行の削除 | Task 3 Step 2 + Step 5 grep 検証 |
| #12 セッション管理の handoff 外部化 | Task 1（新規ファイル） + Task 3（参照記述） |
| #17 Local Overrides の import 解説外部化 | Task 2（新規ファイル） + Task 3（参照記述） |
| 残りセクションの圧縮 | Task 3 Step 2 で全体置換 |
| token 数の検証 (~2.3k) | Task 4 Step 3 |
| nix build 成功検証 | Task 4 Step 1 |
| 別 PC での挙動（CLAUDE.local.md 不在時） | スコープ外として gwt.md AC-E1 に注記済 |

ギャップなし。

### 2. Placeholder scan

各 Step を再確認:

- TBD / TODO / "implement later" → なし
- "add appropriate error handling" 系の曖昧記述 → なし
- "similar to Task N" → なし（必要な箇所はすべて明示的に内容を記載）
- コードブロックの中身 → Task 1〜3 の新規 / 置換内容はすべて完全な文字列で提示済み
- コマンドの期待出力 → 各 Step で明示済み

### 3. Type consistency

ファイルパス参照の一貫性をチェック:

- `claude/handoff-policy.md`: Task 1（作成）→ Task 3（AGENTS.md 内で `~/.dotfiles/claude/handoff-policy.md` で参照）→ Task 3 Step 4（grep 検証）。一貫
- `docs/memory-loading.md`: Task 2（作成）→ Task 3（AGENTS.md 内で `~/.dotfiles/docs/memory-loading.md` で参照）→ Task 3 Step 4（grep 検証）。一貫
- gwt.md パス: Task 4 Step 5 で `docs/superpowers/main/2026-06-21-agents-md-token-reduction-gwt.md`。spec フェーズの書き出しパスと一致

問題なし。

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/main/2026-06-21-agents-md-token-reduction-plan.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - 各タスクに fresh subagent を dispatch、タスク間で review、高速イテレーション

**2. Inline Execution** - このセッションで executing-plans を使ってタスクを順次実行、checkpoint で review

**Which approach?**
