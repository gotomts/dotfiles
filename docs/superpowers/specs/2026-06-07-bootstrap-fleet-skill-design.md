---
title: bootstrap-fleet スキル 設計
date: 2026-06-07
issue: DOT-42
status: approved
depends-on:
  - claude/fleet/inject-fleet.sh
truth-source: projects/ai-org/chat/agent-fleet/design-notes.md
---

# bootstrap-fleet スキル 設計

## 背景・目的

canonical な `inject-fleet.sh`（Claude Code on the web 用 SessionStart hook）を任意リポジトリに敷く作業を、毎回手書きせず再現可能にする再利用形スキル。ANTTT-32 / SCN-32 のような「canonical hook を敷く」作業の再利用形（DOT-42）。

真実源は vault `projects/ai-org/chat/agent-fleet/design-notes.md` の「再利用形：bootstrap スキル」「補足：注入の置き方（full hook vs thin bootstrap）」。本 spec はその設計時判断（full hook 採用）を確定し、dotfiles 上の実体化仕様に落とす。

## スコープ

DOT-42 のスコープに限定する。**含む**:

- 対象リポの `.claude/hooks/inject-fleet.sh` 配置（canonical full hook）
- `.claude/settings.json` の SessionStart 登録（マージ or 新規作成）
- branch / commit / PR（auto-merge しない）
- 冪等（再実行で差分なし＝ no-op）

**含まない**（将来の上位スキル＝広義スキャフォールドに委ねる）:

- cloud-setup.sh 以外の環境組み込み、`.gitignore` 操作
- CodeRabbit / CI / branch protection の設定（これらは repo の `.github/` 側の別レイヤ）

## 設計判断

### full hook 方式（確定）

注入の置き方は **full hook 生成**を採用（vault「補足」の二択より）。対象リポに hook 本体をコミットする＝ reviewable・versioned。`thin bootstrap`（`curl|bash` 的リモート実行）は供給網リスク・レビュー性低下のため不採用。

ただしハイブリッド：リポに置くのは full canonical hook だが、**スキル内に hook 本文を二重持ちしない**。実行時に正本 `claude/fleet/inject-fleet.sh` を取得してコピーする（drift 防止）。

### 置き場所（確定＝常用層）

`claude/skills/bootstrap-fleet/`（常用層・`maintainer: gotomts`）。

理由: (a) bootstrap はどのリポでも使う人間運用ツール（wt-cleanup / create-issue と同類）で dev-* エージェント用スキルではない、(b) fleet 専用（remote-gated）に置くと「fleet を敷くためのスキル」自体が fleet 注入経由でしか届かない鶏卵になる、(c) 規約「fleet/skills は agent 用 vendored 専用・workflow スキルは claude/skills 統一」と整合。

### canonical hook の取得方式（確定＝両対応）

ローカル `~/.dotfiles/claude/fleet/inject-fleet.sh` を優先し、無ければ `https://raw.githubusercontent.com/gotomts/dotfiles/main/claude/fleet/inject-fleet.sh` を fetch する。

- bootstrap は鶏卵制約によりローカル CLI 実行（クラウドの feature-team 実行では作れない）。母艦では `~/.dotfiles` がほぼ常に存在するのでオフライン可・in-flight な hook 編集も拾える。
- raw フォールバックで未チェックアウト機でも動く「任意リポ・任意マシンの再利用形」を満たす。
- 注: `~/.claude/fleet/inject-fleet.sh` は home-manager で symlink されない（symlink 対象は `~/.claude/{agents,skills}` のみ）。ローカル取得は `~/.dotfiles` 経由になる。

## アーキテクチャ

`claude/skills/bootstrap-fleet/SKILL.md` 単一ファイル（pure SKILL.md＝ wt-cleanup と同型：frontmatter + 構造化 bash ステップ）。hook 本文・補助スクリプトは同梱しない。

### frontmatter

```yaml
---
name: bootstrap-fleet
maintainer: gotomts
description: canonical inject-fleet SessionStart hook を任意リポジトリに敷く再利用形。.claude/hooks/inject-fleet.sh 配置 + settings.json SessionStart 登録 + PR。冪等。
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
---
```

### 実行フロー

**Step 0 — 前提チェック・引数**

- git リポジトリのルートであること（`git rev-parse --show-toplevel` と cwd 一致）。違反は abort。
- `gh auth status` OK であること。違反は abort。
- dotfiles 自身では実行しないガード: origin が `gotomts/dotfiles` なら「正本リポには注入不要」と abort。
- 引数: `dry-run`（差分プレビューのみ）のみ対応。未知引数は明示エラー + `exit 1`。

**Step 1 — canonical hook の取得（両対応）**

- `~/.dotfiles/claude/fleet/inject-fleet.sh` が存在 → ローカルを source に。
- 無ければ `https://raw.githubusercontent.com/gotomts/dotfiles/main/claude/fleet/inject-fleet.sh` を temp に fetch。
- 取得物を検証: 非空・先頭が `#!`・`inject-fleet` マーカーを含む。HTML / 404 / 空なら abort（壊れた hook を配らない）。

**Step 2 — hook 配置**

- `.claude/hooks/` を作成し、取得した正本を `.claude/hooks/inject-fleet.sh` に書き出し `chmod +x`。

**Step 3 — SessionStart 登録（settings.json マージ）**

- 登録コマンド: `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/inject-fleet.sh"`。
  - ※ 実装時に SCN-31 / ANTTT-32 の committed hook 参照形へ突合して最終確定する。hook は remote-gated（`CLAUDE_CODE_REMOTE != true` で `exit 0`）のため、local を含む全環境に登録しても無害。
- settings.json 無し → SessionStart エントリ付きで新規作成。
- 有り → `jq` で安全にマージ。同等エントリが既にあれば追加しない（冪等）。
- settings.json が不正 JSON → clobber せず abort してユーザーに報告。

**Step 4 — 冪等判定**

- `.claude/hooks/inject-fleet.sh` が既に正本と同一内容 かつ settings.json に SessionStart エントリ有り → 「既に bootstrap 済み・no-op」を報告し branch / commit せず `exit 0`。

**Step 5 — branch / commit / PR**

- ブランチ `chore/bootstrap-fleet-hook` を切る。
- `.claude/hooks/inject-fleet.sh` と `.claude/settings.json` のみを add（`git add -A` 禁止）。
- commit: `chore(claude): canonical inject-fleet SessionStart hook を導入`。
- `gh pr create`（auto-merge しない）。

**Step 6 — 自走ライフサイクル（vault「完了処理の正準」準拠）**

1. coderabbit-review サイクル: actionable ゼロまで（`coderabbit-review` スキル使用）。
2. CI 監視: green まで。
3. 人レビュー gate で停止: PR URL・CI・指摘状況を報告してマージ待ち（HITL）。
4. マージ後 Linear 連携が自動遷移（自分でマージした場合のみ手動 Done）。

## ガードレール

- 触るのは対象リポの `.claude/hooks/inject-fleet.sh` と `.claude/settings.json` のみ。
- hook 本文をスキル内に固定値で持たない（正本取得）。
- 破壊的操作なし（既存 settings.json は jq マージ、不正時は abort）。

## エラーハンドリング（fail-loud）

| 状況 | 挙動 |
|---|---|
| git リポ外 / ルート外 | abort・メッセージ |
| `gh` 未認証 | abort |
| dotfiles 自身で実行 | abort（正本に注入不要） |
| 正本取得失敗（オフライン＋ローカル無） | abort・取得元を明示 |
| 取得物が不正（HTML / 空） | abort |
| settings.json が不正 JSON | abort（clobber しない） |

## テスト方針

- dotfiles の CI（nix-check）は `nix/**` のみ対象で `claude/` 配下のスキルは CI 非対象。skills 用の bats ハーネスも無い（既存スキルも未テスト）。
- よってスクラッチ git リポでの手動検証を採用:
  1. hook 配置＋実行権が付くこと
  2. settings.json に SessionStart 登録が入ること
  3. 再実行で no-op（冪等）になること
  4. hook 内容が正本と一致すること
- 検証ログを PR 本文に添える。検証ゲートは CodeRabbit ＋人レビュー。

## 完了条件

- 任意リポで実行すると canonical hook ＋ SessionStart 登録の PR ができる。
- 再実行が冪等。
- スキルに `maintainer: gotomts`。
