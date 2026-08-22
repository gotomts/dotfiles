# 復元スコープ確定のための棚卸し表 — Nix 管理 → 旧スクリプト管理

**目的**: `refactor/restore-script-management` ブランチでの復元作業に着手する前に、現行 Nix 管理機能と
Nix 移行前（旧スクリプト管理）の機能を 1 対 1 で対応付け、復元可否・必要作業・失われる/変わる挙動を
明らかにする。**このドキュメント自体は復元範囲を決定しない。** 決定は棚卸し結果を見た上で別途行う。

**ステータス**: レビュー待ち（実装未着手）。実機適用・破壊的操作は一切行っていない。

## 1. 調査手法

- `git log --reverse` で最古コミットから追い、Nix 移行の統合コミット `b6fa354`
  (`feat(nix): 環境構築 Nix 一元化 (Phase A) を統合 (KISSA-20) (#18)`) の**親コミット**の
  ツリーを「旧スクリプト管理方式」の実体として採用した（移行直前のスナップショット）。
- 旧方式のファイル本体（`setup/setup.zsh` / `setup/util.zsh` / `setup/install.zsh` /
  `setup/install/0N_*.zsh` / `Brewfile`）を `git show b6fa354^1:<path>` で全文確認した。
- 現行方式は `nix/darwin.nix` / `nix/home.nix` / `nix/modules/{darwin,home}/*.nix`
  （計 20 ファイル、約 1550 行）を全文確認した。
- 既存の移行設計書 `docs/superpowers/specs/2026-05-02-nix-migration-design.md`
  （「現状の管理範囲」「決定事項」節）を突き合わせ資料として参照した。

## 2. 旧スクリプト管理方式の実体（サマリ）

| コンポーネント | 役割 |
|---|---|
| `setup/setup.zsh` | dotfiles ルートの各ファイル/ディレクトリを `ln -sfv` でループ symlink。`claude/` `config/` `ssh/` は個別のネストしたループで symlink。最後に `install.zsh` を `source` |
| `setup/util.zsh` | `util::info/warning/error/confirm` ログ・確認ヘルパー |
| `setup/install.zsh` | Command Line Tools 前提チェック → `brew bundle --file Brewfile` (要確認プロンプト) → `brew cleanup` → `setup/install/` 配下を番号順に対話的に実行 |
| `setup/install/03_oh_my_zsh.zsh` | oh-my-zsh 本体 + zsh-autosuggestions を `curl`/`git clone` で導入 |
| `setup/install/04〜09_*.zsh` | mise で node/go/ruby/rust/python/dart をインストール、`mise use --global` で最新固定、npm -g / pipx / cargo install / gem install / dart pub global の追加ツールを個別実行 |
| `setup/install/10_claude.zsh` | pmset NOPASSWD sudoers 追加、`claude/skills/*` を個別 symlink、`settings.json` symlink、`enabledPlugins` を jq で読んで `claude plugin install/update` |
| `setup/install/11_appearance.zsh` | `brew install starship yazi fd`（**Brewfile 非宣言、命令的 install**）、pipx で grip、`config/starship` `config/yazi` `config/cmux` を symlink |
| `setup/install/12_linear.zsh` | linear CLI 認証確認、`gh auth refresh -s project` |
| `Brewfile` | tap 4 / brew 25 / cask 25 / mas 5（role 分けなし、単一プロファイル） |

**性質**: 冪等性は個別スクリプトの `if` 文任せ（一部冪等でない、例: `11_appearance.zsh` の cargo/gem
系はガードなし再実行）。宣言外パッケージの自動削除機構なし。バージョン固定機構なし（`mise use --global
X@latest` は実行時点の最新を都度取得、Brewfile も latest 追従）。実行は **人間が対話的に `install.zsh`
を都度たたく前提**で、CI 検証は存在しなかった。

## 3. 対応表

凡例: 復元可否 — 🟢可（工数小〜中） / 🟡条件付き可（設計判断・作り直しが必要） / 🔴不可（旧方式に等価物なし、
新規スクリプト実装が必須）

> **注記（2026-08-22 追記）**: 本節は D 案（6 節）確定前の初期棚卸しであり、「script で完全代替する場合」を
> 前提に書かれている。Homebrew（3.2 節）は D 案確定により Nix（`nix-darwin`/`homebrew.nix`）に無変更で
> 残ることが決まったため、3.2 節の「role 分けの再設計」「`--cleanup --force` の要否」等の課題は**発生しない
> （解消済み）**。3.2 節は「A/B/C 案を選んだ場合の参考」として残す。

### 3.1 symlink 配置（dotfiles → `$HOME`）

| 現行 Nix 実装 | 旧実装 | 復元可否 | 必要な作業 | 失う/変わる挙動 |
|---|---|---|---|---|
| `zsh.nix` `git.nix` `ssh.nix` `misc.nix` 等、**ファイル単位**の `home.file` symlink | `setup.zsh` の `ln -sfv` ループ、**ディレクトリ単位**（`~/.zsh` → `dotfiles/zsh` 等） | 🟡 | 現行ファイル一覧に合わせて `setup.zsh` を書き直す（当時存在しなかった `config/starship` `config/yazi` `config/zed` `config/cmux` `claude/rules/` `claude/hermes/` `codex/config.base.toml` 等を追加） | **ディレクトリ symlink 方式への回帰は過去の障害の再発条件**。過去に stale なディレクトリ symlink が home-manager の `checkLinkTargets` に引っかかり、`~/.claude` 配下だけでなく全 symlink が張られなくなる事故が実際に起きており（`AGENTS.md` の「hooks はファイル単位で symlink する」節に経緯が明記されている）、ファイル単位運用はその再発防止策として確立された。script 側にも同種の衝突（`unlink` 対象が symlink でなく実体ディレクトリだった場合の扱いなど）が起き得るため、旧方式へ単純回帰すると保護が失われる |
| `zed.nix` `ghostty.nix` の `mkOutOfStoreSymlink`（nix store を経由しない書き込み可能 symlink） | 通常の `ln -sfv`（そもそも nix store を経由しないので read-only 制約が存在しない） | 🟢 | そのまま `ln -sfv` に戻すだけ | 挙動差分なし。むしろ script 方式ではこの問題自体が発生しない |
| `claude.nix` の `.claude/settings.json` `.claude/CLAUDE.md` `.claude/AGENTS.md` `.claude/skills` symlink | `setup.zsh` の `claude/` ループ（ディレクトリ単位一括 symlink）+ `10_claude.zsh` の skills 個別 symlink（**二重管理気味**） | 🟢 | `setup.zsh` 側のループのみに統一し `10_claude.zsh` の重複ロジックは削除 | 挙動はほぼ同等。ただし現行は「自作 skill = `gotomts/skills` への相対 symlink、vendor skill = 実体」という 2 層構造（`AGENTS.md` の「Claude Code 設定」節参照）。旧方式にはこの区別がなく、`gotomts/skills` clone の自動化（`cloneSkillsRepo` activation）も存在しない。SSH clone 失敗時のフォールバック文言も script 側で作り直す必要 |
| `~/.claude.json` への MCP servers merge（`jq` recursive merge、add-only） | **等価物なし** | 🔴 | 新規スクリプト実装が必要（running config を壊さずマージする jq ロジックを script として独立させる） | 復元ではなく新規開発。`~/.claude.json` は OAuth token を含む running config のため、旧方式の「ディレクトリ symlink」的発想では扱えない |
| `~/.codex/config.toml` の seed-if-absent | **等価物なし**（Codex CLI 自体が Nix 移行後に追加されたツール） | 🔴 | 新規スクリプト実装 | 同上（running config を symlink できない事情は `~/.claude.json` と同じ） |
| `~/.hermes/SOUL.md` symlink | **等価物なし**（Hermes Agent は Nix 移行後に導入） | 🔴 | 新規 | Hermes 運用自体を維持するなら script 側の新規実装が必須 |
| `~/.gitconfig` を書き込み可能な空実体として用意する activation | 旧構成では `~/.gitconfig` は `dotfiles/gitconfig` への直接 symlink（read-only 問題は当時存在せず） | 🟢 | `ln -sfv` に戻すだけ | **git.nix のコメントが明記する退避ロジック**（CodeRabbit 等が書き込む machineId 用の隔離）が不要になる。副作用: 3rd party ツールが `~/.gitconfig` に書いた PC 固有値がリポジトリ管理下に戻る（旧方式はそもそもこの問題を認識していなかった） |

### 3.2 Homebrew パッケージ管理

| 現行 Nix 実装 | 旧実装 | 復元可否 | 必要な作業 | 失う/変わる挙動 |
|---|---|---|---|---|
| `homebrew.nix`: `darwin-rebuild switch` 一発で `brew bundle` 相当を自動実行、role 別 (`default`/`sub-1`) セット、`cleanup = "zap"`（宣言外を Cellar ごと強制削除）/ `"none"`、tap trust.json 自動生成 | `Brewfile`（role 分けなし単一セット）+ `install.zsh` の対話プロンプトで `brew bundle --file Brewfile` → `brew cleanup`（**`--cleanup` オプションなし = 宣言外パッケージは削除されない**） | 🟡 | role 分けを Brewfile 2 本立て or 環境変数分岐で再設計（**旧方式に前例なし、新規設計判断が必要**）。非対話 `--cleanup --force` 相当を script に明示追加するか、削除しない旧挙動を許容するかも要判断 | **「宣言してから入れる」強制力の喪失**。現行は `brew install` 直打ちが次回 switch で自動的に消される設計（AGENTS.md 「`default` role の手動 `brew install` は禁止」）。script 方式は `brew bundle` の非破壊的マージのみで、手動 install パッケージが残り続ける。tap trust の自動配置（Homebrew 6.0+ の `HOMEBREW_REQUIRE_TAP_TRUST` 対応）も新規実装が必要（旧 Brewfile 時代はこの仕組み自体が存在しなかった） |
| Dock 左右アイコン (`persistent-apps`/`persistent-others`) の宣言化、role 別 | **等価物なし**（手動 Dock 操作前提） | 🔴 | 新規（`defaults write com.apple.dock persistent-apps -array-add …` 相当を script 化） | 復元ではなく新規。実装しないなら「Dock は各 PC で手動設定」に戻る |

### 3.3 言語ランタイム

| 現行 Nix 実装 | 旧実装 | 復元可否 | 必要な作業 | 失う/変わる挙動 |
|---|---|---|---|---|
| `languages.nix`: `nodejs_24` `go` `ruby_3_4` `rustc/cargo/rust-analyzer/rustfmt/clippy` `python313` `poetry` `dart` を nixpkgs 版で固定導入 | `install/04〜09_*.zsh`: **mise** で `mise install X@latest` → `mise use --global X@latest`（実行時点の最新を都度取得、バージョン固定なし） | 🟡 | mise 導入スクリプトの復活。**AGENTS.md には現状「mise は S7 で完全排除」の決定が記録されている（`corepack.nix` のコメント等に残存）。mise 再導入はこの決定を明示的に覆す判断であり、単純な「復元」ではない** | Nix 版は `nixpkgs` の pin されたバージョンで固定される（`flake.lock` 経由の再現性）。mise 版は毎回 `@latest` を取得するため、**2 台の PC で同じコマンドを実行しても異なるバージョンが入り得る**（旧移行 spec の「課題」節が指摘していた再現性問題そのもの） |
| `corepack.nix`: `nodejs_24` 同梱 corepack で pnpm/yarn をプロジェクト宣言優先供給 | **等価物なし**（旧時代は `npm i -g npm-fzf` 程度で pnpm/yarn 個別管理の記述なし） | 🔴 | 新規 or 放棄 | corepack shim 自動生成の設計自体が Nix 移行後の産物 |
| `packages.nix` の `devbox`（プロジェクトごとの言語バージョン管理） | **等価物なし** | 🔴 | 新規 or 放棄 | per-project 言語切り替えの手段が mise（プロジェクトの `.mise.toml`）に戻る想定 |
| `direnv.nix`（per-project Nix shell 自動有効化） | **等価物なし** | 🔴 | 放棄（Nix shell 自体を使わなくなるなら不要） | Flutter iOS pod install の Ruby 3.4 互換性問題など、direnv 導入の元動機が再発する可能性 |

### 3.4 macOS defaults 宣言化

| 現行 Nix 実装 | 旧実装 | 復元可否 | 必要な作業 | 失う/変わる挙動 |
|---|---|---|---|---|
| `defaults.nix`: Dock/Finder/Trackpad/NSGlobalDomain/MenubarClock 計 73 件を宣言化（棚卸 → triage → 翻訳ワークフローの成果物、`nix/README.md` 参照） | **等価物なし**（`11_appearance.zsh` は starship/yazi/grip の導入のみで `defaults write` は一切含まない。当時は手動 GUI 操作 or その場限りの `defaults write` 運用） | 🔴 | 73 件を冪等な `defaults write` コマンド列として script 化する新規実装（相応の工数）。または機能自体を放棄し「新規 PC は手動で GUI 設定」に戻す | これは復元ではなく、**Nix 移行で新規に獲得した「新規 PC を 1 コマンドで同一設定に揃える」再現性の喪失**。旧移行 spec の「明文化されていない設定」課題が復活する |
| `hitoolbox.nix`: IME/入力ソース (`com.apple.HIToolbox` / `com.apple.inputsources`) の `defaults import`（macOS Sonoma 以降のドメイン分離対応） | **等価物なし** | 🔴 | 同上 | 同上 |
| `fonts.nix`（UDEV Gothic / JetBrains Mono を `/Library/Fonts/Nix Fonts/` に配置） | **等価物なし**（フォントは手動 or Brewfile cask 頼み） | 🔴 | `brew install --cask font-*` への置換、または手動 | nixpkgs 収録フォントは Homebrew cask に代替品がない場合がある（要個別確認） |
| `pam.nix`（Touch ID for sudo） | **等価物なし** | 🔴 | `sudo_local` PAM 設定を script で書く新規実装 | 新規 PC で Touch ID sudo が手動設定に戻る |
| （current: なし。移行 spec は `darwin/sudoers.nix` として pmset NOPASSWD 化を計画していたが**未実装のまま現存しない**） | `10_claude.zsh` の pmset NOPASSWD sudoers 追加 | 🟢 | script として復活させるだけ（Nix 側に移植されなかった機能なので競合なし） | 現状 sleep-guard 相当の skill は `claude/skills/` に見当たらず、この設定の利用者が現存するか要確認 |

### 3.5 role 分け（`default`/`sub-1` マルチ PC 対応）

| 現行 Nix 実装 | 旧実装 | 復元可否 | 必要な作業 | 失う/変わる挙動 |
|---|---|---|---|---|
| `flake.nix` が `/etc/dotfiles-role` を読み、`homebrew.nix`/`defaults.nix` が `role` で分岐（casks/brews/masApps/Dock 順） | **概念自体が存在しない**（単一プロファイル前提） | 🔴 | 新規設計（複数 Brewfile、環境変数分岐、あるいは 1 台運用に割り切るか） | 現行の「メイン機はフル構成、サブ機は縮小構成」という運用そのものを維持するなら script 側で作り直しが必要。「role 概念を捨てて 1 プロファイルに戻す」なら実質仕様変更 |

### 3.6 CI / 再現性 / ロールバック

| 現行 Nix 実装 | 旧実装 | 復元可否 | 必要な作業 | 失う/変わる挙動 |
|---|---|---|---|---|
| `.github/workflows/nix-check.yml`（`nix flake check` + closure build を PR ごとに検証） | **存在しない** | 🔴 | script 方式で同等の CI を書くのは困難（`brew bundle` はネットワーク依存で macOS runner 必須、mise の `@latest` はバージョン非決定的） | PR マージ前の「壊れていないことの機械的保証」を失う |
| `flake.lock`（nixpkgs/nix-darwin/home-manager の commit pin） | **等価物なし** | 🔴 | なし相当（brew/mise は元々 pin しない） | 「同じコミットなら同じ環境が再現される」保証を失う。**これは旧移行 spec が Nix 化の動機として明記した課題そのものの再発** |
| `darwin-rebuild switch --rollback` / generations | **等価物なし**（`git revert` するしかない） | 🔴 | なし（git 管理下のファイルは revert できるが、`brew install` 済みパッケージやランタイムは戻らない） | 1 コマンドでの環境ロールバックを失う |

## 4. 横断的な論点（未決事項）

1. **「復元」の対象時点をいつに固定するか**: 3.1〜3.6 で見た通り、現行 Nix 機能の多くは Nix 移行**後**に
   新規開発された機能（macOS defaults 宣言化、role 分け、MCP/Codex/Hermes 統合、CI 検証、
   flake.lock 再現性）であり、旧スクリプトに対応物がない。「元のスクリプト管理方式に戻す」を文字通り実行すると、
   これら 🔴 の機能は**復元ではなく全て新規に script として作り直す**か、**機能そのものを放棄する**かの二択になる。
2. **mise 再導入は既存の明示的決定を覆す**: `languages.nix`/`corepack.nix` のコメントに残る通り、
   mise 排除は Phase A の意図的な決定（S7）。3.3 の復元は単純な「元に戻す」ではなく、この決定の
   再検討を伴う。
3. **Homebrew の「宣言してから入れる」ガード喪失**: `cleanup = "zap"` が持つ強制力（宣言外パッケージの
   自動削除）は旧 `brew bundle` の非破壊マージでは再現できない。運用規律（手動 `brew install` 抑制）を
   人間の自己規律に戻す前提になる。
4. **pmset NOPASSWD sudoers は Nix 側に未実装のまま現存しない**: これは今回の「復元」対象ではなく、
   そもそも Phase A で計画only・未実装だった機能。復元作業の一部として拾うかどうかは別軸の判断。
   sleep-guard 相当の利用実態が現在あるか要確認。
5. **CI・再現性・ロールバックの喪失は「元のスクリプト管理方式」の正確な復元そのものではあるが**、
   旧移行 spec が明記した課題（`docs/superpowers/specs/2026-05-02-nix-migration-design.md` 2章）の
   再発でもある。復元の目的（Nix の何が問題だったのか）が明確でないと、この喪失が許容範囲か判断できない。

## 5. 推奨する進め方（複数選択肢、決定はしない）

| 選択肢 | 概要 | 向いているケース |
|---|---|---|
| **A symlink + Homebrew のみ script化、他は Nix 併存** | 3.1・3.2 のみ script に戻し、3.3〜3.6 (🔴 群) は Nix のまま残す。ハイブリッド構成（Nix 側の一部機能を script に置換） | 「Nix の学習コスト・switch の重さが辛い」等、symlink/Homebrew の運用感だけが不満の場合。崩れる条件: nix-darwin 自体を PC から排除したい場合は不成立（home-manager と nix-darwin は運用上分離しづらい） |
| **B 全面 script 化（🔴 群も含め全て作り直す）** | 3.1〜3.6 全てを script で再実装する。工数最大 | Nix/nix-darwin 自体への強い不満・依存排除が目的の場合 |
| **C 全面 script 化・🔴 群は機能放棄** | 3.1・3.2 のみ script 化し、macOS defaults/role/MCP 統合/CI/再現性は「今後使わない」と決めて削除 | 復元の動機が「シンプルさ優先、多機能は要らない」の場合 |
| **D（推奨・確定版）リアルタイム symlink + Nix は package/build/pin 層のみ** | 「repo を編集したら即座に \$HOME へ反映されるべきもの」（zsh/alias 定義・git 設定・Claude/Codex/Hermes の CLAUDE.md・rules・skills 等）は home-manager の activation を使わず、**script が一度だけ作成する plain symlink** で working tree に直結する。以後の編集は symlink 越しに即時反映され、`switch` は一切不要。Nix (nix-darwin + home-manager) は「明示的にスクリプトを実行した時だけ反映されればよいもの」= Homebrew パッケージ (role 別 zap/none 継続) と CLI tool / 言語ランタイムの install/pin にのみ残す。macOS defaults・IME・フォント・PAM・Claude/Codex/Hermes の running-config seed/merge は Nix からも script 側に切り出し、実行時反映（apply 都度）で済ませる。詳細設計は 6・7 節 | 「編集した瞬間に反映されてほしいものと、明示的に適用コマンドを叩けば十分なものを区別したい」場合。崩れる条件: Homebrew の役割そのものを Nix から外したい場合は不成立（その場合は A/B/C 側で Brewfile 化を検討） |

いずれを選ぶ場合も、選択後は実装 PR を Phase 単位（旧移行の Phase A/B に倣い、影響範囲の小さい symlink →
Homebrew → 各 🔴 機能の順、または D の場合は `bin/` 各コマンド単位）に分割することを推奨する。

## 6. ハイブリッド案（D）詳細設計 — リアルタイム symlink + 限定 Nix

> **改訂履歴**: 本節は当初「`bin/apply` が内部で `darwin-rebuild switch` を呼ぶ」設計を提示したが、
> ユーザーから「`switch` を行わない」の意味は**編集時点での実機リアルタイム反映**であり、
> ラップして隠すだけの案は要件不適合と明示され撤回された。以下は撤回後の確定設計。

**前提（撤回後の確定方針）**:
- home-manager / nix-darwin の **activation による dotfiles・設定ファイル配置は使わない**。
- 「repo 編集 → 即座に \$HOME へ反映されるべきもの」は、script が一度だけ作成する **plain symlink**
  （working tree 直結）で扱う。作成後は `switch` はおろか script の再実行すら不要（symlink なので
  ファイル内容の変更はそのまま透過する）。再実行が要るのは「管理対象ファイルの一覧が増えたとき」だけ。
- Nix (nix-darwin + home-manager) は **package/build/pin 層に限定**して残す。具体的には
  Homebrew（role 別 `zap`/`none` ポリシーを現状通り維持）と、CLI tool / 言語ランタイムの
  install・pin（`home.packages` 等）。
- macOS defaults・IME・フォント・PAM・Claude/Codex/Hermes の running-config seed/merge は、
  「編集して即反映」ではなく「明示的にスクリプトを実行した時に反映されればよい」カテゴリだが、
  **Nix の activation ではなく plain zsh script** として実装する（Nix の残存スコープを
  package/build/pin に厳密に絞るため）。

### 6.1 二層モデル

| Tier | 反映タイミング | 対象カテゴリ | 実装方式 |
|---|---|---|---|
| **Tier 1: リアルタイム反映** | repo 編集の瞬間（symlink 越しなので待ち時間ゼロ） | zsh 設定・alias 定義・git 設定ファイル・ssh config・Claude の `CLAUDE.md`/`AGENTS.md`/`rules/`/`skills/`/`settings.json`/`hooks`（ファイル単位）・Codex `AGENTS.md`・Hermes `SOUL.md`・starship/yazi/zed/ghostty/cmux/grip の設定ファイル | script が一度だけ `ln -sf` で symlink を作成（home-manager 不使用） |
| **Tier 2: 明示的スクリプト実行で反映** | 該当スクリプトを手動実行した時 | Homebrew パッケージ／CLI tool・言語ランタイム install（**Nix 維持**）／macOS defaults・IME・フォント・PAM／Claude plugin sync・MCP servers merge・Codex config.toml seed-if-absent（**Nix から script へ移す**） | 前半は Nix（`darwin-rebuild switch`）、後半は新設の plain zsh script |

**Tier 1 と Tier 2 の境界線**: 「その場で symlink 越しに透過反映できるか」で切る。`~/.claude.json`
（OAuth token を含む running config）や macOS `defaults` domain（plist バイナリで symlink 不可）、
Homebrew パッケージ（ファイルではなくインストール操作）は構造的に symlink できないため Tier 2 になる。

### 6.2 現行 Nix 機能のカテゴリ再分類

| カテゴリ | 現行実装 | 新方式の Tier | 移行先 |
|---|---|---|---|
| zsh 設定・root alias 定義 | `zsh.nix`（`programs.zsh` が zshrc/zshenv を生成） | Tier 1 | 新設 root `zshrc`/`zshenv`/`aliases`（7 節）を symlink |
| git 設定・ssh config | `git.nix`/`ssh.nix` | Tier 1 | `config/git/config` 等の plain ファイルを symlink（`~/.gitconfig` のみ書き込み保護のため実体ファイルのまま） |
| Claude/Codex/Hermes の静的ファイル（CLAUDE.md/AGENTS.md/rules/skills/settings.json/hooks/SOUL.md） | `claude.nix`/`codex.nix`/`hermes.nix` の `home.file` 部分 | Tier 1 | plain symlink |
| starship/yazi/zed/ghostty/cmux/grip 設定 | 各 `*.nix` | Tier 1 | plain symlink |
| **Homebrew（role 別 zap/none）** | `nix-darwin` `homebrew.nix` | Tier 2 | **Nix 維持・無変更**（役割不変） |
| 言語ランタイム install・pin（node/go/ruby/rust/python/dart） | `languages.nix`（nixpkgs 固定バージョン） | Tier 2 | **mise へ移行（確定, 2026-08-22 承認）**。Nix から離脱し、旧 `install/04〜09_*.zsh` 相当の script を復活させる |
| corepack（pnpm/yarn グローバル供給） | `corepack.nix`（`languages.nix` の `nodejs_24` に依存） | Tier 2 | **維持で確定（2026-08-22 承認）**。`setup/languages.zsh`（mise install）の直後に、mise が導入した node に対して `corepack enable` を実行し shim を生成する。`package.json` の `packageManager` 宣言優先という現行挙動を維持する |
| per-project Nix shell 自動有効化 | `direnv.nix`（`nix-direnv`） | — | **廃止で確定（2026-08-22 承認）**。zshrc/zshenv に direnv hook を含めない |
| devbox（プロジェクトごとの言語バージョン管理） | `packages.nix` | — | **廃止で確定（2026-08-22 承認）**。mise の `.mise.toml` が同用途をカバーするため。6.7 節で Homebrew 公式 formula/tap 不在も確認済み |
| CLI tool（jq/gh/ghq/lazygit 等、言語ランタイム・devbox 以外） | `packages.nix` | Tier 2 | **Homebrew へ統合、home-manager 完全廃止で確定（2026-08-22 承認）**。旧 Brewfile に実在した
  tap 不要のツール（jq/bats-core/pwgen/qpdf/fzf/gh/ghq/lazygit/lazydocker/kubectl/kubectx/stern/sops/grpcurl）
  はそのまま Homebrew へ戻す。Nix 移行後に追加された新顔（uv/agent-browser/jujutsu/jjui/tmux/mosh/ffmpeg/ripgrep）は
  6.7 節で Homebrew 移行に支障なしと確認済み |
| macOS defaults（73 件）・IME/入力ソース | `defaults.nix`/`hitoolbox.nix` | Tier 2 | Nix から離脱。新設 zsh script（`defaults write`/`defaults import` を列挙） |
| フォント | `fonts.nix` | Tier 2 | **Homebrew cask 化で確定（2026-08-22 承認）**。`font-udev-gothic`・`font-jetbrains-mono` を `homebrew.nix` の casks に追加し、既に cask 管理の `font-sf-mono` と経路を統一する。専用 script（`fonts.zsh`）は不要 |
| PAM Touch ID | `pam.nix` | Tier 2 | Nix から離脱。新設 zsh script（`/etc/pam.d/sudo_local` 相当を編集） |
| Claude plugin sync / MCP servers merge / Codex config seed / skills repo clone | `claude.nix`/`codex.nix` の `home.activation.*` | Tier 2 | Nix から離脱。新設 zsh script（jq マージ・seed-if-absent ロジックはそのまま移植） |
| CI（`nix flake check`／closure build） | `.github/workflows/nix-check.yml` | — | 検証対象が Homebrew/package 層のみに縮小。Tier 2 の zsh script（defaults/PAM/フォント/running-config）は bats でユニットテスト |
| flake.lock 再現性・generations rollback | Nix 標準機能 | — | 縮小維持。対象は Homebrew/CLI tool/言語ランタイムの package 層のみ |

### 6.3 構成（ディレクトリ案、2026-08-22 時点の確定分を反映）

```
aliases                        # NEW: root 直下、alias 定義の SSOT (7 節)
zshrc / zshenv                 # 既存 (7 節で更新)
config/git/config, config/git/ignore  # NEW: 現行 programs.git 相当の plain ini
setup/
  lib/
    util.zsh                     # ログ・確認ヘルパー
    fs.zsh                       # symlink 安全プリミティブ (fs::link_file 等)
  link.zsh                       # Tier 1: 上記対応表の symlink を一度だけ作成 (再実行は追加分のみ反映)
  languages.zsh                 # Tier 2: mise で node/go/ruby/rust/python/dart を install (旧 install/04〜09_*.zsh 相当)
  defaults.zsh                  # Tier 2: macOS defaults / IME (旧 defaults.nix / hitoolbox.nix を移植)
  pam.zsh                       # Tier 2: PAM Touch ID
  claude-sync.zsh               # Tier 2: plugin sync / MCP merge / skills repo clone
  codex-sync.zsh                # Tier 2: config.toml seed-if-absent
nix/                            # home-manager は完全廃止。nix-darwin (Homebrew) のみ残す
  darwin.nix / homebrew.nix      # 無変更。旧 packages.nix の CLI tool (jq/gh/ghq/lazygit 等、devbox 除く)
                                  # を brews リストへ、UDEV Gothic/JetBrains Mono を casks リストへ追加
                                  # する（font-sf-mono と経路統一）。別ファイルの Brewfile は作らない。
                                  # homebrew.nix の宣言的 attrset がそのまま SSOT
  home.nix・modules/home/**       # 削除（home-manager 自体を使わないため）
  modules/darwin/defaults.nix・hitoolbox.nix・fonts.nix・pam.nix  # 削除（setup/*.zsh へ移植済み）
```

`setup/link.zsh` は Tier 1 表の各行を `fs::link_file <repo path> <\$HOME path>` 1 行ずつ列挙する
（生成・ループ抽象化を避け、1 対応 = 1 行で読めることを優先）。`fs::link_file` は「symlink 済みなら
何もしない／実体ファイルがあれば `.before-setup` に退避してから symlink する」安全策を持つ明示関数とし、
コメントで意図（3rd party 書き込みの保護、既存実体の temperature を壊さない）を明記する。

### 6.4 既存機能の維持

- Homebrew の role 別ポリシー（`default` = `cleanup: "zap"` で宣言外を強制削除、`sub-1` = `cleanup:
  "none"` で手動 install 許容）は `homebrew.nix` を無変更で維持するため**リスクゼロで継続**。
- macOS defaults 73 件・PAM・フォント・running-config seed/merge は Nix から script へ実装を移植する
  ため、A 案や B 案と同種の「再実装コスト・regression リスク」が発生する（3.4〜3.6 の 🔴 群相当）。
  ただし対象は「Nix 実装をそのまま zsh に書き写す」作業であり、ゼロから設計する B 案より確実性が高い。
- CI・flake.lock 再現性・generations rollback は Homebrew/CLI tool 層に限定した縮小版として残る
  （defaults/PAM/フォント/running-config は Nix の外に出るため、この保証の対象外になる）。

### 6.5 移行コスト（概算）

| 項目 | 規模 | 備考 |
|---|---|---|
| `setup/lib/util.zsh` `setup/lib/fs.zsh` | 小 | 既存 `nix/scripts/migrate-symlinks.zsh` の安全策パターンを踏襲 |
| `setup/link.zsh`（Tier 1 symlink、alias SSOT 移行含む） | 中 | 対応表の行数分（約 25 件） |
| `setup/defaults.zsh`（73 件） | 中〜大 | 3.4 節と同等の工数。`defaults.nix` の値をそのまま `defaults write` に変換 |
| `setup/pam.zsh` `setup/fonts.zsh` | 小 | 既存 Nix 実装を素直に script化 |
| `setup/claude-sync.zsh` `setup/codex-sync.zsh` | 中 | `claude.nix`/`codex.nix` の activation ロジック（jq マージ含む）を移植。ロジック自体は既存なので再設計は不要 |
| Homebrew/CLI tool/言語ランタイム | ゼロ | Nix 側無変更 |
| ドキュメント更新（README/AGENTS.md/nix/README.md） | 中 | Tier 1/Tier 2 の境界と操作手順の書き分けが必要 |

**A/B/C との比較で見た位置付け**: 3.1〜3.2（symlink・Homebrew）は A 案と同等かそれ以下のコスト
（Homebrew は無変更なのでゼロ）。3.4〜3.6（defaults/PAM/フォント/running-config）は B 案と同等の
再実装コストが発生する（Nix からの離脱を伴うため）。**総コストは A と B の中間**だが、Homebrew の
role ポリシーだけは無条件で守られる点、および「どのファイルがリアルタイムでどれが script 実行時か」
が体系的に整理される点で、単純な A/B/C のどれとも違う独自の利点を持つ。

### 6.6 A/B/C との比較サマリ（確定版）

| 観点 | A | B | C | D（確定版） |
|---|---|---|---|---|
| 編集の即時反映（symlink） | 3.1 のみ | 3.1〜3.6 全て script（switch 相当なし） | 3.1 のみ | **3.1 系全て**（Tier 1 表参照） |
| `switch` を要する範囲 | 3.3〜3.6 が Nix のまま残るため必要 | なし | なし（3.3〜3.6 放棄） | **Homebrew/CLI tool 層のみ**（Tier 2） |
| Homebrew role 別 zap/none | script 再実装（要設計） | script 再実装（要設計） | script 再実装（要設計） | **Nix 無変更で維持** |
| macOS defaults 73 件等の再実装 | 不要（Nix 残置） | 必要 | 放棄 | **必要**（Nix から離脱するため） |
| CI・flake.lock・rollback | 全範囲維持 | 喪失 | 喪失 | Homebrew/CLI tool 層のみ縮小維持 |
| 実装工数 | 中 | 大 | 中〜大（喪失込み） | 中（A と B の中間） |

### 6.7 home-manager 完全廃止に伴う CLI tool の Homebrew 移行可否確認（読み取り専用, 2026-08-22）

home-manager 廃止・CLI tool の Homebrew 統合が確定したことを受け、Nix 移行後に `packages.nix` へ
追加された非言語ランタイム系ツールのうち、pre-Nix Brewfile に前例がないもの（devbox / uv /
agent-browser / jujutsu / jjui）について `brew info`（ローカル、read-only）と Web 検索で
formula 存在を確認した。**インストール・tap 追加は行っていない。**

| ツール | 確認結果 | 備考 |
|---|---|---|
| `uv` | ✅ homebrew-core に公式 formula あり（0.12.5、bottled、tap 不要） | 問題なし |
| `agent-browser` | ✅ homebrew-core に公式 formula あり（0.34.0、bottled、tap 不要） | 問題なし |
| `jujutsu` | ✅ homebrew-core に公式 formula あり（formula 名 `jj`、`jujutsu` は alias、0.44.0、bottled） | 問題なし。Homebrew 移行時は `jj` を指定する |
| `jjui` | ✅ homebrew-core に公式 formula あり（0.10.9、bottled、tap 不要） | 問題なし |
| `devbox` | ❌ homebrew-core に formula なし。公式 tap（jetify-com/devbox 等）も存在しない | upstream 側に [公式 Homebrew 対応の feature request（jetify-com/devbox#76）](https://github.com/jetify-com/devbox/issues/76) が**未解決のまま残っている**ことを確認。非公式 tap `pilat/devbox` の存在は Web 検索で見つかったが、メンテナンス状況は未検証。移行を阻む明確な問題として扱う |

**devbox は移行を阻む明確な問題が見つかった**唯一のツール。他 4 点は Homebrew 移行に支障なし。

Sources: [jetify-com/devbox Issue #76](https://github.com/jetify-com/devbox/issues/76), [Jetify Devbox Installing Docs](https://www.jetify.com/docs/devbox/installing-devbox)

同様に、`fonts.nix` の 2 フォントについても cask 存在を確認した（read-only）。

| フォント | 確認結果 |
|---|---|
| UDEV Gothic | ✅ `font-udev-gothic` cask あり（2.2.0） |
| JetBrains Mono | ✅ `font-jetbrains-mono` cask あり（2.304） |

両方とも homebrew-cask に公式 cask が存在し、移行を阻む問題なし。`font-sf-mono` は現行から既に
Homebrew cask 管理のため、フォント導入経路が Homebrew cask に一本化される。

## 7. ルート alias SSOT 移行設計（確定, 2026-08-22 承認）

### 7.1 現状の課題

- alias **定義**（`alias foo=bar` 本体）は現在 `nix/modules/home/zsh.nix` の `shellAliases`
  属性にしかなく、独立したファイルとして存在しない（pre-Nix 時代は root 直下に `aliases` ファイルが
  あったが、Nix 移行時に内容が zsh.nix へ吸収され削除された）。
- `aliase/`（末尾 s なし、既存の意図的な綴り）は「alias から呼ばれる**外部スクリプト**」
  （`build-agent-rules.zsh` `claude-board.zsh` `get-gke-credentials.sh`）を置くディレクトリで、
  alias **定義**そのものではない。`aliases`（root 直下、末尾 s あり、新設予定）と
  `aliase/`（ディレクトリ、末尾 s なし、既存）が 1 文字違いで役割も異なるため、このまま両立させると
  誤読・タイポのリスクが高い。

### 7.2 移行案

- **新設**: root 直下 `aliases` ファイルを alias 定義の SSOT として復活させる。中身は現行
  `zsh.nix` の `shellAliases`（`history`/`reload`/`gp`/`repo`/`codeo`/`claude-board`/
  `agent-rules-build` 等）と `initContent` 内の `alias -g KP=...` 等のグローバル alias・`tn()`
  関数を、plain zsh の `alias` 文・関数定義としてそのまま書き写す（Nix の attrset から zsh 構文への
  1:1 変換であり、ロジック変更は発生しない）。
- **リネーム**: `aliase/`（外部スクリプト置き場）は紛らわしい既存名を解消するため `scripts/` へ
  改名する。中身の 3 ファイルはそのまま移動する。
  - `aliase/build-agent-rules.zsh` → `scripts/build-agent-rules.zsh`
  - `aliase/claude-board.zsh` → `scripts/claude-board.zsh`
  - `aliase/get-gke-credentials.sh` → `scripts/get-gke-credentials.sh`
  - （棚卸しで発見した既存ギャップ: 現行 `zsh.nix` は `build-agent-rules.zsh` を `home.file` に
    宣言し忘れている。新方式では 3 ファイルとも揃えて symlink する）

### 7.3 既存参照・互換性移行

| 参照元 | 現行の記述 | 変更後 |
|---|---|---|
| `aliases`（新設ファイル内） | — | `gcgc = "bash $HOME/.scripts/get-gke-credentials.sh"` 等、`.aliase` → `.scripts` に置換 |
| `zsh.nix` コメント・`hermes.nix` コメント | `aliase/build-agent-rules.zsh` | Nix 側の該当モジュールは 6 節で削除・移植されるため、コメントごと消える（残存させない） |
| `AGENTS.md`「リポジトリ構造」節 | `aliase/` — 外部シェルスクリプト | `scripts/` — 外部シェルスクリプト、`aliases` — alias 定義 (root, SSOT) を追記 |
| `~/.aliase/*`（実機の既存 symlink） | Nix の `home.file` が管理 | `setup/link.zsh` 初回実行時に `~/.scripts/*` へ新規作成。旧 `~/.aliase/*` は home-manager の
    `backupFileExtension` 管理外になるため、別途 `unlink` するクリーンアップが必要（実機適用は本ドキュメントの対象外、別途実行時に確認） |

### 7.4 zsh での読み込み

新設 root `zshrc` の冒頭付近（`plugins=(...)` の直後、他の `alias` 定義より前）に以下を追加する:

```zsh
# alias 定義 SSOT (root 直下 aliases ファイルへの symlink)
[[ -f "${HOME}/.aliases" ]] && source "${HOME}/.aliases"
```

`setup/link.zsh` が `${DOTFILES_ROOT}/aliases` → `${HOME}/.aliases` を Tier 1 symlink として作成する
（他の symlink と同じ `fs::link_file` を使うだけで、alias 読み込みのために特別な仕組みは要らない）。

## 8. 推薦

**D（確定版: リアルタイム symlink + Nix は package/build/pin 層のみ）を推薦する。**

根拠:
1. ユーザーの 2 つの目的（「`switch` を要さない」「script の方が理解しやすい」）は、Tier 1
   （repo 編集がそのまま反映される plain symlink）で**文字通り**満たされる。B 案のように defaults
   73 件や running-config 保護を全て作り直す必要があるのは Tier 2 部分（Homebrew を除く）だけであり、
   B 案と同等の作業はそこに限定される。
2. Homebrew の role 別 zap/none ポリシーという、複製すると最もリスクが高い機能
   （3.2 節で 🟡 と判定した部分）を Nix 側に無変更で残せるため、この一点で B 案より安全。
3. A 案と異なり、defaults/PAM/フォント/running-config も含めて「Nix にしか実装がない」という
   状態を解消する（A 案はこれらを Nix に残すため、依存低減という動機には応えられない）。
4. alias SSOT のルート化（7 節）は D 案固有の話ではなく、A/B/C いずれを採っても同時に行うべき
   整理だが、D 案の Tier 1 symlink 基盤を作る際に自然に組み込める。

**崩れる条件**: Homebrew の役割ごと Nix を排除したい場合（依存自体をゼロにしたい場合）は D 案は
成立しない。その場合は B 案（Homebrew も Brewfile 化）を選び、3.2 節の role 分岐再設計コストを
受け入れる必要がある。

## 9. 検証

- 実施した検証: `git show <commit>:<path>` によるファイル内容の直接確認のみ（読み取り専用、副作用なし）
- 未実施: 実機での動作確認、`nix build` 等のビルド検証（復元範囲が未確定のため対象コードがまだ存在しない）
- 本ドキュメントの記述と現行コードの対応関係は 2026-08-21 時点の `refactor/restore-script-management`
  ブランチ（`main` から未分岐、差分なし）を基準にした

## 10. 未決事項（このドキュメントでは解決しない）

**解決済み（ユーザー判断済み）**:
- ~~「5. 推奨する進め方」の A/B/C いずれを採るか~~ → D（確定版）に決定
- ~~Homebrew の role 別ポリシーを維持するか~~ → 維持と明示（6.4 節）
- ~~`switch` 不要の意味~~ → リアルタイム反映と明確化（6 節冒頭の改訂履歴）
- ~~alias 定義の置き場所・`aliase/` の扱い~~ → root 直下 `aliases` を SSOT、`aliase/` は `scripts/`
  へ改名で**確定**（7 節、2026-08-22 承認）
- ~~言語ランタイム管理（node/go/ruby/rust/python/dart）を Nix に残すか~~ → **mise へ移行で確定**
  （2026-08-22 承認）。home-manager の CLI tool package 管理（`packages.nix`、言語ランタイム以外）
  とは別軸の判断であり、混同しないこと（ユーザー明示指摘）
- ~~home-manager の CLI tool package 管理を維持するか、Homebrew へ統合するか~~ → **Homebrew へ統合、
  home-manager 完全廃止で確定**（2026-08-22 承認）。devbox 以外の 4 点（uv/agent-browser/jujutsu/jjui）は
  6.7 節の確認で Homebrew 移行に支障なしと判明
- ~~devbox の扱い~~ → **廃止で確定**（2026-08-22 承認）。ツール一覧から除外する

- ~~direnv（`nix-direnv`、per-project Nix shell 自動有効化）の要否~~ → **廃止で確定**（2026-08-22
  承認）。zshrc/zshenv に direnv hook を含めない。汎用 `.envrc` 用途が必要になった場合の再導入は
  別途 Homebrew formula `direnv` で低コストに可能（本ドキュメントでは扱わない）

- ~~corepack（pnpm/yarn のグローバル供給・バージョン管理）の扱い~~ → **維持で確定**（2026-08-22 承認）。
  mise 導入の node に対し `corepack enable` を実行し、`packageManager` 宣言優先の現行挙動を維持する
- ~~フォント（UDEV Gothic / JetBrains Mono）の導入経路~~ → **Homebrew cask 化で確定**（2026-08-22
  承認）。`font-sf-mono` を含む全 3 フォントが同一経路（Homebrew cask）に統一され、`fonts.zsh` は
  廃止（不要）
- ~~pmset NOPASSWD sudoers を復元スコープに含めるか~~ → **スコープ外で確定**（2026-08-22 承認）。
  sleep-guard 相当の利用実態が確認できないため復元対象に含めない

**未解決（実装フェーズの内部設計。ユーザー確認は個別フェーズ着手時）**:
- `setup/defaults.zsh` 等 Tier 2 の新設 script 群を、フェーズ単位でどう分割して実装するか（Tier 1
  実装計画は `docs/superpowers/plans/2026-08-22-restore-script-management-tier1.md` に起票済み。
  Tier 2 は別途計画を起こす）
- 実機の既存 `~/.aliase/*` `~/.zshrc` 等（home-manager 管理下）を新方式の symlink に切り替える際の
  実機移行手順（本ドキュメント・Tier 1 計画のいずれも実機適用は対象外。切替時に別途判断）
