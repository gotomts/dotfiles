# herdr-notify

`herdr agent prompt` で送信したプロンプトが `done` / `blocked` に達したことを検知し、
送信元の Discord スレッドへ自動通知する。SOUL.md / memory の「即時報告」は助言に過ぎず、
Hermes が次のターンを回さなければ報告が飛ばない問題を、herdr の状態監視で仕組み化して解消する。

## コマンド

Nix 管理下には置かず、`python3 aliase/herdr-notify/cli.py` を直接叩く（PATH 登録が要る場合は
呼び出し側で任意にエイリアス・symlink を張ってよい）。

```sh
# prompt を送信し、Discord スレッドと紐づけて記録する
python3 aliase/herdr-notify/cli.py submit <target> "<prompt本文>" --channel <discord-channel-id> --thread <discord-thread-id> [--mention <discord-user-id>]

# 標準入力から本文を渡す場合
echo "本文" | python3 aliase/herdr-notify/cli.py submit <target> - --channel <id> --thread <id>

# pending レコードを1回分チェックし、done/blocked を検知したものだけ通知する
python3 aliase/herdr-notify/cli.py tick [--dry-run]
```

- `<target>` は `herdr agent list` の `name`（無ければ `agent`）または `pane_id`。
  `herdr agent prompt <target> ...` にそのまま渡せる値と同じ。
- `submit` は `herdr agent prompt` を実行した**後**にレコードを作成する。prompt 送信に
  失敗した場合はレコードを作らず exit 1。
- `tick` は 1 回分の処理のみを行う。常駐プロセスは持たない（下記「起動方法」参照）。

## 起動方法（監視の起動）

`tick` を定期実行することで監視を実現する（常駐デーモンなし = ポーリング方式、DOT設計判断）。
このリポジトリは `tick` の cron/launchd 登録そのものは宣言しない
（`~/.hermes/` や `~/.codex/config.toml` と同様、実行環境固有の running config は
dotfiles の管理対象外という既存方針を踏襲）。実際に有効化するには、以下のいずれかを
ユーザー側で用意する。

- 簡易: `crontab -e` で `*/2 * * * * python3 $HOME/.dotfiles/aliase/herdr-notify/cli.py tick >> ~/.herdr-notify/tick.log 2>&1` のような行を追加
- launchd: `~/Library/LaunchAgents/` に `StartInterval` 120 秒程度の plist を用意し、
  `ProgramArguments` に `python3 $HOME/.dotfiles/aliase/herdr-notify/cli.py tick` を指定する
- Hermes 自身の cron agent 機構（`~/.hermes/cron`）から呼ぶ

いずれの方式でも `tick` は多重起動しても安全（`~/.herdr-notify/tick.lock` で排他）。

## 仕組み

```
Hermes (orchestrator)
   │ herdr-notify submit <target> <text> --channel <id> --thread <id> [--mention <id>]
   ▼
cli.py submit
   │ 1) herdr agent get <target> で pane_id / cwd を解決
   │ 2) herdr agent prompt <target> <text> を実行(送信のみ、--wait しない)
   │ 3) ~/.herdr-notify/records/<uuid>.json にレコード作成 (status: pending)
   ▼
定期実行 (cron/launchd 等)
   ▼
cli.py tick
   │ pending レコードを走査 → herdr agent get <target> で現状態確認
   │ done/blocked を検知したら discord.post_reply で元スレッドへ投稿
   │ → レコードを status: notified に更新 (compare-and-swap で二重通知防止)
```

- 状態ファイルは **dotfiles リポジトリの外**（既定 `~/.herdr-notify/`）に置く。
  スレッド ID・agent 名などユーザー実行時情報をリポジトリへ残さないため
  （`~/.hermes/` と同じ運用パターン）。
- Discord への投稿は `~/.hermes/scripts/post_discord_thread.py` と同じ認証パターンを再利用する
  （`DISCORD_BOT_TOKEN` は環境変数優先、無ければ `~/.hermes/.env` から読む。token をログ・
  引数・例外メッセージへ出さない）。新規スレッド作成はせず、既存スレッドへの返信のみ行う。

## 再起動・プロセス異常への耐性

`tick` は毎回すべての `pending` レコードを `herdr agent get` で再確認する副作用のない処理で、
常駐プロセスの生存に依存しない。プロセスがクラッシュしても、次の `tick` 実行が未配信の
状態変化を拾う。二重投稿は「投稿前にレコードを `pending → notifying` へ原子的に進め、
既に他プロセスが進めていたら黙ってスキップする」compare-and-swap で防ぐ。

## 混線防止

1 レコード = 1 herdr agent target = 1 Discord スレッドの 1 対 1 対応。レコードには
`discord_thread_id` を保持しており、常にそのレコード自身のスレッドにのみ投稿する
（複数リポジトリ・複数スレッドを横断する共有状態は持たない）。

## 通知本文（捏造しない）

エージェントの作業内容・テスト結果の要約は書かない。エージェント自身の出力を
`herdr agent read <target>` で確認させる設計。

- `done`: 「done（Hermes検証待ち）」と明示し、次アクションとして
  `herdr agent read <target>` で差分・テスト結果を確認してから検証するよう促す
- `blocked`: 「blocked（質問を確認して中継が必要）」と明示し、次アクションとして
  `herdr agent read <target>` で最新の質問を確認し中継するよう促す

## 権限について

本ツールは Discord への通知を自動化するだけで、commit / push / PR / merge など
外部変更の許可を発生させない。

## テスト

```sh
python3 -m unittest discover -s tests
```

外部ネットワーク・herdr・Discord への実アクセスは行わない（すべてモック）。

## 既知の限界

- `tick` の実行間隔ぶんだけ通知が遅延する（cron間隔に依存、目安 1〜2 分）
- `pending` のまま対象 agent が終了・worktree が削除されると、レコードは永久に
  `pending` のまま残る（自動 GC は未実装。手動で `~/.herdr-notify/records/` から削除する）
- `herdr agent get` の `agent_status` が `unknown` になるケースは通知対象に含めていない
  （`done`/`blocked` のみを終端状態として扱う）
