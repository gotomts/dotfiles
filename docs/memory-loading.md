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
