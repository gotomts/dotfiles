# 検証

- 検証コマンドは `| head` / `| tail` 等の pipe で exit code を隠さず実行し、実際の exit code を確認してから結果を報告する
- フォーマッタ・リンタは `git diff --name-only` の対象ファイルにだけ適用する

# handoff / resume

- handoff の作成と「ハンドオフから再開」への応答は `~/.dotfiles/claude/handoff-policy.md` に従う
