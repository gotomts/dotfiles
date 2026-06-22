---
title: claude/AGENTS.md トークン削減 — 受け入れ条件（GWT）
issue: N/A
design: ./2026-06-21-agents-md-token-reduction-design.md
summary: ./2026-06-21-agents-md-token-reduction-summary.md
---

# claude/AGENTS.md トークン削減 — 受け入れ条件

> Given-When-Then 形式。各 AC は独立した検証単位。design の方式・summary の TL;DR を満たすことを確認する受け入れ基準とする。

## AC-1: AGENTS.md のトークン数が削減目標に達する

- **Given**: `claude/AGENTS.md` 編集後、`darwin-rebuild switch` で symlink が更新されている
- **When**: Claude Code を起動し `/context` を実行する
- **Then**: メモリ階層に表示される `claude/AGENTS.md` の token 数が **2.1k〜2.5k tokens の範囲**に収まる（目標値 ~2.3k、許容幅 ±200）

## AC-2: 外部化ファイル `claude/handoff-policy.md` が機能する

- **Given**: `claude/handoff-policy.md` がコミット済みで symlink 展開されている
- **When**: 「ハンドオフから再開」をユーザーが指示し、エージェントが AGENTS.md の参照記述に従って `~/.dotfiles/claude/handoff-policy.md` を Read する
- **Then**: ファイルが存在し、保存先パス規約・`<repo-slug>` 解決ロジック・`<branch-slug>` 解決ロジック・`$TMPDIR` OS 差分・skill 本体との関係がすべて記述されている

## AC-3: 外部化ファイル `docs/memory-loading.md` が機能する

- **Given**: `docs/memory-loading.md` がコミット済みである
- **When**: メモリ load 周りのデバッグでエージェントが AGENTS.md の参照記述に従って `~/.dotfiles/docs/memory-loading.md` を Read する
- **Then**: ファイルが存在し、優先順位ルール・import 経路 3 段階・`/memory` 確認手順・PC 別の `CLAUDE.local.md` 不在時の挙動が記述されている

## AC-4: AGENTS.md 残存記述が外部ファイルへの参照を含む

- **Given**: AGENTS.md 編集が完了している
- **When**: `grep -E "handoff-policy\.md|memory-loading\.md" claude/AGENTS.md` を実行する
- **Then**: 両方のファイル名がヒットし、それぞれ `~/.dotfiles/` 配下の絶対パスで参照されている

## AC-5: nix build が成功する

- **Given**: 新規ファイル追加 + AGENTS.md 編集が完了している
- **When**: `USER=ciuser nix build .#darwinConfigurations.default.system --no-link --impure` を実行する
- **Then**: build が exit 0 で完了する

## AC-6: 削除されたルールが Claude default でカバーされる

- **Given**: `#6 コードレビュー` セクションと `#7 L40 OWASP` 行が削除されている
- **When**: Claude Code の system prompt（`/context` で確認可能な範囲）を確認する
- **Then**: OWASP top 10 への注意・即座の修正・安全なコード作成の優先方針が default に含まれていることを目視で確認できる

## 異常系 / エッジケース

### AC-E1: 別 PC で `CLAUDE.local.md` が無い場合のフォールバック

- **Given**: `~/.claude/CLAUDE.local.md` が存在しない PC で本変更を適用する
- **When**: Claude Code を起動する
- **Then**: `@CLAUDE.local.md` の import が skip され、エラーなく起動する。AGENTS.md と外部化ファイルへの参照は通常通り機能する

### AC-E2: 外部化ファイルへの参照が壊れた場合の挙動

- **Given**: `claude/handoff-policy.md` を誤って削除した状態でエージェントがハンドオフ再開を試みる
- **When**: エージェントが AGENTS.md の参照記述に従ってファイルを Read する
- **Then**: Read がエラーになり、エージェントはエラー内容をユーザーに報告して手を止める（推測で進めず確認するルールに従う）

## スコープ外（受け入れ対象としない）

- project AGENTS.md（dotfiles リポジトリ内の 5.2k tokens）のトークン数削減
- handoff skill 本体のロジック改変
- AGENTS.md の文体統一・トーン揃え
- token 削減量の数値検証は ±200 tokens の許容幅内（厳密一致は要求しない）

## 検証チェックリスト

> 各 AC の検証状況を一覧で管理する。テストして AC を満たしたら `- [ ]` を `- [x]` に書き換える。

- [ ] AC-1: AGENTS.md のトークン数が削減目標に達する
- [ ] AC-2: 外部化ファイル `claude/handoff-policy.md` が機能する
- [ ] AC-3: 外部化ファイル `docs/memory-loading.md` が機能する
- [ ] AC-4: AGENTS.md 残存記述が外部ファイルへの参照を含む
- [ ] AC-5: nix build が成功する
- [ ] AC-6: 削除されたルールが Claude default でカバーされる
- [ ] AC-E1: 別 PC で `CLAUDE.local.md` が無い場合のフォールバック
- [ ] AC-E2: 外部化ファイルへの参照が壊れた場合の挙動

## 変更履歴

> テスト実施でバグが発覚し AC を修正した場合や、仕様変更で受け入れ条件が更新された場合に追記する。新しいエントリを上に積む（逆時系列）。

- 2026-06-21: 初版作成
