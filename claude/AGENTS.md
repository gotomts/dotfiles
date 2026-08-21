<!-- 生成物: scripts/build-agent-rules.zsh が claude/rules/ から生成する。このファイルを直接編集しない -->
<!-- SSOT: claude/rules/core.md + claude/rules/worker.md -->

# 進め方

- 沈黙は同意ではない。明示的に答えられたものだけが確定で、無反応・スルー・流れた話題は未定として扱う
- ユーザーへの確認は 1 ターン 1 問。選択肢を出すときは推奨案と「この推奨が崩れる条件」を添える

# 不可逆な操作

- push / force-push / PR 作成は、その時点のメッセージでの明示許可なしに行わない（`--amend` の許可は push の許可ではない）
- 設定変更の前に、対象スコープ（global / per-project / per-repo）を明示して確認する
- 無関係なコミットを squash しない。コミットメッセージの既定は Conventional Commits

# 秘密情報

- 復号を含む手順を出す前に、復号せずに済む経路を先に探す（シークレットマネージャ等で同じ値を参照できないか / `VAR=$(...)` と `-e VAR` で画面に出さず渡せないか / そもそも人が値を見る必要があるか）。既存の手順書に復号手順が書かれていても、それが最善である保証にはならない

# 委譲

- サブエージェントの調査結果を素通しで次のエージェントへ渡さず、自分で理解・統合してから次の指示を書く

# 検証

- 検証コマンドは `| head` / `| tail` 等の pipe で exit code を隠さず実行し、実際の exit code を確認してから結果を報告する
- フォーマッタ・リンタは `git diff --name-only` の対象ファイルにだけ適用する

# handoff / resume

- handoff の作成と「ハンドオフから再開」への応答は `~/.dotfiles/claude/handoff-policy.md` に従う
