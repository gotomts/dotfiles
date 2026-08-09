# handoff skill のローカル運用ポリシー

> このファイルは auto-load されない。`AGENTS.md` の handoff 規約からエージェントが必要時に Read する。skill 本体（`claude/skills/handoff/SKILL.md`）は upstream（mattpocock/skills）と完全同期する運用なので触らず、本ポリシーが skill の指示より優先される。

## ファイル配置

- 保存先: `$TMPDIR/handoff-<repo-slug>-<session-slug>.md`
- 1 セッション 1 ファイル。同一セッションの再保存は上書きする
- 命名規約に一致しないファイル（`handoff-<repo-slug>.md` など）は読まない・消さない

## `<repo-slug>` の解決

- main git working dir の basename
- worktree からは `dirname "$(git rev-parse --git-common-dir)"` 経由で main working dir を解決し、その basename
- git 外ならカレントディレクトリの basename

## `<session-slug>` の解決

主キーは herdr のタブ名。`${HERDR_TAB_ID}` が取れる場合は、そのタブの label を使う。

```sh
herdr tab list | jq -r --arg id "${HERDR_TAB_ID}" '.result.tabs[] | select(.tab_id == $id) | .label'
```

`${HERDR_TAB_ID}` が無い（herdr の外）場合は現在のブランチ名を使う。detached HEAD や git 外でブランチを解決できない場合は `nobranch` とする。

いずれの場合も `:` と `/` を `-` に置換して slug 化する。

例: `HERDR_TAB_ID=w27:t1` → label `v2:ops` → `handoff-socialcoffeenote-v2-ops.md`

タブ名は同一リポジトリ内で一意になるよう付ける。既定のタブ名（連番）は別セッションと重複しうるため、`herdr tab rename` で担当が分かる名前にしてから handoff を保存する。

## `$TMPDIR` の OS 差分

- macOS: `/var/folders/.../T/`
- Linux: 通常 `/tmp`

## 「ハンドオフから再開」要求への応答

ユーザーが「ハンドオフから再開」と言ったら、上記の規則で `$TMPDIR/handoff-<repo-slug>-<session-slug>.md` を Read で読んでから応答する。該当ファイルが無ければユーザーにパスを確認する。
