# リポジトリ構造

このリポジトリは macOS の開発環境を再現するための dotfiles である。

- `CONTEXT.md` — AI エージェント指示の層（規範フラグメント・グローバル / プロジェクト AGENTS.md・SOUL.md・CLAUDE.local.md・channel prompt）を区別する用語集
- `aliases` — alias 定義の SSOT（root 直下、`~/.aliases` にシンボリックリンク）。旧 `nix/modules/home/zsh.nix` の `shellAliases` から移行（`setup/link.zsh` が配置、Tier 1）
- `scripts/` — 外部シェルスクリプト（`aliases` の alias から呼び出される。旧 `aliase/` から改名）
- `setup/` — Tier 1（リアルタイム symlink）・Tier 2（明示的スクリプト実行）・Tier 3（カットオーバー・ロールバック）の実装。`darwin-rebuild switch` を使わず、`zsh setup/link.zsh` で dotfiles を配置し（Tier 1）、`setup/languages.zsh`（mise+corepack）／`setup/defaults.zsh`（macOS defaults・IME）／`setup/pam.zsh`（Touch ID for sudo）／`setup/claude-sync.zsh`（skills clone・plugin sync・MCP merge）／`setup/codex-sync.zsh`（config.toml seed-if-absent）を個別実行する（Tier 2）。既存 PC を home-manager 込みの旧構成から移行する場合は `setup/cutover.zsh`（pre-flight build 確認 + `darwin-rebuild switch`）／`setup/rollback.zsh`（`.before-nix` 衝突検出付きロールバック）を使う（Tier 3）。**実機での実行は `setup/migrate.zsh` が唯一のエントリポイント**（`--dry-run`/`--apply`。Tier 1/2/3 を依存順（Phase 1: link → Phase 2: cutover/pam [root] → Phase 3: languages/defaults/claude-sync/codex-sync）で実行し、`~/.dotfiles-migrate/manifest.log` で部分適用を検出・再開する。fail-closed、rollback.zsh は自動では呼ばない）。個別スクリプトの直接実行はメンテナンス目的のみ。詳細は `setup/README.md` と `docs/superpowers/specs/2026-08-21-restore-script-management-inventory.md`・`docs/superpowers/specs/2026-08-22-restore-script-management-tier3-cutover-design.md`・`docs/superpowers/specs/2026-08-22-migrate-orchestrator-recovery-plan.md` を参照
- `claude/` — Claude Code 設定（`~/.claude/` にシンボリックリンク）
- `claude/rules/` — 全 AI エージェント向けグローバル指示のフラグメント（SSOT）。`core` / `worker` / `orchestrator` / `hermes-identity` の 4 ファイルを `scripts/build-agent-rules.zsh`（旧 `aliase/build-agent-rules.zsh`）が結合して生成物を作る
- `claude/hermes/SOUL.md` — Hermes Agent 用グローバル指示の生成物（`~/.hermes/SOUL.md` にシンボリックリンク）。直接編集しない
- `claude/skills/` — Claude Code 個人スキル層（`~/.claude/skills` にシンボリックリンク）。自作 skill は `gotomts/skills` が SSOT で相対 symlink だけを置き、外部由来のみ実体を持つ
- `claude/hooks/` — Claude Code hook スクリプト（`~/.claude/hooks/<name>` へファイル単位でシンボリックリンク）
- `claude/mcp-servers.json` — user scope の MCP server 宣言（`setup/claude-sync.zsh` 実行時に `~/.claude.json` に merge、Tier 2）
- `codex/config.base.toml` — Codex CLI の宣言的 seed 設定（`~/.codex/config.toml` 不在時のみ `setup/codex-sync.zsh` が cp する、Tier 2。`~/.codex/config.toml` はアプリ所有の running config なので symlink・追跡しない）
- `config/` — アプリケーション設定（starship, yazi, cmux, ghostty, zed）（`~/.config/` にシンボリックリンク）
- `config/git/` — git 設定・ignore（`config`/`ignore`、`~/.config/git/` にシンボリックリンク）。Tier 1 移行時に新設した plain ini（旧 SSOT は `nix/modules/home/git.nix` の `programs.git`）
- `docs/` — 設計ドキュメント・実装プラン（シンボリックリンク対象外）
- `functions/` — zsh カスタム関数（`~/.functions/` にシンボリックリンク）
- git 設定は `config/git/config`（plain ini）が SSOT で、Tier 1 (`setup/link.zsh`) が `~/.config/git/config` へ symlink する（旧 SSOT は nix の `programs.git`、`nix/modules/home/git.nix` は Tier 3 で削除済み）。`~/.gitconfig` は `setup/link.zsh` の `fs::ensure_realfile` が書き込み可能な実体ファイルとして用意し、`git config --global` で書き込むツール（coderabbit の machineId 等）の PC 固有値を隔離する落書き帳として使う（リポジトリには格納しない）
- `.gitignore` — リポジトリ内に偶発的に作られたローカル overlay ファイル（例: `nix/modules/darwin/homebrew.local.nix`）を保険的に除外する
- `gitignore_global` — グローバル gitignore（`~/.gitignore_global` にシンボリックリンク）
- `grip/` — grip 設定（`~/.grip/` にシンボリックリンク）
- `nix/` — nix-darwin + flakes による Homebrew パッケージ管理定義（`darwin-rebuild` から参照される。home-manager は Tier 3 で廃止済み、詳細は `nix/README.md`）
- `ssh/` — SSH 設定（`~/.ssh/` にシンボリックリンク）
- `zsh/` — zsh 補完ファイル（`~/.zsh/` にシンボリックリンク）
- `zshrc` — zsh 設定（`~/.zshrc` にシンボリックリンク）
- `zshenv` — zsh 環境変数（`~/.zshenv` にシンボリックリンク）

# シンボリックリンク管理

シンボリックリンクは Tier 1 (`setup/link.zsh`) で管理する（home-manager は Tier 3 で廃止済み）。新規 dotfiles は `setup/link.zsh` に `fs::link_file <repo path> <$HOME path>` 呼び出しを 1 行追加して宣言すること。

`fs::link_file` は常にリポジトリの実ファイルを直接指す plain symlink を作る（nix store を経由しないため read-only 問題はそもそも起きない）。`config/zed/settings.json` がこの対象で、Zed で UI 操作（テーマ変更・パネル配置）をすると dotfiles に差分が出る。`claude/settings.json` と同じく、コミット時は意図した変更だけ stage すること。

# Homebrew パッケージ管理

- パッケージの追加・削除は `nix/modules/darwin/homebrew.nix` で管理する
- `default` role の手動 `brew install` は禁止（switch 時に zap される）
- `sub-1` role は手動 `brew install` 許容（cleanup = "none"）。ただし別 PC では復元されないため、再現性が必要なら `homebrew.nix` に追記する
- `homebrew.nix` は role 別 declarative セットの宣言。`Brewfile` は削除済み
- 既存のパッケージのみを対象とする。ユーザーが明示的に依頼していないパッケージを追加しない
- `taps` / `brews` / `casks` / `masApps` の区分を守る
- CLI tool は Homebrew (`homebrew.nix` の `brews`) で管理する（Tier 3 で home-manager の `packages.nix` から完全移行済み）
- PC ローカル専用の cask は `~/.config/dotfiles/homebrew.local.nix`（リポジトリ外配置）で declarative に宣言する。`homebrew.nix` が絶対パスで `builtins.pathExists` + `import` する。用途は「git に追跡させたくないが `default` role の zap から守りたい cask」（例: 特定アカウントの個人用ツール、業務用アプリ）。別 PC では復元されないため、再現性が必要なものは `homebrew.nix` 本体に書くこと。現状 casks のみ対応（brews / taps / masApps の overlay が必要になったら `homebrew.nix` の `local` 解決を拡張する）。nix flake は git tree のみコピーするため、`.gitignore` で除外したリポジトリ内ファイルは flake から不可視になる点に注意（リポジトリ外配置を選んでいる理由）

# zsh スクリプト規約

- シバンは `#!/bin/zsh` を使用する
- 環境変数の参照は `${VAR}` 形式で統一する（`$VAR` ではなく）
- パスの参照には `${HOME}` を使用する（`~` ではなく）

# Claude Code 設定

- `claude/` 配下の静的ファイル（settings.json/CLAUDE.md/AGENTS.md/skills/hooks）は Tier 1 (`setup/link.zsh`) により `~/.claude/` にシンボリックリンクされる
- そのため `~/.claude/` を書き換えるツール (plugin install・skill install・settings の UI 操作) の出力は、別リポジトリで作業していてもこのリポジトリの作業ツリーに着地する。commit 前に対象リポジトリ (dotfiles か案件か) を確認し、意図した変更だけを stage すること
- グローバル指示の SSOT は `claude/rules/` のフラグメント。`claude/AGENTS.md` と `claude/hermes/SOUL.md` は **生成物なので直接編集しない**。編集は `claude/rules/` 側で行い、`agent-rules-build` (実体は `scripts/build-agent-rules.zsh`) を実行して生成物を更新する。生成漏れは `.github/workflows/agent-rules-check.yml` の `--check` が PR で落とす
  - `claude/AGENTS.md` = `core` + `worker`。Claude Code は `claude/CLAUDE.md` の `@AGENTS.md` import で取り込み、Codex CLI は `~/.codex/AGENTS.md` への symlink 経由 (`setup/link.zsh`) で同じファイルを読む
  - `claude/hermes/SOUL.md` = `hermes-identity` + `core` + `orchestrator`。Hermes は `~/.hermes/SOUL.md` への symlink 経由 (`setup/link.zsh`) で読む
  - 結合が要るのは Codex CLI も Hermes も `@AGENTS.md` 形式の import を展開しないため。生成物を working tree に置くのは、Tier 1 の symlink が常に working tree を直接指すため、編集がそのまま即時反映されるようにするため
  - ルールを足すときの行き先: 両者共通なら `core`、実装ワーカー (Claude Code / Codex) 専用なら `worker`、オーケストレーター (Hermes) の委譲の作法なら `orchestrator`
  - **グローバルに置いてよいのは「モデルの既定挙動と異なり、かつコードや履歴から読み取れない」ものだけ**。既定でやることを書き直すと、system prompt と競合して判断を鈍らせる。特定リポジトリでしか効かないものは対象リポジトリの `AGENTS.md`、発火条件が限られるものは skill か on-demand の md (`claude/handoff-policy.md` 等) へ置き、常時ルールには 1 行のポインタだけ残す
  - 実装ワーカー側 (`worker.md`) は Claude Code の system prompt が既に持つ規範 (周辺コードに合わせる / 検証結果を忠実に報告する / メモリ管理 / スコープを勝手に広げない) を重複させない
- `claude/CLAUDE.md` は `@AGENTS.md` 1 行のみの薄い参照ファイル。プロジェクト固有のルールはここに書かない (グローバル指示は `claude/rules/` 側に集約)
- `claude/settings.json` は全プロジェクト共通の設定（パーミッション、プラグイン、フック等）を管理する
- `settings.json` の `enabledPlugins` は `setup/claude-sync.zsh`（Tier 2）が同期するが、**未インストールのものを install するだけ**で既存 plugin は更新しない（`homebrew.onActivation.upgrade = false` と同じ方針）。plugin の更新手順は `nix/README.md`「Claude plugin の定期メンテナンス」を参照
- `claude/skills/` は個人スキル層。`setup/link.zsh`（Tier 1）が `~/.claude/skills` に symlink で展開する。中身は 2 系統に分かれ、配置で判別できる
  - **自作 skill = 相対 symlink**。別リポジトリ `gotomts/skills` が SSOT で、`claude/skills/<name>` は `../../../ghq/github.com/gotomts/skills/<name>` を指す。dotfiles 側に実体は置かない。編集は skills リポの working tree で行い、`~/.claude/skills` から 3 段の symlink を辿って即反映される（再実行不要）。絶対パスにするとユーザー名が公開リポに載るため相対で書く（参照先を固定できるのは `ghq.root = ~/ghq` のため）。clone が無いと dangling になるので、`setup/claude-sync.zsh`（Tier 2）が不在時のみ clone する（既存 clone は pull もチェックアウト変更もしない）
  - **外部由来（vendor）skill = 実体**。中身は編集しない（更新は upstream の手順に従う）。SKILL.md frontmatter の `maintainer: gotomts` は自作の出所マーカーで、skills リポ側の SKILL.md に残る
- `claude/hooks/` は hook スクリプト置き場。`settings.json` の `hooks` から `$HOME/.claude/hooks/<name>` で参照する。ブロック目的の hook は exit code を 0（通過）か 2（ブロック）のみに限定すること。それ以外の非ゼロは Claude Code が non-blocking error として扱い、hook が素通りする
- `claude/hooks/` の symlink は `setup/link.zsh`（Tier 1）でファイル単位に宣言する（ディレクトリごとの symlink にしない）。`~/.claude/hooks/` を実体ディレクトリのまま残し、公開リポジトリに載せられない PC 固有 hook を同じディレクトリに同居させるため。ディレクトリごと symlink すると実体と衝突する事故が旧 home-manager 運用時代に実際に起き、`~/.claude` 配下だけでなく **全 symlink が張られなくなった**（system 側は成功するので気づきにくい）。Tier 1 の `fs::link_file` でも同種の衝突は起き得るため、単一ファイル symlink の運用は維持する。dotfiles に hook を追加したら `setup/link.zsh` に `fs::link_file` 呼び出しを 1 行足すこと
- `claude/mcp-servers.json` は user scope の MCP server を declarative 宣言する。`setup/claude-sync.zsh`（Tier 2）実行時に `~/.claude.json` の `mcpServers` キーに recursive merge する (add-only、claude.ai connector など宣言外エントリは保持)。`~/.claude.json` は Claude Code が動的に書き換える running config (OAuth token を含む) のため symlink 化できない事情への対応
- `~/.codex/config.toml` は Codex / ChatGPT desktop アプリが動的に書き換える running config (絶対パス・marketplaces・plugins・trust_level 等) のため symlink・追跡しない。`codex/config.base.toml` を宣言的 seed とし、`setup/codex-sync.zsh`（Tier 2）が **seed-if-absent** (ファイル不在時のみ cp、既存はアプリ所有として一切触らない) で配置する。Codex の MCP server を宣言的に効かせたい場合は `config.base.toml` に書く (新規 PC のみ反映。既存機は `~/.codex/config.toml` へ手動追記)。`~/.claude.json` と同種の「symlink 化不可な running config」対応
- 外部由来 (vendor) の skill を両 agent で共有する場合は `claude/skills/<name>/` を単一ソースとし、`~/.codex/skills/<name>` を `setup/link.zsh`（Tier 1）で個別 entry symlink する (Codex skills ディレクトリはアプリ管理 skill と同居するため全体 symlink はしない)。外部 skill を install すると `~/.claude/skills` 経由で dotfiles 作業ツリーに着地するので、機微情報を grep 確認のうえ vendor として commit する

# Hermes Agent 設定

Hermes はオーケストレーター役の AI エージェントで、実装は Claude Code へ委譲する。読み込み経路の詳細は `docs/memory-loading.md` を参照。

- グローバル規範の注入口は `~/.hermes/SOUL.md` (`setup/link.zsh` が `claude/hermes/SOUL.md` へ symlink)。**cwd に依存せず必ず system prompt に入る唯一のファイル**であり、他の候補 (`~/AGENTS.md` / `~/.hermes.md`) は cwd がリポジトリへ移ると失効する
- Hermes の context file 探索は「最初に見つかった 1 種類だけ」を読む (`.hermes.md` → `AGENTS.md` の git root→cwd チェーン → `CLAUDE.md` → `.cursorrules`)。チェーンは git root より上へ遡らない
- gateway の cwd はホーム固定 (`terminal.cwd: .` はホームに解決される)。ホームは git リポジトリではないため、**対象リポジトリの AGENTS.md は自動注入されない**。Hermes 側は作業開始時に自分で Read する規約を `claude/rules/orchestrator.md` に持つ
- SOUL.md は Hermes の identity 区画に載り、既定の自己紹介文を置き換える。生成物の先頭に `claude/rules/hermes-identity.md` を含めているのは、この置き換えで自己紹介が失われないようにするため
- `~/.hermes/config.yaml` は Hermes が動的に書き換える running config (channel_prompts / onboarding / telemetry 等) なので symlink・追跡しない。`~/.claude.json` や `~/.codex/config.toml` と同種の扱い
- channel prompt (config.yaml の `discord.channel_prompts`) は SOUL.md より後に注入される上書き層。リポジトリ固有の事実 (checkout パス・origin・既定ブランチ・権限の差分・期限付きの暫定例外) だけを置き、汎用ルールは `claude/rules/orchestrator.md` に集約する

# Nix 環境

`~/.dotfiles/nix/` 配下で nix-darwin + flakes による Homebrew パッケージの宣言的管理を行う（home-manager は Tier 3 で廃止済み、`setup/*.zsh` に移行）。詳細手順は `nix/README.md` を参照。

## 主要コマンド

```sh
cd ~/.dotfiles/nix

# 副作用なしビルド確認 (CI と同じ検証を手元で)
USER=ciuser nix build .#darwinConfigurations.default.system --no-link --impure

# 適用 (sudo 必須、USER=$USER は sudo の env_reset で USER=root になるのを回避、--impure は username 動的解決のため必須)
sudo USER=$USER darwin-rebuild switch --flake .#default --impure

# 直前世代に戻す
sudo darwin-rebuild switch --rollback

# 世代一覧
darwin-rebuild --list-generations
```

## 重要な設計判断

- **`nix.enable = false`**: ローカル PC に Determinate Nix がインストールされている前提。nix-darwin の native Nix 管理は Determinate daemon と競合するため、`nix/darwin.nix` で明示的に無効化している。実験的機能 (nix-command / flakes) は Determinate がデフォルト有効化しているため別途宣言不要
- **PC 名・ユーザー名のリポジトリ非格納**: `darwinConfigurations.default` で output 名を hostname フリーに固定し、`username = builtins.getEnv "USER"` で macOS ローカルアカウント名を実行時解決する。公開リポジトリに PC 名や個人アカウント名を晒さないための設計。`--impure` フラグが必須になる代償と引き換え (S15)
- **`homebrew.onActivation.cleanup = "zap"`**: 宣言外パッケージは Cellar ごと削除する強い管理。宣言外のパッケージが残らないよう破壊的に同期する (`nix/modules/darwin/homebrew.nix` のコメント参照)

## 棚卸 → triage → 翻訳ワークフロー (S10)

macOS の `defaults` 値を `setup/defaults.zsh` に翻訳するための人間 in-the-loop プロセス
（Tier 3 で `nix/modules/darwin/defaults.nix` から移行済み）:

1. `zsh nix/scripts/inventory.zsh` を実行 → `docs/inventory/<hostname>-<date>.md` 生成 (READ-ONLY)
2. 生成された Markdown を開き、各項目に `nix化 / 無視 / 検討` をマーク
3. triage 結果を `setup/defaults.zsh` に `defaults write` 行として翻訳
4. `bats setup/tests/defaults.bats` で検証 → 対象マシンで `zsh setup/defaults.zsh` を適用

triage で「無視」マークした項目は OS デフォルト値が PC 間で異なる可能性があるため、複数 PC で運用する場合は PC 別に再評価する必要がある。

## CI 検証 (`nix-check` workflow)

`.github/workflows/nix-check.yml` で PR ごとに以下を検証する:

- `nix flake check` (構文・型・依存解決)
- `USER=ciuser nix build .#darwinConfigurations.default.system --no-link --impure` (closure ビルド)

`darwin-rebuild switch` の activation 自体は CI 範囲外 (環境差で消耗するため)。実機での `darwin-rebuild build` → `switch` で検証する方針。

# 公開リポジトリでの参照ポリシー

このリポジトリは公開されている。本文・コメント・ドキュメント・コミットメッセージのいずれにも、以下を含めないこと:

- 非公開リポジトリへの参照 (`owner/private-repo` 形式のリポジトリ名・パス・URL)
- 非公開 issue / チケットへの参照 (Linear の `TEAM-123` 形式の issue ID、非公開リポジトリの issue/PR 番号・URL、GitHub Project の内部 ID など)

理由: 公開リポジトリから非公開のプロジェクトや issue を参照すると、その存在や内部識別子が外部に漏れる。

守り方:

- スキルやドキュメントの実例は、架空・汎用のサービス名や ID で書く (実在の非公開プロジェクトを焼き込まない)
- 参照先・出力先のリポジトリはプレースホルダ (例: `{prototype-repo}`) で表し、実体は実行時にユーザーへ確認する
- 公開リポジトリ (このリポジトリ自身 `gotomts/dotfiles` や外部 OSS など) への参照は問題ない
- スキルやドキュメントを書き換える際は、旧成果物 (`references/` の取り残しなど) に非公開参照が残っていないか棚卸しすること

# AGENTS.md の自己更新

- リポジトリに新しいディレクトリやファイルを追加した場合、「リポジトリ構造」セクションを更新すること
- 新しい運用ルールが生じた場合、該当するセクションに追記するか、新しいセクションを作成すること
- 更新はユーザー承認後に行うこと
