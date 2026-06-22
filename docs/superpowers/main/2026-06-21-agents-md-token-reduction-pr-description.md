## やったこと

- `claude/AGENTS.md` の冗長セクションを削除・圧縮（3.3k → ~2.3k tokens、約 -29%）
- Claude default 挙動と重複する `# コードレビュー` セクション全体と `# セキュリティ` の OWASP / 積極提案行を削除
- `# セッション管理` の handoff パス命名規約（700+ chars）を `claude/handoff-policy.md` に外部化し、AGENTS.md にはパス参照のみ残す
- `# Local Overrides` の import 解決経路解説を `docs/memory-loading.md` に外部化
- `## 出力方針` を `# コミュニケーション方針` に統合し独立セクションを削除
- その他セクションの文言を圧縮（squash 系項目の統合、対象例のインライン化、冗長な括弧書きの短縮等）

## 補足

- 外部化ファイル（`handoff-policy.md` / `memory-loading.md`）は **`@import` で auto-load しない**。AGENTS.md にパス参照だけ残し、エージェントが必要時に Read する read-on-demand 方式。これにより外部化ファイルの内容がメモリに乗らず、token 削減目的を達成できる。
- `# コードレビュー` セクションは厳密には Claude default と完全重複ではないが、ユーザー判断としてトークン削減を優先。実害が出た場合は `CLAUDE.local.md` 側で個別追加することでロールバック可能。
- handoff skill 本体（`claude/skills/handoff/SKILL.md`）は upstream（mattpocock/skills）同期方針のため触らず、PC 固有の運用規約のみを `claude/handoff-policy.md` に切り出した。

## 動作確認方法

> ※ AGENTS.md は CLI Claude Code が起動時に auto-load するため、ブラウザではなくターミナルで確認する。

1. `darwin-rebuild switch --flake .#default --impure` で nix 設定を適用する（既存 symlink の更新は副作用、新規ファイルは絶対パス参照のため symlink 不要）
2. Claude Code を再起動する
3. Claude Code 内で `/context` コマンドを実行する
4. メモリ階層の `claude/AGENTS.md` 行が **2.1k〜2.5k tokens** 範囲に収まることを確認する（期待値 ~2.3k）
5. ターミナルで `cat ~/.dotfiles/claude/handoff-policy.md` を実行し、handoff 規約が記述されていることを確認する
6. ターミナルで `cat ~/.dotfiles/docs/memory-loading.md` を実行し、memory load の仕組みが記述されていることを確認する
7. `grep -E "handoff-policy\.md|memory-loading\.md" ~/.dotfiles/claude/AGENTS.md` を実行し、両ファイルへのパス参照が AGENTS.md 内に残っていることを確認する
