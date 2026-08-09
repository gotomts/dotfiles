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

例: `HERDR_TAB_ID=w27:t1` → label `v2:ops` → `handoff-myapp-v2-ops.md`

タブ名は同一リポジトリ内で一意になるよう付ける。既定のタブ名（連番）は別セッションと重複しうるため、`herdr tab rename` で担当が分かる名前にしてから handoff を保存する。

## `$TMPDIR` の OS 差分

- macOS: `/var/folders/.../T/`
- Linux: 通常 `/tmp`

## ドキュメントの構成

次のテンプレートに従う。該当する内容が無いセクションは見出しごと落とす。

```markdown
# Handoff — <repo-slug> / <session-slug> — <担当>

最終更新: <YYYY-MM-DD HH:MM> / ブランチ: <branch>

## 役割

このセッションが担当する範囲と、担当しない範囲。

## いまの状態

進行中の作業と、その現在地。未確定のものは未確定と書く。

## 確定事項（再導出しないこと）

決着済みの判断と、そう決めた根拠の要点。次のセッションが蒸し返さないための節。

## 残作業

次のセッションが着手する単位に分けて列挙する。

## 制約

触ってはいけないもの。ユーザーの判断待ちで自分では決めないもの。

## 参照

path / URL のみ。

## Suggested skills
```

書き方の規約:

- 見出しの順序を変えない。読む側は上から必要な分だけ読んで着手する
- 「確定事項」には結論と根拠の要点を書く。根拠が無い結論は次のセッションで蒸し返される
- 事実と推測を混ぜない。未確認のものは確認方法を添える

## 「ハンドオフから再開」要求への応答

ユーザーが「ハンドオフから再開」と言ったら、上記の規則で `$TMPDIR/handoff-<repo-slug>-<session-slug>.md` を Read で読んでから応答する。該当ファイルが無ければユーザーにパスを確認する。
