# リポジトリ構造

このリポジトリは macOS の開発環境を再現するための dotfiles である。

- `CONTEXT.md` — AI エージェント指示の層（グローバル / プロジェクト AGENTS.md・CLAUDE.local.md）を区別する用語集
- `aliase/` — 外部シェルスクリプト（エイリアスから呼び出される）
- `claude/` — Claude Code 設定（`~/.claude/` にシンボリックリンク）
- `claude/skills/` — Claude Code 個人スキル層（`~/.claude/skills` にシンボリックリンク）。自作 skill は `gotomts/skills` が SSOT で相対 symlink だけを置き、外部由来のみ実体を持つ
- `claude/hooks/` — Claude Code hook スクリプト（`~/.claude/hooks/<name>` へファイル単位でシンボリックリンク）
- `claude/mcp-servers.json` — user scope の MCP server 宣言（home-manager activation で `~/.claude.json` に merge）
- `codex/config.base.toml` — Codex CLI の宣言的 seed 設定（`~/.codex/config.toml` 不在時のみ activation が cp する。`~/.codex/config.toml` はアプリ所有の running config なので symlink・追跡しない）
- `config/` — アプリケーション設定（starship, yazi, cmux, ghostty）（`~/.config/` にシンボリックリンク）
- `docs/` — 設計ドキュメント・実装プラン（シンボリックリンク対象外）
- `functions/` — zsh カスタム関数（`~/.functions/` にシンボリックリンク）
- git 設定は nix の `programs.git`（`nix/modules/home/git.nix`）が SSOT で `~/.config/git/config` を生成する。`~/.gitconfig` は nix 非管理の実体ファイルとして `home.activation` で用意し、`git config --global` で書き込むツール（coderabbit の machineId 等）の PC 固有値を隔離する落書き帳として使う（リポジトリには格納しない）
- `.gitignore` — リポジトリ内に偶発的に作られたローカル overlay ファイル（例: `nix/modules/darwin/homebrew.local.nix`）を保険的に除外する
- `gitignore_global` — グローバル gitignore（`~/.gitignore_global` にシンボリックリンク）
- `grip/` — grip 設定（`~/.grip/` にシンボリックリンク）
- `nix/` — nix-darwin + home-manager + flakes による環境構築定義（`darwin-rebuild` から参照される。詳細は `nix/README.md`）
- `ssh/` — SSH 設定（`~/.ssh/` にシンボリックリンク）
- `zsh/` — zsh 補完ファイル（`~/.zsh/` にシンボリックリンク）
- `zshrc` — zsh 設定（`~/.zshrc` にシンボリックリンク）
- `zshenv` — zsh 環境変数（`~/.zshenv` にシンボリックリンク）

# シンボリックリンク管理

シンボリックリンクは home-manager (`nix/modules/home/`) で管理する。新規 dotfiles は `nix/modules/home/` 以下で宣言すること。

# Homebrew パッケージ管理

- パッケージの追加・削除は `nix/modules/darwin/homebrew.nix` で管理する
- `default` role の手動 `brew install` は禁止（switch 時に zap される）
- `sub-1` role は手動 `brew install` 許容（cleanup = "none"）。ただし別 PC では復元されないため、再現性が必要なら `homebrew.nix` に追記する
- `homebrew.nix` は role 別 declarative セットの宣言。`Brewfile` は削除済み
- 既存のパッケージのみを対象とする。ユーザーが明示的に依頼していないパッケージを追加しない
- `taps` / `brews` / `casks` / `masApps` の区分を守る
- nixpkgs 収録済みのパッケージは原則 `nix/modules/home/packages.nix` に置き、Homebrew は nixpkgs 未収録または macOS 特殊事情のあるものに限定する
- PC ローカル専用の cask は `~/.config/dotfiles/homebrew.local.nix`（リポジトリ外配置）で declarative に宣言する。`homebrew.nix` が絶対パスで `builtins.pathExists` + `import` する。用途は「git に追跡させたくないが `default` role の zap から守りたい cask」（例: 特定アカウントの個人用ツール、業務用アプリ）。別 PC では復元されないため、再現性が必要なものは `homebrew.nix` 本体に書くこと。現状 casks のみ対応（brews / taps / masApps の overlay が必要になったら `homebrew.nix` の `local` 解決を拡張する）。nix flake は git tree のみコピーするため、`.gitignore` で除外したリポジトリ内ファイルは flake から不可視になる点に注意（リポジトリ外配置を選んでいる理由）

# zsh スクリプト規約

- シバンは `#!/bin/zsh` を使用する
- 環境変数の参照は `${VAR}` 形式で統一する（`$VAR` ではなく）
- パスの参照には `${HOME}` を使用する（`~` ではなく）

# Claude Code 設定

- `claude/` 配下のファイルは home-manager (`nix/modules/home/claude.nix`) により `~/.claude/` にシンボリックリンクされる
- `claude/AGENTS.md` はグローバル指示のマスター (SSOT)。Claude Code は `claude/CLAUDE.md` の `@AGENTS.md` import で取り込み、Codex CLI は `~/.codex/AGENTS.md` への symlink 経由 (`nix/modules/home/codex.nix`) で同じ AGENTS.md を読む
- `claude/CLAUDE.md` は `@AGENTS.md` 1 行のみの薄い参照ファイル。プロジェクト固有のルールはここに書かない (グローバル指示は `claude/AGENTS.md` 側に集約)
- `claude/settings.json` は全プロジェクト共通の設定（パーミッション、プラグイン、フック等）を管理する
- `settings.json` の `enabledPlugins` は `claude.nix` の `home.activation.claudePlugins` が同期するが、**未インストールのものを install するだけ**で既存 plugin は更新しない（`homebrew.onActivation.upgrade = false` と同じ方針）。plugin の更新手順は `nix/README.md`「Claude plugin の定期メンテナンス」を参照
- `claude/skills/` は個人スキル層。`nix/modules/home/claude.nix` が `~/.claude/skills` に symlink で展開する。中身は 2 系統に分かれ、配置で判別できる
  - **自作 skill = 相対 symlink**。別リポジトリ `gotomts/skills` が SSOT で、`claude/skills/<name>` は `../../../ghq/github.com/gotomts/skills/<name>` を指す。dotfiles 側に実体は置かない。編集は skills リポの working tree で行い、`~/.claude/skills` から 3 段の symlink を辿って即反映される（switch 不要）。絶対パスにするとユーザー名が公開リポに載るため相対で書く（参照先を固定できるのは `ghq.root = ~/ghq` のため）。clone が無いと dangling になるので、`claude.nix` の `home.activation.cloneSkillsRepo` が不在時のみ clone する（既存 clone は pull もチェックアウト変更もしない）
  - **外部由来（vendor）skill = 実体**。中身は編集しない（更新は upstream の手順に従う）。SKILL.md frontmatter の `maintainer: gotomts` は自作の出所マーカーで、skills リポ側の SKILL.md に残る
- `claude/hooks/` は hook スクリプト置き場。`settings.json` の `hooks` から `$HOME/.claude/hooks/<name>` で参照する。ブロック目的の hook は exit code を 0（通過）か 2（ブロック）のみに限定すること。それ以外の非ゼロは Claude Code が non-blocking error として扱い、hook が素通りする
- `claude/hooks/` の symlink は `claude.nix` でファイル単位に宣言する（ディレクトリごとの symlink にしない）。`~/.claude/hooks/` を実体ディレクトリのまま残し、公開リポジトリに載せられない PC 固有 hook を同じディレクトリに同居させるため。ディレクトリごと symlink すると実体と衝突して home-manager の activation が `checkLinkTargets` で止まり、`~/.claude` 配下だけでなく **全 symlink が張られなくなる**（system 側は成功するので気づきにくい）。dotfiles に hook を追加したら `claude.nix` の `home.file` に 1 行足すこと
- `claude/mcp-servers.json` は user scope の MCP server を declarative 宣言する。`darwin-rebuild switch` 時に `nix/modules/home/claude.nix` の `home.activation.syncClaudeMcpServers` が `~/.claude.json` の `mcpServers` キーに recursive merge する (add-only、claude.ai connector など宣言外エントリは保持)。`~/.claude.json` は Claude Code が動的に書き換える running config (OAuth token を含む) のため symlink 化できない事情への対応
- `~/.codex/config.toml` は Codex / ChatGPT desktop アプリが動的に書き換える running config (絶対パス・marketplaces・plugins・trust_level 等) のため symlink・追跡しない。`codex/config.base.toml` を宣言的 seed とし、`nix/modules/home/codex.nix` の `home.activation.syncCodexConfig` が **seed-if-absent** (ファイル不在時のみ cp、既存はアプリ所有として一切触らない) で配置する。Codex の MCP server を宣言的に効かせたい場合は `config.base.toml` に書く (新規 PC のみ反映。既存機は `~/.codex/config.toml` へ手動追記)。`~/.claude.json` と同種の「symlink 化不可な running config」対応
- 外部由来 (vendor) の skill を両 agent で共有する場合は `claude/skills/<name>/` を単一ソースとし、`~/.codex/skills/<name>` を `codex.nix` で個別 entry symlink する (Codex skills ディレクトリはアプリ管理 skill と同居するため全体 symlink はしない)。外部 skill を install すると `~/.claude/skills` 経由で dotfiles 作業ツリーに着地するので、機微情報を grep 確認のうえ vendor として commit する

# Nix 環境

`~/.dotfiles/nix/` 配下で nix-darwin + home-manager + flakes による宣言的環境構築を行う。詳細手順は `nix/README.md` を参照。

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
- **`rtk` overlay**: `flake.nix` の `rtk-src` input から `rustPlatform.buildRustPackage` でビルド。`nix/modules/overlays/rtk.nix` で `pkgs.rtk` として供給され、`home/packages.nix` から参照される

## 棚卸 → triage → 翻訳ワークフロー (S10)

macOS の `defaults` 値を `defaults.nix` に翻訳するための人間 in-the-loop プロセス:

1. `zsh nix/scripts/inventory.zsh` を実行 → `docs/inventory/<hostname>-<date>.md` 生成 (READ-ONLY)
2. 生成された Markdown を開き、各項目に `nix化 / 無視 / 検討` をマーク
3. triage 結果を `nix/modules/darwin/defaults.nix` に翻訳 (`nix/darwin.nix` から import)
4. `nix build` で検証 → `darwin-rebuild switch` で適用

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
