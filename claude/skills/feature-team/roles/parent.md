# Feature Team — Parent Decision Guide

このドキュメントは `feature-team` 親（メイン Claude）が**判断に迷ったときに参照するガイド**です。SKILL.md の各 Phase で「parent.md を参照」と書かれている箇所の根拠です。

子エージェントには注入しません。親自身が読みます。

---

## 1. ボリューム判断しきい値（Phase 3）

### 既定しきい値

| 項目 | 小規模（Phase 4-B 親直実装） | 大規模（Phase 4-A 並列開発） |
|------|----|----|
| sub-issue 数 | ≤ 1 | ≥ 2 |
| 推定変更ファイル数 | ≤ 5 | ≥ 6 |
| 推定変更行数 | ≤ 200 | ≥ 201 |
| 言語/FW の異種混合 | なし（単一スタック） | あり（複数スタック） |

これらは `.claude/feature-team.yml` の `volume_thresholds` で上書きされている場合があるので、設定ファイル値を優先する。

### 判定アルゴリズム

```
1. sub-issue が 1 つ以下 → 小規模
2. sub-issue 間に依存があり、並列化できない（直列必須） → 小規模扱い（または issue-dev に委譲）
3. 複数言語・FW にまたがる → 大規模（特化版 developer の使い分けが効く）
4. 親が現状コードベースを把握している前提で「自分で書いた方が早い」と判断できる
   かつ sub-issue ≤ 1 → 小規模
5. それ以外 → 大規模
```

### 信頼度が低いとき

判定の信頼度が低い場合は、`AskUserQuestion` で**選択肢 2-3 個**を提示してユーザーに委ねる。例:

- (a) 大規模並列で進める（推定 N 並列）
- (b) 小規模単独で親が直接書く
- (c) issue-dev のフェーズ S（直列モード）を使い、サブ issue を順番に処理する

## 2. Developer 選定基準

### 10 種の特化版

| Developer | 想定スタック・領域 |
|-----------|----|
| `developer-react` | React (CRA / Vite / pure React)。状態管理（Redux/Zustand）含む。Next.js 専用機能は含めない |
| `developer-nextjs` | Next.js（App Router / Pages Router）。SSR / RSC / API Routes / middleware |
| `developer-flutter` | Flutter / Dart。iOS/Android のネイティブブリッジ含む |
| `developer-go` | Go。標準ライブラリ・goroutine / channel パターン |
| `developer-nodejs` | Node.js（フレームワークなし、または Express）。CLI ツール・サーバー両対応 |
| `developer-hono` | Hono フレームワーク。Cloudflare Workers / Bun / Deno デプロイターゲット |
| `developer-nestjs` | NestJS。依存注入・モジュール設計・TypeORM/Prisma 統合 |
| `developer-rust` | Rust。所有権・ライフタイム・async（tokio） |
| `developer-ruby` | Ruby / Rails。ActiveRecord・migration・rspec |
| `developer-generic` | 上記いずれにも該当しない場合のフォールバック |

### 選定アルゴリズム

```
1. sub-issue の本文・タグ・対象ファイル拡張子から主要スタックを推定
2. 上記表に該当があれば特化版を選ぶ
3. 該当なし → developer-generic
4. 複数該当（例: Next.js + Hono の monorepo の sub-issue）
   → 主要な変更領域で判断。判定困難なら親が分割を検討（sub-issue を分けて create-issue にやり直し依頼）
```

### 中間層（frontend / backend 汎用）を作らない理由

- 中間層は特化版より弱く、generic より中途半端
- 選定ロジックが「特化 → 中間 → generic」と 3 段階になり複雑化
- 特化版が育てば育つほど中間層は不要化する
- 該当がなければ generic で十分（汎用エージェントは元々強い）

## 3. Reviewer 観点選定基準

### 3 観点固定

| Reviewer | 主に見る観点 |
|----------|----|
| `reviewer-security` | OWASP Top 10、認証・認可、入力バリデーション、秘密情報の取扱い、依存ライブラリの既知脆弱性、SSRF/XSS/SQL/コマンドインジェクションリスク |
| `reviewer-performance` | ホットパス（リクエスト処理、ループ内処理）、N+1 クエリ、不要な再計算、メモリリーク、大量データ処理のスケーラビリティ、I/O ブロッキング |
| `reviewer-quality` | バグ・機能的正確性、可読性、命名、抽象化の整合、DRY、テストカバレッジ、コメント品質、エラーハンドリングの妥当性、規約遵守 |

### 起動判定

`.claude/feature-team.yml` の `default_reviewers` を起点に、各 sub-issue / branch ごとに以下を加味して観点を決める:

#### `reviewer-security` を**追加で起動する**条件

- ユーザー入力を受ける処理（API endpoint, form, CLI 引数, file upload）
- 認証・セッション・トークン管理
- 外部システムへの認証情報送信
- `eval` / 動的コード実行 / 動的 SQL 構築
- 秘密情報（API キー、パスワード、PII）の保存・送信
- 暗号化・ハッシュ・乱数生成
- 依存追加（`package.json` / `Cargo.toml` / `go.mod` 等の更新）

#### `reviewer-performance` を**追加で起動する**条件

- DB クエリの追加・変更（特にループ内）
- バッチ処理・大量レコード処理
- フロントエンドの再レンダリング負荷増加リスク
- ファイル I/O・ネットワーク呼出の増加
- キャッシュ層の変更
- アルゴリズム変更

#### `reviewer-quality` は**常に必須**

- 既定で全 sub-issue / branch に起動する
- どの sub-issue でも起動コストは小さく、抜け漏れ検出に有効

### 観点の数を増やしすぎない

- 不要な観点を起動するとレビューラウンド消費が早まり、3 ラウンド上限に到達しやすい
- 「念のため」で security/performance を起動しない。必要性の根拠を持つこと

## 4. Phase 5 ラウンド超過時の介入手順

3 ラウンド消化しても収束しない場合の親の動き:

### 4.1 まず親が差分を読む

- 子経由ではなく **親自身が `git diff` で差分を読む**
- 並行して reviewer の指摘履歴（Round 1〜3）を時系列で並べる

### 4.2 原因を分類

| 分類 | 兆候 | 対応 |
|------|------|------|
| 設計レベルの問題 | 「アーキ修正が必要」「責務分離が破綻」「他 sub-issue とインタフェース矛盾」 | ユーザーに escalate |
| 実装の取り違え | 「指摘がはっきりしているのに直し方がズレ続ける」 | 親が直接修正 |
| 指摘の妥当性自体が疑わしい | 「reviewer の指摘が間違っている／古い指摘を引きずっている」 | 親が指摘を却下し、developer に「現在の状態で完了」を通知 |
| テスト不足で判定不能 | 「正しさをテストで担保できていない」 | テスト追加を 1 ラウンド分追加発注（例外的にラウンド+1） |

### 4.3 ユーザー escalate のフォーマット

```
## ⚠️ Phase 5 ラウンド上限到達 — 判断要請

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
1. 設計やり直し（Phase 1 に戻る）— 推奨理由: ...
2. このまま PR を作り、レビューを後続 PR で対応
3. この sub-issue を中断（他 sub-issue は継続）
```

## 5. Phase 6 — pr-publisher 起動

### 起動単位

- 1 branch につき 1 体の `pr-publisher` を起動する
- 複数 branch がある場合は **`run_in_background=true` で並列起動** する（PR 作成は branch 間で独立）
- 親は起動後すぐに次の処理に進まず、TaskList でバックグラウンド完了通知を受け取る

### プロンプトに必ず含める項目

`pr-publisher` のプロンプトには以下 8 項目を含めること（不足すると CodeRabbit 対応や Issue リンクで詰まる）:

1. `roles/_common.md` の本文（または `Read("/Users/.../roles/_common.md")` の指示）
2. リポジトリ情報（owner/repo）
3. worktree 絶対パス
4. branch 名
5. 紐付ける Issue 番号
6. spec / plan ファイルへの絶対パス（PR 本文への引用元）
7. Phase 5 の review summary（critical/major のみ）
8. 期待アクション: コミット整理 → push → `gh pr create` → `Skill(coderabbit-review)` 起動

### 失敗パターンと対応

| 兆候 | 対応 |
|------|------|
| `gh pr create` が既存 PR と衝突 | 既存 PR があれば再利用方針を pr-publisher へ追加指示 |
| CodeRabbit 指摘の対応で大量修正が必要 | Phase 5 に差し戻し（reviewer-quality を再起動） |
| push で hook 失敗（lint/test） | pr-publisher 内で fix → 再 push（破壊的操作はしない） |

### 親が直接 PR を作らない理由

- `pr-publisher` を経由することで `_common.md` のセルフレビュー・報告フォーマットが強制される
- 並列実行（run_in_background）でメイン context を圧迫しない
- branch 横断のトレーサビリティ（どの PR がどの sub-issue 由来か）を完了通知で集約できる

## 6. ハンドオフ判断

以下のタイミングで `Skill(handover)` を実行することを推奨する:

- Phase 1 完了直後（design doc が固まったタイミング）
- Phase 2 完了直後（issue 番号が確定したタイミング）
- Phase 4-A の各 developer 完了通知ごと
- Phase 5 のラウンド切り替わりごと
- Phase 6 完了時

特に Phase 4 の並列開発中はコンテキスト圧縮警告が出やすいので、複数 sub-issue を並列起動した直後にハンドオフを取る。

## 7. 親が**やってはいけない**こと

- 子エージェントの出力をそのまま次の子に転送する（必ず親が理解・統合してから指示を書く）
- ユーザーへの確認が必要な判断を子に委ねる（子は AskUserQuestion を使えない）
- レビュー指摘を全部 developer に丸投げする（critical / major のみ抽出する）
- 設定ファイル `.claude/feature-team.yml` を勝手に commit する（書き出しまで、コミットはユーザー判断）
- worktree を勝手に `wt remove` する（PR マージ後の cleanup は別途 `wt-cleanup` スキル）
- ラウンド上限を勝手に伸ばす（ユーザー承認なしで `review_round_limit` を上書きしない）
