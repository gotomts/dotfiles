# dotfiles

macOS の開発環境を宣言的に再現するリポジトリ。AI エージェント（実装ワーカー: Claude Code / Codex CLI、オーケストレーター: Hermes Agent）への指示は、エージェントごとに独立したファイルで管理して配る。層と役割を区別する言葉を定義する。

## Language

**グローバル AGENTS.md**:
`claude/AGENTS.md`。Claude Code と Codex CLI に auto-load される行動規範の層。実装ワーカー向けの指示をここで直接編集する。
_Avoid_: 「dotfiles の AGENTS.md」（プロジェクト AGENTS.md と区別がつかない）

**SOUL.md**:
`claude/hermes/SOUL.md`。Hermes に auto-load される行動規範の層。オーケストレーター向けの指示をここで直接編集する。Hermes 側で cwd に依存せず必ず読まれる唯一のファイルなので、グローバル規範はここに載せる。
_Avoid_: 「Hermes の AGENTS.md」（Hermes は cwd 次第で AGENTS.md も読むため、別物と混同する）

**プロジェクト AGENTS.md**:
リポジトリ直下の `AGENTS.md`。このリポジトリで作業するときだけ読まれる、リポジトリ固有の構造・運用ルールの層。汎用ルールは置かない（グローバル AGENTS.md / SOUL.md へ）。
_Avoid_: 「ローカルの AGENTS.md」（CLAUDE.local.md と紛らわしい）

**CLAUDE.local.md**:
`~/.claude/CLAUDE.local.md`。PC 固有の設定・制約を書く層で、グローバル AGENTS.md を上書きする。Claude Code だけが読む。リポジトリには格納しない。

**channel prompt**:
Hermes の `~/.hermes/config.yaml` に置く、チャンネル単位の指示。Hermes 側で CLAUDE.local.md に相当する上書き層で、SOUL.md より後に注入されるため競合時はこちらが勝つ。リポジトリ固有の事実（checkout パス・origin・既定ブランチ・権限の差分）だけを置く。

## Example dialogue

> 開発者: AGENTS.md にルールを足したい。
> ドメインエキスパート: どの層に？ 実装ワーカー（Claude Code / Codex）に効かせたいならグローバル AGENTS.md、Hermes の委譲の作法なら SOUL.md。このリポジトリの構造の話ならプロジェクト AGENTS.md、この PC だけの事情なら CLAUDE.local.md。
> 開発者: pnpm monorepo の検証コマンドの話。
> ドメインエキスパート: それは特定案件でしか発火しないから、グローバルではなくその案件リポジトリのプロジェクト AGENTS.md に置く。
> 開発者: では「実装エージェントの報告を鵜呑みにしない」は？
> ドメインエキスパート: 委譲する側の規律だから SOUL.md。グローバル AGENTS.md に書くと、実装ワーカーには効かない指示が毎ターン課金される。
