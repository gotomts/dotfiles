---
name: pick-next
description: 「次に何をやるか」を対話で決定する。既存 active issue（Linear / GitHub）の優先度推奨、新規テーマの候補出しと 3 軸スコア比較、判断結果に応じて Issue 作成・既存 Issue 選定・保留の 3 分岐に振り分ける。「次に何やる？」「Linear/GitHub 確認して」「優先度教えて」「次の開発内容を相談したい」と聞かれたら必ず使う。引数なし or 任意のヒント文字列で起動。
argument-hint: "[hint] [--epic <issue-id>] [--all] [--axes <カスタム軸>] [--history] [--review]"
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - Write
  - TaskCreate
  - TaskUpdate
  - ToolSearch
  - Skill
---

# pick-next

「次に何をやるか」を対話で決定する。終端は 3 つの分岐に分かれる:

1. **既存 active issue を選ぶ** → Issue 番号を提示、`/issue-dev <番号>` を案内して終了
2. **新規テーマを作る** → 軽量 spec/plan を書き出し → `Skill: create-issue` で親 + sub-issue を登録
3. **今はやらない / 保留** → 何もしない（判断ログは任意）

## このスキルがしないこと

- 実装の着手（`issue-dev` の責務）
- フル spec / plan の作成（`superpowers:brainstorming` の責務）
- ロードマップ全体の管理（`service-design-builder` の責務）
- Issue 登録の生 API 呼び出し（`create-issue` に委譲）

## 引数

```
/pick-next [hint] [--epic <issue-id>] [--all] [--axes <カスタム軸>] [--history] [--review]
```

- `[hint]`: 任意の方向性ヒント（例: `認証周り強化したい`）
- `--epic <issue-id>`: 特定 epic の sub-issue に既存候補を限定
- `--all`: 既存候補の上位 5 件で打ち切らず全件表示
- `--axes <カスタム軸>`: 3 軸を上書き（例: `インパクト,学習,コスト`）
- `--history`: 過去の `pick-next` セッション一覧を表示して終了
- `--review`: 過去 spec の予想コスト vs 実際所要時間を集計表示して終了

## 対話プロトコル

### Step 0: 環境検出 + handover

`references/environment-detection.md` を参照して並列実行する。
得られる値: `REPO_ROOT` / `BRANCH` / `TRACKER_TYPE` / `HANDOVER_NOTES` / `RECENT_COMMITS` / `RESUMING_SPEC`。

`RESUMING_SPEC` が見つかったら「続きから / 破棄」を確認し、再開なら Step 5 から続行。

### Step 1: 既存 active issue 取得 & ランク付け

`references/ranking-signals.md` を参照。

- `TRACKER_TYPE = linear`: `ToolSearch` で MCP ツールを読み込んで `mcp__linear-server__list_issues` を呼ぶ
- `TRACKER_TYPE = github`: `gh issue list --state open --assignee @me --limit 30` を呼ぶ
- 空: スキップ、Step 2 へ

シグナル加点で上位 3〜5 件を「既存候補」として保持。**スコアは表示せず**、推奨理由を自然言語で持つ。

### Step 2: ヒアリング & 新規候補引き出し

引数 `[hint]` があれば起点に。最大 3 質問:

1. 直近の状況（直近マージ PR、残ってる TODO）
2. 頭にある候補（既に「やりたい」と思ってること）
3. 制約（期限、使える時間、避けたいこと）

過剰なヒアリングは避ける。1 メッセージにつき 1 質問が原則。

### Step 3: 候補統合

| 出所 | 件数の目安 |
|-----|----------|
| 既存候補（Step 1） | 上位 3 件 |
| 新規候補（Step 2） | ユーザー言及候補 |
| 推測候補（コードベース TODO / git log） | 0〜2 件 |

合計 **2〜5 件**。多すぎ → 圧縮、1 件しかない → 「比較対象がない選択は判断にならない」と促す。

各候補に **タイプ**（既存 / 新規 / 推測）をラベリング。

### Step 4: 3 軸スコア & 比較

`references/score-axes.md` を参照。比較表を提示:

```
| # | 候補 | タイプ | インパクト | モチベ | コスト | 推奨理由 / コメント |
|---|------|--------|-----------|--------|--------|--------------------|
```

判定原則: **コストが許容範囲なら、インパクト × モチベの積が高いものを選ぶ**。モチベ低を機械的に選ばない。

`--axes` 引数があれば軸を上書き。

### Step 5: 1 つ選定 & 分岐判定

ユーザーが 1 つ選ぶ。スキル側で **タイプ** を見て分岐:

- 既存 → Step 6A
- 新規 / 推測 → Step 6B
- ユーザーが「今はやらない」 → Step 6C

### Step 6A: 既存 Issue 確定

```markdown
## 確定: <Issue 番号> - <タイトル>

着手するには:
  /issue-dev <Issue 番号>

または直接 worktree を切る場合:
  worktrunk <Issue 番号>
```

何も書き出さず Step 7 へ。

### Step 6B: spec/plan 書き出し → create-issue

`references/spec-template.md` `references/plan-template.md` `references/decomposition-guide.md` を参照。

```bash
DATE=$(date +%Y-%m-%d)
SLUG=<タイトルから ASCII kebab-case>
SPEC=docs/superpowers/specs/${DATE}-${SLUG}-design.md
PLAN=docs/superpowers/plans/${DATE}-${SLUG}.md
```

Write ツールで両ファイルを書き出す。**git commit は自動実行しない**、ユーザーに案内のみ。

その後:

```
Skill: create-issue
args: <SPEC> <PLAN>
```

`create-issue` がエラーで停止した場合（tracker 未設定等）、`pick-next` 側で「`.claude/project.yml` を設定してから `/create-issue <SPEC> <PLAN>` を手動実行」と案内して終了。spec/plan ファイルは残す。

### Step 6C: 保留 (判断ログ任意)

`references/decision-log-template.md` を参照。

ユーザーに「判断ログを残す？」と確認:

- **残す** → `docs/superpowers/decisions/${DATE}-pick-next-skip.md` に書き出す。ディレクトリが無ければ `mkdir -p` する
- **残さない** → 何もしない

### Step 7: 完了報告

3 分岐共通フォーマット:

```markdown
## ✅ pick-next 完了

**選定結果:** <既存 KISSA-XX / 新規テーマ / 保留>
**理由:** <推奨理由 or 3 軸スコア要約>

### 比較した候補
| # | 候補 | タイプ | スコア | 結論 |
|---|------|--------|--------|------|
| 1 | ... | 既存 | ★ 採用 | ... |
| 2 | ... | 新規 | 却下 | <理由> |

### 生成物（新規分岐の場合のみ）
- Spec: <path>
- Plan: <path>
- 親 Issue: <番号>
- Sub-issue: N 件

### 次のステップ
<分岐に応じた案内>
```

## 失敗時の挙動

| 状況 | 挙動 |
|------|------|
| repo 外で起動 | コードベース読込みスキップ、対話続行 |
| tracker 未設定 | 既存候補ゼロで続行、6B 選択時に案内して停止 |
| Linear MCP 認証エラー | 案内して既存候補ゼロで続行 |
| GitHub `gh auth status` NG | 案内して既存候補ゼロで続行 |
| ユーザーが「やめる」 | 何もしない |
| 中断再開検出 | 「続きから / 破棄」確認 |
| sub-issue 分解で「全部 1 件にできない」 | `superpowers:brainstorming` へエスカレーション提案 |
| `create-issue` で重複検出 | 停止メッセージ表示、spec/plan は残す |

## オプション機能（`--history` `--review`）

### `--history`

`docs/superpowers/specs/*-design.md` をスキャンし、フロントマターに `pick-next: true` を含むものを日付降順で一覧表示して終了。

```
## pick-next 過去セッション一覧

| 日付       | タイトル                   | 親 Issue |
|------------|---------------------------|---------|
| 2026-05-14 | auth-rate-limit-improve   | KISSA-72 |
| 2026-05-07 | coffee-log-export         | KISSA-65 |
```

### `--review`

過去 spec の `採用判断（3 軸スコア）` の `コスト` と、関連 PR の作成 → マージ時間を比較する。出力は表のみ:

```
| 日付       | タイトル                | 予想コスト | 実際 (PR 作成 → マージ) | 差分 |
|------------|------------------------|-----------|------------------------|------|
| 2026-05-14 | auth-rate-limit-improve | 中 (3d)   | 4d                     | +1d |
| 2026-05-07 | coffee-log-export      | 小 (1d)   | 1d                     | 0    |
```

自動学習はしない。ユーザーが目視で「自分の見積もりにバイアスがある」と気づく材料を提供するだけ。

## 設計判断

- **スコアは内部のみ vs 表示**: 既存 issue ランキング = 内部のみ（数値見せると無駄な議論）/ 3 軸スコア = 表示（ユーザーが選ぶための材料）
- **モチベ低を機械的に選ばない**: 個人開発はモチベが落ちると進まない
- **git commit は自動実行しない**: spec/plan 書き出し後、ユーザーに案内のみ。誤コミット防止
