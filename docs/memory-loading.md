# AI エージェントのメモリ読み込みの仕組み

> このファイルは auto-load されない。トラブルシュート時と、`claude/rules/orchestrator.md`
> （指示層の優先順位）からの参照時に Read する。

## 生成と配布

グローバル規範は `claude/rules/` のフラグメントが SSOT で、`scripts/build-agent-rules.zsh`
（alias: `agent-rules-build`）が 2 つの生成物を作る。

| 生成物 | 構成 | 読むエージェント |
|---|---|---|
| `claude/AGENTS.md` | `core` + `worker` | Claude Code / Codex CLI |
| `claude/hermes/SOUL.md` | `hermes-identity` + `core` + `orchestrator` | Hermes Agent |

結合が必要なのは、Codex CLI も Hermes も `@AGENTS.md` 形式の import を展開せず、
渡されたファイルの中身をそのまま system prompt へ入れるため。生成物は working tree に
コミットし、symlink は `mkOutOfStoreSymlink` で working tree を直接指す。したがって
フラグメント編集 → `agent-rules-build` だけで反映され、`darwin-rebuild switch` は要らない。

生成漏れは `.github/workflows/agent-rules-check.yml` が `--check` で検出する。

## Claude Code

### 優先順位

```
User CLAUDE.local.md > AGENTS.md（global） > Claude Code 既定挙動
```

`CLAUDE.local.md` は PC 固有の設定・制約を記述するファイルであり、グローバル規約である
`AGENTS.md` を上書きする。

### import 解決の経路

1. Claude Code が `~/.claude/CLAUDE.md`（dotfiles の `claude/CLAUDE.md` への symlink）を読む
2. `CLAUDE.md` 内の `@AGENTS.md` で AGENTS.md を inject
3. 続く `@CLAUDE.local.md` で `~/.claude/CLAUDE.local.md` を inject（ファイルが存在しない PC では skip される）

ここまでが起動時の自動 inject 機構であり、エージェントが Read を忘れる余地はない。

### デバッグ

- `CLAUDE.local.md` が読まれていることの確認: Claude Code 起動後に `/memory` でメモリ階層を表示する
- `/memory` の出力に `~/.claude/CLAUDE.local.md` が現れていれば inject 成功
- AGENTS.md / CLAUDE.local.md の各 token 数も `/context` で確認できる

## Codex CLI

`~/.codex/AGENTS.md` が `claude/AGENTS.md` への symlink。プロジェクト直下の `AGENTS.md` は
Codex CLI が working directory から自動検出するため、symlink せずリポジトリ内に閉じる。

## Hermes Agent

### 優先順位

```
channel prompt（リポジトリ固有） > SOUL.md（グローバル規範） > Hermes 既定挙動
```

channel prompt は ephemeral な区画へ SOUL.md より後に連結されるため、競合時はこちらが勝つ。

### 読み込みの経路

- `~/.hermes/SOUL.md`（dotfiles の `claude/hermes/SOUL.md` への symlink）は `HERMES_HOME`
  固定で読まれ、**cwd に依存せず必ず system prompt に入る**。identity 区画に載るため、
  先頭に Hermes 自身の自己紹介文（`hermes-identity`）を含める必要がある
- プロジェクト context file は「最初に見つかった 1 種類だけ」を読む。優先順は
  `.hermes.md` / `HERMES.md`（git root まで遡上）→ `AGENTS.md`（git root → cwd のチェーンを結合）
  → `CLAUDE.md`（cwd のみ）→ `.cursorrules`（cwd のみ）
- チェーンは git root より上へ遡らない。ホーム直下に置いたファイルは cwd がリポジトリへ
  移った瞬間に失効するため、グローバル規範の置き場にはできない
- gateway の cwd はホームディレクトリ固定（`terminal.cwd: .` はホームに解決される）。
  ホームは git リポジトリではないので、**対象リポジトリの AGENTS.md は自動注入されない**。
  Hermes は作業開始時に対象リポジトリの AGENTS.md / CLAUDE.md を自分で Read する
- context file は system prompt へ入る前に prompt injection スキャンを通り、ヒットすると
  **ファイル全文が `[BLOCKED: ...]` に差し替わる**。規範を書き足したら実際に読まれているか確認する
- 1 ファイルあたりの上限は既定 20,000 文字（`context_file_max_chars` で上書き可）

### デバッグ

- `hermes prompt-size` の `stable (identity/guidance/skills)` 区画に SOUL.md 相当の
  バイト数が乗っているか確認する
- 生成物が届いているかの確認: `readlink -f ~/.hermes/SOUL.md` が working tree
  (`~/.dotfiles/claude/hermes/SOUL.md`) を指していること
- 実チャンネルで「今効いている確認ルールを 1 行で言え」と聞き、channel prompt に書いて
  いない共通ルール（一問一答など）を復唱できるか確かめる

## 外部化ファイルの read-on-demand

規範フラグメント内では以下の外部ファイルへのパス参照のみを残している。`@import` は使わないため
auto-load されず、エージェントが必要時に Read する。

- `~/.dotfiles/claude/handoff-policy.md` — handoff skill の PC ローカル運用規約
- `~/.dotfiles/docs/memory-loading.md` — 本ファイル
