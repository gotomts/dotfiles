# handover.md フォーマット

`state.json` から `render-md.sh` で自動生成される人間可読ビュー。直接編集禁止。

## サンプル出力

```markdown
# Handover: 2026-04-30 15:30

**Project**: /Users/goto/.dotfiles
**Branch**: main
**Status**: READY
**Session**: abc123-def456

## Session Summary
handover スキルの設計を進行中

## Tasks
- [ ] T1: handover スキル本体を実装 (in_progress)
  - Next: SKILL.md を docs/superpowers/specs/ から起こす

## Decisions
- **保存先**: `~/.claude/handover/{project-hash}/{branch}/` を採用
  - 却下: `.agents/`, `.handover.md`
  - 理由: プロジェクト側を汚さず、複数プロジェクト横断で集約管理できる

## Blockers
なし
```

## ルール

- ヘッダ時刻は `created_at` を `YYYY-MM-DD HH:MM` まで切り詰めて表示
- `tasks` が空配列なら `## Tasks` 直下に `なし`
- `decisions` が空配列なら `## Decisions` 直下に `なし`
- `blockers` が空配列なら `## Blockers` 直下に `なし`
- 完了タスクは `- [x]`、未完了は `- [ ]`
- `next_action` フィールドが存在するタスクのみ `- Next:` 行を追加
- `rejected` 配列が非空のときのみ `- 却下:` 行を追加
