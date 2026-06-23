---
name: wt-start
maintainer: gotomts
description: 自由テキスト・Linear issue ID・GitHub issue/PR URL のいずれかから branch 名を提案し、ユーザー承認後に `wt switch --create` で worktree とブランチを同時に作成する。引数が無ければ対話で受け取る。「worktree 切って」「ブランチ作って」「wt で始めて」「issue を worktree で開始」「DOT-xx / ABC-xx で作業開始」など並行作業や worktree 起点の作業開始を示唆する文脈で必ず使う。単独タスクでブランチ切るだけなら使わない (main 直作業を尊重)。
argument-hint: "[<linear-id> | <github-url> | <free-text>]  # 引数なしの場合は対話で受け取る"
allowed-tools:
  - Bash
  - Read
---

# wt-start

worktree + ブランチを 1 アクションで用意するスキル。Linear / GitHub の issue から命名を流用するパスと、自由テキストから命名するパスの両方をサポートする。

## 使うべきとき

並行作業を始めるとき、または「issue を起点に worktree で作業開始」と読み取れる依頼。例:

- 「DOT-47 やろう」「ABC-105 着手したい」 → Linear ID パス
- 「github.com/.../issues/123 で worktree 作って」 → GitHub URL パス
- 「設計ドキュメントの整理を別 worktree で始めたい」 → 自由テキストパス

## 使わないとき (重要)

単独の小タスク (1 ファイル修正、typo 直しなど) は main 直作業が慣行 (記憶: `feedback_worktree_overuse_for_solo_tasks`)。依頼が「worktree」「並行」「別ブランチ」と明示しない限り、worktree を提案しない。

## 命名規約

形式: `<type>/<linear-id-or-empty>-<kebab-slug>`

- **type** (Conventional Commits prefix): `feat | fix | refactor | docs | chore | test`
  - Linear / GitHub title から推測 (Add/Implement → `feat`、Fix/Bug → `fix`、Refactor → `refactor`、Doc → `docs`)
  - 推測がつかなければ `feat` を default にして確認時にユーザーに修正機会を与える
- **linear-id** (任意): Linear ID パスなら必ず含める (`DOT-47`)。それ以外は省略
- **kebab-slug**: lowercase、3〜5 単語目安、日本語は英訳して slug 化

例:

- Linear `DOT-47 / Add wt-start skill` → `feat/DOT-47-add-wt-start-skill`
- GitHub issue #123 `Fix race condition in queue` → `fix/123-fix-race-condition-in-queue` (※ GitHub ID は `gh-` prefix 不要、番号のみ)
- 自由テキスト「設計ドキュメントの整理」 → `docs/reorganize-design-docs`

## 実行ステップ

### Step 1: 入力を確保

引数 (発話末尾の `/wt-start` 以降、または現発話内の明示的なタスク記述) があるかを判定:

- **引数あり** → そのまま Step 2 に進む
- **引数なし** → ユーザーに自由入力を求める。1問で:

  > 何の作業を始めますか? 次のいずれかで答えてください:
  > - Linear ID (例: `DOT-47`)
  > - GitHub issue/PR URL (例: `https://github.com/owner/repo/issues/123`)
  > - 自由テキスト (作業内容を一言で)

  返答を受け取ってから Step 2 に進む。

### Step 2: 入力を判定

得た文字列を次の3パターンに分岐:

1. `^[A-Z]+-[0-9]+$` にマッチ → **Linear ID パス**
2. `^https?://github\.com/.+/(issues|pull)/[0-9]+` にマッチ → **GitHub URL パス**
3. それ以外 → **自由テキストパス**

### Step 3: 元情報を取得

**Linear ID パス:**

```sh
linear issue title <ID>
```

タイトル取得失敗 (auth 切れ等) は、ユーザーに `linear auth status` の確認を促してから自由テキストパスにフォールバック。

**GitHub URL パス:**

URL から `owner/repo` と issue/PR 番号を抽出し:

```sh
gh issue view <N> --repo <owner/repo> --json title,labels 2>/dev/null \
  || gh pr view <N> --repo <owner/repo> --json title,labels
```

**自由テキストパス:**

ユーザーの発話そのものを元に prefix と slug を提案。日本語の場合は英訳した slug を出す。

### Step 4: branch 名候補を提示 (推奨1案 + 代替0〜2案)

例 (Linear ID `DOT-47 / Add wt-start skill` の場合):

```
推奨: feat/DOT-47-add-wt-start-skill
代替: feat/DOT-47-wt-start (短縮版)
base: origin/main
```

「この名前で進めて良いですか? (yes / 代替番号 / 別案テキスト)」と1問で確認。

### Step 5: base ブランチを確認

デフォルトは `origin/main`。ローカル `main` でなく `origin/main` を必ず指定する (記憶: `feedback_sync_origin_main_before_branch` — local main の遅延を避けるため)。

リポジトリの default branch が `main` でない場合は事前に検出:

```sh
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||'
```

### Step 6: 実行

ユーザー承認後にのみ実行:

```sh
wt switch --create <branch> --base <base>
```

実行前に必ずユーザーに最終コマンドを見せ、承認後に Bash で叩く。`-y` (skip approval) は付けない。

### Step 7: 完了報告

worktree のパスと、次のステップ候補 (handoff のメモを参照する案、Linear status の自動連携を期待する旨など) を1〜2行で要約。

## 失敗時の挙動

- `linear` / `gh` コマンドが存在しない: その入力パスは諦め、自由テキストパスにフォールバック
- `wt switch --create` が失敗 (重複ブランチ等): エラーをそのままユーザーに見せて中断。リカバリ手段 (別名を提案 / `wt remove` で消す等) は次の発話でユーザーが選択
- 既に worktree 内にいる場合: `git rev-parse --show-toplevel` で確認し、ユーザーに「現在 worktree 内です。新規追加で進めますか?」と1問確認

## やらないこと

- `wt switch -x` でのコマンド連鎖 (editor 起動・claude 起動は人間に委ねる)
- Linear の status 自動遷移 (`linear issue start` は呼ばない — 記憶 `reference_linear_github_integration_auto_status` のとおり、PR 作成時に自動遷移する)
- branch 命名規約のリポジトリ別カスタマイズ (将来 `.claude/wt-start.yml` で拡張余地)
