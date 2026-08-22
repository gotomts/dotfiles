# Tier 2（明示的スクリプト実行）実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development または
> superpowers:executing-plans でタスク単位に実行すること。チェックボックス (`- [ ]`) で進捗を追う。

**Goal:** `docs/superpowers/specs/2026-08-21-restore-script-management-inventory.md` 6.2/6.3 節で
確定した Tier 2 カテゴリ（言語ランタイム(mise)+corepack／CLI tool の Homebrew 統合／macOS
defaults・IME／PAM Touch ID／Claude plugin・MCP・skills sync／Codex config seed）を、
`setup/link.zsh`（Tier 1、既存 PR #53）に続く独立スクリプト群として実装する。

**Base:** このブランチは `refactor/restore-script-management`（PR #53、Tier 1 実装済み）を base
にした stacked change。PR も同ブランチ向けに作成する（`main` ではない）。

**Architecture:** 既存 `setup/lib/util.zsh` / `setup/lib/fs.zsh` を再利用し、Tier 2 は
`setup/languages.zsh` `setup/defaults.zsh` `setup/pam.zsh` `setup/claude-sync.zsh`
`setup/codex-sync.zsh` の 5 本 + `nix/modules/darwin/homebrew.nix` への CLI tool/font 追加で構成する。
各 zsh script は「本物のコマンド（`defaults`/`mise`/`claude`/`git`/`corepack`）を直接呼ぶ」実装とし、
テストは **PATH に stub 実行ファイルを差し込む** ことで隔離する（bats の `setup()` で
`PATH="${stub_dir}:${PATH}"` を先頭に積む）。stub は呼び出し引数を記録するだけで実際の副作用を
一切起こさない。`$HOME` を要する script（claude-sync/codex-sync）は Tier 1 の `link.bats` と同じ
`HOME=<tmp> run zsh ...` パターンを使う。システムファイル（`/etc/pam.d/sudo_local`）を書く
`pam.zsh` は書き込み先を環境変数でオーバーライド可能にし（本番デフォルトは実パス）、テストは
tmp ファイルを指す。

**Tech Stack:** zsh + bats-core（既存規約と同一）。

**Global Constraints（本計画の実行中、一切行わないこと）:**

- 実機 `$HOME` への適用、実際の `defaults write`/`defaults import`、実際の
  `/etc/pam.d/sudo_local` 書き込み、実際の `mise install`/`brew install`、
  `nix build`/`flake check` 以外の目的での `darwin-rebuild switch`
- `nix build .#darwinConfigurations.default.system --no-link --impure`（closure ビルド、switch
  なし）と `nix flake check --impure` は検証目的で実行してよい（既存 CI と同一コマンド）
- 全スクリプトの動作確認は bats + PATH stub のみで完結させる

**既存 nix モジュール（`packages.nix`/`languages.nix`/`corepack.nix`/`fonts.nix`/`defaults.nix`/
`hitoolbox.nix`/`pam.nix`/`claude.nix`/`codex.nix`/`direnv.nix`）は本計画では削除・変更しない**
（`homebrew.nix` への追記を除く）。Tier 1 実装（PR #53）が `zsh.nix`/`git.nix`/`ssh.nix` を
「新方式の並行構築のみ・削除は実機切替時に別途判断」としたのと同じ前例に倣う。理由:
1) home-manager モジュール削除は `nix/home.nix` の imports 変更を伴い、本計画のスコープ
   （script 新設）と独立した設計判断のため分離する、2) 削除しないことで両経路が併存しても
   （brew 版と nixpkgs 版の同名バイナリが共存するだけで）実害がなく、安全側に倒せる、
   3) 実機の `darwin-rebuild switch` 実行タイミング自体がユーザー判断（本計画スコープ外）
   のため、削除だけ先行させても実質的な効果がない。**この判断は Tier 1 の確立済み前例に基づく
   ものであり、新規の未解決論点ではない。**

---

## Task 1: `nix/modules/darwin/homebrew.nix` — CLI tool・mise・font の追加

**Files:** Modify `nix/modules/darwin/homebrew.nix`

**変更内容（既存 role 分岐・cleanup ポリシー・trust.json ロジックは無変更、追記のみ）:**

- `coreBrews` に追加: `jq` `bats-core` `pwgen` `qpdf` `ffmpeg` `ripgrep` `fzf` `gh` `ghq`
  `lazygit` `lazydocker` `jj`（jujutsu の formula 名）`jjui` `kubectl` `kubectx` `stern` `sops`
  `grpcurl` `uv` `agent-browser` `mise`（言語ランタイム管理、本計画で再導入）
- `defaultOnlyBrews` に追加: `tmux` `mosh`
- `coreCasks` に追加: `font-udev-gothic` `font-jetbrains-mono` `font-sf-mono`
  （3 フォント共通経路に統一。`font-sf-mono` は現状どのファイルにも宣言がなく棚卸しで発見した
  ギャップ — `fonts.nix` のコメントが前提としていた「既に cask 管理」は実際には未宣言だった）
- `devbox` は追加しない（spec 10 節で廃止確定）。`bun`（`oven-sh/bun/bun`）・`pipx`・`fvm`・
  `linear`・`worktrunk`・`herdr`・`hunk`・`crit`・`tailscale` は既存のまま変更しない

- [ ] **Step 1: 追記する**（上記リストを `coreBrews`/`defaultOnlyBrews`/`coreCasks` に追加。
  各エントリに 1 行コメントで「旧 `packages.nix`/`languages.nix` からの Tier 2 移行」を明記）
- [ ] **Step 2: 検証する**

```sh
cd nix
USER=ciuser nix flake check --impure --print-build-logs
USER=ciuser nix build .#darwinConfigurations.default.system --no-link --impure --print-build-logs
```

Expected: 両方とも exit 0（`| head`/`| tail` で隠さず実際の exit code を確認する）

- [ ] **Step 3: commit する**（Task 1 のみ独立 commit。`nix/` 変更は switch を伴わないため
  Global Constraints に抵触しない）

---

## Task 2: `setup/languages.zsh` — mise による言語ランタイム install + corepack enable

**Files:** Create `setup/languages.zsh`, `setup/tests/languages.bats`

**Interfaces:** Consumes `util::*`（既存）。`mise`/`corepack` は PATH 上のコマンドとして呼ぶ
（stub 差し替え可能）。

**仕様（spec 6.2/6.3 節、旧 `install/04〜09_*.zsh` 相当）:**
- 対象: node（`mise use --global node@lts`）、go・ruby・rust・python・dart は `@latest`
  （旧スクリプトの挙動を踏襲。node だけ `lts` にする理由: corepack 同梱の安定性を優先し、
  他言語は旧スクリプトの `@latest` 慣行をそのまま復元する）
- 各言語: `mise install <lang>@<version>` → `mise use --global <lang>@<version>` の順で呼ぶ
- `mise` 未インストール時: `util::error` を出して exit 1（script 内で `brew install` は呼ばない
  — Homebrew は Task 1 で宣言済みなので `darwin-switch` 経由の導入を前提にする）
- corepack: `mise which node` で mise 管理下の node 実行ファイルパスを取得し、その `corepack`
  を `enable --install-directory "${HOME}/.local/share/corepack/bin"` で有効化する
  （`zshenv` の `COREPACK_HOME`/`PATH` 追加は Tier 1 で導入済み、ここでは shim 生成のみ）

- [ ] **Step 1: 失敗するテストを書く**（`setup/tests/languages.bats`）
  - `zsh -n` 構文チェック
  - stub `mise` を PATH に置き、`languages.zsh` 実行後に stub の呼び出しログ
    （`${BATS_TEST_TMPDIR}/mise.log` 等）に `install node@lts` `use --global node@lts` `install
    go@latest` … の 6 言語ぶんが順序通り記録されていることを検証
  - stub `mise which node` が固定パスを返すようにし、そのパス配下の stub `corepack` が
    `enable --install-directory <COREPACK_HOME>/bin` で呼ばれたことを検証
  - `mise` が PATH に無い場合 exit 1 になることを検証
- [ ] **Step 2: 実行し FAIL を確認** — `bats setup/tests/languages.bats`
- [ ] **Step 3: 実装する**
- [ ] **Step 4: 実行し PASS を確認**
- [ ] **Step 5: commit する**

---

## Task 3: `setup/defaults.zsh` — macOS defaults / Dock / IME 宣言の script 化

**Files:** Create `setup/defaults.zsh`, `setup/tests/defaults.bats`

**Interfaces:** Consumes `util::*`。`defaults`/`sudo`（HIToolbox import 用）は PATH 経由（stub 可）。
role 解決は `${DOTFILES_ROLE_FILE:-/etc/dotfiles-role}` を読む（flake.nix の role 解決ロジックと
同じ規約: `#` 始まりの行・空行を無視、最初の content 行を採用、不在/空なら `"default"`、
`default`/`sub-1` 以外は error + exit 1）。

**仕様（`defaults.nix` の 1:1 移植）:**
- Dock（autohide/magnification/mru-spaces/showAppExposeGestureEnabled/wvous-br-corner）、Finder
  11 件、menuExtraClock 3 件、NSGlobalDomain 6 件（native）＋ 12 件
  （CustomUserPreferences."NSGlobalDomain"）、Trackpad 21 件、Finder CustomUserPreferences 6 件、
  ControlCenter 4 件、AppleMultitouchTrackpad 5 件 — 全て `defaults write <domain> <key>
  <-bool|-int|-float|-string> <value>` に変換
- Dock persistent-apps（role 別リスト）: `defaults write com.apple.dock persistent-apps -array`
  でクリアしてから、各アプリパスを
  `<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key>
  <string>PATH</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>`
  形式で `-array-add` する（macOS Dock plist の標準構造）
- Dock persistent-others（Downloads フォルダ、role 非依存）: 同様の `-array-add` で
  `file-type`/`arrangement`/`displayas`/`showas` を反映
- HIToolbox / inputsources: `nix/modules/darwin/hitoolbox.plist` /
  `nix/modules/darwin/inputsources.plist` を **そのまま参照**（複製しない、単一ソース）し、
  `defaults import com.apple.HIToolbox <path>` / `defaults import com.apple.inputsources <path>`
  を呼ぶ
- **バックアップ安全策**: 各 domain を初めて書き込む前に、`${HOME}/.dotfiles-defaults-backup/
  <domain>.plist` が無ければ `defaults export <domain> <backup-path>` で現状のスナップショットを
  1 回だけ取る（2 回目以降の実行はスキップ）。domain が未使用（初回導入等）で export が失敗
  しても script 自体は継続する（`|| true`、warning ログのみ）

- [ ] **Step 1: 失敗するテストを書く**
  - `zsh -n` 構文チェック
  - stub `defaults` で `write com.apple.dock autohide -bool true` 等、代表的な呼び出しが
    ログに記録されることを検証（全 73 件を逐一検証はしない。ドメイン網羅性は「各 domain が
    最低 1 回 write される」ことで確認する）
  - role=`default` と role=`sub-1` で persistent-apps の `-array-add` 呼び出し回数・内容が
    異なることを検証（`DOTFILES_ROLE_FILE` に一時ファイルを指す）
  - 不明な role で exit 1 になることを検証
  - 初回実行で `defaults export com.apple.dock <backup>` が呼ばれ、2 回目実行では
    呼ばれない（バックアップファイルが既に存在するため）ことを検証
  - `defaults import com.apple.HIToolbox <path-to-nix-plist>` が呼ばれることを検証
    （パスが `nix/modules/darwin/hitoolbox.plist` を指していること）
- [ ] **Step 2: FAIL 確認**
- [ ] **Step 3: 実装する**
- [ ] **Step 4: PASS 確認**
- [ ] **Step 5: commit する**

---

## Task 4: `setup/pam.zsh` — Touch ID for sudo (`sudo_local`)

**Files:** Create `setup/pam.zsh`, `setup/tests/pam.bats`

**Interfaces:** 書き込み先は `${SUDO_LOCAL_PATH:-/etc/pam.d/sudo_local}`（テストでオーバーライド）。

**仕様（`pam.nix` の 1:1 移植、`reattach` は Phase A 決定通り含めない）:**
- 期待コンテンツ（1 行、`pam.nix` の `touchIdAuth = true` が生成する内容と同義）:
  `auth       sufficient     pam_tid.so`
- ファイルが無ければヘッダコメント付きで新規作成
- 既存ファイルがあり内容が期待値と一致 → skip（冪等）
- 既存ファイルがあり内容が異なる → `<path>.before-setup` へ退避してから上書き
  （`fs::link_file` の `.before-setup` 退避と同じ思想。退避先が既に存在する場合はエラーで停止し
  上書きしない、`fs::ensure_realfile` の拒否ロジックと同じ）

- [ ] **Step 1: 失敗するテストを書く**
  - `zsh -n` 構文チェック
  - ファイル不在 → 新規作成され期待コンテンツを含む
  - 2 回目実行で冪等（内容不変、`.before-setup` が作られない）
  - 既存内容が異なる場合 `.before-setup` に退避してから期待コンテンツに置き換わる
  - `.before-setup` が既に存在する場合 exit 1 でエラーになり、元ファイルに触れない
- [ ] **Step 2: FAIL 確認**
- [ ] **Step 3: 実装する**
- [ ] **Step 4: PASS 確認**
- [ ] **Step 5: commit する**

---

## Task 5: `setup/claude-sync.zsh` — skills clone / plugin sync / MCP merge

**Files:** Create `setup/claude-sync.zsh`, `setup/tests/claude-sync.bats`

**Interfaces:** `${HOME}` 配下で完結（Tier 1 `link.bats` と同じ `HOME=<tmp> run zsh` パターン）。
`claude`/`git`/`jq` は PATH 経由（`jq` は副作用のない純粋変換なので実バイナリを使ってよい。
`claude`/`git` は stub 化する）。skills clone 先は `${HOME}/ghq/github.com/gotomts/skills`
（`claude.nix` の `cloneSkillsRepo` と同一パス）。

**仕様（`claude.nix` の `cloneSkillsRepo`/`claudePlugins`/`syncClaudeMcpServers` を移植）:**
- skills repo: 既に存在する場合は何もしない（git worktree でなければ警告のみ、削除・pull はしない）。
  不在なら `git clone ssh://git@github.com/gotomts/skills.git <path>`（`GIT_SSH_COMMAND` に
  `BatchMode=yes` 等を付与、失敗しても script 全体は継続）
- plugin sync: `${HOME}/.claude/settings.json` の `enabledPlugins` と `claude plugin list --json`
  の差分（未インストール分）だけ `claude plugin install <id>` する。`settings.json` 不在や
  `plugin list` 失敗時はスキップ（fail-open、nix 版と同じ）
  - `settings.json` は Tier 1 の `setup/link.zsh` が既に symlink 済み前提（本 script では触らない）
- MCP merge: `${DOTFILES_ROOT}/claude/mcp-servers.json` を `${HOME}/.claude.json` の
  `.mcpServers` に `jq` で add-only recursive merge する（宣言外エントリは保持）。
  `~/.claude.json` が無ければ `{}` で新規作成し `chmod 600`

- [ ] **Step 1: 失敗するテストを書く**
  - `zsh -n` 構文チェック
  - skills repo 既存（fake git worktree ディレクトリ）→ `git clone` が呼ばれない
  - skills repo 不在 → stub `git clone` が呼ばれる（呼び出し引数に SSH URL・パスが含まれる）
  - `~/.claude.json` 不在 → 作成され `.mcpServers` に宣言分がマージされる、既存の無関係キー
    （e.g. `oauthAccount`）がある場合はそれを保持したまま merge されることを検証
  - stub `claude plugin list --json` が一部 plugin だけ返すケースで、未インストール分のみ
    `plugin install` が呼ばれることを検証
  - `settings.json` 不在時は plugin sync がスキップされ exit 0 で終わることを検証
- [ ] **Step 2: FAIL 確認**
- [ ] **Step 3: 実装する**
- [ ] **Step 4: PASS 確認**
- [ ] **Step 5: commit する**

---

## Task 6: `setup/codex-sync.zsh` — config.toml seed-if-absent

**Files:** Create `setup/codex-sync.zsh`, `setup/tests/codex-sync.bats`

**Interfaces:** `${HOME}` 配下（`HOME=<tmp> run zsh` パターン）。ソースは
`${DOTFILES_ROOT}/codex/config.base.toml`。

**仕様（`codex.nix` の `syncCodexConfig` を移植）:**
- `${HOME}/.codex/config.toml` が既に存在 → 何もしない（アプリ所有の running config を保護）
- 不在 → `${HOME}/.codex` を作成し `config.base.toml` を `cp`、`chmod 600`
- `config.base.toml` 自体が無ければ warning を出してスキップ（exit 0、fail-open）

- [ ] **Step 1: 失敗するテストを書く**
  - `zsh -n` 構文チェック
  - 不在 → コピーされ中身が一致、`chmod 600` 相当（`-rw-------`）になっている
  - 既存 → 中身が変わらない（book-keeping: 既存ファイルに任意の内容を入れておき、
    実行後も同じ内容であることを assert）
- [ ] **Step 2: FAIL 確認**
- [ ] **Step 3: 実装する**
- [ ] **Step 4: PASS 確認**
- [ ] **Step 5: commit する**

---

## Task 7: CI — `setup/` bats テストの自動実行

**Files:** Create `.github/workflows/setup-check.yml`

**背景（棚卸しで発見したギャップ）:** Tier 1（PR #53）で `setup/tests/*.bats` が追加されたが、
これを実行する CI workflow が存在しない（`nix-check.yml` は `nix/**` のみ、`agent-rules-check.yml`
は `claude/rules/**` のみを対象にしている）。Tier 2 でテスト対象が増える前に、既存の
`agent-rules-check.yml` と同じ構造で bats 実行 workflow を新設する。

- [ ] **Step 1: workflow を書く**
  - トリガー: `pull_request`/`push(main)`、`paths: ['setup/**', '.github/workflows/setup-check.yml']`
  - `runs-on: macos-latest`（bats-core は runner に無いため `brew install bats-core` を実行
    してからテストを走らせる）
  - 実行コマンド: `bats setup/tests/*.bats`
  - concurrency group で同一 ref の重複実行をキャンセル（既存 2 workflow と同一パターン）
- [ ] **Step 2: ローカルで同等コマンドを実行し PASS を確認**
- [ ] **Step 3: commit する**

---

## Task 8: ドキュメント更新

**Files:**
- Modify `setup/README.md`（Tier 2 節を追加。「対象外」節を削除し、実装済みとして記述）
- Modify `AGENTS.md`（root、「リポジトリ構造」節の `setup/` 説明を Tier 1 + Tier 2 に更新）
- Modify `nix/README.md`（Homebrew セクションに Task 1 で追加した CLI tool/font/mise の出自
  一言メモ、「アプリ・パッケージの追加」節の直後に「Tier 2 script との関係」を追記）

- [ ] **Step 1: `setup/README.md` を更新する**（使い方に `zsh setup/languages.zsh` 等 5 本を追記、
  各スクリプトの安全策を 1 行ずつ記載）
- [ ] **Step 2: `AGENTS.md` を更新する**
- [ ] **Step 3: `nix/README.md` を更新する**
- [ ] **Step 4: commit する**

---

## 検証まとめ

| 対象 | コマンド | 期待結果 |
|---|---|---|
| 全 bats テスト（Tier 1 + Tier 2） | `bats setup/tests/*.bats` | 全 PASS |
| 全 zsh 構文 | 各新設ファイルへ `zsh -n <file>` | 全て exit 0 |
| nix 検証（Task 1 のみ） | `USER=ciuser nix flake check --impure` /
  `USER=ciuser nix build .#darwinConfigurations.default.system --no-link --impure` | exit 0 |

`| head`/`| tail` で exit code を隠さず、実際の exit code を確認してから結果を報告する。

## 実装後に行うこと（本計画終了後、承認済み事項）

- 独立レビュー（自分以外の視点、危険パス — `pam.zsh` のシステムファイル書き込み・
  `defaults.zsh` の破壊的 `-array` クリア・`claude-sync.zsh` の `~/.claude.json` merge を重点確認）
- `bats setup/tests/*.bats` と nix 検証を最終実行
- commit（機能単位、Conventional Commits）→ push → PR 作成（base:
  `refactor/restore-script-management`）
- CI green になるまで対応継続

## レビュー可能な判断残り

- なし。本計画の全設計判断（既存 nix モジュール非削除の方針・スクリプトのテスト戦略・
  バックアップ安全策の形）は、Tier 1 の確立済み前例と spec 6 節の確定事項に基づく。
