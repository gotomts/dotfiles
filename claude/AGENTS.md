## Git Commit Rules

- NEVER squash unrelated commits when pushing or creating PRs（each commit は独立を保ち、ユーザーが明示的に squash を指示した場合のみ例外）
- When committing, always confirm the target repository (dotfiles vs project) before running git commands

## Push & PR Policy

- Never `git push` without explicit user authorization in the current message.
- Never force-push without explicit authorization. `--amend` の許可は push の許可ではない。
- Create PRs via the local review-then-submit flow, not direct `gh pr create`.
- Write PR descriptions to a file first; do not paste inline.
- Use 7-character commit hashes (GitHub short SHA standard) when referencing commits in docs/replies.

## Worktree Workflow

- Use the `wt` shell function instead of plain git branch/checkout when starting parallel work
- Never restore deliberately deleted local branches without explicit user confirmation
- When user mentions parallel work, default to worktree-based flow

## Configuration Scope

- 設定変更を行う前に、対象スコープ（global / per-project / per-repo）を明示してユーザーに確認すること。対象は git config・シェル alias / function・claude settings.json・エディタ設定など
- 「グローバルに入れる」と「このリポジトリだけ」では影響範囲が大きく異なるため、判断を委ねずに先に確認する

## Verification

- Always run verification from the repository root (e.g., `pnpm lint`, `pnpm type-check`, `pnpm test`), NOT scoped with `--filter`.
- Never use `| tail`, `| head`, or other pipes that mask exit codes when verifying. Check raw exit status.
- Report 'green' only after seeing the actual passing exit code, not partial output.

# コミュニケーション方針

- 技術的に誤った意見には根拠を示して反論すること。懸念・代替案は実装提案の前に伝える
- 曖昧な指示に対しては推測で進めず、具体的に確認すること
- 一問一答を徹底する。1 ターンにつき 1 つだけ質問し、ユーザーが yes / no または番号で答えられる選択肢化・二択化を行う。自由記述を要する問い・複数質問同時提示・他質問との混在は禁止
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

## Editing Discipline

- Honor 'extension only' / 'preserve existing code' constraints strictly: do not delete JSDoc, restructure tests, or change env vars unless explicitly requested.
- During md-discussion / design phase, do NOT make code changes — discuss only until plan is approved.
- Use absolute paths per the path convention rule; never relative.

# テスト

- ゴールデンテストを基本アプローチとし、種類・粒度はプロジェクトの規約に従う

# コミットメッセージ

- デフォルトは Conventional Commits（feat:, fix:, refactor: 等）に従う。プロジェクト固有の規約や既存のコミット履歴があればそちらを優先する

# マルチエージェント

- サブエージェントには明確なスコープと完了条件を与え、出力を検証する
- デフォルトの分業は Research → Synthesis → Implementation → Verification
- サブエージェントの調査結果をそのまま次のエージェントへ転送せず、オーケストレーター自身が理解・統合してから次の指示を書くこと
- サブエージェント向けプロンプトは自己完結であること。`based on your findings` のような理解責任の再委譲を禁止する
- read-only な探索は積極的に並列化し、同一ファイル群への write-heavy な作業は直列化すること
- 失敗修正や直前作業の継続は同一エージェント continuation を優先し、独立 verification や方針の全面変更は fresh context のエージェントを使うこと

# セッション管理

- 完了タスクの要約・整理はユーザーに指摘される前に行う
- コンテキスト圧縮警告 / ツール呼び出し増加時は作業状態の保存を提案する
- handoff skill の保存先・命名規約は `~/.dotfiles/claude/handoff-policy.md` に従う。「ハンドオフから再開」と言われたら同ファイルの規則で Read してから応答すること

## Resume / Handoff Protocol

- When invoked via handoff or resume, load context and produce a brief state summary, then STOP and wait for explicit user direction.
- Do NOT proactively call AskUserQuestion or propose next actions on resume — the user may be waiting for review or have their own next step.
- Verify handoff intent against spec/PR before implementing; do not assume direction of renames, removals, or ENV changes.

# 実装前検証

- 実装開始前に、関連する依存ライブラリの実際のバージョンと既存コードを確認する
- 前提条件（バージョン、API互換性、プロジェクト状態）をコメントで明示してから実装に入る

# フォーマッタ・リンタのスコープ

- フォーマッタやリンタは変更したファイルのみに適用すること
- git diff --name-only で対象を特定し、全体実行しないこと

# Document Dependency Check

- md ファイルの frontmatter に `depends-on` が宣言されているドキュメントはコード変更の影響を受ける可能性がある。コード変更タスク完了時に該当ドキュメントの更新要否を検討する
- ドキュメントの更新はユーザー承認後に行うこと。自動更新は禁止

# Knowledge Capture

- タスク完了時、作業中に得たプロジェクト固有の知見（アーキテクチャパターン・暗黙の制約・落とし穴・ドメイン知識・ビジネスルール・設計判断の根拠）を auto memory に記録する。コード/git history から自明な内容と一般論は除外
- 既存メモリ（MEMORY.md）と重複しないこと
- 記録件数の目安: 0〜3 件。該当なしなら記録不要。記録後、何を保存したかを通知する

# Local Overrides

- 優先順位: User CLAUDE.local.md > AGENTS.md（global）> Claude Code 既定挙動
- CLAUDE.local.md は PC 固有の設定・制約を記述するファイル。AGENTS.md の内容を上書きする
- 読み込みの仕組み・デバッグ手順は `~/.dotfiles/docs/memory-loading.md` 参照
