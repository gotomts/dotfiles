---
name: issue-decomposer
description: tech-designer の技術設計（接頭辞付き機能一覧 F-{MODULE}-{連番}・モジュール構造・ドメインモデル）とプロトタイプ実体を入力に、機能を実装単位の issue に分解する、サービス開発ワークフローのフェーズ 5（分解専任）スキル。実行環境は Claude Chat。内部は 2 ステージ（ステージ 1＝Obsidian の index.md に issue 一覧を出して人間レビュー、ステージ 2＝Linear に詳細 issue を作成）。分解単位は垂直スライス（tracer bullet）＝1 PR、各 issue に HITL/AFK タグと推奨スキル注釈を付け、束ね親（capability 単位）で feature-team の起動単位を作る。mattpocock/skills の to-issues の Linear 版。下流 feature-team が Linear issue を依存順・AFK 優先で消化する。ユーザーが「issue に分解したい」「機能を issue 化したい」「Linear に起票したい」「タスク分解したい」と言ったとき、あるいは技術設計が固まって実装計画の話を始めたときは、このスキルを使うべきかどうかを必ず検討する。
maintainer: gotomts
---

# issue-decomposer

サービス開発ワークフロー（6 スキル）の 5 番目に位置する **分解専任** スキル。tech-designer が出した接頭辞付き機能一覧（`F-{MODULE}-{連番}`）・モジュール構造・ドメインモデルと、prototype-builder が生成したプロトタイプ実体を入力に、機能を実装単位の issue に変換する。実行環境は **Claude Chat**。内部は **2 ステージ**構成（ステージ 1＝Obsidian に issue 一覧を出して人間レビュー、ステージ 2＝Linear に詳細 issue を作成）。

## このスキルの役割（全体の中での位置）

サービス開発は次の 6 スキルで進む。本スキルはその 5 番目:

1. service-designer（企画 / Claude Chat）
2. prototype-designer（デザイン設計 / Claude Chat）
3. prototype-builder（プロトタイプ生成 / Claude Code）
4. tech-designer（技術設計 / Claude Chat）
5. **issue-decomposer**（分解 / Claude Chat）← このスキル
6. feature-team（実装 / Claude Code）

- 入力：tech-designer の `04-tech-designer/` 配下（接頭辞付き機能一覧・モジュール構造・ドメインモデル・ADR/CONTEXT.md）＋プロトタイプ実体（GitHub `gotomts/ai-prototypes/{service}/`）。
- 出力：ステージ 1＝`projects/active-dev/{service}/05-issue-decomposer/index.md`（軽い一覧）／ステージ 2＝Linear（MCP 経由の詳細 issue）。
- 下流：feature-team（Claude Code）が Linear の issue を依存順・AFK 優先で消化する。

## いつ使うか

- 技術設計（tech-designer）が固まり、機能を実装単位の issue に分解する段階になったとき
- ユーザーが「issue に分解したい」「機能を issue 化したい」「Linear に起票したい」「タスク分解したい」と言ったとき
- 技術設計の話から実装計画・着手の話に移ったとき（明示的に言っていなくても提案する）

## 設計の土台（2 つのアンカー）

このスキルは 2 つの既存決定の上に立つ。

1. **参照スキル：mattpocock/skills の `to-issues` の Linear 版を作る。** 分解単位は「1 機能 1 issue」ではなく **tracer bullet（垂直スライス）**。各 issue は schema/API/UI/test を端から端まで貫く薄い完結パスで、単体でデモ・検証できる。各スライスに **HITL / AFK** タグを付け、番号リストで quiz して承認まで往復、issue は依存順（blocker 先）に作成、本文は「What to build／受入条件／Blocked by」。
2. **ブランチ戦略（確定済み）：GitHub Flow（trunk-based）。** 1 機能＝1 ブランチ＝1 PR、main は branch protection ＋ CI 必須、squash で 1 機能 1 コミットに圧縮。1 スライスが 1 PR に収まらないときだけ **stacked PR（gh-stack）** を使い、スタックは機能と共に生まれ main に畳まれて消える（常設ブランチにしない）。

→ この 2 つが噛み合い、**「1 issue ＝ 1 垂直スライス ＝ 1 PR」** が素直な対応になる。

## 分解単位：垂直スライス（tracer bullet）＝ 1 PR

**各 issue は schema/API/UI/test を端から端まで貫く薄い完結パス**で、単体でデモ・検証できる。横方向（1 レイヤだけ）には切らない。F-ID（接頭辞付き機能一覧）は各 issue の **カバー範囲**として紐づける（1 スライスが複数 F-ID を部分的に跨ぐことも、単純な機能で結果的に F-ID と 1:1 になることもある）。これでトレーサビリティを保つ。

- **大小の判断基準**（単位を決めたことで内蔵される）：
  - 大きい＝1 PR に収まらない／独立にデモできない完結パスを複数含む → 分割。収まらないものは stacked PR にする。
  - 小さい＝それ単体ではデモ・検証できない水平スライス（DB スキーマだけ等）→ 垂直スライスに束ねる。
  - 「行数」ではなく **「完結性 × 1 PR」**で切る。最終判断は Claude が案を出し人間が確認（参照スキルの quiz と同じ）。

### 2 種の親（束ね親 / stacked PR 親）

親には意味の異なる 2 種がある。**Linear ではどちらも親子だが、区別は構造が主**（束ね親の子は相互に blocked-by 無し＝並列／stacked の子は依存チェーン）。人の可読性のためラベルでも明示する。

- **束ね親（feature grouping）**：1 つの feature 配下に **独立した兄弟スライス**を束ねる。子は並列・各自が別 PR。**feature-team の起動単位＝この束ね親**（1 起動に複数の独立スライスが入ることで feature-team の Phase 2-A 並列が成立する）。束ね親に `feature` ラベルを付す。
- **stacked PR 親**：1 スライスが 1 PR に収まらないときの **依存層**を束ねる。子は逐次・collapse して 1 PR（ブランチ戦略の「スタックは機能と共に生まれ main に畳まれて消える」と一致）。

基本構造は **束ね親＋独立兄弟スライス＋ blocked-by 依存**。stacked PR 親は「1 PR に収まらない」例外運用。

**feature-team の collapse 注意**：現 feature-team は stacked PR の依存子を **1 PR に collapse する**（子ごとの PR 粒度は出ない）。stacked の細粒度を期待しない。独立スライスを別 issue にする方針は feature-team の並列前提と一致しており、これがあるべき姿。

### feature 境界（束ね親）の決め方

束ね親＝**一つの用途まとまり（user-facing capability）単位**。関連 F-ID 群＋プロトタイプ動線＋ドメイン集約から「これで一機能」という束ねを Claude が提案し、**人が ステージ 1 の関所で確認・調整**する（粒度・依存・HITL/AFK レビューと同じ流れ＝新機構なし）。

- サイズ目安：独立スライス数個（およそ 2〜6）。大きい capability は sub-capability に分割（並列幅と PR バッチのレビュー性を保つ）。
- 単一スライスしかない feature はそのまま（feature-team 側で sub-issue ≤1＝親直実装になる）。
- feature 内のスライスは基盤（器構築）へ依存を向けるため基本独立＝そのまま並列。feature 間の依存は blocked-by（器構築や前段 feature に向く）。

## HITL / AFK タグ

**各 issue に HITL / AFK の 2 値タグを付ける。**

- **HITL**＝実装の途中で人の判断が要る（設計判断・デザイン/UX レビュー・要件の曖昧さ等）。
- **AFK**＝今の情報で仕様が固まり、止まらず実装まで通せる。

feature-team は AFK を止まらず消化、HITL は人の関所で止まる。なるべく **AFK 優先**（自律度を上げる）。これは **land 直前の人間レビュー（branch protection で常時 ON）とは別レイヤ**で、「実装途中に人の判断が要るか」を表す。器構築 issue にも付ける（多くは AFK だが技術・運用判断を含むものは HITL）。Linear ではラベル（英略語 `HITL` / `AFK`）。

## 2 ステージの進行と境界

**ステージ 1 で index.md を生成 → 人間が「この内容で Linear に起票してよい」と明示承認するまでステージ 2（Linear への実 issue 作成）に進まない。** tech-designer のハイブリッド完了判定と同型だが、**外部書き込み（不可逆寄り）の前なので承認は必須（省略不可）に強める**。軽い中間生成物（index.md）で粒度・依存・HITL/AFK をレビューさせ、明示承認を関所にする。

**逃げ道**：重いサービスや時間を空けたいときは「セッション分割（ステージ 1 で完結 → 別セッションでステージ 2 起動）」に切ってよい（tech-designer と同じ折衷）。

## ステージ 1：index.md

出力先は `projects/active-dev/{service}/05-issue-decomposer/index.md`（単一ファイル、毎回まるごと再生成）。**テーブル＋（依存が非自明なときだけ）Mermaid 依存グラフ**。ステージ 1 は「タイトル＋依存順」までの軽い一覧で、**人間が粒度・依存・HITL/AFK の妥当性をレビューする関所**。詳細な受入条件はステージ 2（Linear）で生成する。

- **列**：No.（＝冪等キー `S-{nn}` の連番）／タイトル／種別（HITL/AFK）／Blocked by／カバー F-ID（任意で主モジュール）。
- **親子の見せ方＝親列（条件付き・2 種拡張）**：feature（束ね）でグルーピング表示し、stacked がある行は親 No. を参照。**stacked が 1 件でもあれば列を追加、無ければ省く**（右サイズ）。Mermaid では feature をサブグラフ、stacked を入れ子サブグラフで示す。
- 先頭に **HITL/AFK の凡例**を置く。
- 受入条件本文は載せない（ステージ 2 で生成）。Mermaid は依存が非自明なときだけ（右サイズ：単純な小規模では省く）。

## 依存（blocked-by）の引き方

- **推論材料は総合**：モジュール構造（クリーンアーキの依存方向・コンテキスト間依存）＋ドメインモデル（集約の関連）＋プロトタイプ動線（画面遷移の前提）を総合し、Claude が依存案を出して人間が index.md で確認・修正する。
- **依存の濃さ＝折衷**：器構築（共有基盤）への依存は厳密に引き、機能スライス同士は最小限にする。各機能スライスは「器構築に blocked-by ＋必要な前段機能だけ」という形になる。基盤は壊れると広く波及するので依存明示の価値が高く、機能スライス同士は独立着手を優先（AFK と相性）。

## 器構築 issue

**ハイブリッド。** ウォーキングスケルトン（最初の薄い end-to-end 垂直スライスがリポジトリ・CI・全レイヤを立ち上げる）を依存の根に置きつつ、それに乗らない運用系（branch protection・CI 設定・シークレット・CLAUDE.md/ADR/CONTEXT.md の repo 設置 等）は専用の器構築 issue にする。

- これらの器構築（スケルトン＋運用系専用 issue）が「厳密に依存を引く基盤」に当たり、機能スライスの blocked-by の根になる。
- 器構築 issue にも HITL/AFK タグを付ける。
- tech-designer 申し送り：CLAUDE.md/ADR/CONTEXT.md の repo 設置は「器構築＝feature-team 側」。その設置を運用系の器構築 issue として生成する。

## 受入条件の生成ロジック（BDD／チェックリスト）

- **判定材料は総合**：プロトタイプ screen-specs（状態遷移・エッジケース）＋ドメイン不変条件＋機能一覧の種別ヒント（tech-designer が F-ID 単位で BDD か チェックリストかを付与）から受入条件を生成。
- **割り当て＝混在可**：1 issue（＝垂直スライス）内で、振る舞い部分は Given-When-Then（BDD）、表示のみ部分はチェックリスト、と混ぜてよい。垂直スライスは複数レイヤ・複数 F-ID を跨ぐので、F-ID 単位の種別ヒントが issue 単位では混ざるのが自然。
- 受入条件の本文はステージ 2（Linear）で生成（ステージ 1 の index.md には載せない）。

## ステージ 2：Linear 起票フォーマット

- **タイトル**：`[MODULE] スライスを表す動詞句`（例：`[AUTH] メールでログインできる`）。複数モジュール跨ぎは主モジュール。F-ID はタイトルに入れず本文の参照へ。
- **本文**：次の構成（受入条件の後・参照の前に `### 推奨スキル`、該当なければ省略）。

  - **What to build**：端から端までの振る舞いを 1 段落（レイヤ別に書かない）。
  - **受入条件**：BDD は Gherkin、表示のみは `- [ ]`、混在可。
  - **推奨スキル**（後述）。
  - **Blocked by**：無ければ「なし＝即着手可」。
  - **参照**：カバー F-ID・関連 screen-specs/プロトタイプ URL・関連 ADR/CONTEXT.md。
  - 末尾に冪等キーのマーカー（例：`<!-- slice: S-003 -->`）。
- **参照リンクは必須扱い**：feature-team は前段成果物（プロトタイプ・01〜04）を直読みせず、**Linear issue 本文の参照リンク経由でしか前段文脈を受け取らない**。プロトタイプ URL・関連設計（screen-specs / ADR / CONTEXT.md）へのリンクは **省略不可**。欠けると feature-team は文脈なしで実装することになる。
- **依存**：Linear の blockedBy / blocks。依存順（blocker 先）に作成し、実 issue 番号で繋ぐ。
- **親子**：束ね親（feature）は parentId で独立兄弟スライスをぶら下げる。stacked PR 親は parentId で依存層をぶら下げる（collapse して 1 PR）。
- **ラベル**：種別は英略語 `HITL` / `AFK`。issue ごとの 1 行説明はしない。定義は層状に配置：① SKILL.md の凡例（正本・安定）、② index.md 先頭の凡例（再生成で最新）、③ Linear のラベル説明 or プロジェクト説明に一度だけ。
- **その他**：estimate/priority は既定で付けない（人や feature-team が後付け）。新規は Backlog 起点。team/project は起動時に確認。

### Linear 書き込み運用（再実行の安全性）

**冪等キー方式。** 各スライスに安定 ID（index.md の連番＝`S-{nn}`）を振り、Linear issue 本文末尾にマーカー（`<!-- slice: S-003 -->`）で埋める。再実行時は list_issues で既存を照合 → あれば update、なければ create。重複せず、index.md ⇄ Linear が安定 ID で対応する。

- 承認：AGENTS の Linear 書き込みルール（都度承認 or「常に許可」設定）に従う。**起票ターンは AskUserQuestion を併用しない**（同一ターン併用は承認モーダルを潰す疑い）。バッチ起票は 1 ターンで複数 save_issue。
- 破壊的な「全消し→再作成」はしない（冪等な update/create のみ）。

## 推奨スキル注釈（`dev-*` × スキル）

各 issue に「どの `dev-*` で・どのスキルを使って実装するか」の助言を `### 推奨スキル` として付ける。

- **責務＝助言（advisory）**：issue-decomposer は「推奨 `dev-*`＋推奨スキル＋理由」を提案として書くが、**最終的な `dev-*` 選定は feature-team parent が権威**。parent は自分が選んだ `dev-*` の `skills:` 許可リストと推奨スキルを交差させ、外れたものは落とす（安全フォールバック）。
- **生成元**：dotfiles（`gotomts/dotfiles`）の `claude/agents/*.md` の `skills:` 許可リストと `claude/skills/*/SKILL.md` の name＋description を GitHub MCP で直読し、issue 内容と突き合わせて提案する。
- **フォーマット（リスト・スキルごとに理由）**：推奨 `dev-*` は見出しに 1 回だけ示し（1 issue＝1 `dev-*` 割当）、各スキルを `- skill-name：理由（1 行）` で列挙。

  ```
  ### 推奨スキル
  推奨 dev-*: dev-flutter
  - widget-test：UI 状態遷移を含むため widget テストで受入条件を担保
  - declarative-routing：画面遷移を新設するため型安全ルートを使う
  ```
- **置き場所**：ステージ 2 Linear 本文のみ（受入条件の後・参照の前）。該当スキルが無ければセクションを省略。**ステージ 1 index.md には載せない**（スキル系は受入条件と同じ「実装の詳細」としてステージ 2 で生成）。
- **取捨選択**：スキルの足し引きは計画フェーズ（Claude Chat）の対話で行い、確定セットを Linear 本文へ。feature-team（実行）はそれを読むだけで人に問わない（明示的な選択ステップは作らない）。

## 共通要件

### 1. 入出力契約

- **入力：** 必須＝接頭辞付き機能一覧（F-ID）・モジュール一覧／補助＝ドメインモデル・screen-specs・ADR/CONTEXT.md・プロトタイプ実体。
- **出力：** ステージ 1＝`05-issue-decomposer/index.md`／ステージ 2＝Linear issues（冪等キー付き）。
- **前提チェック＝折衷**：必須（機能一覧・モジュール）が欠ければ停止して人間に知らせる。補助（ドメインモデル詳細・sketches 等）は欠けても警告のみで続行し、index.md に「要確認」印で残す。

### 2. 読み方の地図

- 読む順：00-README → AGENTS → workflow-design → tech-designer 出力（`04-tech-designer/`）→ プロトタイプ実体。
- 各入力が効く所：機能一覧 → スライス候補／モジュール・ドメイン・動線 → 依存／screen-specs → 受入条件。

### 3. 完了時の次スキル案内（ハイブリッド完了判定）

ステージ 2 まで揃ったことを検知したら、サマリ＋未反映の論点を提示して一拍確認する。ユーザー合意で次スキル案内を出す。ステージ境界（明示承認ゲート）でも同じ判定を使う。

案内の文言（実行環境も添える）:

> issue 分解が固まりました。次は feature-team（Claude Code）で Linear の issue を依存順・AFK 優先に実装しましょう。

申し送り：index.md ⇄ Linear の対応・HITL の関所・器構築が依存の根、を feature-team に伝える。

### 4. 運用知見（運用しながら追記する）

最初は空でよい。運用しながら動的に知見を追記する場。分解の癖・判断基準の構造的な更新は design-notes/decision-log（真実源）へ、MCP・ワークフローの不具合/改善は Linear（KISSA プロジェクト）へ送る。

```markdown
## 運用知見（運用しながら追記する）

### 判断に迷ったときの参照優先度
（運用しながら書き加える）

### 過去のはまりどころ
（運用しながら書き加える）

### 分解粒度（垂直スライス）で迷った例
（運用しながら書き加える）

### feature 境界（束ね親）の切り方で迷った例
（運用しながら書き加える）

### 依存（blocked-by）の引き方ではまった例
（運用しながら書き加える）

### HITL/AFK 判定で迷った例
（運用しながら書き加える）

### Linear 起票・冪等キー運用のはまりどころ
（運用しながら書き加える）
```

## 重要な原則

- **分解専任**：本実装のコードは書かない（それは feature-team）。ここは機能を実装単位の issue に変換する意思決定とドキュメント化。
- **垂直スライス＝ 1 PR**：レイヤ横断の薄い完結パスで切る。「完結性 × 1 PR」が単位。水平スライス（1 レイヤだけ）は束ねる。
- **外部書き込み前は必ず関所**：ステージ 2（Linear 起票）は人の明示承認を省略不可。軽い index.md でレビューさせる。
- **基盤は厳密・機能スライスは独立優先**：依存は器構築に集約し、機能スライス同士は最小限にして並列・AFK を効かせる。
- **参照リンクは必須**：feature-team は issue 本文の参照経由でしか前段文脈を受け取らない。プロトタイプ URL・設計リンクを省略しない。
- **再実行は冪等**：冪等キー `S-{nn}` で update/create。破壊的な全消し→再作成はしない。
- **確認質問は 1 ターンに 1 つずつ**。
