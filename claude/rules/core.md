# 進め方

- 沈黙は同意ではない。明示的に答えられたものだけが確定で、無反応・スルー・流れた話題は未定として扱う
- ユーザーへの確認は 1 ターン 1 問。選択肢を出すときは推奨案と「この推奨が崩れる条件」を添える

# 不可逆な操作

- merge（`git merge` / `gh pr merge` / `gh stack merge` / GitHub REST・GraphQL の merge API 経由、およびそれらの shell wrapper を含む）は実行しない。merge は人間が行う
- 意図的に stack した作業は GitHub 純正の stacked pull requests 機能を実際に使う。作成は `gh stack`（`gh extension install github/gh-stack` で導入済み。`gh stack init` / `add` / `submit`）で行い、各 dependent PR を「親 PR の head branch を base にした実際の stacked PR」にする（branch の祖先関係を手で真似ただけの PR は不可）。手動での代替を通常経路にせず、`gh stack` が使えない/対象外のケースは黙って別手段に迂回せず blocker として報告する
- 設定変更の前に、対象スコープ（global / per-project / per-repo）を明示して確認する
- 無関係なコミットを squash しない。コミットメッセージの既定は Conventional Commits

# 操作手段

- ブラウザ操作より先に、CLI で実行できないかを確認する

# Herdr

- Herdr の配布・更新経路は dotfiles の Homebrew 宣言（`nix/modules/darwin/homebrew.nix`）だけ。`herdr update` や `~/.local/bin/herdr` を作る自己更新・直接インストールは使わない。更新が必要なら `brew upgrade herdr` のみを使う
- Herdr を操作する前に `command -v herdr` が `/opt/homebrew/bin/herdr` に解決されることを確認する。異なれば操作せず停止して報告する

# 秘密情報

- 復号を含む手順を出す前に、復号せずに済む経路を先に探す（シークレットマネージャ等で同じ値を参照できないか / `VAR=$(...)` と `-e VAR` で画面に出さず渡せないか / そもそも人が値を見る必要があるか）。既存の手順書に復号手順が書かれていても、それが最善である保証にはならない

# 委譲

- サブエージェントの調査結果を素通しで次のエージェントへ渡さず、自分で理解・統合してから次の指示を書く

# コミュニケーションの使い分け

- 人間向け・リポジトリ散文（ドキュメント・コメント・コミットメッセージ・PR/レビュー文）は既定で日本語を使う
- コミットメッセージは Conventional Commits の type/scope トークン（`feat`/`fix`/`docs` 等の識別子と丸括弧内のスコープ名）と、やむを得ない固有名詞・技術識別子（コマンド名・ファイルパス・API/関数名・エラーメッセージ原文等）を除き、説明文は日本語で書く（例: `docs(rules): コミットメッセージの日本語化ルールを明文化`）
- エージェント間通信（Hermes↔Claude Code のタスク指示・状況報告・ブロッカー・検証結果）も既定で日本語を使う。定型の英語テンプレート（Goal / Scope / Do / Do not / Verification / Stop only if 等）は必須にしない。翻訳できない・すべきでないもの（コマンド・パス・API/関数名・エラーメッセージ原文、外部プロトコルが要求する機械可読フォーマット）だけは原文のまま残す
