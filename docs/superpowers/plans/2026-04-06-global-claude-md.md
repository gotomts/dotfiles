# グローバル CLAUDE.md 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Claude Code の全セッション・全プロジェクトに適用されるグローバルな CLAUDE.md を作成する

**Architecture:** `~/.dotfiles/claude/CLAUDE.md` にファイルを作成する。`setup.zsh` の既存ループ処理（24-30行目）により `~/.claude/CLAUDE.md` へ自動シンボリックリンクされるため、セットアップスクリプトの変更は不要。

**Tech Stack:** Markdown, zsh (symlink verification)

---

### Task 1: CLAUDE.md ファイルの作成

**Files:**
- Create: `claude/CLAUDE.md`

- [ ] **Step 1: CLAUDE.md を作成する**

`~/.dotfiles/claude/CLAUDE.md` に以下の内容で作成する:

```markdown
# コミュニケーション方針

- 技術的に誤った意見には根拠を示して反論すること。懸念・代替案は実装提案の前に伝える
- 曖昧な指示に対しては推測で進めず、具体的に確認すること

## 出力方針

- 設計・レビュー・分析は分割確認せず、完全な形で一度に出力すること

# コードレビュー

- レビューは厳格に行うこと。問題点は妥協せず明確に指摘する
- バグ、パフォーマンス問題、設計上の欠陥、可読性の低下を見逃さない
- セキュリティ上の懸念は最優先で指摘すること

# セキュリティ

- OWASP Top 10 に該当する脆弱性を発見した場合、即座に報告・修正すること
- セキュリティ改善の提案を積極的に行うこと（依頼がなくても）
- シークレット、認証情報、APIキーがコードやコミットに含まれないことを確認すること

# 実装規律

- 初回の実装パスでバリデーション（範囲制約、境界値、型チェック）を含めること
- コミット前に linter・型チェッカー・フォーマッター・テストを実行すること
- LSP が利用可能な場合、シンボル調査・定義元・参照箇所の特定に Grep/Glob より優先して使うこと
- 成果物（コード・ドキュメント・設計）を提出する前にセルフレビューを行うこと。プレースホルダー、矛盾、曖昧さがないことを確認する

# テスト

- テストは積極的に実装すること。Unit・Integration・E2E・VRT すべてを対象とする
- ゴールデンテストを基本アプローチとすること
- テストの種類・粒度はプロジェクトの規約に従うこと

# コミットメッセージ

- デフォルトは Conventional Commits（feat:, fix:, refactor: 等）に従うこと
- プロジェクト固有の規約や既存のコミット履歴がある場合はそちらを優先すること

# マルチエージェント

- サブエージェントには明確なスコープと完了条件を与え、作業の重複を防ぐこと
- サブエージェントの出力は検証すること
- デフォルトの分業は Research → Synthesis → Implementation → Verification とすること
- サブエージェントの調査結果をそのまま次のエージェントへ転送せず、オーケストレーター自身が理解・統合してから次の指示を書くこと
- サブエージェント向けプロンプトは自己完結であること。`based on your findings` のような理解責任の再委譲を禁止する
- read-only な探索は積極的に並列化し、同一ファイル群への write-heavy な作業は直列化すること
- 失敗修正や直前作業の継続は同一エージェント continuation を優先し、独立 verification や方針の全面変更は fresh context のエージェントを使うこと

# セッション管理

- 完了タスクの要約・整理はユーザーに指摘される前に行うこと
- コンテキスト圧縮警告が出た場合やツール呼び出しが多くなった場合、作業状態の保存を提案すること
- 中断・再開に備え、進行中のタスク状況・決定事項・既知の問題を構造化して記録できる状態を維持すること

# 実装前検証

- 実装開始前に、関連する依存ライブラリの実際のバージョンと既存コードを確認すること
- 前提条件（バージョン、API互換性、プロジェクト状態）をコメントで明示してから実装に入ること

# フォーマッタ・リンタのスコープ

- フォーマッタやリンタは変更したファイルのみに適用すること
- git diff --name-only で対象を特定し、全体実行しないこと

# Document Dependency Check

- md ファイルの frontmatter に `depends-on` が宣言されている場合、そのドキュメントはコード変更の影響を受ける可能性がある
- コード変更を含むタスクを完了する際、関連ドキュメントの更新が必要か検討すること
- ドキュメントの更新はユーザー承認後に行うこと。自動更新は禁止

# Knowledge Capture

- タスク完了時、作業中に得たプロジェクト固有の知見を auto memory に記録すること
- 対象: アーキテクチャパターン、暗黙の制約・落とし穴、ドメイン知識・ビジネスルール、設計判断の根拠
- 除外: コード/git history から自明なもの、一般的なベストプラクティス
- 既存メモリ（MEMORY.md）と重複しないこと
- 記録件数の目安: 0〜3件。該当なしなら記録不要
- 記録後、何を保存したかを通知すること
```

- [ ] **Step 2: ファイルの内容を検証する**

Run: `cat ~/.dotfiles/claude/CLAUDE.md | head -5`
Expected: `# コミュニケーション方針` が先頭に表示される

- [ ] **Step 3: コミットする**

```bash
git add claude/CLAUDE.md
git commit -m "add: グローバル CLAUDE.md を作成"
```

### Task 2: シンボリックリンクの検証

**Files:**
- Verify: `~/.claude/CLAUDE.md` (symlink)

- [ ] **Step 1: 現在のシンボリックリンク状態を確認する**

Run: `ls -la ~/.claude/CLAUDE.md 2>/dev/null || echo "symlink not found"`
Expected: シンボリックリンクが存在しない場合は "symlink not found" が表示される

- [ ] **Step 2: setup.zsh のシンボリックリンク処理を実行する**

`setup.zsh` の claude ディレクトリ用ループ（24-30行目）を手動で実行して、CLAUDE.md のシンボリックリンクを作成する:

```bash
cd ~/.dotfiles/claude && for name in *; do if [[ -L ${HOME}/.claude/$name ]]; then unlink ${HOME}/.claude/$name; fi; ln -sfv ${PWD}/${name} ${HOME}/.claude/${name}; done
```

Expected: `'~/.claude/CLAUDE.md' -> '~/.dotfiles/claude/CLAUDE.md'` を含む出力

- [ ] **Step 3: シンボリックリンクが正しいことを確認する**

Run: `ls -la ~/.claude/CLAUDE.md && head -1 ~/.claude/CLAUDE.md`
Expected: シンボリックリンクが `~/.dotfiles/claude/CLAUDE.md` を指しており、先頭行に `# コミュニケーション方針` が表示される

- [ ] **Step 4: コミットする（変更がある場合のみ）**

```bash
git status
```

Expected: `nothing to commit, working tree clean`（ファイル作成は Task 1 でコミット済み）
