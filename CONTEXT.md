# dotfiles

macOS の開発環境を宣言的に再現するリポジトリ。AI エージェント（Claude Code / Codex CLI）への指示ファイルを 2 層で持つため、層を区別する言葉を定義する。

## Language

**グローバル AGENTS.md**:
`claude/AGENTS.md`。全プロジェクト・全セッションに auto-load される行動規範の層。プロジェクトを問わず常に効くルールだけを置く。
_Avoid_: 「dotfiles の AGENTS.md」（プロジェクト AGENTS.md と区別がつかない）

**プロジェクト AGENTS.md**:
リポジトリ直下の `AGENTS.md`。このリポジトリで作業するときだけ読まれる、リポジトリ固有の構造・運用ルールの層。汎用ルールは置かない（グローバル AGENTS.md へ）。
_Avoid_: 「ローカルの AGENTS.md」（CLAUDE.local.md と紛らわしい）

**CLAUDE.local.md**:
`~/.claude/CLAUDE.local.md`。PC 固有の設定・制約を書く層で、グローバル AGENTS.md を上書きする。リポジトリには格納しない。

## Example dialogue

> 開発者: AGENTS.md にルールを足したい。
> ドメインエキスパート: どの層に？ 全プロジェクトで効かせたいならグローバル AGENTS.md、このリポジトリの構造の話ならプロジェクト AGENTS.md、この PC だけの事情なら CLAUDE.local.md。
> 開発者: pnpm monorepo の検証コマンドの話。
> ドメインエキスパート: それは特定案件でしか発火しないから、グローバルではなくその案件リポジトリのプロジェクト AGENTS.md に置く。
