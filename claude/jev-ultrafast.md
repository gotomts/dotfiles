# Jev Ultrafast の使い方（Claude Code / Hermes 共通）

`jev-ultrafast` は browser-use/jev-ultrafast を専用ブラウザで走らせる共有 CLI。Claude Code と
Hermes はこの同じファイルを読み、同じ条件で使う・やめる。実体は `scripts/jev-ultrafast.zsh`、
導入は `setup/jev-ultrafast.zsh`、revision・profile・port の宣言は `setup/lib/jev-ultrafast.zsh`。

## 使う条件

次をすべて満たすときだけ使う。

- 公開 Web ページ上の操作で、ログイン・既存 cookie・拡張機能が要らない
- ゴールを 1 つの自然言語で書け、検索・絞り込み・フォーム入力・ページを開く程度で終わる
- 速さに価値がある（Jev は 1 判断 1 往復で操作を選ぶ。スクリーンショットは使わない）
- 有料 API（TypeSafe と文字入力用の small LLM）を呼んでよい作業である

## 通常のブラウザ tool へ戻る条件

次のどれかに当たったら Jev を使わず（または使うのをやめ）、各 agent の通常のブラウザ tool
（Claude Code は agent-browser skill など、Hermes は組み込みの browser tool）へ戻る。

- ログイン済みセッション・認証・2 要素認証・既存の Chrome profile が必要
- 購入・予約・送信・投稿・削除・設定変更など、取り消せない操作や外部へ影響する操作を含む
- パスワード・API key・個人情報などの秘密をページへ入力する必要がある
- shadow root・iframe・canvas・ファイルアップロード・ポップアップタブ・入れ子スクロール・
  独自キーボード操作の UI が対象（upstream の MVP の範囲外）
- `status` が `blocked`、または同じゴールで 1 回失敗した（ブラウザ操作は自動で再試行しない）
- スクリーンショットや目視確認そのものが成果物である

## 安全境界

- ブラウザは Jev 専用 profile（`~/.local/state/jev-ultrafast/chrome-profile`）と専用 port
  （`127.0.0.1:9339`）だけを使う。普段の Chrome、実行中の live profile、Hermes の
  real-profile snapshot（`Profile 6`）には接続しない。それらで remote debugging を有効にしない
- `BU_CDP_URL` / `BU_CDP_WS` / `BH_HOME` を手で渡して接続先を変えない（CLI が毎回上書きする）
- 秘密値を `--goal`・`--url`・コマンドライン・ファイルへ書かない。API key は環境変数で受け取り、
  値を表示・ログ出力・検索しない。有無の確認は `jev-ultrafast doctor` で行う
- `done` は成功の証拠ではない。結果 JSON の `url` と `text` で、ゴールの成否を独立に確かめる

## 使い方

```sh
# 状態確認（revision・profile・専用ブラウザ・key の有無。値は出さない）
jev-ultrafast doctor

# 実行（API key が未注入なら opsa-development 経由で注入する）
opsa-development run -- jev-ultrafast run --url https://example.com --goal '<1 つのゴール>'
```

- `run` の経過は stderr、結果（`status` / `url` / `actions` / `elapsed_ms` / `text`）は stdout に
  JSON 1 行。終了コードは `done` で 0、`blocked` で 3、それ以外の失敗は非 0
- 専用ブラウザは `run` が必要なら起動し、起動済みなら再利用する。`jev-ultrafast browser` で
  先に起動だけもできる
- alias が使えない shell では `${HOME}/.local/bin/jev-ultrafast` と
  `zsh ${HOME}/.scripts/opsa-development.zsh` を直接呼ぶ
