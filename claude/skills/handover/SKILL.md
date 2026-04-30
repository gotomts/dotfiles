---
name: handover
description: セッションの引き継ぎメモを作成・破棄・確認する。コンパクト前後で文脈が失われる事故を防ぐ。
argument-hint: "[clear | status]"
allowed-tools:
  - Bash
  - Read
  - Write
---

# Handover

セッションのタスク状態と決定事項を `~/.claude/handover/{project-hash}/{branch}/{fingerprint}/` 配下に記録し、次セッションで自動引き継ぎを可能にする。

## アクション判定

- 引数なし → 書込（メモ作成・更新）
- `clear` → 当該プロジェクト・ブランチの未消費メモを一括 consumed
- `status` → 現在の未消費メモ一覧を表示

## 書込（引数なし）

### 1. パス解決

Bash で `~/.claude/skills/handover/scripts/resolve-path.sh` を実行し、出力を `eval` で取り込む:

```sh
eval "$(${HOME}/.claude/skills/handover/scripts/resolve-path.sh)"
```

これにより以下が利用可能になる:
- `${PROJECT_PATH}` `${PROJECT_HASH}` `${BRANCH}` `${FINGERPRINT}` `${HANDOVER_DIR}`

### 2. 既存セッション再利用判定

Bash で:

```sh
${HOME}/.claude/skills/handover/scripts/list-active.sh "${PROJECT_HASH}" "${BRANCH}" "${CLAUDE_SESSION_ID}"
```

戻り値の JSON 配列が:
- 空 → 新規 fingerprint で作成: `target_dir="${HANDOVER_DIR}/${FINGERPRINT}"`
- 1 件以上 → 最初の要素の `abs_path` を再利用: `target_dir="$(jq -r '.[0].abs_path' <<< ...)"` 既存 state.json をマージベースで更新

### 3. state.json の構築

このセッションで観測したタスク・決定事項・ブロッカーを整理し、以下のスキーマで JSON を構築する。スキーマ詳細は `references/state-schema.md` を参照。

含めるべき内容（仕様書に基づく）:

- **tasks**: 残タスク・進行中タスク（最低限 `id` `description` `status` を埋める。`next_action` は明確なら埋める）
- **decisions**: このセッションで採用したアプローチ。却下した選択肢・採用理由を含める
- **blockers**: 着手を止めている事象（あれば）
- **session_summary**: 1〜2 行の要約

### 4. status 自動判定

`tasks[]` を走査:
- 全要素 `completed` または空 → `status = "ALL_COMPLETE"`
- それ以外 → `status = "READY"`

### 5. 書き出し

`${target_dir}/state.json` を Write ツールで書き出す。

### 6. handover.md を再生成

```sh
${HOME}/.claude/skills/handover/scripts/render-md.sh "${target_dir}/state.json" > "${target_dir}/handover.md"
```

### 7. cleanup 実行

```sh
${HOME}/.claude/skills/handover/scripts/cleanup.sh
```

### 8. ユーザーに報告

書き込み先の絶対パスとハイライト（タスク数、status）を表示する。

## 破棄（`/handover clear`）

### 1. パス解決

```sh
eval "$(${HOME}/.claude/skills/handover/scripts/resolve-path.sh)"
```

### 2. 当該ブランチの全 state.json を消費済みに

```sh
for f in "${HANDOVER_DIR}"/*/state.json(N); do
  ${HOME}/.claude/skills/handover/scripts/consume.sh "${f}"
done
```

zsh の `(N)` は null glob オプション（マッチがゼロでもエラーにしない）。

### 3. 現セッションのマーカーを削除

このセッションでも自動読込通知が再発火しないよう:

```sh
rm -f "${TMPDIR:-/tmp}/claude-handover-checked-${CLAUDE_SESSION_ID}"
```

代わりに作成:

```sh
touch "${TMPDIR:-/tmp}/claude-handover-checked-${CLAUDE_SESSION_ID}"
```

これで通知済み扱いとなり、UserPromptSubmit で再通知されない。

### 4. ユーザーに報告

何件の state.json を consumed したかを表示する。

## 状態確認（`/handover status`）

### 1. パス解決と列挙

```sh
eval "$(${HOME}/.claude/skills/handover/scripts/resolve-path.sh)"
${HOME}/.claude/skills/handover/scripts/list-active.sh "${PROJECT_HASH}" "${BRANCH}"
```

### 2. 結果表示

JSON 配列を読み解いて、以下の形式で表示:

```
Project: {project_hash}
Branch:  {branch}

Active handovers:
- {fingerprint}: {summary}
    created: {created_at}
    session: {session_id}
    path:    {abs_path}/handover.md
```

該当なしなら `No active handovers.` と表示。

## 不明な引数

`Unknown subcommand: {arg}. Use one of: (none) / clear / status` を表示し、何もせず終了する。

## 制約

- `state.json` の編集は `consume.sh` 経由 or Write ツールで行うこと（直接 sed しない）
- `handover.md` は `render-md.sh` でしか書かないこと（直接編集禁止）
- このセッションで実際に観測した事実のみ書く。推測や補足は含めない
