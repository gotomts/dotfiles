# ワイヤーフレーム作成のワークフロー

UI が重要なサービスの場合、ワイヤーフレームを HTML プロトタイプとして作って保存先に紐付けられる。
保存先のモードによって添付方法が変わる:

- **Obsidian モード**: HTML / zip を vault 内の所定フォルダに配置して、ワイヤーフレームノートから相対パスでリンクする
- **Notion 退避モード**: zip をワイヤーフレームノートに添付する（手動アップロード）

ただしこれは**オプション**。ユーザーが UI 設計をしたいと言ってから着手する。

## いつ作るか

- ユーザーが「UI も考えたい」「画面イメージを作りたい」と言ったとき
- 機能スコープが固まって、具体的な画面を議論する段階
- ステークホルダーや投資家に見せる必要がある場合

## いつ作らないか

- 設計フェーズの初期（憲章・ペルソナを固める段階）
- API / バックエンドサービスで UI が薄いとき
- ユーザーが「UI は後でいい」と言っているとき

## 作り方の流れ

### Step 1: 画面リストの整理

まず、どんな画面が必要か対話で洗い出す。例（anttt の場合）:

- ホーム画面（モバイル / PC）
- 記事詳細（モバイル / PC）
- ソース一覧（モバイル / PC）
- ブックマーク（モバイル / PC）
- 各種モーダル（4 分岐モーダル、追加トークン購入など）
- Chrome 拡張機能オーバーレイ

「Phase 1 で実際にユーザーが触る画面」をリストアップする。

### Step 2: 1 画面ずつ visualize ツールで作る

`visualize:read_me` で必要なモジュールを読み込んでから、`visualize:show_widget` で 1 画面ずつ作る。

ポイント:
- モバイルは width 375px、PC は max-width 1200px くらい
- ユーザーの反応を見ながら反復改善
- 「次のソースに行く方法は?」のような細かい点も丁寧に確認
- 一度に複数画面を作らず、1 画面ごとに合意を取る

### Step 3: 設計判断の記録

各画面で出てきた設計判断は記録する。例:

- 「サムネはオプショナル（全画面で同じルール）」
- 「メタ情報はタイトル上に配置」
- 「日付は YYYY/MM/DD 形式」

これらは後で CLAUDE.md やワイヤーフレームノートに残す。

### Step 4: HTML ファイル化

完成したワイヤーフレームを HTML ファイルにまとめる:

1. 各画面を個別の HTML ファイルに整形
2. 目次ページ (`index.html`) を作る（カード形式の一覧）
3. 個別 HTML には:
   - 戻るリンク
   - 画面カテゴリ
   - 画面タイトル
   - 説明文
   - 設計判断の折りたたみリスト
   - ワイヤーフレーム本体

### Step 5: zip 化して提供

`zipfile` モジュールで zip 圧縮。圧縮率 9 で。

```python
import zipfile
import os

zip_path = '/mnt/user-data/outputs/<service-name>-wireframes.zip'
with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
    for filename in sorted(os.listdir(out_dir)):
        full = os.path.join(out_dir, filename)
        zf.write(full, arcname=f'<service-name>-wireframes/{filename}')
```

`present_files` で zip を提示する。

### Step 6: 保存先にノートとして記録

「27. ワイヤーフレーム」のようなノートを作り、以下を記録する。

**Obsidian モード**:

- vault 内に `<ルートフォルダ>/wireframes/` のような専用フォルダを作って、unzip 後の `index.html` と個別 HTML を配置する
- ノート本文からは相対パスで `[index.html](wireframes/<service-name>-wireframes/index.html)` のように参照する
- zip 自体も `wireframes/<service-name>-wireframes.zip` で残しておくと配布しやすい

**Notion 退避モード**:

- ノート本文に zip を添付する（Notion 上でユーザーが手動でアップロード）

どちらのモードでも、ノート本文には以下を記録する:

- 画面一覧（採用状況の表）
- 主要な設計判断
- モバイル / PC の対応関係
- 未着手の画面
- 更新ルール

## HTML ファイルの構造（参考）

各画面の個別 HTML は以下の構造:

```html
<!DOCTYPE html>
<html lang="ja">
<head>
  <title>{画面タイトル} | {サービス名} ワイヤーフレーム</title>
  <!-- 共通 CSS / フォント / アイコンライブラリ -->
</head>
<body>
  <div class="page-header">
    <a class="back-link" href="index.html">← 一覧へ戻る</a>
    <div class="screen-category">{カテゴリ}</div>
    <h1 class="screen-title">{画面タイトル}</h1>
    <p class="screen-description">{説明}</p>
    <details class="screen-decisions">
      <summary>設計判断 ({N} 件)</summary>
      <ul>
        <li>{判断1}</li>
        ...
      </ul>
    </details>
  </div>
  <div class="screen-preview">
    {ワイヤーフレーム本体（visualize ツールで作った HTML）}
  </div>
</body>
</html>
```

目次ページ (`index.html`) は:

- サービス名 + ワイヤーフレーム一覧のタイトル
- カテゴリ別にグループ化
- 各画面をカード形式で表示（番号 + タイトル + 説明の冒頭）
- カードクリックで個別ページへ

## CSS 変数（共通）

visualize ツールが使う設計トークンを引き継ぐ:

```css
:root {
  --color-background-primary: #ffffff;
  --color-background-secondary: #f7f7f5;
  --color-background-tertiary: #efefec;
  --color-text-primary: #1a1a1a;
  --color-text-secondary: #6b6b6b;
  --color-text-tertiary: #8e8e8e;
  --color-border-primary: #d0d0d0;
  --color-border-secondary: #e0e0e0;
  --color-border-tertiary: #e8e8e6;
  --color-accent-primary: #c45c2e;
  --border-radius-sm: 4px;
  --border-radius-md: 6px;
  --border-radius-lg: 10px;
  --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.04);
  --shadow-md: 0 4px 12px rgba(0, 0, 0, 0.08);
  --shadow-lg: 0 8px 24px rgba(0, 0, 0, 0.12);
}
```

アイコンは Tabler Icons の CDN を使う:

```html
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@tabler/icons-webfont@latest/dist/tabler-icons.min.css">
```

フォントは Noto Sans JP:

```html
<link href="https://fonts.googleapis.com/css2?family=Noto+Sans+JP:wght@400;500;600;700&display=swap" rel="stylesheet">
```

## anttt のワイヤーフレーム実例

anttt では 12 画面を 47KB の zip にまとめた。中身:

- `index.html` (目次)
- `01_home_mobile.html` 〜 `12_overlay_pattern.html` (12 画面)

参考までに、構成と画面数:

- **メイン画面** (6): ホーム × 2、記事詳細 × 2、ソース一覧 × 2
- **ユーザー画面** (2): ブックマーク × 2
- **機能 UI** (2): 4 分岐モーダル、追加トークン購入
- **Chrome 拡張機能** (2): オーバーレイ 4 状態、パターン比較

## 注意点

- **完璧を目指さない**: 基本パターン（ヘッダー、カードリスト、ナビ）の組み合わせで実装時に作れるなら、ワイヤーフレームに労力をかけすぎない
- **重要な分岐 UI を優先**: 複雑な遷移、複数モーダル、状態変化などを優先して作る
- **アカウント画面・サインインなどは後回し可**: 一般的な画面は実装時に作れる
- **モバイル / PC の両方が必要かは判断**: API サービスなら PC のみで十分
