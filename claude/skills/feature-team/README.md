# Feature Team — 設計ドキュメント（保守者向け）

このディレクトリは Claude Code 用の **マルチエージェント・フィーチャー開発オーケストレーション** スキルです。

実行時に Claude が読むのは `SKILL.md` / `roles/_common.md` / `roles/parent.md` です。この `README.md` は **人間（=今後このスキルを改修したくなったあなた）向け** の設計概要です。

## TL;DR

```
ユーザーが「機能 X を作りたい」と言う
  → Phase 1: brainstorming で spec → writing-plans で plan → issue 用サマリー作成
  → Phase 2: Linear or GitHub に親 issue + n 個の sub-issue を作成
  → Phase 3: 大規模か小規模かを判定
  → Phase 4: 大規模なら sub-issue を並列実装、小規模なら親直実装
  → Phase 5: 観点別レビュー（security/performance/quality）をストリーミング起動
  → Phase 6: pr-publisher を branch ごとに並列起動して PR 作成
```

ポイント:
- **親はメイン Claude セッション自身**（サブエージェント化しない）
- **子エージェントは `~/.claude/agents/` 配下の 14 体**（developer 10 + reviewer 3 + pr-publisher 1）
- **レビュー往復は最大 3 ラウンド**で打ち切り、超過時は親介入 → ユーザー escalate
- **設定は `.claude/project.yml`**（リポジトリ単位）

---

## 1. 体制全体図（コンポーネントとレイヤー分離）

```
┌──────────────────────────────────────────────────────────────────────────┐
│                  USER (人間)                                              │
│  - Phase 1 brainstorming で要件出す                                       │
│  - Phase 2 で Linear/GitHub どちらか口頭指定（または .claude/project.yml）   │
│  - escalate 時に判断                                                      │
└──────────────┬───────────────────────────────────────────────────────────┘
               │ 対話 (AskUserQuestion / 通常応答)
               ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  PARENT = メイン Claude セッション                                        │
│  ─────────────────────────────────────────────────────────────────────   │
│  読み込むファイル:                                                        │
│   • feature-team/SKILL.md       ← 6 フェーズの進行規約（このスキル）       │
│   • roles/parent.md             ← しきい値・選定基準・escalate 条件        │
│   • roles/_common.md            ← 子に注入するための定型プロトコル         │
│                                                                          │
│  責務:                                                                    │
│   • フェーズ進行の制御                                                    │
│   • ボリューム判断 (大規模 vs 小規模)                                      │
│   • 観点別 reviewer の選定 (security/perf/quality)                       │
│   • レビューラウンドの収束判定 (上限 3)                                    │
│   • ユーザーへの escalate                                                 │
│   • 子の出力を統合・検証                                                  │
└──┬───────────────────────────────────────────────────────────────────────┘
   │
   │ Skill ツール呼び出し                  Agent ツール呼び出し
   │ (プロセス・ナレッジ系)                 (実装・レビュー系)
   ▼                                       ▼
┌─────────────────────────────┐   ┌─────────────────────────────────────┐
│ SKILLS (~/.claude/skills/)  │   │ SUBAGENTS (~/.claude/agents/) 14 体  │
│ ─────────────────────────   │   │ ──────────────────────────────────  │
│ Phase 1:                    │   │ DEVELOPERS (10):                    │
│  • superpowers:brainstorming│   │  • developer-react                  │
│  • superpowers:writing-plans│   │  • developer-nextjs                 │
│                             │   │  • developer-flutter                │
│ Phase 2:                    │   │  • developer-go                     │
│  • create-issue             │   │  • developer-nodejs                 │
│    (引数で linear/github)    │   │  • developer-hono                   │
│                             │   │  • developer-nestjs                 │
│ Phase 6:                    │   │  • developer-rust                   │
│  • coderabbit-review        │   │  • developer-ruby                   │
│    (pr-publisher 内で呼ぶ)  │   │  • developer-generic    ← フォールバック │
│                             │   │                                     │
│ 補助:                        │   │ REVIEWERS (3):                      │
│  • handover                 │   │  • reviewer-security                │
│                             │   │  • reviewer-performance             │
│                             │   │  • reviewer-quality                 │
│                             │   │                                     │
│                             │   │ PUBLISHER (1):                      │
│                             │   │  • pr-publisher                     │
│                             │   │    Phase 6 で branch ごとに並列起動 │
│                             │   │                                     │
│                             │   │ 起動時に親が _common.md の規約を     │
│                             │   │ prompt として注入する (二層分離)      │
└─────────────────────────────┘   └─────────────────────────────────────┘
                                            │
                                            │ 各エージェントは
                                            ▼
                                  ┌──────────────────────┐
                                  │ worktrunk (wt)       │
                                  │ で worktree 隔離     │
                                  │ Brewfile に既登録    │
                                  └──────────────────────┘
```

## 2. 6 フェーズのフロー（時系列とゲート）

```
 USER
  │
  │ "feature 作りたい"
  ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Phase 1: 要件確定 (3 段階)                                               │
│  1.1 PARENT → Skill(superpowers:brainstorming)                          │
│       成果物: spec (docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md)│
│  1.2 PARENT → Skill(superpowers:writing-plans)                          │
│       成果物: plan (docs/superpowers/plans/YYYY-MM-DD-<topic>.md)       │
│  1.3 PARENT が spec/plan をもとに Issue 用サマリーを下書き                │
└──────────────┬──────────────────────────────────────────────────────────┘
               │ ゲート: spec/plan にユーザー承認?
               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Phase 2: イシュー化                                                      │
│  PARENT → Skill(create-issue,                                            │
│             args="<spec-path> <plan-path>")                              │
│         （create-issue が .claude/project.yml の tracker を自己解決）    │
│  成果物: 親 issue + sub-issues (n 個)                                    │
└──────────────┬──────────────────────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Phase 3: ボリューム判断                                                  │
│  PARENT が parent.md のしきい値で判定                                     │
│  ──────────────────────────────────────                                  │
│   ┌─────────────┐                  ┌──────────────┐                     │
│   │ 大規模？     │                  │ 小規模？      │                     │
│   │ 独立性高？   │                  │ 単純な変更？  │                     │
│   └──────┬──────┘                  └──────┬───────┘                     │
└──────────┼──────────────────────────────────┼──────────────────────────┘
           │ YES                              │ YES
           ▼                                  ▼
┌──────────────────────────────┐    ┌────────────────────────────────────┐
│ Phase 4-A: 並列開発           │    │ Phase 4-B: 親直接実装                │
│ ──────────────────────────   │    │ ──────────────────────────────────│
│ 各 sub-issue ごとに wt 作成    │    │ 親が wt を 1 個作成して直接コーディング │
│ Agent(developer-XXX)         │    │                                    │
│   × N (run_in_background)    │    │                                    │
│                              │    │                                    │
│ 完了通知ごとにストリーミング   │    │                                    │
│ で reviewer 起動 (Phase 5)    │    │                                    │
└──────┬───────────────────────┘    └─────────┬──────────────────────────┘
       │                                       │
       ▼                                       │
┌──────────────────────────────┐               │
│ Phase 5: 観点別レビュー        │               │
│ ──────────────────────────   │               │
│ Agent(reviewer-security)     │               │
│ Agent(reviewer-performance)  │               │
│ Agent(reviewer-quality)      │               │
│                              │               │
│ 親が指摘を統合 → developer に  │               │
│ 戻して修正                    │               │
│                              │               │
│ ループ上限: 3 ラウンド         │               │
│  ↳ 超過時 → 親が介入 / escalate│               │
└──────┬───────────────────────┘               │
       │                                       │
       └──────────┬────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Phase 6: PR                                                             │
│  Phase 4-A → n 個の独立 PR / Phase 4-B → 1 個の統合 PR                    │
│  PARENT → Agent(pr-publisher) を branch ごとに並列起動                    │
│   pr-publisher 内: コミット整理 → push → gh pr create                    │
│                  → Skill(coderabbit-review) で指摘対応                   │
└─────────────────────────────────────────────────────────────────────────┘
```

## 3. Phase 4-5 のストリーミング並列詳細

```
時刻 ─────────────────────────────────────────────────────────────────────►

t0   PARENT: 3 個の sub-issue を起動
       │
       ├─ Agent(developer-go)      [wt: feat/api ]    ← run_in_background
       ├─ Agent(developer-react)   [wt: feat/ui  ]    ← run_in_background
       └─ Agent(developer-nextjs)  [wt: feat/page]    ← run_in_background

t1   PARENT: 通常作業継続 (待たない)

t2   ▼ developer-go が完了通知
     PARENT: 即座に対応する reviewer を起動
       ├─ Agent(reviewer-security) [対象: feat/api]   ← run_in_background
       ├─ Agent(reviewer-quality)  [対象: feat/api]
       └─ (perf は対象外と判断 → 起動しない)

t3   ▼ developer-react 完了
     PARENT: 即座に対応する reviewer を起動
       ├─ Agent(reviewer-quality)  [対象: feat/ui]
       └─ (security/perf は対象外)

t4   ▼ reviewer-security@feat/api 完了 (指摘あり)
     PARENT: 指摘を整理して developer-go に戻す
       └─ Agent(developer-go) [Round 2/3] ← 再開

t5   ▼ developer-nextjs 完了 / reviewer-quality@feat/ui 完了 (指摘なし)
     PARENT: feat/ui は Phase 6 (PR) へ進める
            feat/page は新たに reviewer 起動

      ...

tN   ▼ feat/api が Round 3 でも収束しない
     PARENT: 親自身が介入 → それでも無理なら USER へ escalate
```

なぜストリーミングなのか:
- 全員待ちは非効率。遅い developer が他の流れをブロックする
- developer 完了 → reviewer 起動 → 修正 → 再 review、を独立に進められる
- 並列度が高いほど効果が出る

## 4. レイヤー分離（なぜスキルとエージェントを分けるか）

```
┌─────────────────────────────────────────────────────────────────────────┐
│ レイヤー A: スキル (claude/skills/feature-team/)                          │
│   役割: このスキル特有のオーケストレーション・プロトコル                   │
│   性質: feature-team を呼んだ時だけ有効                                   │
│   内容:                                                                  │
│    • 6 フェーズの進行手順（SKILL.md）                                     │
│    • レビュー往復 3 ラウンドのルール（_common.md）                         │
│    • worktrunk 運用ルール（_common.md）                                   │
│    • 子に渡す報告フォーマット（_common.md）                                │
│    • しきい値と判断基準（parent.md）                                      │
└─────────────────────────────────────────────────────────────────────────┘
                          │
                          │ 親が prompt 注入
                          ▼ (Agent ツール呼び出し時、_common.md を埋め込む)
┌─────────────────────────────────────────────────────────────────────────┐
│ レイヤー B: エージェント (~/.claude/agents/) 14 体                        │
│   役割: 専門領域の知識・イディオム・典型エラー・テスト戦略                  │
│   性質: 全プロジェクト横断資産。feature-team 以外からも呼べる              │
│   内容:                                                                  │
│    • developer-XXX: 言語/FW 固有の規約・テスト・依存管理                   │
│    • reviewer-YYY: 観点固有のチェックリスト・既知パターン                  │
│    • pr-publisher: PR 本文生成・CodeRabbit 対応・push/PR 作成             │
└─────────────────────────────────────────────────────────────────────────┘

理由:
 ・ 一体化すると: スペシャリストが feature-team 専用になり再利用不能
 ・ 完全分離だと: feature-team 固有のラウンド規約・報告書式を保てない
 ・ 二層分離で:   再利用性とプロトコル統制を両立
```

---

## 認識確認テーブル

| # | 項目 | 設計値 |
|---|------|--------|
| A | 親 = メイン Claude セッション | サブエージェント化しない（ユーザー対話と escalate のため） |
| B | スペシャリストの配置 | `~/.claude/agents/` 配下の 14 体 |
| C | プロトコルの注入方法 | 親が `roles/_common.md` の内容を Agent プロンプトに埋め込む |
| D | レビュアー起動 | ストリーミング（developer 完了通知ごとに `run_in_background: true`）|
| E | レビュー往復上限 | 3 ラウンド（`.claude/project.yml` の `review.round_limit` で上書き可）|
| F | PR 単位 | 大規模 = n 個独立 PR / 小規模 = 1 個統合 PR |
| G | reviewer の種類 | security / performance / quality の 3 観点固定 |
| H | developer の種類 | 10 種特化 + generic フォールバック。中間層なし |
| I | Phase 1 の流れ | brainstorming → writing-plans → Issue 用サマリー の 3 段階 |
| J | Phase 2 の tracker 選択 | `create-issue` が `.claude/project.yml` の `tracker.type` を直接参照。`feature-team` は読まない。不在時は親が雛形書出 + ユーザー判断でコミット |
| K | worktree 管理 | worktrunk (`wt`) を使用 |
| L | PR 単位の確定タイミング | Phase 3（ボリューム判断時） |
| M | Phase 2 のイシュー化スキル | `create-issue`（引数 `<spec-path> <plan-path>`、tracker は config 自己解決） |
| O | Phase 6 の PR 作成 | `pr-publisher` エージェントを branch ごとに `run_in_background=true` で並列起動 |

---

## 設計判断の根拠

### なぜ親をサブエージェント化しないのか

- ユーザーへの `AskUserQuestion` での escalate 経路が必須（設定ファイル不在時、ラウンド上限超過時、ボリューム判定信頼度低下時など）
- サブエージェントはユーザーと直接対話できないので、親をサブエージェント化すると escalate がデッドロックする
- 状態保持（ラウンド数、起動済み子の追跡）も親側で管理する方が自然

### なぜレビュー観点を 3 つに固定したのか

- 観点別に分けると指摘の質が向上する（security 観点で見ているときに quality 指摘が混ざらない）
- 4 つ目以降（accessibility, i18n, etc.）は `quality` reviewer の延長として扱える
- 必要観点だけ起動するためコスト最適化が効く

### なぜ developer を 10 種に絞ったのか

- 中間層（frontend / backend）は特化版より弱く generic より中途半端で、選定ロジックも複雑化する
- 10 種は現実的なカバレッジ（react / nextjs / flutter / go / nodejs / hono / nestjs / rust / ruby / generic）
- 該当なしは `developer-generic` でフォールバックすれば運用上問題ない

### なぜレビュー上限を 3 ラウンドにしたのか

- Round 1 で過半は収束する（指摘の多くは明確）
- Round 2 で残りの大半が片付く
- Round 3 でも収束しない場合は **設計レベルの問題**である可能性が高く、子に修正を続けさせるよりユーザー判断を仰ぐ方が早い
- 上限を伸ばすと無限ループに陥りやすい

### なぜ create-issue は config から tracker を自己解決するのか

- 共通フェーズ（重複チェック・構造化・セルフレビュー）を一元化しつつ、tracker 設定はリポジトリ単位で固定するのが自然
- `feature-team` 親が tracker 設定を読む必要がなくなり、責務分離が明確になる
- 内部で tracker 別に分岐するため、フェーズ単位の差異（GitHub Project / Linear Sub-issue）は明示的に扱える

### なぜ Phase 1 で brainstorming → writing-plans の 2 段階を踏むのか

- `superpowers:brainstorming` は「何を作るか（spec）」、`superpowers:writing-plans` は「どう作るか（plan）」を担う相補スキル
- brainstorming → writing-plans は superpowers 標準の正式トランジション（HARD-GATE で要請されている）
- spec のみで Issue 化すると実装フェーズで再設計が頻発する。plan を先に固めることで sub-issue 分割の精度が上がる
- 出力先は `docs/superpowers/specs/` と `docs/superpowers/plans/` の標準パスを利用（独自の `.claude/tmp/` を作らない）

### なぜ Phase 6 で pr-publisher エージェントを使うのか

- branch ごとの PR 作成は独立タスクなので **`run_in_background=true` で並列化**できる。親が直接 Skill を呼ぶと直列処理になる
- `_common.md` のセルフレビュー・報告フォーマットを強制でき、PR 本文の品質が安定する
- CodeRabbit 指摘対応が大量修正に発展した場合の切り分け（Phase 5 へ差し戻すべきか pr-publisher 内で完結するか）が、エージェント単位の完了通知で明確になる
- 親は集約・通知に専念でき、メイン context の圧迫を抑えられる

---

## 改修するときの注意点

### `_common.md` を変更する前に

子エージェントに注入される定型プロトコルなので、**全 14 体の挙動に影響**する。変更前に:

1. 各 developer / reviewer のエージェント定義（`~/.claude/agents/<agent>.md`）と矛盾しないか確認
2. SKILL.md の Phase 4 / Phase 5 の Agent プロンプトテンプレートと整合しているか確認
3. 報告フォーマット変更時は、親の集約ロジック（SKILL.md Phase 5.3）も合わせて更新

### `parent.md` を変更する前に

親自身の判断基準なので、**SKILL.md からの参照箇所**（Phase 3, 5）と整合しているか確認する。

### しきい値を変更したいとき

`.claude/project.yml` の `volume_thresholds` で**リポジトリ単位で上書き**するのが第一選択。`parent.md` の既定値は最後の砦として残しておく。

### 新しい developer / reviewer を追加するとき

1. `~/.claude/agents/<new-agent>.md` を新設
2. `parent.md` の選定基準テーブルに行を追加
3. `SKILL.md` 本体は変更不要（選定ロジックは `parent.md` に委譲しているため）
