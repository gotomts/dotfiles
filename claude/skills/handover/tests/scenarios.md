# 手動シナリオテスト

bats では検証できない統合動作（Claude が実際に SKILL.md を解釈して動くこと、
フックが Claude Code から実際に発火すること）を手動で検証する。

実行は実装完了後、最低 1 周通すこと。

## A. 基本サイクル: 書込 → 別セッション起動 → 引き継ぎ

1. 任意の git リポジトリで `claude` を起動
2. `/handover` を実行
3. `~/.claude/handover/{hash}/{branch}/{fingerprint}/state.json` と `handover.md` が作られていることを確認
4. `claude` を終了
5. 同じディレクトリで再度 `claude` を起動
6. **期待**: 起動直後に「未消費の handover があります、引き継ぎますか？」の確認が出る
7. 「引き継ぐ」と答え、内容が会話に反映されることを確認
8. `state.json` の `consumed: true` を確認

## B. ALL_COMPLETE は通知対象外

1. 全タスク完了状態（または tasks 空）で `/handover` 実行
2. `state.json` の `status` が `ALL_COMPLETE` であることを確認
3. 別セッションで起動
4. **期待**: 通知が出ない

## C. TTL 7日超は通知対象外

1. 過去のテスト用 state.json を `created_at: 10 日前` で配置
2. `claude` 起動
3. **期待**: 通知が出ない
4. `~/.claude/skills/handover/scripts/cleanup.sh` 実行で削除されることを確認（status=ALL_COMPLETE のとき）

## D. /handover clear で破棄

1. `/handover` で未消費メモを作る
2. `/handover clear` を実行
3. 別セッション起動
4. **期待**: 通知が出ない
5. `state.json` の `consumed: true` を確認

## E. 手動 /compact は事前に /handover が必要

1. 新規セッション起動（`/handover` 履歴なし）
2. `/compact` を実行
3. **期待**: コンパクトがブロックされ「セッション開始後に /handover を実行してから...」reason が表示される
4. `/handover` を実行
5. 再度 `/compact`
6. **期待**: 今度は通る

## F. 自動コンパクトでもブロック

1. コンテキストを大量に消費する作業を行い、自動コンパクトが発火する状態にする
2. `/handover` を打たずに継続
3. **期待**: 自動コンパクト発火時にブロックされる
4. `/handover` を実行 → 自動コンパクトが進む

## G. 同セッション続行: コンパクト後の重複通知抑止

1. `/handover` → `/compact`（成功）
2. コンパクト後に何かプロンプトを送る
3. **期待**: UserPromptSubmit で通知が出るのは最大 1 回のみ
4. もう一度プロンプトを送る
5. **期待**: 既にマーカーがあるので通知は出ない

## H. 別ブランチに切り替えると通知対象外

1. `feature/x` ブランチで `/handover`
2. `git checkout main` で別ブランチへ
3. 同セッションで `claude` を再起動
4. **期待**: `feature/x` の handover は通知対象外（プロジェクトハッシュ + ブランチ単位の分離が機能）

## I. /handover status

1. `/handover` でメモを作る
2. `/handover status` を実行
3. **期待**: 該当ブランチの未消費メモ一覧が表示される
4. `/handover clear` 後に `/handover status`
5. **期待**: `No active handovers.` 表示

## 結果記録

各シナリオ実行後、PR 説明欄に成否を記録すること:

| シナリオ | 結果 |
|---|---|
| A. 基本サイクル | □ |
| B. ALL_COMPLETE | □ |
| C. TTL 7 日超 | □ |
| D. /handover clear | □ |
| E. 手動 /compact ブロック | □ |
| F. 自動コンパクトブロック | □ |
| G. 重複通知抑止 | □ |
| H. ブランチ分離 | □ |
| I. /handover status | □ |
