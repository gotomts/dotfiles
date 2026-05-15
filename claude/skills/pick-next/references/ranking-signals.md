# ranking-signals

既存 active issue を「ランク付け」するときに使う**内部スコア**の定義。
スコアそのものはユーザーに表示せず、推奨理由を自然言語で出力する（`linear-next` から移植した設計判断）。

## tracker 別の Issue 取得

### Linear

`ToolSearch` で MCP ツール schema を読み込む:

```
ToolSearch query="select:mcp__linear-server__list_issues,mcp__linear-server__get_issue,mcp__linear-server__list_issue_statuses"
```

`list_issues` を以下フィルタで呼ぶ:

- `state`: "In Progress" / "Todo" / "Backlog" のいずれか（3 回呼ぶ or 全件取得して filter）
- `assignee`: `me` を優先、ヒットしなければ無指定で project 全体
- `project`: `.claude/project.yml` の `tracker.linear.project` 値、なければリポジトリ名から推測
- `limit`: 100

`--epic <issue-id>` 引数があれば `parentId: <issue-id>` でフィルタ。

### GitHub

```bash
# 自分が assignee の active issue
gh issue list --state open --assignee @me --limit 30 \
  --json number,title,labels,assignees,milestone,projectItems

# project がある場合は項目とその status も取得
gh project item-list <PROJECT_NUMBER> --owner <OWNER> --format json --limit 200
```

`--epic <issue-id>` 引数の挙動: GitHub には Linear の `parentId` のような明示 epic 概念が薄い。代わりに `gh issue view <epic-id> --json body` から「タスクリスト形式の sub-issue 番号」を抽出してフィルタする。抽出パターン: `^- \[[ x]\] #(\d+)`。

## スコアシグナル

各 issue にスコアを加算する。**最終スコアは表示しない**。

| シグナル | 加点 | 検出方法 |
|---------|------|---------|
| handover に該当 issue 名・ブランチ名が出現 | +100 | `HANDOVER_NOTES` を grep |
| 現ブランチ名と一致（gitBranchName） | +50 | Linear: `gitBranchName` フィールド / GitHub: ブランチ名に issue 番号が含まれるか |
| status = In Progress | +30 | tracker のステータス |
| priority = Urgent | +40 | Linear: priority=1 / GitHub: `priority:urgent` ラベル |
| priority = High | +20 | Linear: priority=2 / GitHub: `priority:high` ラベル |
| 親 epic の blocker が解消済み | +10 | 親 epic を取得し、前提 sub-issue が Done/closed か |
| 親 epic に未解決 blocker あり | -50 | 同上、前提 sub-issue が未完 |
| status = Backlog かつ親 epic 不明 | -10 | 親 epic 検出失敗 + Backlog |

合計スコア降順で上位 3〜5 件を「**既存候補**」として保持。タイブレークは `updatedAt` 新しい順。

`--all` 引数があれば 5 件で打ち切らず全件返す。

## 推奨理由（ユーザー向け）

スコアが付いた要因のうち最も加点が高いもの 1 つを「推奨理由」として自然言語で表現する。

| 主な加点要因 | 自然言語例 |
|-----------|----------|
| handover (+100) | 「中断作業の再開（handover 未消費メモあり）」 |
| 現ブランチ一致 (+50) | 「現在のブランチで進行中」 |
| Urgent priority (+40) | 「priority=Urgent」 |
| In Progress (+30) | 「着手中」 |
| High priority (+20) | 「priority=High」 |
| 親 epic blocker 解消 (+10) | 「依存先が解消済み、着手可能」 |

複数該当する場合は最も加点が高いもの優先。負の加点（blocker 未解消、Backlog）の場合は推奨理由ではなく「**注意**」として表記:

| 減点要因 | 自然言語例 |
|---------|----------|
| 親 epic blocker 未解消 (-50) | 「⚠ 依存先が未完、現状では着手不可」 |
| Backlog かつ親 epic 不明 (-10) | 「Backlog（着手前提が曖昧）」 |

## 設計判断

- **スコアは内部のみ**: ユーザーに数値を見せると「なぜ 50 点？」と無駄な議論になる。理由を自然言語で書く方が建設的（`linear-next` の設計判断を踏襲）
- **推測時間 (estimate) は出さない**: 既存 issue の estimate フィールドが空のとき、推測すると害が大きい。書くなら issue 側に estimate が入っているときだけ
- **ユーザーが選ぶ**: 自動で「これをやる」と断定せず、ランク付けして候補に出すまでが本 reference の責務。最終決定は Step 5 でユーザーが行う
