# safe-worktree

Herdr のローカルプラグイン。allowlist に登録したリポジトリだけを対象に、
**リモートから取り直した実 SHA** を base にして linked worktree を作る。

## 何を防ぐか

Herdr 標準の `herdr worktree create --base <ref>` は `<ref>` をローカルで解決する。

```sh
herdr worktree create --branch feat/x --base main   # ローカルの main（数日前かもしれない）
herdr worktree create --branch feat/x --base HEAD   # 今チェックアウト中のコミット
```

どちらも成功して worktree ができるので、古い base で作ったことに気づくのは
だいたい PR を出したあとになる。このプラグインは

1. base をローカル ref のまま受け取らない（`HEAD` とローカルブランチ名は拒否）
2. 既定ブランチは毎回 `git ls-remote --symref origin HEAD` で問い合わせる
3. fetch してから SHA に解決し、その SHA を base として渡す
4. 作成後に実際の HEAD と突き合わせてから成功を報告する

の 4 点で、この経路を塞ぐ。2 のおかげで、上流が既定ブランチを付け替えても
（`v2` → `main` など）ローカルの設定を触らずに追従する。

## 使い方

### popup から（人間）

`herdr plugin action invoke dotfiles.safe-worktree.create` か、
`config.toml` にキーバインドを足して呼ぶ。

```toml
[[keys.command]]
key = "prefix+W"
type = "plugin_action"
command = "dotfiles.safe-worktree.create"
description = "safe worktree create"
```

popup が開いてブランチ名を尋ね、リポジトリ・base・SHA を表示してから確認を取る。

### コマンドラインから（エージェント含む）

```sh
~/.dotfiles/herdr/plugins/safe-worktree/bin/create.zsh --repo dotfiles --branch feat/x
```

| 引数 | 意味 |
| --- | --- |
| `--repo <label\|path>` | 対象リポジトリ。allowlist の `label` か作業ツリーのパス。省略時は Herdr の呼び出しコンテキスト → カレントディレクトリの順で解決する |
| `--branch <name>` | 作成するブランチ名。TTY があれば省略時に尋ねる |
| `--base <ref>` | 省略時はリモートの既定ブランチ。明示するなら `origin/<branch>` か存在するコミット SHA のみ |
| `--label <text>` | Herdr ワークスペースのラベル |
| `--reuse` | ローカルにブランチが既にある場合、新規作成の代わりに `herdr worktree open` で開く |
| `--yes` | 対話確認を省略する |
| `--focus` / `--no-focus` | 作成したワークスペースにフォーカスを移すか（既定は `--no-focus`） |

終了コード:

| コード | 意味 |
| --- | --- |
| 0 | 成功 |
| 1 | git / herdr の実行失敗、リモートへの問い合わせ不能、状態ディレクトリ・監査マーカーの書き込み失敗 |
| 2 | 引数・設定ファイルの不備 |
| 3 | origin URL が allowlist に無い |
| 4 | base として受け付けない ref |
| 5 | 既存ブランチでの新規作成要求（`--reuse` を促す） |
| 6 | 作成結果の照合失敗 |

## allowlist

設定は Herdr のプラグイン設定ディレクトリ
（`herdr plugin config-dir dotfiles.safe-worktree`）に置く。2 ファイルを結合して使う。

| ファイル | 実体 | 用途 |
| --- | --- | --- |
| `repos.json` | dotfiles の `config/repos.json` への symlink | 公開リポジトリ。dotfiles で追跡する |
| `repos.local.json` | マシンローカルの実ファイル | 非公開リポジトリ。追跡しない |

配置は `setup/herdr-sync.zsh`（Tier 2）が行う。ただし `herdr plugin link` は渡された
パスをそのまま登録先として保存するため、**primary チェックアウト（`~/.dotfiles`）から
実行したときだけ** link と設定配置を行う。使い捨ての worktree を登録すると、その worktree を
消した時点でプラグイン本体と allowlist の symlink が同時に壊れる。primary 以外から
実行された場合は link も設定配置も両方まとめてスキップする（片方だけ実行すると、
登録されているプラグインとは別の場所の allowlist を指す symlink が残る）。

`repos.json` が無い場合、
プラグインは「allowlist が空」ではなく「設定が壊れている」として fail-closed で停止する。

```json
{
  "version": 1,
  "defaults": { "remote": "origin" },
  "repos": [
    { "label": "dotfiles", "origin": "https://github.com/gotomts/dotfiles.git", "root": "~/.dotfiles" }
  ]
}
```

`origin` の突き合わせは scheme・userinfo・port・末尾の `.git` を無視した
`ホスト/パス` で行う。ssh 経由と https 経由で同じリポジトリを別物として扱わないため。
どちらかの URL が正規化できない場合は「不一致」として扱う（正規化に失敗した空文字列同士が
一致して allowlist をすり抜けるのを防ぐ）。
`root` は `--repo <label>` で場所を指定するときにだけ使う（allowlist の判定には使わない）。

**非公開リポジトリを `repos.json` に書かないこと。** このリポジトリは公開されており、
非公開リポジトリ名がそのまま外部に出る。`repos.local.json` を使う。

## 拒否する条件

| 条件 | 終了コード | 理由 |
| --- | --- | --- |
| origin が allowlist に無い | 3 | 対象外のリポジトリで worktree を作らない |
| base が `HEAD` / ローカルブランチ名 / 相対指定 | 4 | ローカルが古いまま作られる事故を防ぐ |
| base のリモートが設定と違う / ブランチ名が不正 / SHA が存在しない | 4 | 解決できない base を herdr へ渡さない |
| ローカルに同名ブランチがある | 5 | 新規作成ではない。`--reuse` で `open` に回す |
| リモートに同名ブランチがある | 5 | base から作ると同名で別履歴が 2 つできる。`--reuse` でも拒否する |
| リモートに問い合わせできない | 1 | 判定できないまま作らない |
| 状態ディレクトリを作れない / 監査マーカーを書けない | 1 | 監査できない作成をしない（`herdr` を呼ぶ前に停止する） |
| 設定 (`repos.json`) が置かれていない | 2 | allowlist が空なのか未配置なのか区別する |
| 値を取るオプションに値が無い | 2 | 引数解析を止める |
| 作成後の HEAD が渡した base と違う | 6 | 照合失敗。worktree は残したまま報告する |

リモートのブランチ有無は `git ls-remote` で毎回問い合わせる。ローカルの
`refs/remotes/<remote>/<branch>` を見ないのは、それ自体が古くなりうるため
（「fetch していないので気づかなかった」がこの plugin の防御対象そのもの）。
問い合わせ自体が失敗した場合は「存在しない」と読み替えず、判定不能として停止する
（ネットワーク障害のたびにリモートの同名ブランチを見落とすなら、この確認に意味が無い）。

## linked worktree からの呼び出し

`--repo` に linked worktree を渡しても、メイン作業ツリー
（`git worktree list --porcelain` の先頭）へ正規化してから herdr に渡す。理由は 2 つ:

1. Herdr の `worktree create` / `open` は linked worktree からの実行を
   `linked_worktree_source` エラーで拒否する
2. `worktree.created` イベントの `repo_root` は常にメイン作業ツリーを指すため、
   作成側が揃えないと監査マーカーのキーが一致せず、plugin 経由の作成が
   「直接作成」として誤検出される

## 監査（worktree.created）

Herdr の TUI キーバインドや素の `herdr worktree create` はこのプラグインを通らない。
`worktree.created` イベントフックが、そうした作成も含めて全件を
`${HERDR_PLUGIN_STATE_DIR}/audit.jsonl` に記録する。

| verdict | 意味 |
| --- | --- |
| `plugin_ok` | このプラグイン経由。HEAD が渡した base と一致 |
| `plugin_sha_mismatch` | このプラグイン経由だが HEAD が base と違う |
| `direct_create_at_known_tip` | 直接作成。base は既知の `origin/HEAD` と一致 |
| `direct_create_stale_base` | 直接作成。base が既知の `origin/HEAD` より古い |
| `direct_create_unexpected_base` | 直接作成。base が既知の `origin/HEAD` の履歴上にない |
| `direct_create_unverified` | 直接作成。`origin/HEAD` が未取得で判定できない |

`plugin_ok` 以外かつ allowlist 対象のリポジトリなら Herdr の通知も出す。

`herdr worktree open` は `worktree.created` を発火しない（herdr 0.8.2 で実機確認済み）。
そのため `--reuse` は監査ログにも通知にも現れない。

### 作成マーカー

`create.zsh` は作成直前に `${HERDR_PLUGIN_STATE_DIR}/pending/` へ期待値を書き、
イベントフックがそれを消費する。マーカーは `SWT_PENDING_TTL_SECONDS`（既定 120 秒）を
過ぎると無効になり、作成側とフックの両方が期限切れを掃除する。
時間切れのマーカーを信用すると、あとから同じリポジトリ・同じブランチ名で「直接」
作られた worktree が plugin 経由として承認されてしまうため、期限切れは一切信用しない。

マーカーの後始末は「worktree が作られていないと言い切れるか」で分ける。

| 失敗の種類 | 後始末 |
| --- | --- |
| herdr を呼ぶ前に落ちた | 即削除（作られていない） |
| herdr が JSON のエラーを返した | 即削除（要求が拒否されただけで作られていない） |
| それ以外の失敗・応答の解釈失敗 | TTL に任せる（作られたか分からない） |

最後の行で消しに行かないのは、`worktree.created` が create の応答より先に飛びうるため。
失敗と判断した側が消すと、フックが正当なマーカーを読む前に奪う競合になる。

マーカーを書けない場合は、`herdr` を呼ぶ前に exit 1 で停止する。監査できない作成を
黙って通すと「plugin 経由なのに直接作成として鳴る」誤検知になり、通知が信用されなくなる。

逆にイベントフック側は、状態ディレクトリを用意できなければ何も書かずに静かに終わる。
Herdr の worktree 作成自体は成功しているので、監査できないことを理由に利用者の操作を
止める筋合いはない（作成を止めるのは作成側の役目）。

### ログの大きさ

`audit.jsonl` が `SWT_AUDIT_MAX_BYTES`（既定 1 MiB）を超えたら `audit.jsonl.1` へ
1 世代だけ退避する。切り替えは `mkdir` のアトミック性でロックし、ロックが取れなければ
その回は見送る。追記自体はロックしない（1 行が `PIPE_BUF` より十分短く、`O_APPEND` の
単一 `write` はアトミックなため）。

判定はローカルに既知の `refs/remotes/<remote>/HEAD` に対して行う。イベントフックは
worktree 作成直後に走るため、ここでネットワーク I/O をして待たせない。
つまり「最後に fetch した時点のリモート像」に対する判定であって、リモートの現在値
そのものではない。

**このフックは監査だけを行う。** worktree の削除・base の付け替え・ブランチの作り直しは
一切しない。自動修復は「気づかないうちに作業が消える」側に倒れるため、意図的に持たない。

## 依存

zsh / git / jq / herdr。いずれも `nix/modules/darwin/homebrew.nix` で宣言済み。

## テスト

```sh
bats herdr/plugins/safe-worktree/tests/safe-worktree.bats
```

実際の herdr は呼ばない。worktree 作成はスタブが `git worktree add` に読み替える。
