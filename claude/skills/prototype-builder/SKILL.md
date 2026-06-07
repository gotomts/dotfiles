---
name: prototype-builder
description: prototype-designer のデザイン設計を入力に、HTML プロトタイプを生成・整理して GitHub に push する、サービス開発ワークフローのフェーズ 3（プロトタイプ生成専任）スキル。実行環境は Claude Code。技術は HTML + Tailwind CSS（CDN）+ Alpine.js、ビルドツールなし、ブラウザで開くだけで動く。「触れる仕様書」として状態遷移・エッジケースまで含むが、本実装には流用しない（捨てる前提）。ユーザーが「プロトタイプを作りたい」「HTML を生成したい」「画面を動く形にしたい」「ai-prototypes に上げたい」と言ったとき、あるいはデザイン設計が固まってプロトタイプ化の話を始めたときは、このスキルを使うべきかどうかを必ず検討する。
maintainer: gotomts
---

# prototype-builder

サービス開発ワークフロー（6 スキル）の 3 番目に位置する **プロトタイプ生成専任** スキル。prototype-designer のデザイン設計（`02-prototype-designer/` 配下の 5 成果物）を入力に、HTML プロトタイプを生成・整理して GitHub（`gotomts/ai-prototypes/{service}/`）に push する。実行環境は **Claude Code**（ファイル生成・整理・長時間自律が中心のため）。

## このスキルの役割（全体の中での位置）

サービス開発は次の 6 スキルで進む。本スキルはその 3 番目:

1. service-designer（企画 / Claude Chat）
2. prototype-designer（デザイン設計 / Claude Chat）
3. **prototype-builder**（プロトタイプ生成 / Claude Code）← このスキル
4. tech-designer（技術設計 / Claude Chat）
5. issue-decomposer（分解 / Claude Chat）
6. feature-team（実装 / Claude Code）

- 入力：prototype-designer の `02-prototype-designer/`（特に screen-specs/・design-concept.md・screens.md）＋ **提供形態（PRFAQ〔03〕冒頭）**。
- 出力：GitHub `gotomts/ai-prototypes/{service}/` の HTML 一式 ＋ vault `03-prototype-builder/README.md`（メタ台帳）。
- 下流：tech-designer（Claude Chat）が、企画・デザイン・プロトタイプ実体を参照して本実装の技術設計に進む。
- **「触れる仕様書」**として状態遷移・エッジケースまで動かす。ただし**本実装には流用しない（捨てる前提）**。

## いつ使うか

- デザイン設計（prototype-designer）が固まり、動くプロトタイプにする段階に入ったとき
- ユーザーが「プロトタイプを作りたい」「HTML を生成したい」「画面を動く形にしたい」「ai-prototypes に上げたい」と言ったとき
- デザインの話からプロトタイプ化・実装の話に移ったとき（明示的に言っていなくても提案する）

## 技術スタックと方針

- **HTML + Tailwind CSS（CDN）+ Alpine.js（CDN）**。ビルドツールなし。ブラウザで開くだけで動く。
- **1 画面 1 HTML**：screen-spec 1 ファイル → `.html` 1 つに対応。画面間の移動は `<a href>` のファイル遷移、画面内の状態遷移は Alpine で切り替える。
- **捨てる前提**：本実装には流用しない。CDN 前提（オフライン動作要件は課さない）。design-concept の hex 等の例示値を作業用トークンとして固定する（確定は tech-designer／本実装）。

## ディレクトリ構成（出力先）

GitHub `gotomts/ai-prototypes/{service}/` 配下は、HTML を直下にフラットで並べ、共通アセットを `assets/` にまとめる（アセット分離）:

```
ai-prototypes/{service}/
  index.html        # 入口＝画面一覧（ナビゲーションハブ）
  {screen}.html     # 各画面（1 画面 1 HTML・直下フラット）
  assets/
    theme.js        # Tailwind config（色・フォント等トークン）
    styles.css      # Web フォント読込・CSS 変数・base・デバイスフレーム CSS
    mock.js         # 共通モックデータ
```

HTML を全て同階層に置くことで `<a href>` の相対パスがフラット（`home.html`）で安定する。各画面は `assets/theme.js` 等を一定の相対パスで参照する。

## 各画面 HTML の作り方

### `<head>` の定型ボイラープレート

各 HTML の `<head>` は共通土台を参照する定型にする（Claude Code が定型生成）:

- Tailwind CDN を読み込む → 直後に `assets/theme.js`（`tailwind.config = {…}` で色・フォントを設定。**順序依存：CDN script の後に theme.js**）
- `assets/styles.css` を `<link>` で読む（Web フォント・CSS 変数・base・デバイスフレーム CSS）
- Alpine.js CDN を読む
- body 末尾で `assets/mock.js` を読む

### screen-spec → HTML の写し方

- **レイアウト構成** → Tailwind クラスでの構造
- **状態と遷移** → Alpine の `x-data`（状態）＋ `x-show`・`x-if`（出し分け）
- **エッジケース** → 追加の状態分岐
- **含む機能・目的** → 操作要素とダミーデータ参照（`mock.js` を `x-data` から参照）
- 画面間遷移は screens.md の導線に従い `<a href>` でファイル遷移

### 状態の実装（Alpine.js に統一）

画面内の状態（バリデーション・ローディング・エラー・モーダル等）を `x-data` に持ち、`x-show`／`x-if` で宣言的に出し分ける。**全画面で Alpine に統一**する（素の JS と混在させない＝生成パターンを一定にして自律生成を安定させる）。

### モックデータ（共通 mock.js）

共通モックモジュール `assets/mock.js` を各画面 HTML が `<script src>` で読み込み、グローバルに乗ったダミーデータを Alpine の `x-data` から参照する。`<script>` 読み込みは `file://` 直開きでも CORS 制限を受けないため「開くだけで動く」を満たす。複数画面に同じエンティティが出ても 1 箇所のデータを共有し、画面間の一貫性を保つ（JSON+fetch は file:// でブロックされるため不採用）。

### 視覚トークン（共通スタイル土台）

デザイントークン（色・フォント等）を共有ファイルに集約する。`theme.js`（Tailwind config）＋ `styles.css`（Web フォント・CSS 変数・base）。1 画面 1 HTML でも視覚トークンの真実源は 1 つに保つ（design-concept の価値＝画面間の視覚的一貫性のため）。デザインが変われば 1 箇所直せば全画面に効く。

### 提供形態別のデバイスフレーム

提供形態に応じた共有デバイスフレーム（枠）を用意し、各画面 content をその枠に流し込む（モバイル→電話幅カラム＋簡易ステータスバー等／デスクトップ→ウィンドウ風枠／Web→実質フル幅）。

- 枠の CSS は `assets/styles.css`。ラッパー markup は build なしでは共有ファイル化できないため、各 HTML の body が定型のラッパー div で content を包む（Claude Code が定型生成）。
- **提供形態は PRFAQ〔03〕冒頭の「提供形態」から直接読む**（提供形態の真実源は service-designer の PRFAQ。複製を避けて直接参照）。
- モバイル単一形態なら枠は薄くてよい（過剰実装しない）。

### 生成順

共通アセット（theme.js／styles.css／mock.js）を先に用意 → 1 画面ずつ HTML 化 → 最後に入口の `index.html`（画面一覧＝ナビゲーションハブ）。

## push 方法

**GitHub MCP 経由**。自作 github-mcp の `push_files`（複数ファイル 1 コミット）で `gotomts/ai-prototypes/{service}/` に push する。更新・再生成時は `list_files`／`get_file` で既存を確認し `push_files` で上書きする。

- プロトタイプはビルド不要のテキスト群で git の高機能（ブランチ/PR）は不要。
- **フォールバック**：`push_files` が承認まわりで落ちる場合は git コマンド（clone→add/commit/push）に切り替える。

## vault メタ台帳（`03-prototype-builder/README.md`）

vault 側に「何が・どの spec から生成されたか」を一覧できるメタ台帳を置く。ビルドのたびに Claude Code が再生成して同期する。

書式:

- frontmatter：`title`（{service} / プロトタイプ）／`updated`／`status`（生成済み / 再生成待ち 等）
- `# {service} プロトタイプ` ＋ 一行説明（vault 側の参照台帳・実体は GitHub）
- **実体（真実源＝GitHub）**：リポジトリ `gotomts/ai-prototypes/{service}/`／入口 index.html（file:// 直開き）／最終生成日（commit）
- **入力（根拠）**：デザイン設計 `02-prototype-designer/`（design-concept の版・日付）／提供形態（PRFAQ〔03〕由来）
- **画面一覧（screen-specs との対応）**：表〔画面 | HTML | 由来 screen-spec〕
- **見方**：index.html → `<a href>` 遷移、画面内は Alpine
- **次のスキル**：tech-designer

## 共通要件

### 1. 入出力契約

- **入力：** 主入力は `02-prototype-designer/` 配下のうち **screen-specs/**（HTML 化の主入力）・**design-concept.md**（視覚トークン→theme.js／styles.css）・**screens.md**（画面一覧＝`<a href>` 導線の根拠）。moodboard.md は参考、sketches/ は任意（必須入力にしない）。**加えて提供形態を PRFAQ〔03〕冒頭の「提供形態」から直接読む**（真実源は service-designer の PRFAQ）。
- **出力：** GitHub `gotomts/ai-prototypes/{service}/`（`index.html`＋各画面 `.html`＋`assets/{theme.js,styles.css,mock.js}`）＋ vault `03-prototype-builder/README.md`（メタ台帳）。

### 2. 読み方の地図

- 前段は prototype-designer。優先して読むのは screen-specs/・design-concept.md・screens.md。moodboard は必要時、sketches は任意。
- **提供形態（PRFAQ〔03〕冒頭）はデバイスフレーム選択に必須。** 提供形態が無い／service-designer が未完了なら、企画（service-designer）へ差し戻す。
- 生成順：共通アセット（theme.js／styles.css／mock.js）を先に → 1 画面ずつ HTML 化 → 最後に index.html。

### 3. 完了時の次スキル案内（ハイブリッド完了判定）

screens.md の全画面に対応する HTML が生成され、各 screen-spec が HTML 化され、GitHub に push 済み、vault README（メタ台帳）が生成された、を検知したら、(a) サマリと (b) 未生成の画面／未反映の spec を提示して一拍確認する。ユーザー合意で次スキル案内を出す。**screens.md の画面一覧（機能カバレッジ）を完了条件に連動**させる。検知はスキルが能動的に、進む決定はユーザーに委ねる。

案内の文言（実行環境も添える）:

> プロトタイプができました。次は tech-designer（Claude Chat）で本実装の技術設計に進みましょう。

### 4. 運用知見（運用しながら追記する）

最初は空でよい。運用しながら動的に知見を追記する場。

```markdown
## 運用知見（運用しながら追記する）

### 判断に迷ったときの参照優先度
（運用しながら書き加える）

### 過去のはまりどころ
（運用しながら書き加える）

### Alpine／Tailwind 実装で迷った例
（運用しながら書き加える）

### file:// で動かないときの対処（CORS／相対パス）
（運用しながら書き加える）

### デバイスフレーム・提供形態別レイアウトの勘所
（運用しながら書き加える）
```

## 重要な原則

- **プロトタイプ生成専任**：本実装には踏み込まない。生成物は捨てる前提（CDN・ビルドなし・例示トークン固定）。確定仕様は tech-designer／本実装。
- **生成パターンを一定に**：`<head>` ボイラープレート・Alpine 統一・共通アセット参照を定型化し、Claude Code の自律生成を安定させる。
- **真実源を 1 つに**：視覚トークンは theme.js／styles.css、モックデータは mock.js、提供形態は PRFAQ〔03〕。複製せず参照する。
- **提供形態が未定なら差し戻す**：デバイスフレーム選択の前提が欠けたまま生成しない。
- **vault メタ台帳は GitHub 実体への参照**：真実源は GitHub の HTML 実体、vault README は台帳（再生成で同期）。
