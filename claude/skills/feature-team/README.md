# Feature Team — 設計ドキュメント (保守者向け)

このディレクトリは Claude Code 用の **マルチエージェント実装オーケストレーション** スキルです。

実行時に Claude が読むのは `SKILL.md` / `roles/_common.md` / `roles/parent.md` です。この `README.md` は **人間 (=今後このスキルを改修したくなったあなた) 向け** の設計概要です。

## TL;DR

```
このスキルは「実装専任」。
要件定義 / 計画作成 / Issue 作成はやらない。

ユーザーが /feature-team <issue-番号|ID> または --spec <path> [--plan <path>] で起動
  → Phase 0: 実装対象の受領と妥当性確認 (対象不在/薄い時は 4 択案内で停止)
  → Phase 1: 大規模か小規模かを判定
  → Phase 2: 大規模なら sub-issue を並列実装、小規模なら親直実装
  → Phase 3: 観点別レビュー (quality 必須、security/performance は条件付き)
              + CONTEXT.md / ADR 候補スクリーニング (該当時)
  → Phase 4: pr-publisher を branch ごとに並列起動して PR 作成
```

前段スキルとの組み合わせ:

```
要件詰め (任意)              計画化           issue 化           実装〜PR
────────────────         ──────────────   ──────────────    ──────────────
brainstorming            writing-plans    create-issue      feature-team
grill-me                                                        ↑
grill-with-docs                                            <issue-番号|ID>
pick-next (一括)                                                または
手動 (UI から登録)                                       --spec <path> [--plan <path>]
```

ポイント:

- **親はメイン Claude セッション自身** (サブエージェント化しない)
- **子エージェントは `~/.claude/agents/` 配下の 14 体** (developer 10 + reviewer 3 + pr-publisher 1)
- **レビュー往復は最大 3 ラウンド**で打ち切り、超過時は親介入 → ユーザー escalate
- **rev-quality は全実装で必須**。規約違反・テスト不足の素通りを防ぐ最重要ハブ
- **設定は `.claude/project.yml`** (リポジトリ単位)。`feature-team` が読むのは `review.*` と `volume_thresholds.*` のみ

---

## 1. 体制全体図 (コンポーネントとレイヤー分離)

```
┌──────────────────────────────────────────────────────────────────────────┐
│                  USER (人間)                                              │
│  - 要件は前段スキル (brainstorming / grill-me / grill-with-docs / pick-next) │
│    で詰め、issue 化は create-issue が行う                                 │
│  - feature-team の起動時に実装対象 (issue 番号 or spec/plan パス) を明示    │
│  - escalate 時に判断                                                      │
└──────────────┬───────────────────────────────────────────────────────────┘
               │ 対話 (AskUserQuestion / 通常応答)
               ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  PARENT = メイン Claude セッション                                        │
│  ─────────────────────────────────────────────────────────────────────   │
│  読み込むファイル:                                                        │
│   • feature-team/SKILL.md       ← 5 フェーズの進行規約                    │
│   • roles/parent.md             ← しきい値・選定基準・escalate 条件        │
│   • roles/_common.md            ← 子に注入するための定型プロトコル         │
│                                                                          │
│  責務:                                                                    │
│   • 実装対象の受領と妥当性確認 (Phase 0)                                  │
│   • ボリューム判断 (大規模 vs 小規模)                                      │
│   • 観点別 reviewer の選定 (security/perf/quality)                       │
│   • レビューラウンドの収束判定 (上限 3)                                    │
│   • CONTEXT.md 用語追記 / ADR 化判断のトリガー                            │
│   • ユーザーへの escalate                                                 │
│   • 子の出力を統合・検証                                                  │
│                                                                          │
│  しないこと:                                                              │
│   • 要件定義の対話 (Phase 0 (d) ルートでは最小限の対話のみ。詰めるなら戻す)   │
│   • Issue 作成                                                            │
│   • ADR の 3 条件判定 (grill-with-docs に委譲)                            │
└──┬───────────────────────────────────────────────────────────────────────┘
   │
   │ Skill ツール呼び出し                  Agent ツール呼び出し
   │ (プロセス・ナレッジ系)                 (実装・レビュー系)
   ▼                                       ▼
┌─────────────────────────────┐   ┌─────────────────────────────────────┐
│ SKILLS (~/.claude/skills/)  │   │ SUBAGENTS (fleet/agents) 12 体       │
│ ─────────────────────────   │   │ ──────────────────────────────────  │
│ Phase 3.5 (該当時):         │   │ DEVELOPERS (8):                     │
│  • grill-with-docs          │   │  • dev-react (React + Next.js)      │
│    (ADR 化判定の対話)       │   │  • dev-react-native                 │
│                             │   │  • dev-flutter                      │
│ Phase 4:                    │   │  • dev-nodejs (Node/NestJS/Hono)    │
│  • coderabbit-review        │   │  • dev-go                           │
│    (pr-publisher 内で呼ぶ)  │   │  • dev-rust                         │
│                             │   │  • dev-infra                        │
│ 補助:                        │   │  • dev-generic   ← フォールバック   │
│  • handoff                  │   │                                     │
│                             │   │ REVIEWERS (3):                      │
│ 前段 (このスキルからは        │   │  • rev-security                     │
│ 呼ばない):                    │   │  • rev-performance                  │
│  • brainstorming            │   │  • rev-quality                      │
│  • writing-plans            │   │      (CONTEXT/ADR 候補スクリーニングも) │
│  • grill-me                 │   │                                     │
│  • create-issue             │   │ PUBLISHER (1):                      │
│  • pick-next                │   │  • pr-publisher                     │
│                             │   │    Phase 4 で branch ごとに並列起動 │
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
                                  └──────────────────────┘
```

## 2. 5 フェーズのフロー (時系列とゲート)

```
 USER
  │
  │ /feature-team <issue-番号|ID> or --spec <path> or 引数なし
  ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Phase 0: 起動 (実装対象の受領と妥当性確認)                                 │
│  0.1 引数解析                                                             │
│  0.2 引数あり → 対象取得 (gh issue view / linear issue view / Read spec/plan)│
│  0.3 「薄い」判定 → ユーザー確認 (続行 / 要件詰めに戻る)                     │
│  0.4 引数なし → 4 択案内して停止 ((a)〜(d))                                │
│      ※(d) 対話モードでも質問は最大 3 つまで。超えたら (a) に戻す             │
└──────────────┬──────────────────────────────────────────────────────────┘
               │ ゲート: 対象が確定したか
               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Phase 1: ボリューム判断                                                  │
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
│ Phase 2-A: 並列開発           │    │ Phase 2-B: 親直接実装                │
│ ──────────────────────────   │    │ ──────────────────────────────────│
│ 各 sub-issue ごとに wt 作成    │    │ 親が wt を 1 個作成して直接コーディング │
│ Agent(dev-XXX)         │    │                                    │
│   × N (run_in_background)    │    │                                    │
│                              │    │                                    │
│ 完了通知ごとにストリーミング   │    │                                    │
│ で reviewer 起動 (Phase 3)    │    │                                    │
└──────┬───────────────────────┘    └─────────┬──────────────────────────┘
       │                                       │
       ▼                                       │
┌──────────────────────────────┐               │
│ Phase 3: 観点別レビュー        │               │
│ ──────────────────────────   │               │
│ Agent(rev-quality)      │               │
│   ← 全実装で必須              │               │
│   ← CONTEXT/ADR 候補も拾う    │               │
│ Agent(rev-security)     │               │
│   (該当時のみ)                │               │
│ Agent(rev-performance)  │               │
│   (該当時のみ)                │               │
│                              │               │
│ 親が指摘を統合 → developer に  │               │
│ 戻して修正                    │               │
│                              │               │
│ Phase 3.5 (CONTEXT/ADR 連携): │               │
│  • 用語追記候補 → 親が Edit   │               │
│  • ADR 化候補 → 3 択 →        │               │
│    Skill(grill-with-docs) へ │               │
│                              │               │
│ ループ上限: 3 ラウンド         │               │
│  ↳ 超過時 → 親が介入 / escalate│               │
└──────┬───────────────────────┘               │
       │                                       │
       └──────────┬────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Phase 4: PR                                                             │
│  Phase 2-A → n 個の独立 PR / Phase 2-B → 1 個の統合 PR                    │
│  PARENT → Agent(pr-publisher) を branch ごとに並列起動                    │
│   pr-publisher 内: コミット整理 → push → gh pr create                    │
│                  → Skill(coderabbit-review) で指摘対応                   │
└─────────────────────────────────────────────────────────────────────────┘
```

## 3. Phase 2-A / Phase 3 のストリーミング並列詳細

```
時刻 ─────────────────────────────────────────────────────────────────────►

t0   PARENT: 3 個の sub-issue を起動
       │
       ├─ Agent(dev-go)      [wt: feat/api ]    ← run_in_background
       ├─ Agent(dev-react)   [wt: feat/ui  ]    ← run_in_background
       └─ Agent(dev-nodejs)  [wt: feat/page]    ← run_in_background

t1   PARENT: 通常作業継続 (待たない)

t2   ▼ dev-go が完了通知
     PARENT: 即座に対応する reviewer を起動
       ├─ Agent(rev-quality)  [対象: feat/api]   ← 全実装で必須
       ├─ Agent(rev-security) [対象: feat/api]   ← API endpoint があるため
       └─ (perf は対象外と判断 → 起動しない)

t3   ▼ dev-react 完了
     PARENT: 即座に対応する reviewer を起動
       ├─ Agent(rev-quality)  [対象: feat/ui]   ← 全実装で必須
       └─ (security/perf は対象外)

t4   ▼ rev-security@feat/api 完了 (指摘あり)
     PARENT: 指摘を整理して dev-go に戻す
       └─ Agent(dev-go) [Round 2/3] ← 再開

t5   ▼ dev-nodejs 完了 / rev-quality@feat/ui 完了 (CONTEXT 追記候補)
     PARENT: feat/ui の用語追記候補を判断 → 親が Edit で追記
            feat/ui を Phase 4 (PR) へ進める
            feat/page は新たに reviewer 起動

      ...

tN   ▼ feat/api が Round 3 でも収束しない
     PARENT: 親自身が介入 → それでも無理なら USER へ escalate
```

なぜストリーミングなのか:

- 全員待ちは非効率。遅い developer が他の流れをブロックする
- developer 完了 → reviewer 起動 → 修正 → 再 review、を独立に進められる
- 並列度が高いほど効果が出る

## 4. レイヤー分離 (なぜスキルとエージェントを分けるか)

```
┌─────────────────────────────────────────────────────────────────────────┐
│ レイヤー A: スキル (claude/skills/feature-team/)                          │
│   役割: このスキル特有のオーケストレーション・プロトコル                   │
│   性質: feature-team を呼んだ時だけ有効                                   │
│   内容:                                                                  │
│    • 5 フェーズの進行手順 (SKILL.md)                                      │
│    • レビュー往復 3 ラウンドのルール (_common.md)                          │
│    • worktrunk 運用ルール (_common.md)                                   │
│    • 子に渡す報告フォーマット (_common.md)                                 │
│    • しきい値と判断基準 (parent.md)                                       │
│    • CONTEXT/ADR 連携の役割分担 (parent.md)                              │
└─────────────────────────────────────────────────────────────────────────┘
                          │
                          │ 親が prompt 注入
                          ▼ (Agent ツール呼び出し時、_common.md を埋め込む)
┌─────────────────────────────────────────────────────────────────────────┐
│ レイヤー B: エージェント (~/.claude/agents/) 14 体                        │
│   役割: 専門領域の知識・イディオム・典型エラー・テスト戦略                  │
│   性質: 全プロジェクト横断資産。feature-team 以外からも呼べる              │
│   内容:                                                                  │
│    • dev-XXX: 言語/FW 固有の規約・テスト・依存管理                   │
│    • rev-YYY: 観点固有のチェックリスト・既知パターン                  │
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
| A | 親 = メイン Claude セッション | サブエージェント化しない (ユーザー対話と escalate のため) |
| B | スペシャリストの配置 | `~/.claude/agents/` 配下の 14 体 |
| C | プロトコルの注入方法 | 親が `roles/_common.md` の内容を Agent プロンプトに埋め込む |
| D | レビュアー起動 | ストリーミング (developer 完了通知ごとに `run_in_background: true`) |
| E | レビュー往復上限 | 3 ラウンド (`.claude/project.yml` の `review.round_limit` で上書き可) |
| F | PR 単位 | 大規模 = n 個独立 PR / 小規模 = 1 個統合 PR |
| G | reviewer の種類 | security / performance / quality の 3 観点固定 |
| H | developer の種類 | 10 種特化 + generic フォールバック。中間層なし |
| I | スキル責務 | **実装専任**。要件定義 / 計画作成 / Issue 作成は前段の独立スキル |
| J | 起動引数 | `<issue-番号|ID>` または `--spec <path> [--plan <path>]` または引数なし (4 択案内) |
| K | worktree 管理 | worktrunk (`wt`) を使用 |
| L | PR 単位の確定タイミング | Phase 1 (ボリューム判断時) |
| M | 対象が薄い/不在時の挙動 | 親が要件定義を肩代わりせず 4 択案内で停止: (a) 要件詰めへ / (b) 既存 issue 指定 / (c) spec/plan 指定 / (d) ad-hoc 対話で最小実装 (質問 3 つ超で (a) へ戻す) |
| N | rev-quality の必須化 | 全実装で必須 (Phase 2-A の各 sub-issue、Phase 2-B、ad-hoc spec すべて) |
| O | Phase 4 の PR 作成 | `pr-publisher` エージェントを branch ごとに `run_in_background=true` で並列起動 |
| P | CONTEXT.md / ADR 連携 | CONTEXT.md / docs/adr/ 存在時のみ。rev-quality が候補列挙 → 用語追記は親が Edit、ADR 化判定は `Skill(grill-with-docs)` に委譲 |
| Q | 前段スキルとの組み合わせ | `pick-next` / `brainstorming → writing-plans → create-issue` / `grill-me` or `grill-with-docs` + 手書き spec/plan / UI 手動 |

---

## 設計判断の根拠

### なぜ Phase 1 (要件定義) と Phase 2 (Issue 作成) を切り離したのか

- 旧設計は brainstorming → writing-plans → create-issue → 実装 を一本道で抱える神スキルだった
- 結果: 「実装したい」と思ってもまず brainstorming から始める必要があり、起動コストが高くなって**ほぼ起動されなくなった**
- すると **reviewer も走らなくなり、規約違反・テスト不足・バグが素通り** する状態が続いた (今回の改修の最大の動機)
- 責務を実装に絞ることで:
  - 起動契約が「実装対象を渡す」の 1 行で説明できる
  - 要件詰めスキル (brainstorming / grill-me / grill-with-docs) を**自由に選べる**
  - issue 経由でも spec/plan 直渡しでも入れる
  - 結果として feature-team が起動されやすくなり、reviewer 経路に乗る確率が上がる
- 前段スキルが試用段階で、どれを使うか見極め中の現状では、要件詰めスキルにロックインしない設計が柔軟性として大きい

### なぜ Phase 0 (起動) を新設したのか

- 旧設計には「起動引数」のセクションがなく、対象は Phase 1 (brainstorming) で口頭で受け取る暗黙仕様だった
- 実装専任化に伴い、対象の受領と妥当性確認は明示的な Phase として独立させる必要があった
- Phase 0 はさらに 3 つの責務を持たせた:
  - 引数解析 (issue 番号 / spec パス / 引数なし)
  - 「薄い」判定 (受入条件・変更対象・依存関係の不在チェック)
  - 引数なし時の交通整理 (4 択案内、要件定義は外部スキルへ)
- 「薄い」判定で要件詰めに戻す案内を入れることで、薄い対象を無理に実装して手戻りする失敗パターンを未然に防ぐ

### なぜ親をサブエージェント化しないのか

- ユーザーへの `AskUserQuestion` での escalate 経路が必須 (Phase 0 の薄い判定、ラウンド上限超過時、ボリューム判定信頼度低下時、ADR 化判定の 3 択など)
- サブエージェントはユーザーと直接対話できないので、親をサブエージェント化すると escalate がデッドロックする
- 状態保持 (ラウンド数、起動済み子の追跡) も親側で管理する方が自然

### なぜレビュー観点を 3 つに固定したのか

- 観点別に分けると指摘の質が向上する (security 観点で見ているときに quality 指摘が混ざらない)
- 4 つ目以降 (accessibility, i18n, etc.) は `quality` reviewer の延長として扱える
- 必要観点だけ起動するためコスト最適化が効く

### なぜ rev-quality を全実装で必須にしたのか

- 旧設計でも parent.md に「quality は常に必須」と書かれていたが、旧 Phase 4-B (小規模親直実装、現 Phase 2-B 相当) の文中で「最低 quality 観点で 1 回」と緩めに書かれていた箇所もあり、運用上スキップされやすかった
- 規約違反・テスト不足・バグの素通り防止の最後の砦なので、新設計では SKILL.md / parent.md 両方で**全実装必須**を強調する形に統一した
- ad-hoc spec (Phase 0.4 (d)) の小実装でも省略不可

### なぜ developer を 10 種に絞ったのか

- 中間層 (frontend / backend) は特化版より弱く generic より中途半端で、選定ロジックも複雑化する
- 10 種は現実的なカバレッジ (react / nextjs / flutter / go / nodejs / hono / nestjs / rust / ruby / generic)
- 該当なしは `dev-generic` でフォールバックすれば運用上問題ない

### なぜレビュー上限を 3 ラウンドにしたのか

- Round 1 で過半は収束する (指摘の多くは明確)
- Round 2 で残りの大半が片付く
- Round 3 でも収束しない場合は **設計レベルの問題** である可能性が高く、子に修正を続けさせるよりユーザー判断を仰ぐ方が早い
- 上限を伸ばすと無限ループに陥りやすい

### なぜ CONTEXT.md / ADR 連携を grill-with-docs に委譲したのか

- grill-with-docs スキル本体に既に 3 条件判定 (Hard to reverse / Surprising without context / Real trade-off) と CONTEXT-FORMAT / ADR-FORMAT が定義されている
- これを feature-team 側に再定義すると **判断基準が 2 箇所に分散** し、grill-with-docs 側の改修が将来あったとき同期忘れで崩壊する典型的なアンチパターンになる
- 役割分担:
  - rev-quality: 候補スクリーニングだけ (3 条件判定はしない)
  - 親: 候補ありで grill-with-docs を起動するかどうかをユーザーに 3 択提示
  - grill-with-docs: 3 条件判定と ADR 書き出し (一元管理)
- 用語追記は軽量判断なので grill-with-docs を呼ばず親が直接 Edit する (フォーマットだけ CONTEXT-FORMAT.md を参照)

### なぜ Phase 4 で pr-publisher エージェントを使うのか

- branch ごとの PR 作成は独立タスクなので **`run_in_background=true` で並列化** できる。親が直接 Skill を呼ぶと直列処理になる
- `_common.md` のセルフレビュー・報告フォーマットを強制でき、PR 本文の品質が安定する
- CodeRabbit 指摘対応が大量修正に発展した場合の切り分け (Phase 3 へ差し戻すべきか pr-publisher 内で完結するか) が、エージェント単位の完了通知で明確になる
- 親は集約・通知に専念でき、メイン context の圧迫を抑えられる

---

## 改修するときの注意点

### `_common.md` を変更する前に

子エージェントに注入される定型プロトコルなので、**全 14 体の挙動に影響**する。変更前に:

1. 各 developer / reviewer のエージェント定義 (`~/.claude/agents/<agent>.md`) と矛盾しないか確認
2. SKILL.md の Phase 2 / Phase 3 の Agent プロンプトテンプレートと整合しているか確認
3. 報告フォーマット変更時は、親の集約ロジック (SKILL.md Phase 3.3) も合わせて更新

### `parent.md` を変更する前に

親自身の判断基準なので、**SKILL.md からの参照箇所** (Phase 1, 3, 3.5) と整合しているか確認する。

特に「8. CONTEXT.md / ADR 連携」は grill-with-docs スキルとの境界が肝。判定基準を `feature-team` 側で書き直さないこと (二重定義禁止)。

### しきい値を変更したいとき

`.claude/project.yml` の `volume_thresholds` で**リポジトリ単位で上書き**するのが第一選択。`parent.md` の既定値は最後の砦として残しておく。

### 新しい developer / reviewer を追加するとき

1. `~/.claude/agents/<new-agent>.md` を新設
2. `parent.md` の選定基準テーブルに行を追加
3. `SKILL.md` 本体は変更不要 (選定ロジックは `parent.md` に委譲しているため)

### 前段スキル (brainstorming / grill-me / grill-with-docs / create-issue / pick-next) の挙動が変わったとき

- `feature-team` 内に前段スキルの仕様を**コピー**している箇所が無いか確認
- 唯一参照しているのは:
  - Phase 0.4 の (a) 案内文 (要件詰めスキルへの誘導)
  - Phase 3.5 の grill-with-docs 起動条件
  - 認識確認テーブル Q
- これらの記述は「スキル名 + 起動方法」レベルに留めており、スキル内部の手順は書いていない
- 万一書いてしまったら静かな崩壊が始まる兆候なので即削除する
