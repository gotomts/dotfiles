# Linear + GitHub Projects 連携ワークフロー設計

## 概要

Linear を企画・設計層、GitHub Projects を実行層として活用する二層タスク管理ワークフローを Claude Code のスキルで実現する。対象リポジトリは `gotomts/socialcoffeenote`。

## 背景

- GitHub Project（SocialCoffeeNote Project #4）で509件のアイテムを管理中
- ステータスフロー: ToDo → Backlog → Ready → In Progress → Review → Release QA → Close
- 現状 Issue の body がほぼ空で、タイトルのみの運用になっている
- Linear を導入し、アイデアの構造化・階層管理・依存関係管理を行い、整理された内容を GitHub Issue に反映させたい

## 全体アーキテクチャ

```
┌─────────────────────────────────────────────────────────┐
│                    企画フェーズ (Linear)                   │
│                                                         │
│  アイデア → /linear-plan → Linear Issue 詳細化            │
│  ・タイトル・説明・受入条件・優先度                          │
│  ・Sub-issue 分割                                        │
│  ・依存関係（blocks / blocked by）                        │
└───────────────────────┬─────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│                 同期フェーズ (Linear → GitHub)             │
│                                                         │
│  /issue-sync SCN-42 → GitHub Issue 生成                  │
│  ・Linear の内容を GitHub Issue body に反映               │
│  ・GitHub Project に自動登録（Status: Ready）              │
│  ・Linear Issue に GitHub Issue URL を逆リンク            │
└───────────────────────┬─────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│               開発フェーズ (GitHub)                       │
│                                                         │
│  /issue-dev #748 → フルサイクル実行                       │
│  ① GitHub Issue 読み込み                                 │
│  ② ブランチ作成（feature/xxx-issue-748）                  │
│  ③ Project Status → In Progress                         │
│  ④ 開発・コミット                                        │
│  ⑤ PR 作成（Resolves #748）                              │
│  ⑥ Project Status → Review                              │
└─────────────────────────────────────────────────────────┘
```

## 前提条件

- Linear アカウントが作成済みであること
- Linear 上にチーム（例: チーム識別子 `SCN`）とプロジェクトが作成済みであること
- `linear` CLI で認証済みであること（`linear auth`）
- Issue ID のプレフィックス（`SCN-42` の `SCN` 部分）は Linear のチーム識別子に由来する

## インフラストラクチャ

### 追加するもの

| 対象 | 変更内容 |
|---|---|
| `Brewfile` | `tap 'schpet/tap'` + `brew 'schpet/tap/linear'` を追加 |
| `claude/settings.json` | `linear-cli@linear-cli` プラグインを有効化 |
| `claude/settings.json` | `Bash(linear:*)` を permissions.allow に追加 |

### 追加しないもの

| 対象 | 理由 |
|---|---|
| Linear の GitHub ネイティブ連携 | Claude Code スキルで制御するため二重同期になる |
| シェルエイリアス | スキル経由で操作するため不要 |

## スキル設計

### linear-plan — 企画構造化スキル

**配置:** `claude/skills/linear-plan/SKILL.md`

**目的:** 曖昧なアイデアや要望を Linear Issue として構造化する。

**引数:** アイデアの自由記述テキスト（省略時は対話的に聞き取り）

**処理フロー:**

1. **コンテキスト収集** — socialcoffeenote の既存 Linear Issue を `linear issue list` で検索し重複チェック。関連する既存 Issue があれば提示
2. **対話的な詳細化** — Claude Code がユーザーに質問して以下を明確化:
   - 目的・背景
   - 受入条件（完了の定義）
   - 影響範囲
3. **構造化提案** — 以下を整理してユーザーに提示:
   - タイトル、説明文、優先度、ラベル
   - サブタスク分割案（1サブタスク = 1 GitHub Issue = 1 PR を基準）
   - 他 Issue との依存関係（blocks / blocked by）
4. **ユーザー承認** — 提案内容を確認してもらう
5. **Linear に登録** — `linear issue create` で親 Issue + Sub-issue を作成し、依存関係を設定

**制約:**
- ステップ4のユーザー承認なしに Linear への登録を行わない
- サブタスク分割の粒度は「1つの GitHub Issue = 1つの PR」を基準とする

### issue-sync — Linear → GitHub 同期スキル

**配置:** `claude/skills/issue-sync/SKILL.md`

**目的:** Linear Issue の内容を GitHub Issue に変換し、GitHub Project に登録する。

**引数:** Linear Issue ID（複数指定可）

**処理フロー:**

1. **Linear Issue 読み込み** — `linear issue show` でタイトル、説明、受入条件、優先度、ラベル、Sub-issue 一覧、依存関係を取得
2. **GitHub Issue body 生成** — 以下のフォーマットで構築:
   ```markdown
   ## 概要
   （Linear の説明文）

   ## 受入条件
   - [ ] 条件1
   - [ ] 条件2

   ## 関連
   - Linear: SCN-42
   - Blocked by: #745
   ```
3. **ユーザー承認** — 生成内容を提示して確認
4. **GitHub Issue 作成** — `gh issue create --repo gotomts/socialcoffeenote` で登録。ラベル付与
5. **GitHub Project に追加** — `gh project item-add` でプロジェクト #4 に登録し、Status を「Ready」に設定
6. **Linear に逆リンク** — Linear Issue のコメントに GitHub Issue URL を記録
7. **Sub-issue 処理** — Sub-issue がある場合、再帰的に GitHub Issue 化し、Parent issue フィールドを設定

**制約:**
- 既に同期済みの Issue を二重作成しない（Linear コメントに GitHub URL があればスキップ）
- 依存関係（blocks）は GitHub Issue body 内のテキストリンクで表現（GitHub Projects にネイティブの blocks 機能がないため）

### issue-dev — フルサイクル開発スキル

**配置:** `claude/skills/issue-dev/SKILL.md`

**目的:** GitHub Issue を起点に、ブランチ作成から PR 作成・ステータス更新までを実行する。

**引数:** GitHub Issue 番号。オプション `--type hotfix|feature|refactor` でブランチプレフィックスを指定

**処理フロー:**

1. **Issue 読み込み + コンテキスト構築** — `gh issue view` で内容取得。受入条件、関連 Issue、ラベルを把握。ラベルからブランチタイプを推定（`bug` → `hotfix/`、それ以外 → `feature/`）
2. **ブランチ作成** — 命名規則: `{type}/{slug}-issue-{number}`（例: `feature/coffee-equipment-category-issue-748`）
3. **GitHub Project ステータス更新** — Status を「In Progress」に変更
4. **--- ここでスキルを終了し、通常の開発に移行 ---** — Issue の受入条件を Claude Code のコンテキストとして出力し、開発の指針を示す。開発作業自体はスキルのスコープ外
5. **PR 作成（開発完了後にユーザーが再度スキルを起動、または手動で実行）** — Conventional Commits 形式のタイトル。Body は `## Issue\nResolves #{number}` を含む。`gh pr create` で作成
6. **ステータス更新** — GitHub Project Status を「Review」に変更

**ブランチタイプ推定ルール:**
- `--type` 指定あり → そのまま使用
- Issue ラベルに `bug` → `hotfix/`
- Issue ラベルに `refactor` → `refactor/`
- それ以外 → `feature/`

**制約:**
- 開発作業（ステップ4）自体の実行はスキルのスコープ外。スキルは「開発の前後の儀式」を自動化する
- PR の body フォーマットは既存の規約（`## Issue\nResolves #N`）を踏襲する

## GitHub Project 操作の技術詳細

### ステータス更新コマンド

GitHub Project のステータス更新には以下の情報が必要:

- Project ID: `PVT_kwHOAxAVd84ACA3Q`
- Status フィールド ID: `PVTSSF_lAHOAxAVd84ACA3QzgBKlac`
- 各ステータスの Option ID:
  - ToDo: `bc2f97c0`
  - Backlog: `146068ae`
  - Ready: `a3fe5591`
  - In Progress: `47fc9ee4`
  - Review: `52fe9807`
  - Release QA: `35ba55ee`
  - Close: `98236657`

更新は `gh project item-edit` コマンドで実行する。

## 対象リポジトリ

- リポジトリ: `gotomts/socialcoffeenote`
- GitHub Project: `https://github.com/users/gotomts/projects/4`（Project #4）
- 既存のブランチ命名規則: `{type}/{description}-issue-{number}`
- 既存の PR 規約: Conventional Commits タイトル + `## Issue\nResolves #N` body
- CodeRabbit によるレビュー自動化が導入済み

## スキルの独立性

3つのスキルは疎結合に設計されている:

- `linear-plan` のみ単独で使用可能（Linear だけで企画整理）
- `issue-sync` は `linear-plan` なしでも手動作成した Linear Issue に対して使用可能
- `issue-dev` は `issue-sync` なしでも手動作成した GitHub Issue に対して使用可能
- 3つをパイプラインとして連結して使用することも可能
