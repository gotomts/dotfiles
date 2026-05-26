# Feature Team — Parent Decision Guide

このドキュメントは `feature-team` 親 (メイン Claude) が**判断に迷ったときに参照するガイド**です。SKILL.md の各 Phase で「parent.md を参照」と書かれている箇所の根拠です。

子エージェントには注入しません。親自身が読みます。

`feature-team` は実装専任です。要件定義 / 計画作成 / Issue 作成はこのスキルの責務外で、前段の独立スキル (`grill-me` / `superpowers:brainstorming` / `superpowers:writing-plans` / `create-issue` / `pick-next`) に任せます。このガイドも実装フェーズ (Phase 0〜4) の判断のみを扱います。

---

## 1. ボリューム判断しきい値 (Phase 1)

### 既定しきい値

| 項目 | 小規模 (Phase 2-B 親直実装) | 大規模 (Phase 2-A 並列開発) |
|------|----|----|
| sub-issue 数 | ≤ 1 | ≥ 2 |
| 推定変更ファイル数 | ≤ 5 | ≥ 6 |
| 推定変更行数 | ≤ 200 | ≥ 201 |
| 言語/FW の異種混合 | なし (単一スタック) | あり (複数スタック) |

これらは `.claude/project.yml` の `volume_thresholds` で上書きされている場合があるので、設定ファイル値を優先する。

### 判定アルゴリズム

```
1. sub-issue が 1 つ以下 → 小規模
2. sub-issue 間に依存があり、並列化できない (直列必須) → 小規模扱い (または issue-dev に委譲)
3. 複数言語・FW にまたがる → 大規模 (特化版 developer の使い分けが効く)
4. 親が現状コードベースを把握している前提で「自分で書いた方が早い」と判断できる
   かつ sub-issue ≤ 1 → 小規模
5. ad-hoc spec (Phase 0.4 (d) ルート) → 通常は小規模 (sub-issue 構造を持たないため)
6. それ以外 → 大規模
```

### 信頼度が低いとき

判定の信頼度が低い場合は、`AskUserQuestion` で**選択肢 2-3 個**を提示してユーザーに委ねる。例:

- (a) 大規模並列で進める (推定 N 並列)
- (b) 小規模単独で親が直接書く
- (c) issue-dev のフェーズ S (直列モード) を使い、サブ issue を順番に処理する

## 2. Developer 選定基準

### 10 種の特化版

| Developer | 想定スタック・領域 |
|-----------|----|
| `developer-react` | React (CRA / Vite / pure React)。状態管理 (Redux/Zustand) 含む。Next.js 専用機能は含めない |
| `developer-nextjs` | Next.js (App Router / Pages Router)。SSR / RSC / API Routes / middleware |
| `developer-flutter` | Flutter / Dart。iOS/Android のネイティブブリッジ含む |
| `developer-go` | Go。標準ライブラリ・goroutine / channel パターン |
| `developer-nodejs` | Node.js (フレームワークなし、または Express)。CLI ツール・サーバー両対応 |
| `developer-hono` | Hono フレームワーク。Cloudflare Workers / Bun / Deno デプロイターゲット |
| `developer-nestjs` | NestJS。依存注入・モジュール設計・TypeORM/Prisma 統合 |
| `developer-rust` | Rust。所有権・ライフタイム・async (tokio) |
| `developer-ruby` | Ruby / Rails。ActiveRecord・migration・rspec |
| `developer-generic` | 上記いずれにも該当しない場合のフォールバック |

### 選定アルゴリズム

```
1. sub-issue の本文・タグ・対象ファイル拡張子から主要スタックを推定
2. 上記表に該当があれば特化版を選ぶ
3. 該当なし → developer-generic
4. 複数該当 (例: Next.js + Hono の monorepo の sub-issue)
   → 主要な変更領域で判断。判定困難なら親が分割を検討 (sub-issue を分けて create-issue にやり直し依頼)
```

### 中間層 (frontend / backend 汎用) を作らない理由

- 中間層は特化版より弱く、generic より中途半端
- 選定ロジックが「特化 → 中間 → generic」と 3 段階になり複雑化
- 特化版が育てば育つほど中間層は不要化する
- 該当がなければ generic で十分 (汎用エージェントは元々強い)

## 3. Reviewer 観点選定基準

### 3 観点固定

| Reviewer | 主に見る観点 |
|----------|----|
| `reviewer-security` | OWASP Top 10、認証・認可、入力バリデーション、秘密情報の取扱い、依存ライブラリの既知脆弱性、SSRF/XSS/SQL/コマンドインジェクションリスク |
| `reviewer-performance` | ホットパス (リクエスト処理、ループ内処理)、N+1 クエリ、不要な再計算、メモリリーク、大量データ処理のスケーラビリティ、I/O ブロッキング |
| `reviewer-quality` | バグ・機能的正確性、可読性、命名、抽象化の整合、DRY、テストカバレッジ、コメント品質、エラーハンドリングの妥当性、規約遵守。**CONTEXT.md / docs/adr/ が存在する場合は候補スクリーニング** (3.5 参照) |

### 起動判定

`.claude/project.yml` の `review.default_reviewers` を起点に、各 sub-issue / branch ごとに以下を加味して観点を決める。

#### `reviewer-quality` は**全実装で必須**

- 既定で全 sub-issue / branch / ad-hoc spec 実装に起動する
- どんな小規模変更でも起動コストは小さく、抜け漏れ検出に有効
- **省略不可**。Phase 0.4 (d) ルートの最小実装でも、Phase 2-B の親直実装でも、必ず 1 回は走らせる
- このスキルが起動されない・reviewer-quality が走らないことが、規約違反・テスト不足・バグを素通りさせる主因なので、ここは絶対に妥協しない

#### `reviewer-security` を**追加で起動する**条件

- ユーザー入力を受ける処理 (API endpoint, form, CLI 引数, file upload)
- 認証・セッション・トークン管理
- 外部システムへの認証情報送信
- `eval` / 動的コード実行 / 動的 SQL 構築
- 秘密情報 (API キー、パスワード、PII) の保存・送信
- 暗号化・ハッシュ・乱数生成
- 依存追加 (`package.json` / `Cargo.toml` / `go.mod` 等の更新)

#### `reviewer-performance` を**追加で起動する**条件

- DB クエリの追加・変更 (特にループ内)
- バッチ処理・大量レコード処理
- フロントエンドの再レンダリング負荷増加リスク
- ファイル I/O・ネットワーク呼出の増加
- キャッシュ層の変更
- アルゴリズム変更

### 観点の数を増やしすぎない

- 不要な観点を起動するとレビューラウンド消費が早まり、3 ラウンド上限に到達しやすい
- 「念のため」で security/performance を起動しない。必要性の根拠を持つこと
- `quality` だけは例外で、根拠なしでも常に起動する

## 4. Phase 3 ラウンド超過時の介入手順

3 ラウンド消化しても収束しない場合の親の動き:

### 4.1 まず親が差分を読む

- 子経由ではなく **親自身が `git diff` で差分を読む**
- 並行して reviewer の指摘履歴 (Round 1〜3) を時系列で並べる

### 4.2 原因を分類

| 分類 | 兆候 | 対応 |
|------|------|------|
| 設計レベルの問題 | 「アーキ修正が必要」「責務分離が破綻」「他 sub-issue とインタフェース矛盾」 | ユーザーに escalate |
| 実装の取り違え | 「指摘がはっきりしているのに直し方がズレ続ける」 | 親が直接修正 |
| 指摘の妥当性自体が疑わしい | 「reviewer の指摘が間違っている／古い指摘を引きずっている」 | 親が指摘を却下し、developer に「現在の状態で完了」を通知 |
| テスト不足で判定不能 | 「正しさをテストで担保できていない」 | テスト追加を 1 ラウンド分追加発注 (例外的にラウンド+1) |

### 4.3 ユーザー escalate のフォーマット

```
## ⚠️ Phase 3 ラウンド上限到達 — 判断要請

**対象:** sub-issue #<番号> / branch: <branch>
**消化ラウンド:** 3

### Round 1 〜 3 の指摘履歴
- R1: <要点>
- R2: <要点>
- R3: <要点>

### 親の診断
分類: <設計問題 / 実装取り違え / 指摘の妥当性疑問 / テスト不足>
根拠: <差分から読み取った理由>

### 選択肢
1. 設計やり直し (要件詰めスキルに戻る) — 推奨理由: ...
2. このまま PR を作り、レビューを後続 PR で対応
3. この sub-issue を中断 (他 sub-issue は継続)
```

選択肢 1 で「設計やり直し」を選んだ場合、`feature-team` は中断する。ユーザーは別途 `Skill(grill-me)` / `Skill(superpowers:brainstorming)` 等で詰め直し、必要なら issue を `create-issue` で作り直してから `feature-team` を再起動する。

## 5. Phase 4 — pr-publisher 起動

### 起動単位

- 1 branch につき 1 体の `pr-publisher` を起動する
- 複数 branch がある場合は **`run_in_background=true` で並列起動** する (PR 作成は branch 間で独立)
- 親は起動後すぐに次の処理に進まず、TaskList でバックグラウンド完了通知を受け取る

### プロンプトに必ず含める項目

`pr-publisher` のプロンプトには以下 8 項目を含めること (不足すると CodeRabbit 対応や Issue リンクで詰まる):

1. `roles/_common.md` の本文 (または `Read("/Users/.../roles/_common.md")` の指示)
2. リポジトリ情報 (owner/repo)
3. worktree 絶対パス
4. branch 名
5. 紐付ける Issue 番号 (ad-hoc spec の場合は無し)
6. spec / plan ファイルへの絶対パス (PR 本文への引用元、ad-hoc spec の場合は省略)
7. Phase 3 の review summary (critical/major のみ、CONTEXT/ADR 更新の有無)
8. 期待アクション: コミット整理 → push → `gh pr create` → `Skill(coderabbit-review)` 起動

### 失敗パターンと対応

| 兆候 | 対応 |
|------|------|
| `gh pr create` が既存 PR と衝突 | 既存 PR があれば再利用方針を pr-publisher へ追加指示 |
| CodeRabbit 指摘の対応で大量修正が必要 | Phase 3 に差し戻し (reviewer-quality を再起動) |
| push で hook 失敗 (lint/test) | pr-publisher 内で fix → 再 push (破壊的操作はしない) |

### 親が直接 PR を作らない理由

- `pr-publisher` を経由することで `_common.md` のセルフレビュー・報告フォーマットが強制される
- 並列実行 (run_in_background) でメイン context を圧迫しない
- branch 横断のトレーサビリティ (どの PR がどの sub-issue 由来か) を完了通知で集約できる

## 6. ハンドオフ判断

以下のタイミングで `Skill(handoff)` を実行することを推奨する:

- Phase 0 で実装対象が確定したタイミング (issue 本文 / spec/plan の内容を memory に書き出してから先に進む)
- Phase 1 完了直後 (大規模 / 小規模判定が確定したタイミング)
- Phase 2-A の各 developer 完了通知ごと
- Phase 3 のラウンド切り替わりごと
- Phase 3.5 で `Skill(grill-with-docs)` を起動する直前
- Phase 4 完了時

特に Phase 2-A の並列開発中はコンテキスト圧縮警告が出やすいので、複数 sub-issue を並列起動した直後にハンドオフを取る。

## 7. 親が**やってはいけない**こと

- 子エージェントの出力をそのまま次の子に転送する (必ず親が理解・統合してから指示を書く)
- ユーザーへの確認が必要な判断を子に委ねる (子は AskUserQuestion を使えない)
- レビュー指摘を全部 developer に丸投げする (critical / major のみ抽出する)
- worktree を勝手に `wt remove` する (PR マージ後の cleanup は別途 `wt-cleanup` スキル)
- ラウンド上限を勝手に伸ばす (ユーザー承認なしで `review.round_limit` を上書きしない)

### 実装専任化に伴う追加禁止事項

- **要件定義を自分で始めない**。Phase 0 で対象が不在/薄いとき、grill-me / brainstorming 等の対話を肩代わりせず、4 択案内で停止する
- **`Skill(create-issue)` を呼ばない**。Issue 作成は前段の責務。`feature-team` は既に存在する issue または手元の spec/plan を消費するだけ
- **Phase 0 で対象を推測しない**。issue 番号が不明、spec/plan が薄い、状況証拠だけがあるといった状況で「たぶんこれだろう」で進めない。確信が持てなければユーザーに確認する
- **3 条件判定を `reviewer-quality` や親が代行しない**。ADR 化判断は `Skill(grill-with-docs)` に必ず委譲する (詳細は 8. 参照)
- **CONTEXT.md / ADR を勝手に書き換えない**。reviewer-quality からの候補列挙を起点に、用語追記は直接 Edit してよいが、ADR は必ず grill-with-docs を経由する

## 8. CONTEXT.md / ADR 連携

リポジトリに `CONTEXT.md` または `docs/adr/` が存在する場合に限り、実装で生じた用語/決定をそこへ反映する。grill-with-docs と同じ作法に従う (判断基準の二重定義を避けるため、`feature-team` 側では基準を再定義しない)。

### 8.1 役割分担

| 主体 | 責務 |
|------|------|
| `reviewer-quality` | 候補スクリーニング: 新用語・重要決定を Minor / Major 指摘として列挙する。3 条件判定はしない |
| 親 (メイン Claude) | 集約と起動判断: 用語追記は直接 Edit、ADR 化候補はユーザーに 3 択提示して `Skill(grill-with-docs)` を呼ぶ |
| `Skill(grill-with-docs)` | 3 条件 (Hard to reverse / Surprising without context / Real trade-off) の最終判定、ADR の書き出し、CONTEXT.md の正規フォーマット適用 |

### 8.2 判定基準の参照先 (唯一の SSOT)

- `~/.claude/skills/grill-with-docs/SKILL.md` の "Update CONTEXT.md inline" / "Offer ADRs sparingly" セクション
- `~/.claude/skills/grill-with-docs/CONTEXT-FORMAT.md`
- `~/.claude/skills/grill-with-docs/ADR-FORMAT.md`

このスキルの内部に判定基準のコピーを置かない。基準が将来 grill-with-docs 側で改修されたら自動的に追従するため。

### 8.3 親の動き (Phase 3.5)

1. reviewer-quality の候補列挙を読む
2. **CONTEXT.md 追記候補 (Minor)**: 親が直接 Edit で追記。フォーマットは `CONTEXT-FORMAT.md` 準拠。実装コミットと混ぜず別コミット (`docs: add <term> to CONTEXT.md` 等)
3. **ADR 化候補 (Major)**: `AskUserQuestion` で 3 択提示:
   - (i) 今すぐ `Skill(grill-with-docs)` で対話判定
   - (ii) PR を先に出してから別途検討 (Phase 4 に進む、ADR は後日)
   - (iii) ADR 化しない (スキップ)
4. (i) が選ばれたら `Skill(grill-with-docs)` を起動。grill-with-docs が 3 条件をすべて満たすと判定したときのみ ADR を書く (1 つでも欠ければスキップ)

### 8.4 該当ファイルが存在しないリポジトリでの挙動

- reviewer-quality の追加プロンプトを**含めない** (起動コスト削減 + プロンプト膨張回避)
- 親側の Phase 3.5 もスキップ
- 静かに退避する (ユーザーに「CONTEXT.md がありません」と通知しない)

## 9. Phase 0 の対象判定基準

`feature-team` を起動したとき、渡された対象 (issue / spec+plan / ad-hoc spec) が「実装可能な状態か」を判定する。判断のブレを抑えるための基準。

### 9.1 「薄い」判定 — 以下のいずれかに該当

- 受入条件が無い、または 1 行のみで具体性に欠ける
- 変更対象 (ファイル / モジュール / 機能) が不明
- 主要な依存関係・スコープが不明
- 既存コードベースとの接続点が記述されていない (新規機能なのに既存 API の改変有無が不明、等)

該当時は `AskUserQuestion` で「考慮漏れが発生しやすい状態です。要件詰めに戻る / このまま進める」を確認する。

### 9.2 「進められない」判定 — 該当時はエラー停止

- issue 番号が実在しない
- spec/plan のファイルパスが存在しない
- 受入条件が完全に欠落しており、対話で補完しても発散する規模 (= ad-hoc spec ルートに退避できない)

### 9.3 ad-hoc spec 運用 (Phase 0.4 (d) ルート)

対話で受入条件・変更対象・主要依存を聞き取り、親メモリ上に保持して進む。

#### 制約

- 質問は**実装可能になる最小限**のみ (受入条件・対象ファイル・主要依存の 3 点が骨格)
- 設計判断 / 代替案検討 / 前提整理 / ドメイン探求はしない (それは grill-me / brainstorming の責務)
- **質問が 3 つ目を超えそうになったら、ad-hoc 運用を中断して grill-me / brainstorming に案内し直す**
- ad-hoc spec のファイル化はデフォルト無し。ユーザーが「後で振り返れる形にしたい」と希望したときのみ `docs/superpowers/specs/` に書き出す
- ad-hoc spec で実装するときも Phase 3 の reviewer-quality は必須

#### ad-hoc 運用が向くケース

- typo 修正・1 関数の小修正
- 設定値の変更
- alias / function の追加
- テスト 1 件の追加
- lint / format の適用

#### ad-hoc 運用が向かないケース (案内で (a) に戻す)

- 複数ファイル横断
- 設計判断を伴う
- 既存挙動の変更 (破壊的変更の可能性)
- 影響範囲が読めない
