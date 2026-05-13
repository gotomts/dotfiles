# Implementation Plan: 環境構築の Nix 一元化 (Phase A)

- 作成日: 2026-05-02
- 関連 spec: `docs/superpowers/specs/2026-05-02-nix-migration-design.md`
- 対象スコープ: **Phase A のみ**（並存期間。Phase B の Brewfile/setup 削除は別 plan）

## 前提

- spec で確定済の決定事項 11 項目を実装に落とす
- 作業ディレクトリ: `~/.dotfiles/nix/`（新規）と `~/.dotfiles/docs/`（既存）
- 各ステップは独立 PR / sub-issue として並列実装可能（依存関係を守る限り）
- 検証は手元 macOS マシンで実施。CI は対象外（Phase A 範囲では）
- すべての Nix ファイルに対して `nix flake check` が通ることを最低限の品質保証とする

## ステップ一覧（依存関係付き）

```
S1: 棚卸スクリプト ────┐
                      ├─→ S10: nix-darwin defaults.nix
S2: nix/ 雛形 + flake ─┤
                      ├─→ S3..S8 (home-manager 全モジュール)
                      ├─→ S9: nix-darwin homebrew
                      ├─→ S11: nix-darwin sudoers/fonts/pam
                      └─→ S12: 検証 + README + 別 PC 手順
                                  │
                                  └─→ S13: CLAUDE.md 更新
```

S2 が他の全てを blocks する。S1 は S10 のみを blocks（独立並列実装可）。S12 は S3..S11 全てに blocked-by。S13 は S12 に blocked-by。

## ステップ詳細

### S1: 棚卸スクリプト + 初回 triage 文書生成

**目的**: 現マシンの macOS 設定を自動ダンプし、人間 triage 用のチェックリストを `docs/inventory/<hostname>-2026-05-02.md` として生成する。

**変更対象**
- `nix/scripts/inventory.zsh`（新規）
- `docs/inventory/<hostname>-2026-05-02.md`（生成物。コミット対象）

**実装内容**
- `defaults domains` から既知優先ドメイン（`com.apple.dock`, `com.apple.finder`, `com.apple.menuextra.clock`, `NSGlobalDomain`, `com.apple.controlcenter`, `com.apple.universalaccess`, `com.apple.HIToolbox`, `com.apple.screencapture`, `com.apple.trackpad`, `com.apple.AppleMultitouchTrackpad`）を抜粋して `defaults read <domain>` でダンプ
- `mas list` の出力をチェックリスト化
- `launchctl list | grep <user>` の出力を抽出
- `ls /etc/sudoers.d/` の中身ダンプ
- `brew bundle dump --file=/tmp/Brewfile.dump --no-restart` を実行し、現 Brewfile と diff
- `fc-list :family` と `~/Library/Fonts` の比較（自前フォント検出）
- 上記をすべて `docs/inventory/<hostname>-<date>.md` に Markdown チェックリスト形式で出力（`<!-- nix化 / 無視 / 検討 -->` プレースホルダ付き）
- スクリプトのシバンと util.zsh ロードは既存 `setup/util.zsh` の規約に従う（`#!/bin/zsh`、`util::info` など）

**受入条件**
- [ ] `zsh nix/scripts/inventory.zsh` を引数なしで実行すると `docs/inventory/<hostname>-<YYYY-MM-DD>.md` が生成される
- [ ] 生成物に `defaults` の各ドメインのダンプが含まれている
- [ ] 生成物に `mas list` の結果が含まれている
- [ ] 生成物に `brew bundle dump` 差分が含まれている
- [ ] チェックリスト形式で各項目に `<!-- nix化 / 無視 / 検討 -->` が付いている
- [ ] スクリプトが `set -e` 相当の挙動でエラー時に止まる
- [ ] スクリプトに最低限のテスト（`bats-core` で `--help` と空ディレクトリ実行）

**依存**: なし（並列実装可能）
**blocks**: S10

### S2: `nix/` 雛形 + `flake.nix` + `lib/mkHost.nix`

**目的**: nix の基盤ディレクトリ構造を作り、最小限の flake で `darwin-rebuild build` がエラーなしで通る状態にする。

**変更対象**
- `nix/flake.nix`（新規）
- `nix/flake.lock`（生成）
- `nix/README.md`（新規）
- `nix/lib/mkHost.nix`（新規）
- `nix/hosts/<hostname>/default.nix`（新規。ホスト名は実装時に確定）
- `nix/hosts/<hostname>/darwin.nix`（新規。空モジュール）
- `nix/hosts/<hostname>/home.nix`（新規。空モジュール）

**実装内容**
- `flake.nix`: `nixpkgs`, `nix-darwin`, `home-manager`, `rtk-src` の 4 input を宣言（rtk-src は実装時にリポジトリ URL を確定）
- `lib/mkHost.nix`: `{ hostname, system, username }` を受け取り `darwin.lib.darwinSystem` を返すヘルパー
- `hosts/<hostname>/default.nix`: `darwin.nix` と `home.nix` を import するだけのスタブ
- `nix/README.md`: 「`darwin-rebuild build --flake .#<hostname>` の手順」「`flake.lock` の更新コマンド」「ホスト追加手順」を記述

**受入条件**
- [ ] `cd nix && nix flake check` がエラーなしで通る
- [ ] `darwin-rebuild build --flake .#<hostname>` がエラーなしで完了する（空モジュールでも構成は成立する）
- [ ] `flake.lock` がコミットされている
- [ ] README に最低限の運用手順が記載されている

**依存**: なし
**blocks**: S3, S4, S5, S6, S7, S8, S9, S10, S11

### S3: home-manager `packages.nix`（CLI ツール群移植）

**目的**: Brewfile の brew セクション（CLI ツール）を `home.packages` に翻訳する。

**変更対象**
- `nix/modules/home/packages.nix`（新規）
- `nix/hosts/<hostname>/home.nix`（import 追加）

**実装内容**
- 既存 Brewfile の以下セクションを `home.packages = with pkgs; [ ... ]` で宣言:
  - `# Utilities`: jq, bats-core, pwgen, qpdf 等
  - `# Shell & Terminal`: fzf
  - `# Git & Version Control`: gh, ghq, lazygit, lazydocker, worktrunk
  - `# Cloud & DevOps`: kubectl, kubectx, stern, sops
  - `# Languages & Runtimes`: bun, fvm, pipx
  - `# Network & API`: grpcurl, tailscale
  - `# Task Management`: linear (schpet/tap)
- nixpkgs に存在しないパッケージ（`schpet/tap/linear`, `leoafarias/fvm/fvm`, `manaflow-ai/cmux/cmux`）は **コメントで「Brewfile 残置」と明示** し、`darwin/homebrew.nix` 側で `brews = [...]` として管理
- ビルド系（autoconf, automake, pkg-config 等）は home.packages にも入れず、必要時に `nix shell` で対応する旨をコメント

**受入条件**
- [ ] `nix flake check` 成功
- [ ] `darwin-rebuild build --flake .#<host>` 成功
- [ ] 生成された profile に `which jq`, `which gh` 等が `~/.nix-profile/bin/` 配下を返す
- [ ] nixpkgs 不在パッケージは `darwin/homebrew.nix` 側に残置されコメントで根拠が記述されている

**依存**: S2
**blocks**: なし

### S4: home-manager `zsh.nix`（programs.zsh + oh-my-zsh 宣言化）

**目的**: 既存 `zshrc`, `zshenv`, `aliases`, `functions/` を `programs.zsh` モジュールに分解移植する。

**変更対象**
- `nix/modules/home/zsh.nix`（新規）
- `nix/hosts/<hostname>/home.nix`（import 追加）

**実装内容**
- `programs.zsh.enable = true`
- `programs.zsh.oh-my-zsh.enable = true` + 必要プラグインの宣言（zsh-autosuggestions 等を `plugins = [ ... ]` で）
- 既存 `aliases` ファイルの内容を `programs.zsh.shellAliases` 属性セットに移植
- 既存 `zshrc` の独自設定（PATH 操作、関数 source、completion 設定等）を `programs.zsh.initExtra` に移植
- `functions/fzf-history` は `home.file."./.functions/fzf-history".source` で symlink、`initExtra` 内で `source` 呼び出し
- `aliase/get-gke-credentials.sh` も同様 symlink
- 既存 `zshenv` の内容を `programs.zsh.envExtra` に移植

**受入条件**
- [ ] `nix flake check` 成功
- [ ] `darwin-rebuild switch` 後に新しい zsh セッションを開いて、`alias` コマンドで既存 alias が全て出る
- [ ] `compinit` が機能する
- [ ] `fzf-history` 関数が実行できる
- [ ] 既存 zshrc/zshenv/aliases ファイルは Phase A 期間中は残す（home-manager が生成する `~/.zshrc` を優先するため、 dotfiles の zshrc symlink は競合しないよう home-manager 側でハンドリング）
- [ ] 生成された `~/.zshrc` を新規シェルで `source` した際にエラーゼロ

**依存**: S2
**blocks**: なし

### S5: home-manager `git.nix` / `starship.nix` / `yazi.nix` / `ssh.nix`

**目的**: 設定ファイル系の宣言化をまとめて行う（量が小さい複数モジュールの集約）。

**変更対象**
- `nix/modules/home/git.nix`（新規）
- `nix/modules/home/starship.nix`（新規）
- `nix/modules/home/yazi.nix`（新規）
- `nix/modules/home/ssh.nix`（新規）
- `nix/hosts/<hostname>/home.nix`（import 追加）

**実装内容**
- **git.nix**: `programs.git.{enable, userName, userEmail, extraConfig, ignores}` で `gitconfig` と `gitignore_global` を移植。`gitmessage` は `programs.git.extraConfig.commit.template`
- **starship.nix**: `programs.starship.enable = true` + `settings = (builtins.fromTOML (builtins.readFile ../../../config/starship/starship.toml))` で既存設定をそのまま読み込む
- **yazi.nix**: `programs.yazi.enable = true` + `settings`/`keymap` を同様に TOML 読み込み
- **ssh.nix**: `home.file.".ssh/config".source = ../../../ssh/config`（鍵ファイルは対象外）

**受入条件**
- [ ] `nix flake check` 成功
- [ ] `git config --global --get user.email` が `mh.goto.web@gmail.com` を返す
- [ ] `starship` プロンプトが期待通り表示される
- [ ] `yazi` 起動時にカスタム keymap が効く
- [ ] `ssh -G <host>` で `~/.ssh/config` の設定が反映されている

**依存**: S2
**blocks**: なし

### S6: home-manager `claude.nix`（plugin sync activation）

**目的**: `~/.claude/{agents,skills,settings.json,...}` を home-manager 経由で symlink し、`enabledPlugins` を読んで `claude plugin install/update` を activation script で実行する。

**変更対象**
- `nix/modules/home/claude.nix`（新規）
- `nix/hosts/<hostname>/home.nix`（import 追加）

**実装内容**
- `home.file.".claude/agents".source = ../../../claude/agents` を再帰的に
- `home.file.".claude/skills".source = ../../../claude/skills` を再帰的に
- `home.file.".claude/settings.json".source = ../../../claude/settings.json`
- `home.file.".claude/RTK.md".source = ../../../claude/RTK.md`
- `home.activation.claudePlugins = lib.hm.dag.entryAfter ["writeBoundary"] ''...''` で:
  - `claude plugin marketplace update`（失敗しても続行）
  - `jq -r '.enabledPlugins // {} | keys[]' ~/.claude/settings.json` をループ
  - 各 plugin に対し `claude plugin install` または `claude plugin update`
  - 失敗しても他のプラグインは続行（warning ログ）

**受入条件**
- [ ] `nix flake check` 成功
- [ ] `darwin-rebuild switch` 後 `~/.claude/agents/<some-agent>.md` が dotfiles リポジトリのファイルへの symlink になっている
- [ ] `claude plugin list` で `enabledPlugins` 全てがインストール済み
- [ ] activation 実行ログに plugin 同期の進捗が出る
- [ ] 既存 `setup/install/10_claude.zsh` の sudoers 編集 (pmset NOPASSWD) は **このモジュールの対象外**（S11 で扱う）

**依存**: S2
**blocks**: なし

### S7: home-manager `languages.nix`（言語ツールチェーン）

**目的**: mise 経由の言語ランタイムと cargo install / pipx で入れていたツールを `home.packages` 経由に置換。

**変更対象**
- `nix/modules/home/languages.nix`（新規）
- `nix/hosts/<hostname>/home.nix`（import 追加）

**実装内容**
- 言語ランタイム:
  - Node.js: `nodejs_20`, `nodejs_22` 等を `home.packages`（複数バージョン併存はラッパーで切替）
  - Go: `go`
  - Ruby: `ruby_3_3` 等
  - Rust: `fenix` overlay 採用 or `rustc` + `cargo` + `rust-analyzer` + `rustfmt` + `clippy` を home.packages
  - Python: `python311` または `python312`
  - Dart: `dart`（fvm は Brewfile 残置）
- cargo / pip ツール:
  - `cargo-nextest`, `cargo-watch` を nixpkgs から
  - `poetry` を nixpkgs から
  - `grip` を nixpkgs から（pipx 不要に）
- mise は **`darwin/homebrew.nix` から外す**（このステップで変更を予告コメント）

**受入条件**
- [ ] `nix flake check` 成功
- [ ] `which node`, `which go`, `which rustc`, `which python3` が `~/.nix-profile/bin/` 配下を返す
- [ ] `cargo nextest --version`, `cargo watch --version` 動作
- [ ] `poetry --version`, `grip --version` 動作
- [ ] `which mise` が解決しない or `homebrew.nix` 側で「移行中残置」コメント付きの場合のみ残る

**依存**: S2
**blocks**: なし

### S8: rtk overlay（flake input + buildRustPackage）

**目的**: `rtk` を flake input から `rustPlatform.buildRustPackage` でビルドし、`pkgs.rtk` として供給。Brewfile の `# AI Tooling` セクションから `brew 'rtk'` を外す前提を作る。

**変更対象**
- `nix/modules/overlays/rtk.nix`（新規）
- `nix/flake.nix`（`rtk-src` input 確定 + overlay 適用）
- `nix/modules/home/packages.nix`（`rtk` を追加）

**実装内容**
- `rtk-src` の URL を実装時に確定（GitHub の rtk リポジトリ）
- overlay で `final.rtk = prev.rustPlatform.buildRustPackage { ... }` を定義
- `cargoLock.lockFile` で再現性確保
- `pname = "rtk"`, `version = inputs.rtk-src.shortRev` で flake 評価時のリビジョンを反映
- meta 情報（`description`, `homepage`, `license`, `mainProgram = "rtk"`）も定義

**受入条件**
- [ ] `nix flake check` 成功
- [ ] `darwin-rebuild switch` 後 `which rtk` が `~/.nix-profile/bin/rtk` を返す
- [ ] `rtk --version` が動作
- [ ] `rtk gain` 等のメタコマンドが動作
- [ ] flake.lock に `rtk-src` がロックされ、再現性確保

**依存**: S2
**blocks**: なし

### S9: nix-darwin `homebrew.nix`（cask + mas + 例外 brew）

**目的**: Brewfile の cask / mas / 例外 brew（nixpkgs 未収録）を `homebrew.{casks, masApps, brews, taps}` で宣言する。

**変更対象**
- `nix/modules/darwin/homebrew.nix`（新規）
- `nix/hosts/<hostname>/darwin.nix`（import 追加）

**実装内容**
- `homebrew.enable = true`
- `homebrew.onActivation.{autoUpdate, cleanup} = "zap"` 等の挙動を選択
- `homebrew.taps = [ "leoafarias/fvm", "manaflow-ai/cmux", "oven-sh/bun", "schpet/tap" ]`（rtk が flake input になったので不要なら外す）
- `homebrew.casks`: 現 Brewfile の cask 全 25 個
- `homebrew.masApps = { LINE = 539883307; Magnet = 441258766; ... }`
- `homebrew.brews`: nixpkgs に無いもの（`leoafarias/fvm/fvm`, `manaflow-ai/cmux/cmux` 等）

**受入条件**
- [ ] `nix flake check` 成功
- [ ] `darwin-rebuild switch` で全 cask がインストール済みになる
- [ ] `mas list` で 5 アプリすべてがリストされる
- [ ] `homebrew.brews` に残したパッケージは正常に動作
- [ ] 既存 `Brewfile` から `mise` と `rtk` が外れることが S7 / S8 完了後に成立

**依存**: S2
**blocks**: なし

### S10: nix-darwin `defaults.nix`（棚卸 triage 翻訳）

**目的**: S1 で生成 + ユーザー triage 済みの `docs/inventory/<host>-<date>.md` を `system.defaults.*` に翻訳する。

**変更対象**
- `nix/modules/darwin/defaults.nix`（新規）
- `nix/hosts/<hostname>/darwin.nix`（import 追加）
- `docs/inventory/<host>-<date>.md`（triage マーク済みであること。**人間レビューが先行している前提**）

**実装内容**
- triage で「Nix 化」マークされた項目を `system.defaults.{NSGlobalDomain,dock,finder,...}` に翻訳
- nix-darwin が直接サポートしない key は `system.defaults.NSGlobalDomain.<key>` の generic スロット、それでも書けないものは `system.activationScripts.postUserActivation.text` で `defaults write` を直接呼ぶ
- 翻訳できなかった項目（triage で「無視」「検討」マーク）は `defaults.nix` の **コメントで列挙** し、なぜ無視したかを記録

**受入条件**
- [ ] `nix flake check` 成功
- [ ] `darwin-rebuild switch` 後に `defaults read com.apple.dock` 等で triage で「Nix 化」した値が反映されている
- [ ] 翻訳しなかった項目の根拠が `defaults.nix` のコメントに残っている
- [ ] `system.activationScripts` を使った場合、その内容が冪等（複数回実行しても問題なし）

**依存**: S1, S2
**blocks**: なし

### S11: nix-darwin `sudoers.nix` / `fonts.nix` / `pam.nix`

**目的**: 小粒の nix-darwin モジュールをまとめて。

**変更対象**
- `nix/modules/darwin/sudoers.nix`（新規）
- `nix/modules/darwin/fonts.nix`（新規）
- `nix/modules/darwin/pam.nix`（新規）
- `nix/hosts/<hostname>/darwin.nix`（import 追加）

**実装内容**
- **sudoers.nix**: `security.sudo.extraRules = [{ users = ["goto"]; commands = [{ command = "/usr/bin/pmset"; options = ["NOPASSWD"]; }]; }]` で `setup/install/10_claude.zsh` の pmset NOPASSWD を再現
- **fonts.nix**: `fonts.packages = with pkgs; [ sf-mono ]`（nixpkgs に sf-mono が無ければ Brewfile 残置）。または cask 経由のままで `homebrew.casks` に残す判断
- **pam.nix**: `security.pam.services.sudo_local.touchIdAuth = true`（新規宣言。棚卸で見つかった場合のみ）

**受入条件**
- [ ] `nix flake check` 成功
- [ ] `sudo pmset` がパスワードなしで実行できる
- [ ] `fc-list :family | grep "SF Mono"` が結果を返す
- [ ] Touch ID for sudo が機能する（棚卸で有効化が望ましいと判明した場合）

**依存**: S2
**blocks**: なし

### S12: 検証 + README + 別 PC 手順

**目的**: 全モジュール統合後の最終検証を行い、`nix/README.md` を別 PC セットアップ手順を含めて充実させる。

**変更対象**
- `nix/README.md`（更新）
- `docs/inventory/<host>-2026-05-02.md`（baseline diff の結果を追記）

**実装内容**
- `darwin-rebuild build --flake .#<host>` 実行（switch せず）
- `nvd diff /run/current-system result` で差分確認
- `darwin-rebuild switch --flake .#<host>` 適用
- 適用後、棚卸 baseline `docs/inventory/baseline-com.apple.dock.txt` 等と `defaults read` 出力を diff
- `which jq`, `which rtk`, `which node` 等の確認
- `claude plugin list` の確認
- README に以下を追記:
  - 別 PC への展開手順（Command Line Tools → Nix インストール → flake clone → `darwin-rebuild switch`）
  - トラブルシューティング（flake.lock が壊れた場合の復旧、rollback コマンド）
  - `flake.lock` 更新運用（`nix flake update` の頻度方針）

**受入条件**
- [ ] `darwin-rebuild build --flake .#<host>` がエラーなしで完了
- [ ] `nvd diff` 出力が PR コメントに記録されている
- [ ] `darwin-rebuild switch` 適用後、shellと CLI ツールが期待通り動作
- [ ] 別 PC 手順が README に記載されている
- [ ] baseline diff の結果が triage で「無視」とマークされた項目以外で完全一致している（一致しない場合はその根拠を inventory に追記）

**依存**: S3, S4, S5, S6, S7, S8, S9, S10, S11
**blocks**: S13

### S13: CLAUDE.md 更新

**目的**: dotfiles のグローバルドキュメントを Phase A の現実に合わせる。

**変更対象**
- `CLAUDE.md`（既存。リポジトリ root）

**実装内容**
- 「リポジトリ構造」セクションに `nix/` を追加
- 「Brewfile」セクションに「Phase B で削除予定。Phase A 期間中は読み取り専用バックアップとして残す」注記
- 「シンボリックリンク管理」セクションに「home-manager がメインで管理。`setup.zsh` は Phase B で削除予定」注記
- 新規セクション「Nix 環境」を追加:
  - flake 構造の概要
  - `darwin-rebuild` 運用コマンド
  - 棚卸 → triage → 翻訳ワークフロー
  - 別 PC への展開ポインタ（`nix/README.md` 参照）

**受入条件**
- [ ] `CLAUDE.md` の差分が Phase A の構造変化を全てカバー
- [ ] `nix/README.md` への参照が貼られている
- [ ] 既存セクション間の整合性（`Brewfile` セクションが「現在の事実」と齟齬しない）

**依存**: S12
**blocks**: なし

## 横断的な作業ルール

- 各ステップは **独立 worktree** で実装し、独立 PR を出す（`feature-team` の Phase 4-A 並列開発に対応）
- 各 PR は `nix flake check` と `darwin-rebuild build`（必要に応じ）が通ることを最低ライン
- ブランチ命名: `feature/nix-migration-s<step-number>-<slug>` 例: `feature/nix-migration-s2-flake-skeleton`
- レビュー観点: quality 必須、`security`（sudoers / pam を扱う S11）、`performance`（該当なし）

## リスクと検証ステップ

| リスク | 検証 |
|---|---|
| 棚卸で漏れがある | S12 で baseline diff を取って漏れを検出 |
| `home.activation` で claude plugin が壊れる | `lib.mkAfter` で末尾置き、失敗しても他は通す（S6 受入条件に明記） |
| `darwin-rebuild switch` が macOS 本体に副作用 | switch 前に `build` で停止確認、ロールバック手順を README に記載 |
| 並列 PR の merge 順序ミス | S2 を最初にマージ、他は S2 に rebase してから |
| `defaults` の key 名間違い | `darwin-rebuild build` が catch するキーは可視、catch しないキーは S12 baseline diff で検出 |

## Phase B（参考）

このプランの範囲外。Phase A 完了後、運用安定を確認してから別 plan として:
- `Brewfile` 削除
- `setup/install/` 削除
- `setup/setup.zsh` 削除
- `CLAUDE.md` の関連セクション削除
- `nix/` の root 昇格検討

## 完了の定義（Phase A）

- [ ] S1〜S13 全ステップが完了
- [ ] `darwin-rebuild switch --flake .#<host>` が新規セッションで成功
- [ ] 棚卸 baseline と switch 後の `defaults read` の diff がゼロ（triage 「無視」項目を除く）
- [ ] PR がマージされ main の `CLAUDE.md` に Nix 環境セクションが含まれる
- [ ] 別 PC で `darwin-rebuild` 初回実行のドライランが README 通りに進む（実機なくても手順 trace で検証）
