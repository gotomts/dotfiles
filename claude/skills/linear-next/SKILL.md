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
- `--epic <KISSA-NN>`: 特定 epic の sub-issue に限定 (例: `--epic KISSA-50` → Phase B の sub のみ)
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
ToolSearch query="select:mcp__linear-server__list_issues,mcp__linear-server__get_issue,mcp__linear-server__list_issue_statuses"
```

### Step 3: active issue 取得

`mcp__linear-server__list_issues` を以下フィルタで呼ぶ:

- `state`: "In Progress" / "Todo" / "Backlog" のいずれか (3 回呼ぶ or 全件取得して filter)
- `assignee`: "me" を優先。ヒットしなければ無指定で project 全体を見る
- `project`: `.claude/project.yml` の `linear.project` 値、なければリポジトリ名から推測 (例: `dotfiles`)
- `limit`: 100

epic 引数 (`--epic KISSA-NN`) があれば `parentId: KISSA-NN` でフィルタ。

### Step 4: ランク付け

各 issue にスコア付け。**スコアは表示しない**、推奨順を決めるだけに使う。

| シグナル | 加点理由 |
|---|---|
| **handover に該当 issue 名・ブランチ名が出現** | 中断作業の再開は最優先。+100 |
| **現ブランチ名と一致** (gitBranchName) | 今このリポジトリで進行中。+50 |
| **status = In Progress** | 着手済み。+30 |
| **priority = Urgent (1)** | +40 |
| **priority = High (2)** | +20 |
| **親 epic で blocker が解消済み** (前提 sub-issue が Done) | 着手可能。+10 |
| **親 epic に未解決 blocker あり** (前提 sub-issue が未完) | 着手不可。減点 -50 |
| **status = Backlog** + 親 epic 不明 | 着手前提が曖昧。減点 -10 |

合計スコア降順で上位 5 件。タイブレークは `updatedAt` 新しい順。

### Step 5: 出力

以下のフォーマットで出す。**スコアや内部判定は出さない**、人間が読んで分かる "理由" のみ書く。

```markdown
## 次にやるべき issue (推奨順)

### 1. KISSA-XX: <タイトル>
- 状態: <status>
- 理由: <なぜ今これを推奨するか — 1 行>
- 親 epic: <親があれば KISSA-NN: title、なければ「(独立)」>
- URL: <issue url>

### 2. ...

### 3. ...
```

最後に 1〜2 行の総括を添える。例:

> handover 由来の KISSA-55 が最優先。Phase B 着手は KISSA-55 完了後に B1/B2 並行で進めるのが効率的。

## エッジケース

### Linear MCP が応答しない / 認証エラー

「Linear MCP がエラー (xxx)。`/mcp` で接続確認、もしくは `linear auth login` の再実行が必要かも」と提示して終了。推測で issue を捏造しない。

### project が解決できない

`.claude/project.yml` が無く git remote からも推測不可な場合、ユーザーに「どの Linear project を見ますか？」と聞く。盲目的に全 project を舐めない。

### active issue が 0 件

「active issue なし。完了お疲れさまでした。新規タスクが必要なら epic から sub-issue を切り出すか、Backlog の優先順位を見直すタイミング」と返す。捻り出さない。

### handover メモが古い (1 週間以上前)

`created_at` を確認し、1 週間以上経過していれば「handover メモが 〜 日前のものです。まだ有効か確認してください」の一言を添える。

## 設計判断

- **推測時間 (estimate) は出さない**: Linear の estimate フィールドが空の場合に水増しすると害が大きい。書くなら issue 側に estimate が入ってる時だけ
- **ユーザー判断材料を残す**: 自動で「これをやる」と断定せず、推奨順を提示してユーザーが選ぶ。状況依存の判断 (今日の集中時間、並行作業、DL 時間) はユーザーが握る
- **スコアは内部のみ**: 数値を見せると「なぜ 50 点？」と無駄な議論になる。理由を自然言語で書く方が建設的
