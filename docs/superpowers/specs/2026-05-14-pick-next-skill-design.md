---
title: pick-next スキル設計
date: 2026-05-14
status: draft
---

# pick-next スキル設計

## 1. 目的とスコープ

### 1.1 このスキルがすること

「次に何をやるか」を対話で決定する。決定の出口は 3 つに分岐する。

| 出口 | 何が起きる |
|------|----------|
| A. 既存 active issue を選ぶ | Issue 番号を提示、`issue-dev` 起動を案内して終了 |
| B. 新規テーマを作る | 軽量 spec/plan を書き出し → `create-issue` を呼んで親 + sub-issue を登録 |
| C. 今はやらない / 保留 | 何もしない（判断ログを `docs/superpowers/decisions/` に残すかオプション） |

### 1.2 このスキルがしないこと

- 実装の着手（`issue-dev` の責務）
- フル spec / plan の作成（`superpowers:brainstorming` の責務）
- ロードマップ全体の管理（`service-design-builder` の責務）
- Issue 登録の生 API 呼び出し（`create-issue` に委譲）

### 1.3 ポジショニング

```
[大型機能]   superpowers:brainstorming → writing-plans → create-issue → feature-team
                                                                 ↑
[次の一手]   pick-next ─────────────────────────────────────────┘
              ├─ 既存 issue を選ぶ → issue-dev 起動を案内
              ├─ 新規テーマ → 軽量 spec/plan → create-issue へ合流
              └─ 保留 → 終了（判断ログ任意）

[サービス全体] service-design-builder（Notion）
```

### 1.4 `linear-next` との関係

`linear-next` の機能（既存 active issue の優先度推奨）はすべて `pick-next` に内包する。`pick-next` 安定後に `linear-next` は別 PR で削除する（§11）。

## 2. 非要件（YAGNI で削る）

以下の機能は今回の設計に含めない。

- 自動学習（3 軸スコアの精度を機械学習で改善する仕組み）
- 複数プロジェクトの横断比較（プロジェクトを跨いで「次に何やる」を決める）
- 並行作業（同時に複数の「次の一手」を返す）
- スコアの自動算出（インパクト・モチベ・コストはあくまで対話で決める）
- dry-run モード（実運用で十分検証可能）

これらは将来必要になった時に追加できるよう、SKILL.md と references の責務分離は維持する。

## 3. 入出力

### 3.1 起動

```
/pick-next [hint] [--epic <issue-id>] [--all] [--axes <カスタム軸>] [--history] [--review]
```

- `[hint]`: 任意の方向性ヒント（例: `認証周り強化したい`）
- `--epic <issue-id>`: 特定 epic の sub-issue に既存候補を限定
- `--all`: 既存候補の上位 5 件で打ち切らず全件表示
- `--axes <カスタム軸>`: 3 軸を上書き（例: `インパクト,学習,コスト`）
- `--history`: 過去の `pick-next` セッション一覧を表示して終了
- `--review`: 過去 spec の予想コスト vs 実際所要時間を集計表示して終了

### 3.2 出力

| 分岐 | 主な生成物 |
|------|----------|
| 6A: 既存 | なし（Issue 番号と次アクション案内のみ） |
| 6B: 新規 | `docs/superpowers/specs/<date>-<slug>-design.md`、`docs/superpowers/plans/<date>-<slug>.md`、`create-issue` 経由で親 + sub-issue 登録 |
| 6C: 保留 | 任意で `docs/superpowers/decisions/<date>-pick-next-skip.md` |

## 4. ファイル構成

```
claude/skills/pick-next/
├── SKILL.md                          # 入口、Step 0〜7、分岐ロジック、create-issue 連携
└── references/
    ├── score-axes.md                 # 3 軸の定義、対話テンプレ、軸カスタムの扱い
    ├── ranking-signals.md            # 既存 issue 推奨用シグナル（linear-next から移植）
    ├── spec-template.md              # 軽量 spec のテンプレ + 記入例
    ├── plan-template.md              # 軽量 plan のテンプレ + 記入例
    ├── decomposition-guide.md        # 親 + sub 1 段、半日〜2 日粒度、エスカレーション基準
    ├── environment-detection.md      # repo / tracker / handover / コミット履歴の検出
    └── decision-log-template.md      # 「保留」の判断ログ（オプション）
```

`setup.zsh` は `claude/` 配下を再帰展開するため、新ディレクトリ追加で setup スクリプト改修は不要。

## 5. SKILL.md フロントマター

```yaml
---
name: pick-next
description: 「次に何をやるか」を対話で決定する。既存 active issue（Linear / GitHub）の優先度推奨、新規テーマの候補出しと 3 軸スコア比較、判断結果に応じて Issue 作成・既存 Issue 選定・保留の 3 分岐に振り分ける。「次に何やる？」「Linear/GitHub 確認して」「優先度教えて」「次の開発内容を相談したい」と聞かれたら必ず使う。引数なし or 任意のヒント文字列で起動。
argument-hint: '[hint] [--epic <issue-id>] [--all] [--axes <カスタム軸>]'
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
```

## 6. 対話プロトコル

### 6.1 Step 0: 環境検出 + handover

`environment-detection.md` を参照。並列実行（どれか失敗しても他は続行）。

```bash
git rev-parse --show-toplevel
git branch --show-current
git status --porcelain | head -10
git log --oneline -20
cat .claude/project.yml 2>/dev/null
# handover 未消費メモ
${HOME}/.claude/skills/handover/scripts/list-active.sh "$PROJECT_HASH" "$BRANCH"
# 中断再開検出: pick-next 由来の spec/plan があるか
ls docs/superpowers/specs/*-design.md 2>/dev/null | head -5
```

中断再開検出: `docs/superpowers/specs/` に `pick-next: true` フロントマター付き spec があれば「続きから再開する？破棄して新規？」を確認。

### 6.2 Step 1: 既存 active issue 取得 & ランク付け

`ranking-signals.md` を参照。tracker タイプで分岐。

- **Linear**: `ToolSearch` で `mcp__linear-server__list_issues` を読み込んで取得
- **GitHub**: `gh issue list --state open --limit 30` + 必要なら `gh project item-list`
- **なし**: スキップして Step 2 へ

ランキングシグナル（`linear-next` から移植、内部スコア。ユーザーには表示しない）。

| シグナル | 加点 |
|---------|------|
| handover に該当 issue 名・ブランチ名が出現 | +100 |
| 現ブランチ名と一致（gitBranchName） | +50 |
| status = In Progress | +30 |
| priority = Urgent | +40 |
| priority = High | +20 |
| 親 epic の blocker が解消済み | +10 |
| 親 epic に未解決 blocker あり | -50 |
| status = Backlog かつ親 epic 不明 | -10 |

上位 3〜5 件を「既存候補」として保持。タイブレークは `updatedAt` 新しい順。**スコアは表示せず**、推奨理由を自然言語で持つ。

### 6.3 Step 2: ヒアリング & 新規候補引き出し

引数 `[hint]` があれば起点に。最大 3 質問。

1. 直近の状況（直近マージ PR、残ってる TODO）
2. 頭にある候補（既に「やりたい」と思ってること）
3. 制約（期限、使える時間、避けたいこと）

ユーザーから「新規アイデア候補」を引き出す。

### 6.4 Step 3: 候補統合

| 出所 | 件数の目安 |
|-----|----------|
| 既存候補（Step 1） | 上位 3 件 |
| 新規候補（Step 2） | ユーザーが言及した候補 |
| 推測候補（コードベース TODO / git log） | 0〜2 件 |

合計 2〜5 件にまとめる。多すぎ → 圧縮、1 件しかない → 「比較対象がない選択は判断にならない」と促す。

各候補に **タイプ**（既存 / 新規 / 推測）をラベリング。

### 6.5 Step 4: 3 軸スコア & 比較

`score-axes.md` を参照。比較表（既存・新規どちらにも適用）。

```
| # | 候補                       | タイプ | インパクト | モチベ | コスト | 推奨理由 / コメント                |
|---|---------------------------|-------|-----------|--------|--------|----------------------------------|
| 1 | ABC-101: 認証強化         | 既存  | 高 (3)    | 中 (2) | 中 (3d) | handover に未消費メモあり         |
| 2 | コーヒーログ機能拡張        | 新規  | 中 (2)    | 高 (3) | 低 (1d) | 自分が一番使う、すぐ出せる         |
| 3 | ABC-102: SEO 改善         | 既存  | 高 (3)    | 低 (1) | 中 (3d) | priority=High だが効果出るのが遅い |
```

スコア定義:

- インパクト: 高 (3) / 中 (2) / 低 (1) — KPI・ユーザー価値・サービス品質への効き
- モチベーション: 高 (3) / 中 (2) / 低 (1) — 自分が今やりたいか
- コスト: 小 (1d 以下) / 中 (2-5d) / 大 (1w+) — ざっくり実装工数

判定原則: 「コストが許容範囲なら、**インパクト × モチベの積**が高いものを選ぶ。モチベ低を機械的に選ばない」。個人開発はモチベが落ちると進まないため、機械的なソートは避ける。

軸カスタム: `--axes インパクト,学習,コスト` などで上書き可。

### 6.6 Step 5: 1 つ選定 & 分岐判定

ユーザーが 1 つ選ぶ。スキル側で **タイプ** を見て分岐先を決定。

- 選ばれた候補が **既存** → Step 6A
- 選ばれた候補が **新規 / 推測** → Step 6B
- ユーザーが「**今はやらない**」と言う → Step 6C

### 6.7 Step 6A: 既存 Issue 確定

```markdown
## 確定: <Issue 番号> - <タイトル>

着手するには:
  /issue-dev <Issue 番号>

または直接 worktree を切る場合:
  worktrunk <Issue 番号>
```

何も書き出さず Step 7 へ。

### 6.8 Step 6B: spec/plan 書き出し → create-issue

`spec-template.md` `plan-template.md` `decomposition-guide.md` を参照。

```bash
DATE=$(date +%Y-%m-%d)
SLUG=<タイトルから ASCII kebab-case>
SPEC=docs/superpowers/specs/${DATE}-${SLUG}-design.md
PLAN=docs/superpowers/plans/${DATE}-${SLUG}.md
```

Write ツールで両ファイルを書き出す。**git commit は自動実行しない**、ユーザーに案内のみ（誤コミット防止）。

その後 `Skill` ツール経由で `create-issue` を呼ぶ。

```
Skill: create-issue
args: <SPEC> <PLAN>
```

### 6.9 Step 6C: 保留 (判断ログ任意)

`decision-log-template.md` を参照。ユーザーに「判断ログを残す？」と聞く。

- **残す** → `docs/superpowers/decisions/${DATE}-pick-next-skip.md` に「3 軸スコア + なぜ今やらないか」を書き出し
- **残さない** → 何もしない

判断ログは `--review` の入力データとして将来使う。

### 6.10 Step 7: 完了報告

3 分岐共通フォーマット。

```markdown
## ✅ pick-next 完了

**選定結果:** <既存 KISSA-XX / 新規テーマ / 保留>
**理由:** <推奨理由 or 3 軸スコア要約>

### 比較した候補
| # | 候補 | タイプ | スコア | 結論 |
|---|------|--------|--------|------|
| 1 | ... | 既存 | ★ 採用 | ... |
| 2 | ... | 新規 | 却下 | <理由> |
| 3 | ... | 既存 | 却下 | <理由> |

### 生成物（新規分岐の場合のみ）
- Spec: <path>
- Plan: <path>
- 親 Issue: <番号>
- Sub-issue: N 件

### 次のステップ
<分岐に応じた案内>
```

## 7. 軽量 spec フォーマット

`references/spec-template.md` で配布する。

```markdown
---
labels: [feature]
pick-next: true
---

# <タイトル>

## 目的・背景
<5〜10 行。「なぜ今これか」「何の問題を解くか」を明記。
3 軸スコアの根拠もここに含める。>

## 採用判断（3 軸スコア）
- インパクト: 高 (3) — <理由>
- モチベーション: 高 (3) — <理由>
- コスト: 中 (2-5d) — <内訳の概算>

## 受入条件
- [ ] <ユーザー視点で完了が確認できる条件>
- [ ] <技術的な条件>
- [ ] <テストが追加されている>

## スコープ外
- <今回はやらないこと>
- <将来の拡張ポイント>

## 却下した代替案
| 候補 | インパクト | モチベ | コスト | 却下理由 |
|------|-----------|--------|--------|----------|
| A: ... | 高 | 中 | 中 | <理由> |
| C: ... | 高 | 低 | 中 | <理由> |

## アプローチ（任意、必要なら）
<技術的な方針が複数ある場合、選んだ方針と理由>
```

`pick-next: true` フロントマターは中断再開検出と `--history` 一覧で識別子として使う。

## 8. 軽量 plan フォーマット

`references/plan-template.md` で配布する。

```markdown
# <タイトル> - 実装プラン

## ステップ概要
1. <ステップ 1 タイトル> （0.5d）
2. <ステップ 2 タイトル> （1d）
3. <ステップ 3 タイトル> （0.5d）

## ステップ詳細

### Step 1: <タイトル>
**変更対象**:
- `path/to/file_a.ts`
- `path/to/file_b.ts`

**受入条件**:
- [ ] <ステップ固有の完了条件>
- [ ] テストが追加されている

**依存**: なし

### Step 2: <タイトル>
**変更対象**:
- `path/to/file_c.ts`

**受入条件**:
- [ ] ...

**依存**: Step 1 完了後

## 検証手順（任意、必要なら）
- <手動テスト手順>

## ロールバック方針（任意、DB マイグレ等）
- <あれば書く>
```

## 9. 失敗時の挙動

| 状況 | 挙動 |
|------|------|
| repo 外で起動 | コードベース読込みスキップ、対話続行 |
| tracker 未設定 | 既存候補ゼロで続行（新規候補のみ）、6B 分岐選択時に「`.claude/project.yml` を設定してから `/create-issue <spec> <plan>` を手動実行」と案内して停止 |
| Linear MCP 認証エラー | 案内して既存候補ゼロで続行 |
| GitHub `gh auth status` NG | 案内して既存候補ゼロで続行 |
| ユーザーが「やめる」 | 何もしない |
| 中断再開検出 | 既存 spec/plan 検出時に「続きから / 破棄」確認 |
| sub-issue 分解で「全部 1 件にできない」 | `superpowers:brainstorming` へエスカレーション提案 |
| `create-issue` で重複検出 | 停止メッセージ表示、spec/plan は残す |

## 10. オプション機能

| 機能 | 仕様 |
|------|-----|
| 過去セッション一覧 | `/pick-next --history` で `docs/superpowers/specs/*-design.md` のうち `pick-next: true` のものを日付降順で一覧表示 |
| 振り返り学習 | `/pick-next --review` で「予想コスト vs 実際所要時間」を集計。spec の `採用判断（3 軸スコア）` の `コスト` と、関連 PR の作成 → マージ時間を比較。出力は表のみ（自動学習はしない） |
| 軸カスタム | `--axes <カンマ区切り>` で 3 軸を上書き |
| 判断ログ | 「保留」分岐で `docs/superpowers/decisions/` にログ任意保存 |

## 11. references の役割分担

| ファイル | 内容 | 主な参照タイミング |
|---------|------|---|
| `score-axes.md` | 3 軸定義、スコア例、対話テンプレ、軸カスタムの扱い | Step 4 |
| `ranking-signals.md` | 既存 issue の +100/+50 等のシグナル定義 | Step 1 |
| `spec-template.md` | 軽量 spec の完全テンプレ + 記入例 | Step 6B |
| `plan-template.md` | 軽量 plan の完全テンプレ + 記入例 | Step 6B |
| `decomposition-guide.md` | 分解粒度、エスカレーション基準 | Step 6B |
| `environment-detection.md` | 検出コマンドと grace degrade、handover 連携 | Step 0 |
| `decision-log-template.md` | 「保留」判断ログのフォーマット | Step 6C |

## 12. CLAUDE.md への追記

dotfiles の `CLAUDE.md`「Claude Code 設定」セクションに以下を追加する。

```markdown
- `claude/skills/pick-next/` は「次に何をやるか」を決定するスキル。既存 active issue（Linear / GitHub）の優先度推奨と、新規テーマの 3 軸スコア比較を統合し、結果に応じて Issue 作成・既存 Issue 選定・保留の 3 分岐に振り分ける。`linear-next` の機能を内包しており、安定後に `linear-next` は削除予定
```

## 13. `linear-next` 削除のタイミング

削除は本実装プランに含めず、別 PR で行う。

1. `pick-next` を完成・コミット
2. 3〜5 回実運用、issue 推奨ロジックの精度を検証
3. 不具合がなければ `claude/skills/linear-next/` を削除する PR を別途作成
4. `claude/CLAUDE.md` の「Claude Code 設定」セクションも合わせて更新

`pick-next` の SKILL.md には `linear-next` への言及を残さず、独立スキルとして自己完結させる（移行作業を簡単にするため）。

## 14. テストと検証

ユニットテストなし。実運用で検証する。

- **最初の実走**: social coffee note のロードマップ作りで使う
- **検証観点**:
  - 既存候補と新規候補が混在したときの 3 軸比較の自然さ
  - handover 未消費メモが正しく最優先化されるか
  - 「保留」分岐がスムーズか
  - `create-issue` 連携の引き継ぎが滑らかか
- 出てきた課題は `feedback_*.md` / `project_*.md` として auto memory に記録

## 15. 受入条件

- [ ] `claude/skills/pick-next/SKILL.md` と 7 つの references ファイルが配置される
- [ ] `/pick-next` で起動し、既存 active issue 取得 → 候補出し → 3 軸スコア → 分岐判定 → 完了報告まで動作する
- [ ] tracker = Linear のとき MCP 経由で issue 取得できる
- [ ] tracker = GitHub のとき `gh` CLI 経由で issue 取得できる
- [ ] tracker 未設定のとき新規候補のみで動作する
- [ ] 中断再開検出が動作し、既存 spec/plan があれば「続きから / 破棄」確認が出る
- [ ] 6B 分岐で軽量 spec/plan が `docs/superpowers/specs/` `docs/superpowers/plans/` に書き出される
- [ ] 6B 分岐から `create-issue` が `Skill` 経由で呼ばれる
- [ ] handover 未消費メモがランキングで +100 加点される
- [ ] dotfiles の `CLAUDE.md` に新スキルへの言及が追加される
- [ ] `linear-next` は本 PR では触らない（別 PR）

## 16. スコープ外（次回以降）

- `linear-next` の削除作業
- `--history` `--review` の高度な可視化
- 自動学習による 3 軸スコア精度改善
- Notion ロードマップページの取り込み
