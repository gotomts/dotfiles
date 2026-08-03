# handoff skill のローカル運用ポリシー

> このファイルは auto-load されない。`AGENTS.md` の handoff 規約からエージェントが必要時に Read する。skill 本体（`claude/skills/handoff/SKILL.md`）は upstream（mattpocock/skills）と完全同期する運用なので触らず、本ポリシーが skill の指示より優先される。

## ファイル配置

- 保存先: `$TMPDIR/handoff-<repo-slug>-<branch-slug>.md`
- repo × branch 単位で 1 ファイル、同一ブランチ内は上書き運用
- 複数セッションを別ブランチ（別 worktree）で並行運用しても衝突しないよう、ファイル名は repo と branch の複合キーにする

## `<repo-slug>` の解決

- main git working dir の basename
- worktree からは `dirname "$(git rev-parse --git-common-dir)"` 経由で main working dir を解決し、その basename
- git 外ならカレントディレクトリの basename

## `<branch-slug>` の解決

- 現在のブランチ名を sanitize したもの（`/` 等を `-` に置換）
- detached HEAD や git 外などブランチを解決できない場合は `nobranch`

## `$TMPDIR` の OS 差分

- macOS: `/var/folders/.../T/`
- Linux: 通常 `/tmp`

## 同一 repo × branch で複数セッションが動く場合

repo × branch の複合キーは「別セッション＝別ブランチ（別 worktree）」を前提にしている。**メインワークスペースで複数のセッションが同じブランチに居るとファイル名が衝突する**。並行運用のオーケストレーターと、別テーマを担当するセッションが両方 default branch に居る構成で実際に起きる。

このとき**上書きしない**。1 ファイルの中をセクションに分ける。

- 冒頭に、どのセクションが誰の担当かを担当範囲・タブ名・pane ID・最終更新日で示す
- 見出しは `# セクション A — <担当>` の形にし、セクション内だけを更新する旨を明記する
- 自分の担当セクションだけを書き換える。他セクションは、内容が古くなったことを確認できた箇所に限り取り消し線と参照先を足すに留める

書き込む前に既存ファイルを Read し、別セッションのセクションが無いかを確認する。

## 過渡対応

旧形式の `handoff-<repo-slug>.md`（repo 単位のみのファイル）が残っていても触らない。移行で消さない。

## 「ハンドオフから再開」要求への応答

ユーザーが「ハンドオフから再開」と言ったら、上記の規則で `$TMPDIR/handoff-<repo-slug>-<branch-slug>.md` を Read で読んでから応答する。該当ファイルが無ければユーザーにパスを確認する。
