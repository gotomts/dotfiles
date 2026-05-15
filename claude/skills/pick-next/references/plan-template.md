# plan-template

`pick-next` の Step 6B で `docs/superpowers/plans/<date>-<slug>.md` に書き出す軽量 plan のテンプレ。

## ファイル名規則

- 日付・slug は spec と同じ（spec-template.md 参照）
- 拡張子: `.md`（`-design` は付けない）

例: `docs/superpowers/plans/2026-05-14-auth-rate-limit-improve.md`

## テンプレ全文

````markdown
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
````

## sub-issue が 1 件のときのテンプレ

`decomposition-guide.md` の通り、sub-issue が 1 件しか出ない場合は以下のように 1 ステップだけ書く。

````markdown
# <タイトル> - 実装プラン

## ステップ概要

1. <作業全体> （Xd）

## ステップ詳細

### Step 1: <作業全体>

**変更対象**:
- <該当ファイル>

**受入条件**:
- [ ] <親 Issue の受入条件と同じで OK>
- [ ] テストが追加されている

**依存**: なし
````

## sub-issue が 0 件（親 Issue だけ）のときのテンプレ

コスト「小」のテーマでは sub-issue ゼロ。plan は省略してもよいが、`create-issue` のセルフレビューを通すため最小限の plan を書き出す。

````markdown
# <タイトル> - 実装プラン

## ステップ概要

1. <作業全体> （Xd）

このテーマは sub-issue 分割なしで親 Issue 1 本で扱う。

## ステップ詳細

### Step 1: <作業全体>

**変更対象**:
- <該当ファイル>

**受入条件**:
- [ ] <親 Issue の受入条件と同じ>

**依存**: なし
````

## フィールドの意味

- **ステップ概要**: 番号付きリスト。`create-issue` が親 Issue 本文の「## サブタスク」に転載する
- **Step N の変更対象**: `create-issue` が sub-issue 本文の「## 変更対象」に転載
- **Step N の受入条件**: sub-issue 本文の「## 受入条件」に転載
- **Step N の依存**: `create-issue` が `blocks` / `blocked by` として登録
- **検証手順 / ロールバック方針**: あれば親 Issue 本文末尾に追記
