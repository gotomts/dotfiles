---
name: linear-next
maintainer: gotomts
description: Linear の active issue (Backlog/Todo/In Progress) を確認し、依存関係・進行中作業・現在のブランチ状態を統合して、次にやるべき issue を推奨順で提示する。「次に何やる？」「Linear 確認して」「優先度教えて」と聞かれたら必ず使う。引数なしで動作。
argument-hint: "[--epic <issue-id> | --all]"
allowed-tools:
  - Bash
  - Read
  - ToolSearch
---

# Linear Next

`active issue` (Backlog / Todo / In Progress) を全体俯瞰し、**今このセッションで最も着手すべき 3〜5 件** を推奨順に並べて提示する。

判断材料は次の 3 つを統合する:

1. **Linear の active issue** — 自分が assignee、または現プロジェクトに紐づく未完了 issue
2. **handover の未消費メモ** — 過去セッションで意図的に中断・引き継ぎした作業 (再開最優先)
3. **現リポジトリの状態** — 現在のブランチ・未コミット変更 (進行中作業の継続を優先)

## 引数

- 引数なし: デフォルト挙動。上記 3 ソースを統合して上位 3〜5 件提示
- `--epic <ISSUE-ID>`: 特定 epic の sub-issue に限定 (例: `--epic ABC-105` → Phase B の sub のみ)
- `--all`: 上位 5 件で打ち切らず、active 全件を表示

## 実行ステップ

### Step 1: コンテキスト解決

並列実行 (どれか失敗しても他は続行):

```sh
# 現在のリポジトリ・ブランチ・未コミット変更
git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null
git -C "$(pwd)" branch --show-current 2>/dev/null
git -C "$(pwd)" status --porcelain 2>/dev/null | head -10
```

```sh
# プロジェクト設定 (もしあれば Linear team / project がここに書かれている)
cat .claude/project.yml 2>/dev/null || true
```

```sh
# handover 未消費メモ一覧 (現プロジェクト・現ブランチ)
eval "$(${HOME}/.claude/skills/handover/scripts/resolve-path.sh)" 2>/dev/null
${HOME}/.claude/skills/handover/scripts/list-active.sh "${PROJECT_HASH}" "${BRANCH}" 2>/dev/null
```

### Step 2: Linear MCP ツール読み込み

Linear ツールは deferred なので `ToolSearch` で schema を取得:

```
ToolSearch query="select:mcp__linear__list_issues,mcp__linear__get_issue,mcp__linear__list_issue_statuses"
```

ツール名は `mcp__linear__*`。`mcp__linear-server__*` ではない (ToolSearch の結果を見て確定させること)。

### Step 3: active issue 取得

`mcp__linear__list_issues` を以下フィルタで呼ぶ:

- `state`: "backlog" / "unstarted" / "started" の **type** で引く (3 回呼ぶ)
- `team`: `.claude/project.yml` の `linear.team` 値
- `assignee`: 無指定で team 全体を見る。`"me"` だけだと Unassigned の真のブロッカーを取りこぼす
- `fields`: `projectMilestone` を**必ず含める**。他に `title` / `priority` / `url` / `gitBranchName` / `status` / `labels` / `project` / `updatedAt`
- `limit`: 100

epic 引数 (`--epic ABC-NN`) があれば `parentId: ABC-NN` でフィルタ。

**依存 relation は `list_issues` の fields に無いので、別途 raw GraphQL で取る:**

```sh
linear api '{ team(id:"<TEAM>") { issues(first:80, filter:{ state:{ type:{ nin:["completed","canceled"] } } }) { nodes { identifier inverseRelations { nodes { type issue { identifier state { type } } } } } } } }'
```

`inverseRelations` の `type: "blocks"` が「この issue をブロックしているもの」。`relations` は逆向き (この issue がブロックしているもの) なので取り違えない。

> **このクエリに `2>/dev/null` を付けないこと。** Linear の GraphQL は complexity 上限 10000 を持ち、`first` を増やしたり `description` と `relations` を同時に要求すると `Query too complex` で 400 を返す。エラーを握りつぶすと jq が空を出し、relation が登録済みでも「依存は 1 件も登録されていない」と読めてしまう。落ちたら `first` を下げるかクエリを分割する。

### Step 4: 候補から落とす (ランク付けより先)

次に当たるものは**表に出さない**。順位を下げるのではなく除外する。除外した件数と理由だけ最後に 1 行で報告する。

1. **status が `Pending`** — 依存・期日・方針判断で着手できないことを表す state。type は `backlog` なので type フィルタには出てくる。**名前で判別する**
2. **未完了の issue に blocked by されている** — `inverseRelations` の `type: "blocks"` で、相手の state type が `completed` / `canceled` 以外
3. **本文の冒頭に保留・凍結の判断が書かれている** — `description` の先頭 400 文字を「保留」「見送」「凍結」で検索する。status が Backlog のままでも、本文で実装を止めていることがある

### Step 4b: ランク付け

**milestone (`projectMilestone`) を持つ project では、milestone の順序が第一ソートキー。** 前の Phase に着手可能な issue が 1 件でも残っているうちは、次の Phase の issue を推奨しない。スコアは同じ milestone 内の並び替えにしか使わない。

milestone が未設定の issue は**末尾に置く** (milestone の `sortOrder` に大きい数を代入して混ぜない)。後から起票された改善系がここに溜まるので、Phase の途中に割り込ませると計画側の順序が崩れる。

同じ milestone 内で優劣が付かないときは、**その issue が blocks している未完了 issue の数**で並べる。数が多いものがクリティカルパス上にある。`relations` (inverseRelations ではない方) の `type: "blocks"` を数える。

その上で各 issue にスコア付け。**スコアは表示しない**、推奨順を決めるだけに使う。

| シグナル | 加点理由 |
|---|---|
| **handover に該当 issue 名・ブランチ名が出現** | 中断作業の再開は最優先。+100 |
| **現ブランチ名と一致** (gitBranchName) | 今このリポジトリで進行中。+50 |
| **status = In Progress** | 着手済み。+30 |
| **priority = Urgent (1)** | +40 |
| **priority = High (2)** | +20 |

合計スコア降順で上位 5 件。タイブレークは `updatedAt` 新しい順。

> **`sortOrder` を「整備された着手順」として信用しない。** Linear は新規 issue を上 (負の絶対値が大きい方) へ自動挿入するので、負値ゾーンは単なる起票順の裏返しであることが多い。人が手で並べた区間は値が連番的になる (1000 / 1100 / 1200 …)。両者が混在している場合、負値側を着手順と読むと新しく起票された issue ほど上位に見え、前半の Phase を飛ばして後半の issue を推奨してしまう。

### Step 5: 出力

以下のフォーマットで出す。**スコアや内部判定は出さない**、人間が読んで分かる "理由" のみ書く。

```markdown
## 次にやるべき issue (推奨順)

### 1. ABC-XX: <タイトル>
- 状態: <status>
- Phase: <projectMilestone があればその名前、なければ「(milestone なし)」>
- 理由: <なぜ今これを推奨するか — 1 行>
- 親 epic: <親があれば ABC-NN: title、なければ「(独立)」>
- URL: <issue url>

### 2. ...

### 3. ...
```

最後に 1〜2 行の総括と、**除外した件数**を添える。例:

> handover 由来の ABC-101 が最優先。Phase B 着手は ABC-101 完了後に B1/B2 並行で進めるのが効率的。
> 除外: 12 件 (blocked by 未解消 9 / Pending 2 / 本文で保留 1)

## エッジケース

### Linear MCP が応答しない / 認証エラー

「Linear MCP がエラー (xxx)。`/mcp` で接続確認、もしくは `linear auth login` の再実行が必要かも」と提示して終了。推測で issue を捏造しない。

### project が解決できない

`.claude/project.yml` が無く git remote からも推測不可な場合、ユーザーに「どの Linear project を見ますか？」と聞く。盲目的に全 project を舐めない。

### active issue が 0 件

「active issue なし。完了お疲れさまでした。新規タスクが必要なら epic から sub-issue を切り出すか、Backlog の優先順位を見直すタイミング」と返す。捻り出さない。

### Step 4 の除外で候補が 0 件になった

「active issue はあるが、全部ブロックされている」状態。これは 0 件とは別物なので、そう伝える。何が誰を待っているかを出す:

```
着手できる issue が 0 件。全 N 件が次の理由で止まっています。
  ABC-101  blocked by ABC-99 (In Progress)
  ABC-102  Pending — 期日待ち
```

ブロッカー側 (上の例では ABC-99) が進行中なら、そこに人を足せないかを提案する。ブロッカーが未着手なら、それを推奨に切り替える。

### handover メモが古い (1 週間以上前)

`created_at` を確認し、1 週間以上経過していれば「handover メモが 〜 日前のものです。まだ有効か確認してください」の一言を添える。

## 設計判断

- **推測時間 (estimate) は出さない**: Linear の estimate フィールドが空の場合に水増しすると害が大きい。書くなら issue 側に estimate が入ってる時だけ
- **ユーザー判断材料を残す**: 自動で「これをやる」と断定せず、推奨順を提示してユーザーが選ぶ。状況依存の判断 (今日の集中時間、並行作業、DL 時間) はユーザーが握る
- **スコアは内部のみ**: 数値を見せると「なぜ 50 点？」と無駄な議論になる。理由を自然言語で書く方が建設的
