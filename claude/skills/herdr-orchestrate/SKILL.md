---
name: herdr-orchestrate
maintainer: gotomts
description: herdr 上で親セッションをオーケストレーターとして使い、issue (GitHub 番号 / Linear ID) から worktree + workspace + タブを作り、子 Claude セッションを起動して初回プロンプトを投入し、Linear 起点なら status を In Progress に進める。起動済みの子セッション群を巡回して blocked / done を拾い質問に回答するモードと、未コミット・未 push を数えてから worktree / タブ / ブランチをどこまで消すか確認して落とすモードも持つ。「ABC-123 立ち上げて」「issue 46 を別セッションで走らせて」「並行で回したい」「子セッション起動して」「各セッションの状況どう」「blocked ないか見て」「巡回して」「ABC-123 落として」「あのタブ閉じて」「もう要らないから片付けて」など、複数 issue の並行進行・起動済みセッションの様子見・子セッションの後片付けを示唆する文脈で必ず使う。対象は起動元セッションと同じリポジトリの workspace のみで、別リポジトリの子には触らない。worktree を作るだけで子セッションを起こさないなら wt-start を使う。
argument-hint: "[<issue-id> | patrol]  # 例: ABC-123 / 46 / patrol"
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
---

# herdr-orchestrate

親セッション (このセッション) を「issue を配る側」に固定し、実作業は issue ごとの worktree で走る子 Claude セッションに任せるためのスキル。

herdr は workspace / tab / pane の階層で端末を持ち、pane に入った coding agent の状態 (`idle` / `working` / `blocked` / `done`) を認識する。この状態認識があるので、親は「どの子が詰まっているか」をポーリングで拾える。手で各タブを覗いて回る作業がこのスキルの置き換え対象。

## 前提チェック (最初に必ず)

```sh
test "${HERDR_ENV:-}" = 1
```

`HERDR_ENV=1` でなければ herdr 管理下の pane で動いていない。その場合は「herdr の外なので worktree タブを作れない」と伝えて中断する。herdr 外から socket を叩くと、どの workspace を親とみなすかが決まらず誤ったところにタブが生える。

親自身の位置は環境変数で分かる: `HERDR_WORKSPACE_ID` / `HERDR_TAB_ID` / `HERDR_PANE_ID`。

## スコープ: 起動元リポジトリのみ

**このスキルが触ってよいのは、起動元セッションと同じリポジトリの workspace だけ。** 他リポジトリの子には、起動も巡回も停止もしない。

herdr は 1 つの画面に複数リポジトリの workspace を同居させる。`herdr agent list` は**全 workspace の agent を無差別に返す**ので、絞らずに使うと別プロジェクトの作業中セッションにプロンプトを投げたり、落としたりできてしまう。親は他リポの文脈を持っていないので、そこで何が起きているか判断する材料がない。

### 対象 workspace の求め方

```sh
repo_root=$(git rev-parse --show-toplevel)
herdr worktree list --cwd "$repo_root" --json
```

`--cwd` を渡すと、そのリポジトリの worktree だけが返る (渡さないと**フォーカス中の workspace のリポジトリ**が対象になり、親がどの pane に居るかで結果が変わる。必ず明示する)。

返る各 worktree の `open_workspace_id` が対象の workspace ID。このフィールドが無いものは herdr で開いていない worktree (`wt` などで作ったもの) なので、対象外として扱う。

これに親自身の `HERDR_WORKSPACE_ID` を加えた集合が、このスキルの守備範囲。

### 絞り込みの適用

- **巡回モード** — `herdr agent list` の結果を `workspace_id` が上の集合に入るものだけに絞る。範囲外の agent は状態も報告しない (「別リポで 3 つ動いています」も余計な情報)
- **停止モード** — 対象が範囲外なら実行せず、「別リポジトリ (`<repo_name>`) の workspace なので、そちらのセッションから操作してください」と伝えて止まる
- **起動モード** — `herdr worktree create --cwd "$(git rev-parse --show-toplevel)"` が自リポに閉じるので追加の絞りは不要

ユーザーが明示的に別リポの workspace ID を指定してきた場合だけは例外だが、そのときも「別リポですが本当に操作しますか」と 1 問確認する。issue ID の取り違えで隣のプロジェクトを消すのが一番ありがちな事故。

## モード判定

- 引数が `patrol` / 「状況」「巡回」「様子」「blocked」等を含む → **巡回モード**
- 「落とす」「閉じる」「片付ける」「終わり」「もういい」等 → **停止モード**
- 引数が issue 識別子、または「立ち上げて」「走らせて」等 → **起動モード**
- 判断がつかない → 1 問で確認する

---

## 起動モード

### Step 1: issue を特定する

引数の形で取得先が決まる。

| 形 | 例 | 取得先 |
|---|---|---|
| `^[0-9]+$` | `46` | GitHub (`gh`) |
| `^[A-Z]+-[0-9]+$` | `ABC-123` | Linear |
| GitHub issue URL | `https://github.com/o/r/issues/123` | GitHub (`gh`) |

**GitHub:**

```sh
gh issue view <N> --json number,title,body,labels
```

リポジトリは起動元の remote から自動解決される。URL 形式なら `--repo <owner/repo>` を付ける。

**Linear:**

Linear MCP が使えるならそれで取得する (本文をそのまま扱えるため)。無ければ `linear issue view <ID>` にフォールバックする。

取得に失敗したら (auth 切れ、issue 不在) そこで止めて原因をユーザーに見せる。推測した issue 内容で worktree を作ると、後から気づいたときにブランチごと捨てる羽目になる。

### Step 2: 3 つの名前を決める

herdr は用途ごとに別の名前空間を使うので、1 つの issue に対して 3 つ決める。制約が違うので使い回せない。

| 用途 | 例 | 制約 |
|---|---|---|
| ブランチ名 | `fix/flaky-login-redirect-issue-ABC-123` | git の制約のみ |
| タブ label | `ABC-123` | 自由 (大文字可) |
| agent 名 | `abc-123` | **小文字始まり、`[a-z0-9_-]` のみ、1〜32 文字** |

agent 名の制約は実際にエラーで弾かれる (`invalid_agent_name`)。issue ID をそのまま渡さず小文字化する。

**ブランチ命名規約** — 対象リポジトリの既存ブランチに合わせる。`git branch --list` で数本見れば規約が読める。読めない場合の既定は:

```
<type>/<kebab-slug>-issue-<ISSUE-ID>
```

- **type**: `feat | fix | refactor | docs | chore | test` を issue タイトルから推測 (Add/Implement → `feat`、Fix/Bug → `fix`、Refactor → `refactor`、Doc → `docs`)。推測がつかなければ `feat`
- **kebab-slug**: lowercase 3〜5 単語。日本語タイトルは英訳する
- **ISSUE-ID**: Linear は `ABC-123`、GitHub は番号のみ (`46`)

規約をリポジトリごとに読み直すのは、`wt-start` (手動作業用) と規約が食い違っているリポジトリが実在するため。手で作った worktree と AI が作った worktree でブランチ名の形が違うと、`git branch` を見たときにどちらの経路で作ったか分からなくなる。

### Step 3: base を決める

既定は `origin/main`。ローカル `main` は fetch 遅れで古いことがあるため使わない。

default branch が `main` でないリポジトリを踏む可能性があるので検出する:

```sh
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||'
```

### Step 4: 一度だけ承認を取る

worktree 作成・タブ生成・子セッション起動・プロンプト投入をまとめて 1 回で見せる。子が走り出すと止めるコストが高いので、投入する初回プロンプトの本文まで見せてから実行する。

```
issue:   ABC-123 / Add push notification opt-in
branch:  fix/push-notification-opt-in-issue-ABC-123
base:    origin/main
タブ名 / セッション名:  ABC-123   (agent 名: abc-123)
Linear:  Todo → In Progress
初回プロンプト:
  <実際に投げる本文をそのまま>

これで起動しますか? (yes / branch 名を変える / プロンプトを直す)
```

### Step 5: 実行

**5-1. worktree + workspace を作る**

```sh
herdr worktree create \
  --cwd "$(git rev-parse --show-toplevel)" \
  --branch <branch> \
  --base <base> \
  --label <ISSUE-ID> \
  --no-focus --json
```

`--no-focus` は親の視界を奪わないため。起動直後に画面が飛ぶと、親セッションで次の issue を仕込む作業が中断される。

作られた workspace はサイドバーで親リポの workspace の下にグループ表示される。配置は `~/.herdr/worktrees/<repo>/<branch-slug>` (slug は小文字化される)。手動作業の `wt` が使う `<repo>.<slug>` とは別の場所になるが、これは「AI が立てたものはここ」という識別として機能する。

JSON から 3 つの ID を取る。ID は不透明な文字列なので、必ず JSON から読む — `wE:p1` のような形から自分で組み立てない:

```sh
.result.workspace.workspace_id   # 例 wE
.result.root_pane.tab_id         # 例 wE:t1
.result.root_pane.pane_id        # 例 wE:p1
```

**5-2. タブに issue ID を付ける**

`worktree create --label` は workspace 名にしか効かず、タブ名は `1` のまま残る。タブ一覧で issue を見分けたいので明示的に rename する:

```sh
herdr tab rename <tab_id> <ISSUE-ID>
```

**5-3. 子 Claude を起動する**

```sh
herdr agent start <agent-name> --kind claude --pane <pane_id>
```

agent 名を付けておくと、以降の `agent prompt` / `agent read` / `agent get` をその名前で引ける。名前なしで手動起動された agent は `pane_id` でしか指定できず、巡回時の扱いが面倒になる。

pane が対話シェルプロンプトに居ないと失敗する。作りたての worktree pane なら通常は問題ない。失敗したら `herdr agent explain` で検出状態を見る。

**5-4. Claude Code のセッション名を付ける**

```sh
herdr agent prompt <agent-name> "/rename <ISSUE-ID>"
```

これは本命のプロンプトより先に送る。Claude Code はセッション名を未設定のままだと直近の作業内容を要約したタイトルを出し続けるので、サイドバーの表示が作業のたびに変わって issue と結びつかなくなる。`/rename` を通すとタイトルがそこで固定され、issue ID のまま残る。

タブ label と同じ大文字表記でよい (agent 名だけが小文字制約を持つ)。反映されたかは `herdr agent get <agent-name>` の `terminal_title_stripped` で確認できるが、送信直後は 1 秒ほど古い値が返る。確認するなら一拍置くか、次のステップに進んでから見る。

**5-5. 初回プロンプトを投入する**

```sh
herdr agent prompt <agent-name> "<本文>"
```

`--wait` は付けない。親は制御を即座に取り戻して次の issue に進む必要がある。

本文の組み立て方 — 子は issue の文脈を一切持っていないので、これだけで作業を始められる形にする:

```
<ISSUE-ID>: <title>

<issue 本文>

このリポジトリの worktree (branch: <branch>) で作業しています。
まず着手前に方針を 3〜5 行で整理して、そこで一度止まってください。
判断に迷う点があれば実装を進めず質問として出してください。
```

「一度止まる」を入れているのは、親が巡回で拾える形にするため。子が黙って最後まで走ると、方針違いに気づくのが PR 段階になる。逆に「止まらず最後までやって」と明示された issue なら、この行は外してよい。

**5-6. Linear の status を進める**

Linear 起点の issue なら、子が動き出した時点で status を更新する:

```sh
linear issue update <ISSUE-ID> -s "In Progress"
```

`--team` は不要 (issue ID から解決される)。同じ値を設定しても成功するので、既に In Progress でも気にしなくてよい。

これを入れているのは、**GitHub 連携の自動遷移が push 時にしか発火しない**ため。worktree を作って子を走らせた段階では push されていないので、Linear 上は Todo のまま残る。並行で 5 本も走らせると、Linear を見ても何に着手済みか分からなくなる。後で push されたとき自動遷移が走るが、同じ状態への遷移なので競合しない。

status 名は全 team で `In Progress` を確認済み。名前が違う team を踏んで失敗したら、その team の workflow state を引いて `type: started` かつ `In Review` でないものを選ぶ:

```sh
linear api 'query { teams(filter: { key: { eq: "<KEY>" } }) { nodes { states { nodes { name type } } } } }'
```

`type: started` には `In Progress` と `In Review` の両方が該当するので、type だけで選ぶと In Review を引く。名前で判断する。

GitHub issue 起点の場合、issue に status の概念がないのでこのステップは飛ばす。

### Step 6: 制御を返す

作ったものを 3 行で報告して終わる。親がここで待たないことが並行数を稼ぐ前提になっている。

```
ABC-123 起動: workspace wE / タブ ABC-123 / branch fix/...-issue-ABC-123
worktree: ~/.herdr/worktrees/<repo>/<slug>
Linear:   In Progress
次: 続けて別の issue を起動するか、patrol で様子を見る
```

---

## 巡回モード

### Step 1: 全体の状態を取る

```sh
herdr agent list
```

返った agent を「スコープ」で求めた workspace 集合で絞る。このコマンドは全リポジトリの agent を返すので、絞らないと別プロジェクトの状態まで報告してしまう。

返る各 agent で見るフィールド:

- `agent_status` — 状態 (下記)
- `name` — `agent start` で名付けたもの。**手動で立てたタブは空**になるので、その場合は `pane_id` を指定に使う
- `tab_id` — `herdr tab list` の label と突き合わせると issue ID が分かる
- `terminal_title_stripped` — Claude Code のセッション名。このスキルが起動した子は `/rename` 済みなので issue ID が入る。手動タブで `/rename` されていないものは直近の作業を要約したタイトルになり、何をしているかの手掛かりとして読める

`agent_status` の意味:

- `idle` — 入力待ち。タブは UI で確認済み
- `done` — 未確認のまま作業が終わった状態の idle。**見に行くべき筆頭**
- `blocked` — 承認 UI か質問を検出。**止まっている**
- `working` — 実行中。触らない
- `unknown` — agent は居るが分類できない

### Step 2: 要注意のものだけ読む

`blocked` と `done` に絞る。`working` を読みに行くと出力が途中で意味を成さず、トークンを食うだけになる。

```sh
herdr agent read <agent-name-or-pane-id> --source recent-unwrapped --lines 120
```

### Step 3: 親が要約して報告する

読んだ生ログをそのまま貼らない。1 件あたり 2〜3 行に落とす:

```
ABC-123  blocked — DB マイグレーションの後方互換を壊してよいか確認待ち
ABC-124  done    — 実装+テスト完了。PR 未作成
ABC-125  working — 触らない
```

このスキルが起動していない手動タブも `agent list` には出る。それらも状態は読めるので報告に含めてよいが、勝手にプロンプトを投げない (親が文脈を持っていないため)。

### Step 4: 回答する

`blocked` の子に返す内容は、親が決めてよいものとユーザーの判断が要るものに分かれる。

- リポジトリの規約や既存コードを見れば決まること → 親が調べて回答してよい
- 仕様・優先度・破壊的変更の可否 → ユーザーに 1 問ずつ確認する

回答の投入:

```sh
herdr agent prompt <agent-name-or-pane-id> "<回答>"
```

複数の子が同時に blocked のときは 1 件ずつ順に片付ける。まとめて質問をユーザーに投げると、どの回答がどの子のものか取り違える。

---

## 停止モード

子を落とすとき、消える対象は 3 段階ある。どこまで消すかは中身を見ないと決められないので、確認してから聞く。

| 操作 | workspace / タブ | worktree の中身 | ブランチ |
|---|---|---|---|
| `herdr workspace close <ws>` | 消える | **残る** | 残る |
| `herdr worktree remove --workspace <ws>` | 消える | 消える | **残る** |
| 上 + `git branch -D <branch>` | 消える | 消える | 消える |

コミット済みの作業はブランチに残るので、`worktree remove` までなら失われない。失われるのは `git branch -D` を足したときだけ。

### Step 1: 対象を特定する

issue ID で言われることが多いので、タブ label から workspace を引く:

```sh
herdr worktree list --cwd "$(git rev-parse --show-toplevel)"  # 自リポの worktree と workspace_id
herdr tab list                                                # label (issue ID) から workspace_id を照合
```

引いた workspace が「スコープ」の集合に無ければ、そこで止めて別リポである旨を伝える。

### Step 2: 失うものを数える

3 点を確認する。この確認を飛ばすと、聞くべきかどうかの判断自体ができない。

```sh
herdr agent get <agent-name>                    # agent_status が working なら実行中
git -C <checkout_path> status --short           # 未コミットの変更
git -C <checkout_path> log --oneline @{u}..HEAD # 未 push のコミット (upstream 未設定なら origin/main..HEAD)
```

### Step 3: 状態を見せて 1 問で聞く

```
ABC-123 を落とします。現在の状態:
  agent:     idle
  未コミット: 2 ファイル (src/foo.ts, src/bar.ts)
  未 push:   3 commits

どこまで消しますか?
  1. タブだけ閉じる (worktree もブランチも残る / 後で開き直せる)
  2. worktree も消す (ブランチは残るので未 push の 3 commits は無事)
  3. ブランチごと消す (未 push の 3 commits が失われる)
```

`working` 中なら「実行中ですが止めますか?」を先に確認する。途中で pane を閉じると、子が書きかけのファイルがそのまま残る。

未コミット変更がある状態で 2 か 3 を選ばれた場合、`herdr worktree remove` は `--force` なしだと `dirty_worktree_requires_force` で拒否する。この拒否は保護なので、`--force` を機械的に付けない。拒否されたら未コミットの中身 (`git -C <path> diff`) を見せて、捨ててよいか改めて確認してから `--force` を足す。

### Step 4: 実行して報告する

```sh
# 1 の場合
herdr workspace close <ws>

# 2 の場合
herdr worktree remove --workspace <ws> [--force]

# 3 の場合 (2 に続けて)
git -C <repo-root> branch -D <branch>
git -C <repo-root> worktree prune
```

`worktree prune` は、herdr が消した checkout の登録が git 側に残ることがあるので付けておく。

### Step 5: Linear をどうするか

落とし方で扱いが変わる。

- **完了して片付ける** → 触らない。PR マージ時に GitHub 連携が Done へ進める
- **中断・放棄する** → `linear issue update <ID> -s "Todo"` で戻す。In Progress のまま放置すると、Linear 上は着手中に見えて次に拾えなくなる

どちらか判断がつかないときは Step 3 の確認と一緒に聞く。落とす理由は本人しか知らない。

---

## やらないこと

- **`--wait` で子の完了を待つ** — 親が直列化して並行数が 1 に落ちる。完了は次の巡回で拾う
- **別リポジトリの workspace に触る** — 起動も巡回の報告も停止もしない。親はそのリポの文脈を持っていない (「スコープ」参照)
- **自分が作っていない workspace / タブを閉じる、プロンプトを投げる** — 同じリポジトリでも手動で立てたタブが混在している。明示依頼がない限り触らない
- **停止モードの確認を飛ばして worktree を消す** — 未コミット・未 push を数える前に消すと、何を失ったのか後から誰も分からない。`--force` を確認なしに付けるのも同じ (あれは git の保護であって、邪魔な警告ではない)
- **worktree を `wt` で作る** — herdr の workspace に紐づかず、`herdr worktree list` から辿れなくなる。手動作業の `wt` 運用とは分ける
- **`In Progress` より先の status に進める** — `In Review` / `Done` は PR 作成・マージ時に GitHub 連携が自動で進める。親が先回りすると実態とずれる。親が手で触るのは起動時の `In Progress` だけ

## 失敗時

- `agent start` が `invalid_agent_name` で落ちた → 大文字か記号が混じっている。小文字化して再実行する
- `worktree create` がブランチ重複で落ちた → 既に走っている可能性が高い。`herdr worktree list` と `herdr tab list` で既存タブを探し、あればそこに合流する案をユーザーに出す
- `agent start` がタイムアウト → pane はできている。`herdr agent explain` で検出状態を見せ、手動で claude を起動する選択肢を出す
- `gh` / `linear` が無い → 起動モードは成立しない。issue 内容を直接ユーザーから受け取る形に切り替えてよいか 1 問で確認する
