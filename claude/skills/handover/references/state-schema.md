# state.json スキーマ

handover メモの真実を保持する機械可読ファイル。`render-md.sh` がこれを `handover.md` に変換する。

## サンプル

```json
{
  "version": 1,
  "session_id": "abc123-def456",
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

## フィールド定義

| フィールド | 型 | 必須 | 説明 |
|---|---|:---:|---|
| `version` | int | ✅ | スキーマバージョン。現状 `1` 固定 |
| `session_id` | string | ✅ | `$CLAUDE_SESSION_ID` の値 |
| `created_at` | ISO 8601 string | ✅ | 初回作成時刻 |
| `updated_at` | ISO 8601 string | ✅ | 最終更新時刻 |
| `consumed` | bool | ✅ | 読込で消費済みなら `true` |
| `status` | enum | ✅ | `READY` または `ALL_COMPLETE` |
| `project.path` | string | ✅ | リポジトリルート絶対パス |
| `project.hash` | string | ✅ | `{basename}-{sha1[0:8]}` 形式 |
| `project.branch` | string | ✅ | サニタイズ済みブランチ名 |
| `session_summary` | string | ✅ | 1〜2 行のセッション要約 |
| `tasks` | array | ✅ | タスク配列。空配列も可 |
| `decisions` | array | ✅ | 決定事項配列。空配列も可 |
| `blockers` | array of string | ✅ | ブロッカー配列。空配列も可 |

### tasks[] 要素

| フィールド | 型 | 必須 | 説明 |
|---|---|:---:|---|
| `id` | string | ✅ | `T1`, `T2`, ... |
| `description` | string | ✅ | タスク内容 |
| `status` | enum | ✅ | `in_progress` / `blocked` / `completed` |
| `next_action` | string | 任意 | 次の一歩 |

### decisions[] 要素

| フィールド | 型 | 必須 | 説明 |
|---|---|:---:|---|
| `topic` | string | ✅ | 決定対象 |
| `chosen` | string | ✅ | 採用したアプローチ |
| `rejected` | array of string | 任意 | 却下選択肢 |
| `rationale` | string | ✅ | 採用理由 |

## status 自動判定ルール

`/handover` 実行時に `tasks[]` を走査して再計算する:

- `tasks` が空、または全要素が `status == "completed"` → `ALL_COMPLETE`
- `tasks` に `in_progress` または `blocked` を 1 件でも含む → `READY`
