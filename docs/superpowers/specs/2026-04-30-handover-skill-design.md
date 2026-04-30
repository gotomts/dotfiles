---
title: handover スキル設計
date: 2026-04-30
status: draft
---

# handover スキル設計

## 1. 目的

Claude Code セッションのコンパクト前後で文脈が失われる事故を防ぐため、引き継ぎメモを残し、次セッション開始時に自動で読み込む仕組みを構築する。

## 2. 要件

- 手動コマンド `/handover` で引き継ぎメモを作成・更新できる
- コンパクト直前に「未 handover 状態」を検出してコンパクトをブロックし、ユーザーに `/handover` を促す（手動 `/compact`・自動コンパクト両方）
- 次セッション開始時、または同セッションでのコンパクト後最初のプロンプト時に未消費の handover を検出し、ユーザーに「引き継ぐ／新規」を確認した上で内容を Claude のコンテキストに注入する
- 別プロジェクト・別ブランチ・古いメモ・完了済みメモは自動で読込対象から除外し、ユーザー確認自体を出さない
- 任意のタイミングで未消費メモを一括破棄できる（`/handover clear`）

## 3. 非要件（YAGNI で削る）

以下の機能は今回の設計に含めない:

- マルチエージェント対応（チーム判定、後継エージェント自動生成）
- pipeline ワークフロー連携（Phase Summary 生成）
- 外部チケットシステム（Linear 等）への自動 sync
- worktree 検出と保存先確認のインタラクティブ判定

これらは将来必要になった時、`state.json` の `version` で互換管理しつつ追加できる。

## 4. 調査結果（設計前提）

Claude Code 公式ドキュメント (https://code.claude.com/docs/en/hooks) を確認した結果、以下の仕様制約が判明している。設計はこれらに準拠する:

- フックの stdout が Claude のコンテキストに注入されるのは `SessionStart` / `UserPromptSubmit` / `UserPromptExpansion` の 3 種のみ
- `PreCompact` の stdout はコンテキストに注入されない（debug ログ行きのみ）。代わりに `decision: "block"` でコンパクト中止と `reason` 表示が可能
- `PreCompact` は `matcher: "manual" | "auto"` で発火源を区別できる（手動 `/compact` と自動コンパクト両方で発火する）
- フックには `$CLAUDE_SESSION_ID` 環境変数が渡されるため、セッション識別子として利用可能

この制約により、「Claude に handover スキルを自律実行させる」のは仕様上不可能。代わりに **「未 handover 時はコンパクトをブロックしてユーザーに /handover を促す」半自動方式** を採用する。

## 5. アーキテクチャ

3 種の構成要素で成り立つ。

```
┌──────────────────────────────────────────────┐
│ ユーザー操作                                   │
│  ・/handover            → メモ作成・更新       │
│  ・/handover clear      → 未消費メモ一括破棄  │
│  ・/handover status     → 現状表示            │
└──────────────┬───────────────────────────────┘
               │
┌──────────────▼───────────────┐
│ Claude Code フック             │
│ ・PreCompact                   │
│   未 handover ならブロック     │
│ ・SessionStart                 │
│   未消費メモあれば確認指示注入 │
│ ・UserPromptSubmit             │
│   コンパクト後の検出と注入     │
└──────────────┬───────────────┘
               │
┌──────────────▼───────────────────────────────┐
│ ストレージ                                     │
│ ~/.claude/handover/                           │
│   └ {project-hash}/{branch}/{fingerprint}/    │
│       ├ state.json   (機械可読・真実)         │
│       └ handover.md  (人間可読ビュー)         │
└──────────────────────────────────────────────┘
```

## 6. リポジトリ内ファイル配置

```
.dotfiles/
├ claude/
│  ├ skills/
│  │  └ handover/
│  │      ├ SKILL.md                     # 引数で create / clear / status を分岐
│  │      ├ references/
│  │      │  ├ state-schema.md           # state.json スキーマ詳細
│  │      │  └ handover-md-format.md     # handover.md フォーマット
│  │      └ scripts/
│  │          ├ resolve-path.sh          # project-hash / branch / fingerprint 解決
│  │          ├ consume.sh               # consumed フラグを立てる
│  │          ├ cleanup.sh               # TTL 超過 ALL_COMPLETE の削除
│  │          ├ render-md.sh             # state.json → handover.md 再生成
│  │          └ list-active.sh           # 未消費・READY・TTL 内のメモを列挙
│  ├ hooks/                              # 新設
│  │  ├ pre-compact.sh
│  │  ├ session-start.sh
│  │  └ user-prompt-submit.sh
│  └ settings.json                       # 上記フックを登録
```

`hooks/` を新設する理由は、`settings.json` インライン記述だと `jq` 等の処理が書きづらくスクリプト化が必要なため。

## 7. データ構造

### 7.1 `state.json` スキーマ

```json
{
  "version": 1,
  "session_id": "abc123-...",
  "created_at": "2026-04-30T15:30:00+09:00",
  "updated_at": "2026-04-30T15:45:00+09:00",
  "consumed": false,
  "status": "READY",
  "project": {
    "path": "/Users/goto/.dotfiles",
    "hash": "dotfiles-a1b2c3d4",
    "branch": "main"
  },
  "session_summary": "handover スキルの設計を進行中",
  "tasks": [
    {
      "id": "T1",
      "description": "handover スキル本体を実装",
      "status": "in_progress",
      "next_action": "SKILL.md を docs/superpowers/specs/ から起こす"
    }
  ],
  "decisions": [
    {
      "topic": "保存先",
      "chosen": "~/.claude/handover/{project-hash}/{branch}/",
      "rejected": ["{repo-root}/.agents/", "{cwd}/.handover.md"],
      "rationale": "プロジェクト側を汚さず、複数プロジェクト横断で集約管理できる"
    }
  ],
  "blockers": []
}
```

#### フィールド定義

| フィールド | 型 | 必須 | 説明 |
|---|---|:---:|---|
| `version` | int | ✅ | スキーマバージョン。現状 `1` 固定。将来の互換管理用 |
| `session_id` | string | ✅ | `$CLAUDE_SESSION_ID` の値。PreCompact 判定で使用 |
| `created_at` | ISO 8601 string | ✅ | 初回作成時刻（タイムゾーン付き） |
| `updated_at` | ISO 8601 string | ✅ | 最終更新時刻 |
| `consumed` | bool | ✅ | 自動読込で消費済みなら `true`。読込対象から除外する |
| `status` | enum | ✅ | `READY` または `ALL_COMPLETE` |
| `project.path` | string | ✅ | リポジトリルート絶対パス（非 git なら CWD） |
| `project.hash` | string | ✅ | `{basename}-{sha1[0:8]}` 形式 |
| `project.branch` | string | ✅ | サニタイズ済みブランチ名 |
| `session_summary` | string | ✅ | 1〜2 行のセッション要約 |
| `tasks` | array | ✅ | タスク配列。空配列も可 |
| `decisions` | array | ✅ | 決定事項配列。空配列も可 |
| `blockers` | array of string | ✅ | ブロッカー文字列配列。空配列も可 |

#### `tasks[]` 要素

| フィールド | 型 | 必須 | 説明 |
|---|---|:---:|---|
| `id` | string | ✅ | `T1`, `T2`, ... のシーケンシャル ID |
| `description` | string | ✅ | タスク内容 |
| `status` | enum | ✅ | `in_progress` / `blocked` / `completed` |
| `next_action` | string | 任意 | 次にやるべき具体的な一歩 |

#### `decisions[]` 要素

| フィールド | 型 | 必須 | 説明 |
|---|---|:---:|---|
| `topic` | string | ✅ | 決定対象 |
| `chosen` | string | ✅ | 採用したアプローチ |
| `rejected` | array of string | 任意 | 却下した選択肢（あれば） |
| `rationale` | string | ✅ | 採用理由 |

#### `status` 自動判定ルール

`/handover` 実行時に `tasks[]` を走査して再計算する:

- `tasks` が空、または全要素の `status == "completed"` → `ALL_COMPLETE`
- `tasks` に `in_progress` または `blocked` を 1 件でも含む → `READY`

### 7.2 `handover.md` フォーマット

`state.json` から `render-md.sh` で自動生成する。直接編集禁止。

```markdown
# Handover: 2026-04-30 15:30

**Project**: /Users/goto/.dotfiles
**Branch**: main
**Status**: READY
**Session**: abc123-...

## Session Summary
handover スキルの設計を進行中

## Tasks
- [ ] T1: handover スキル本体を実装 (in_progress)
  - Next: SKILL.md を docs/superpowers/specs/ から起こす

## Decisions
- **保存先**: `~/.claude/handover/{project-hash}/{branch}/` を採用
  - 却下: `.agents/`, `.handover.md`
  - 理由: プロジェクト側を汚さず、複数プロジェクト横断で集約管理できる

## Blockers
なし
```

## 8. パス解決ルール

`resolve-path.sh` の責務。

### 8.1 project-hash

```sh
repo_root="$(git rev-parse --show-toplevel 2>/dev/null || echo "${PWD}")"
project_hash="$(basename "${repo_root}")-$(printf '%s' "${repo_root}" | shasum -a 1 | cut -c1-8)"
# 例: dotfiles-a1b2c3d4
```

### 8.2 branch

```sh
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo nogit)"
# detached HEAD の場合
if [ "${branch}" = "HEAD" ]; then
  branch="detached-$(git rev-parse --short=7 HEAD)"
fi
# サニタイズ: /, :, スペースを - に置換
branch="$(printf '%s' "${branch}" | sed 's|[/:[:space:]]|-|g')"
```

### 8.3 fingerprint

```sh
fingerprint="$(date +%Y%m%d-%H%M%S)"
```

同一秒内の衝突は実用上考慮しない。

### 8.4 保存先

```
~/.claude/handover/{project-hash}/{branch}/{fingerprint}/
  ├ state.json
  └ handover.md
```

### 8.5 既存セッションの再利用判定

`/handover` 実行時、新規 fingerprint を切るか既存を更新するかの判定:

```
{project-hash}/{branch}/ 配下を走査
  ├ session_id == $CLAUDE_SESSION_ID の state.json が見つかる
  │   → そのディレクトリを再利用、updated_at のみ更新してマージ書込
  └ 見つからない
      → 新規 fingerprint ディレクトリを作成
```

これにより、同セッションで `/handover` を複数回打っても 1 ファイルにまとまる。

## 9. データフロー

### 9.1 書込フロー: `/handover`

1. `resolve-path.sh` で保存先決定
2. 既存 state.json の有無確認:
   - あり → 読込してマージベースで更新
   - なし → 新規作成
3. Claude が現セッション内容を `tasks` / `decisions` / `blockers` / `session_summary` に整理
4. `status` 自動判定（`tasks[]` 走査）
5. `state.json` 書き出し
6. `render-md.sh` で `handover.md` 再生成
7. `cleanup.sh` で同 `{project-hash}/{branch}/` 配下の TTL 超過 + ALL_COMPLETE を削除

### 9.2 書込フロー: PreCompact フック発火時

1. `pre-compact.sh` が `$CLAUDE_SESSION_ID` を取得
2. `list-active.sh` で当該セッション ID の state.json を検索（プロジェクト・ブランチ問わず全走査）
3. ヒット **あり** → `exit 0`（コンパクト続行を許可）
4. ヒット **なし** → 以下の JSON を stdout に出力して `exit 0`

   ```json
   {
     "decision": "block",
     "reason": "セッション開始後に /handover を実行してから再度コンパクトしてください。"
   }
   ```

5. Claude Code が `reason` をユーザーに表示し、コンパクト中止
6. ユーザーが `/handover` を実行 → `state.json` 作成
7. ユーザーが再度 `/compact` → 今度は通る

### 9.3 読込フロー: `/handover clear`

1. `resolve-path.sh` で当該プロジェクト・ブランチのディレクトリ特定
2. 配下の全 `state.json` に対し `consumed=true`, `updated_at` 更新
3. ファイル自体は残す（履歴）。7 日経てば `cleanup.sh` で自動削除

### 9.4 読込フロー: `/handover status`

1. `list-active.sh` で当該プロジェクト・ブランチの未消費メモを列挙
2. 結果を整形して表示（fingerprint, status, session_summary, tasks のサマリ）

### 9.5 読込フロー: SessionStart フック発火時

1. `session-start.sh` が現 CWD から project-hash, branch を計算
2. 配下の state.json を走査
3. フィルタ:
   - `consumed == false`
   - `status == "READY"`
   - `created_at` が 7 日以内
4. ヒット 0 件 → `exit 0`（何もしない）
5. ヒット 1 件以上 → 以下の JSON を stdout 出力

   ```json
   {
     "hookSpecificOutput": {
       "hookEventName": "SessionStart",
       "additionalContext": "[HANDOVER NOTICE]\n未消費の handover が見つかりました:\n- {fingerprint}: {session_summary} ({created_at})\n  パス: {abs_path}/handover.md\n\nユーザーに「引き継ぎますか？それとも新規会話にしますか？」を確認してください。\n - 引き継ぐ → 上記 handover.md の内容を Read で読み込み、scripts/consume.sh {abs_path} を Bash で実行\n - 新規 → scripts/consume.sh {abs_path} のみ実行（読込はしない）"
     }
   }
   ```

6. 通知出力後、重複発火対策のマーカーファイルを作成:

   ```
   ${TMPDIR:-/tmp}/claude-handover-checked-${CLAUDE_SESSION_ID}
   ```

7. Claude が起動直後にこの指示を読み、ユーザーに確認

### 9.6 読込フロー: UserPromptSubmit フック発火時

セッション内の重複発火対策として、まずマーカーファイルの存在チェックを行う:

```
${TMPDIR:-/tmp}/claude-handover-checked-${CLAUDE_SESSION_ID}
```

- 存在 → 何もせず `exit 0`（SessionStart で既に通知済み、または前回の UserPromptSubmit で通知済み）
- 存在しない → 9.5 と同じフィルタ・通知ロジックを実行（`consumed == false` AND `status == "READY"` AND `created_at` が 7 日以内）し、通知を出した場合はマーカーファイルを作成

これにより、SessionStart で通知済みの場合も、コンパクト後の最初の UserPromptSubmit で重複通知される事象を防ぐ。同セッション内で UserPromptSubmit が連続発火しても通知は 1 回のみ。

通知 JSON の `hookEventName` のみ `UserPromptSubmit` に変える。`additionalContext` の中身は 9.5 と同じ。

## 10. スキル仕様（`/handover` の引数別動作）

`SKILL.md` の frontmatter:

```yaml
---
name: handover
description: セッションの引き継ぎメモを作成・破棄・確認する。
argument-hint: "[clear | status]"
allowed-tools:
  - Bash
  - Read
  - Write
---
```

### 10.1 引数なし: `/handover`

書込フロー（9.1）を実行。

### 10.2 `/handover clear`

破棄フロー（9.3）を実行。

### 10.3 `/handover status`

状態表示フロー（9.4）を実行。

### 10.4 不明な引数

`Unknown subcommand: {arg}. Use one of: (none) / clear / status` を表示して終了。

## 11. エラーハンドリング

| 状況 | 対応 |
|---|---|
| `jq` が PATH に無い | フックは `exit 0` で sile 警告を stderr に出力。Claude セッションを止めない。`Brewfile` に `brew "jq"` を追加して導入を担保 |
| `~/.claude/handover/` 未作成 | スキル・フックとも `mkdir -p` で先回り作成 |
| state.json が JSON パース不能 | 該当ファイルをスキップ。stderr に warning。他ファイルは正常処理 |
| state.json がスキーマ違反（必須フィールド欠損） | 同上。スキップ + warning |
| `git rev-parse` 失敗（非 git） | branch を `nogit` に fallback、project.path は CWD |
| detached HEAD | branch を `detached-{sha7}` に fallback |
| フックスクリプト自体が失敗 | `exit 0` を保証。stderr に warning |
| `$CLAUDE_SESSION_ID` 未設定 | フックは何もせず `exit 0`（警告のみ） |

## 12. テスト戦略

### 12.1 シェルスクリプト単体テスト（bats）

`claude/skills/handover/tests/` 配下に bats テストを配置。

- `resolve-path.sh`
  - git リポジトリでの project-hash・branch 算出
  - detached HEAD で `detached-{sha7}` になること
  - 非 git ディレクトリで `nogit` になること
  - ブランチ名のサニタイズ（`/`, `:`, スペース）
- `consume.sh`
  - `consumed: false` → `true` への遷移
  - 既に `true` なら冪等
  - 不正 JSON は拒否（exit code 非ゼロ）
- `cleanup.sh`
  - 7 日超 + `ALL_COMPLETE` のディレクトリ削除
  - 7 日超でも `READY` は残ること
  - 7 日以内は無条件で残ること
- `render-md.sh`
  - 標準的な state.json から想定 Markdown を生成（ゴールデンテスト）
  - 空の `tasks` で「タスクなし」表示

### 12.2 フックの統合テスト

`pre-compact.sh`, `session-start.sh`, `user-prompt-submit.sh` について、環境変数（`CLAUDE_SESSION_ID`, `CWD` 等）を変えた場合の stdout を bats で検証。

### 12.3 手動シナリオテスト

スキル全体は Claude 挙動依存のため自動化が難しい。以下のシナリオを `claude/skills/handover/tests/scenarios.md` に記載し、実装後に手動実行する:

- **シナリオ A**: `/handover` → 別シェルで `claude` 起動 → 「引き継ぎますか？」確認が出る
- **シナリオ B**: 全タスク完了状態（`status: ALL_COMPLETE`）で `/handover` → 次セッションで通知が出ない
- **シナリオ C**: 7 日経過したメモ → 通知が出ない
- **シナリオ D**: `/handover clear` 後、次セッションで通知が出ない
- **シナリオ E**: `/compact` を打ったが事前に `/handover` していない → ブロックされ `reason` が表示される
- **シナリオ F**: 自動コンパクト発火（コンテキスト上限近く）で同セッションに `/handover` 履歴なし → ブロック
- **シナリオ G**: `/handover` → `/compact` → そのまま続行 → UserPromptSubmit で「引き継ぎますか？」が 1 回だけ出る
- **シナリオ H**: 別ブランチに切り替えて `claude` 起動 → 元ブランチの handover は通知対象外
- **シナリオ I**: `/handover status` で現状一覧が表示される

## 13. 既存規約との整合

### 13.1 リポジトリ規約

- `claude/skills/{name}/SKILL.md` 規約に準拠
- `claude/hooks/` ディレクトリ新設は CLAUDE.md の「リポジトリ構造」更新が必要
- フック内 shell は `#!/bin/zsh`、`${VAR}` 形式、`${HOME}` 使用（zsh スクリプト規約）

### 13.2 Brewfile

- `jq` が未導入なら `Brewfile` の `# Utilities` セクションに `brew "jq"` を追加

### 13.3 CLAUDE.md 更新事項

実装後、以下を CLAUDE.md に追記する想定:

- 「リポジトリ構造」セクションに `claude/hooks/` を追加
- 「Claude Code 設定」セクションに handover スキルとフックの説明を追加

## 14. 後続作業

この設計が承認されたら:

1. `superpowers:writing-plans` スキルで実装プランを起こす
2. プランに従って実装
3. シェルスクリプトの bats テストを通す
4. 手動シナリオテスト（13 項目）を実行
5. CLAUDE.md と Brewfile を更新
6. PR 作成
