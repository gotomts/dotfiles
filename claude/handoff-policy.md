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

## 踏んだ罠

このセッションで実際に起きた失敗。型ごとに実例を 1 行で書く。該当が無い型は行ごと落とす。

- **沈黙を同意として扱った** — 例: <どの発言を同意と読み、何を確定扱いにしたか>
- **確定していない内容を次の工程へ流した** — 例: <未確定のまま何をどこへ投入したか>
- **実測せずに断定した** — 例: <何を確認せずに「済んだ」と書いたか>
- **入力に混入があった** — 例: <何が意図せず本文に混ざったか>
- **上記に当てはまらないもの** — 例: <型を 1 行で言語化して書く>

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
- 「踏んだ罠」を状態より先に置く。状態は文書とリポジトリから復元できるが、踏んだ罠は書かなければ失われる。同じ失敗を次のセッションに繰り返させないことが引き継ぎの主目的で、状態の受け渡しはその次
- 「いまの状態」は記憶で書かない。branch の ahead / behind、作業ツリーの clean 判定、未 push 数、成果物のファイル数と行数は、コマンドで取った値を書く。取れなかった項目は「未確認」と明記する
- 「確定事項」には結論と根拠の要点を書く。根拠が無い結論は次のセッションで蒸し返される
- 事実と推測を混ぜない。未確認のものは確認方法を添える

## 「ハンドオフから再開」要求への応答

ユーザーが「ハンドオフから再開」と言ったら、上記の規則で `$TMPDIR/handoff-<repo-slug>-<session-slug>.md` を Read で読んでから応答する。該当ファイルが無ければユーザーにパスを確認する。
