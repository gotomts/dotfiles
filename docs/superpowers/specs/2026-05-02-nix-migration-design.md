# Design: 環境構築の Nix 一元化

- 作成日: 2026-05-02
- 対象リポジトリ: `~/.dotfiles` (github.com/gotomts/dotfiles)
- 関連 plan: `docs/superpowers/plans/2026-05-02-nix-migration.md`

## 1. 目的・成功条件

### 目的
`~/.dotfiles` の環境構築を **Nix（nix-darwin + home-manager + flakes）** に最大限寄せて、宣言的・再現可能・マルチホスト対応にする。CLI / GUI / macOS 設定 / シェル / Claude Code プラグインまでを単一の `darwin-rebuild switch` で復元できる状態を作る。

### 成功条件（受入条件）
- [ ] 現マシン上で `darwin-rebuild switch --flake ~/.dotfiles/nix#<hostname>` 一発で「現在の環境と同等」が再現できる
- [ ] CLI / GUI（cask）/ App Store（mas）/ macOS defaults / sudoers / launchd / フォント / シェル設定 / claude plugins が flake から復元できる
- [ ] mise / pipx / cargo install / rustup の global 状態に依存しない（Brewfile からも mise が外れている）
- [ ] `~/.dotfiles/Brewfile` と `~/.dotfiles/setup/install/` が削除されている（Phase B 完了後）
- [ ] `setup.zsh` 由来の symlink 群が home-manager の `home.file` で再現されている
- [ ] 別 PC で flake をクローンして `darwin-rebuild` を初回実行する README 手順がある
- [ ] 棚卸 → triage → 翻訳の人間 in-the-loop ワークフローが文書化されている
- [ ] `rtk` が flake input 経由でビルドされ、バージョン pin できている

## 2. 背景と現状

### 現状の管理範囲
- **Brewfile**: tap 4 / brew 25 / cask 25 / mas 5 / fonts 1（合計約 60 entry）
- **setup.zsh**: dotfiles ルートと `claude/`, `config/`, `ssh/` を `~/` 配下に symlink
- **install/ 11 スクリプト**: oh-my-zsh、mise（node/go/ruby/rust/python/dart）、claude plugins、starship/yazi/grip、linear 認証、pmset NOPASSWD sudoers
- **複数の補助マネージャ**: mise（言語ランタイム）、pipx（poetry, grip）、cargo install（cargo-nextest, cargo-watch）、npm -g（npm-fzf）、rustup component
- **macOS 固有副作用**: sudoers 編集、mas、cask、Application Support パス
- **明文化されていない設定**: `defaults write` 系の Mac 設定は現状 dotfiles に宣言が一つも存在しない

### 課題
1. **再現性の欠如**: install スクリプトが手続き的で、現在のマシン状態を厳密に再現する保証がない
2. **マルチマシン対応不能**: ホスト間で「同じ状態」を維持する仕組みがない
3. **macOS 設定が暗黙**: `defaults write` 系がドキュメント化されておらず、PC 移行時に欠落しがち
4. **依存マネージャの分散**: brew / mise / pipx / cargo / npm / rustup の 6 系統が並立している

## 3. 主要な意思決定（決定事項一覧）

| # | 軸 | 決定 |
|---|---|---|
| 1 | スコープ | 最大化（mise/pipx/cargo install も置換） |
| 2 | 移行戦略 | 段階移行（並存 → 逆転 → 削除） |
| 3 | shell config | `programs.zsh` で宣言化（initExtra / shellAliases / oh-my-zsh モジュール） |
| 4 | macOS 設定 | フル（defaults / sudoers / services / cask / mas / fonts） |
| 5 | flake 構造 | マルチホスト（`hosts/<hostname>/` + `modules/`） |
| 6 | mise | 完全削除（Brewfile からも外す） |
| 7 | rtk | flake input として GitHub から fetch、`rustPlatform.buildRustPackage` でビルド |
| 8 | claude plugins | 宣言化（`enabledPlugins` を読んで `home.activation` で同期） |
| 9 | oh-my-zsh | 宣言化（`programs.zsh.oh-my-zsh` モジュール） |
| 10 | macOS 棚卸 | 現マシン = source of truth、自動 inventory → 人間 triage → 翻訳 |
| 11 | リポジトリ構造 | Approach A（`nix/` サブディレクトリ）。Phase B で root 昇格を別検討 |

## 4. 全体アーキテクチャ

```
~/.dotfiles/
├── nix/                                ← 新規追加。Phase A の作業対象
│   ├── flake.nix                       ← inputs / outputs ルート
│   ├── flake.lock                      ← 全 input のロック
│   ├── README.md                       ← nix/ 配下の運用手順
│   ├── hosts/
│   │   └── <hostname>/
│   │       ├── default.nix             ← ホスト固有の合成
│   │       ├── darwin.nix              ← nix-darwin module 集約
│   │       └── home.nix                ← home-manager module 集約
│   ├── modules/
│   │   ├── darwin/
│   │   │   ├── defaults.nix            ← system.defaults.* (棚卸結果から翻訳)
│   │   │   ├── homebrew.nix            ← cask / mas / 例外 brew を宣言
│   │   │   ├── sudoers.nix             ← pmset NOPASSWD など
│   │   │   ├── fonts.nix               ← font-sf-mono 等
│   │   │   ├── launchd.nix             ← (棚卸で発見されたもの)
│   │   │   └── pam.nix                 ← Touch ID for sudo
│   │   ├── home/
│   │   │   ├── packages.nix            ← CLI ツール (jq, fzf, gh, … nixpkgs から)
│   │   │   ├── zsh.nix                 ← programs.zsh + oh-my-zsh + initExtra
│   │   │   ├── git.nix                 ← gitconfig / gitignore_global を宣言化
│   │   │   ├── starship.nix            ← starship 設定
│   │   │   ├── yazi.nix                ← yazi.toml / keymap.toml
│   │   │   ├── claude.nix              ← claude plugin 同期 + symlink
│   │   │   ├── ssh.nix                 ← ssh/ symlink (鍵以外)
│   │   │   └── languages.nix           ← Node/Go/Ruby/Rust/Python/Dart toolchain
│   │   └── overlays/
│   │       └── rtk.nix                 ← rtk を flake input としてビルド
│   ├── lib/
│   │   └── mkHost.nix                  ← ホスト合成ヘルパー
│   └── scripts/
│       └── inventory.zsh               ← 棚卸スクリプト
├── docs/
│   ├── superpowers/specs/2026-05-02-nix-migration-design.md   ← この spec
│   ├── superpowers/plans/2026-05-02-nix-migration.md          ← writing-plans が作る
│   └── inventory/
│       └── <hostname>-2026-05-02.md    ← 棚卸結果と triage チェックリスト
├── Brewfile                            ← Phase A 期間中は読み取り専用バックアップ
├── setup/                              ← Phase A 期間中は使わない
├── claude/                             ← 維持（home.file で symlink 化）
├── config/                             ← 維持（home.file または各 module）
├── functions/                          ← 維持（programs.zsh.initExtra から source）
├── ssh/                                ← 維持（home.file で symlink）
├── zshrc / zshenv / aliases            ← 中身は programs.zsh モジュールに移植
└── CLAUDE.md                           ← nix/ セクションを追加
```

## 5. コンポーネント設計

### 5.1 `nix/flake.nix` (inputs / outputs)

```nix
{
  description = "gotomts macOS dotfiles via nix-darwin + home-manager";

  inputs = {
    nixpkgs.url            = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url         = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url       = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    rtk-src = { url = "github:<rtk-repo>"; flake = false; };
  };

  outputs = { self, nixpkgs, nix-darwin, home-manager, rtk-src, ... }@inputs:
    let
      mkHost = import ./lib/mkHost.nix { inherit inputs; };
    in {
      darwinConfigurations.<hostname> = mkHost {
        hostname = "<hostname>";
        system   = "aarch64-darwin";
        username = "goto";
      };
    };
}
```

### 5.2 nix-darwin モジュール

| モジュール | 役割 | 翻訳元 |
|---|---|---|
| `darwin/defaults.nix` | `system.defaults.{NSGlobalDomain,dock,finder,trackpad,…}` | 棚卸 triage 結果 |
| `darwin/homebrew.nix` | `homebrew.{enable, casks, masApps, brews}` | 現 Brewfile の cask + mas + 例外 brew |
| `darwin/sudoers.nix` | `security.sudo.extraRules` | `setup/install/10_claude.zsh` の pmset NOPASSWD |
| `darwin/fonts.nix` | `fonts.packages` | `cask 'font-sf-mono'` |
| `darwin/launchd.nix` | `launchd.user.agents.*` | 棚卸で見つかったエージェント |
| `darwin/pam.nix` | `security.pam.services.sudo_local.touchIdAuth = true` | 新規宣言 |

> nix-darwin の `homebrew` モジュールは **brew 自体を `services.nix-darwin` 的に管理しない**。brew は引き続き手動で（または `homebrew.onActivation.autoUpdate` 経由で）動作するが、Brewfile.nix 等価が flake で表現される。

### 5.3 home-manager モジュール

| モジュール | 役割 |
|---|---|
| `home/packages.nix` | CLI ツール群を `home.packages = with pkgs; [ ... ]` で宣言。Brewfile の `# Utilities` 〜 `# Network & API` セクションを移植 |
| `home/zsh.nix` | `programs.zsh.{enable, oh-my-zsh, shellAliases, initExtra}`。現 zshrc/aliases/functions の中身を分解して移植 |
| `home/git.nix` | `programs.git.{enable, userName, userEmail, extraConfig, ignores}` |
| `home/starship.nix` | `programs.starship.{enable, settings}` |
| `home/yazi.nix` | `programs.yazi.{enable, settings, keymap}` |
| `home/claude.nix` | `~/.claude/{agents,skills,settings.json,...}` を `home.file.*.source` で symlink。`enabledPlugins` を読んで `home.activation.claudePlugins` で `claude plugin install/update` |
| `home/ssh.nix` | `programs.ssh` または `home.file.".ssh/<file>".source`（鍵は対象外） |
| `home/languages.nix` | Node/Go/Ruby/Rust/Python/Dart の各ツールチェーン。`fenix` overlay 等を必要に応じて使う。`cargo-nextest`, `cargo-watch`, `poetry`, `grip` も `home.packages` |

### 5.4 rtk overlay

```nix
# nix/modules/overlays/rtk.nix
final: prev: {
  rtk = prev.rustPlatform.buildRustPackage {
    pname     = "rtk";
    version   = inputs.rtk-src.shortRev;
    src       = inputs.rtk-src;
    cargoLock = { lockFile = "${inputs.rtk-src}/Cargo.lock"; };
  };
}
```

flake input でバージョンをロックし、`pkgs.rtk` として供給。`home/packages.nix` から参照。

## 6. データフロー / アクティベーション

```
ユーザー操作                      Nix システムの動き
──────────                      ──────────────────
$ darwin-rebuild switch \
   --flake ~/.dotfiles/nix#<host>
  │
  ├─ flake 評価
  │   └─ inputs (nixpkgs, home-manager, nix-darwin, rtk-src) を fetch
  │
  ├─ darwinConfigurations.<host> ビルド
  │   ├─ system.defaults.* を生成 (defaults write 等価)
  │   ├─ homebrew モジュールが brew bundle 実行 (cask/mas)
  │   ├─ security.sudo.extraRules を /etc/sudoers.d/* に書く
  │   ├─ fonts.packages を /Library/Fonts に配置
  │   └─ launchd エージェント生成
  │
  └─ home-manager.users.<user> 適用
      ├─ home.packages を ~/.nix-profile に
      ├─ programs.zsh が ~/.zshrc を生成
      ├─ home.file が ~/.claude/skills/* など symlink 群を生成
      └─ home.activation スクリプト (claude plugin sync) 実行
```

ロールバック: `darwin-rebuild --rollback` または `darwin-rebuild switch --flake .#<host> --switch-generation <prev>`。

## 7. 段階移行戦略

### Phase A — 並存（nix が主、Brewfile が読み取り専用バックアップ）

1. **A0: 棚卸 & triage**
   - `nix/scripts/inventory.zsh` を新設し、`defaults`/`mas list`/`launchctl list`/sudoers/brew/font の現状を `docs/inventory/<host>-<date>.md` に出力
   - ユーザーが triage 文書を 1 件ずつ「Nix 化 / 無視 / 別途検討」とマーク
   - triage 結果を `nix/modules/darwin/defaults.nix` 等に翻訳
2. **A1: nix/ ディレクトリと flake 雛形作成**
3. **A2: home-manager モジュール構築**（packages → git → zsh → claude → 言語）
4. **A3: nix-darwin モジュール構築**（homebrew → defaults → sudoers → fonts → pam）
5. **A4: rtk overlay**（flake input + buildRustPackage）
6. **A5: 検証**: 現マシンで `darwin-rebuild build`（switch せず）→ diff 確認 → `switch` 適用
7. **A6: Brewfile / setup/ をリポジトリ内で「使わない」状態に**（README に「Phase B で削除予定」記載）

### Phase B — 削除と整理

1. Phase A の運用が安定（後述ゲート充足）したのち
2. `Brewfile` / `setup/install/` / `setup/setup.zsh` を削除
3. `CLAUDE.md` の「リポジトリ構造」「Brewfile」「setup スクリプト」関連セクションを更新
4. 任意: `nix/` を repo root に昇格させるかは別 issue で検討

### Phase A → B のゲート
- `darwin-rebuild switch` がエラー無しで複数回連続して完了（具体回数は plan で確定）
- 棚卸 triage で「Nix 化」マーク済み項目が全て nix-darwin 宣言に翻訳されている
- ユーザーが日常使う CLI/GUI/設定が全て nix 経由で再現できる
- 別 PC への展開シミュレーション（ドライラン）が完了

## 8. 棚卸 & 人間 in-the-loop

### 8.1 自動部分
`nix/scripts/inventory.zsh` が以下を出力:
- `defaults domains` の全ドメインから既知優先ドメイン（`com.apple.dock`, `com.apple.finder`, `com.apple.menuextra.clock`, `NSGlobalDomain` 等）を抜粋し `defaults read` でダンプ
- `mas list`
- `launchctl list | grep <user>`
- `ls /etc/sudoers.d/` の中身
- `brew bundle dump --no-restart` を `/tmp` に出して現 Brewfile と diff（手動追加の検出）
- `fc-list :family` から自前フォント検出

出力形式: チェックリスト Markdown
```markdown
## defaults: com.apple.dock
- [ ] orientation = "bottom"               <!-- nix化 / 無視 / 検討 -->
- [ ] tilesize    = 48
```

### 8.2 手動部分
- ユーザーが triage（チェック / 削除 / コメント）
- triage 完了後、人間が `nix/modules/darwin/defaults.nix` に翻訳
- 翻訳結果は `darwin-rebuild build` で構文・型チェック
- `darwin-rebuild switch` で適用

### 8.3 マルチホスト時の注意
nix-darwin は「明示宣言した key だけを書く」設計のため、triage で「無視」とマークした項目は **未宣言のまま** となる。現 PC では現状値が事実上維持されるが、別 PC では OS デフォルト値が露出する。triage で「無視」を選ぶ条件は **「OS デフォルトと同じであること」を確認した上で** とし、文書化する。

## 9. エラー処理 / ロールバック

| シナリオ | 対応 |
|---|---|
| `darwin-rebuild switch` が中途半端に失敗 | 自動で前世代に戻る（nix-darwin 標準動作）。手動なら `darwin-rebuild --rollback` |
| flake.lock が壊れる / inputs の hash 不整合 | `git restore nix/flake.lock` |
| rtk のビルド失敗（input rev が壊れた） | `flake.lock` で前 rev に固定、追って修正 |
| home-manager activation で claude plugin が壊れる | `home.activation.claudePlugins` を `lib.mkAfter` で末尾に置き、失敗しても他は通す。エラーは warning ログ |
| Brewfile.nix の cask が brew に存在しない | `darwin-rebuild` がエラー停止。修正は cask 名 typo 確認 |

Phase A 中は **Brewfile 自体は残っている** ので、最悪 `brew bundle --file ~/.dotfiles/Brewfile` で旧来手順に戻れる。これが phased 戦略の安全弁。

## 10. テスト / 検証戦略

| レベル | 検証方法 |
|---|---|
| 構文 | `nix flake check` がエラーなしで通る |
| ビルド | `darwin-rebuild build --flake .#<host>` が成功 |
| dry-run diff | `nvd diff /run/current-system result` で適用差分を表示 |
| 副作用 | switch 後に `defaults read com.apple.dock` 等で実値確認 |
| 別 PC シミュレーション | clean な VM or 別ユーザーで `darwin-rebuild switch` 初回実行 |
| 回帰 | `nix profile history` で前世代を残し、次回 switch 後の diff を PR コメントに貼る |

ゴールデンテスト的に: 棚卸時点の `defaults read com.apple.dock` 出力を `docs/inventory/baseline-com.apple.dock.txt` で凍結し、A6 の switch 後に同コマンドの出力と diff を取る。差分が triage で「無視」したもの以外なら failed とする。

## 11. CLAUDE.md / 文書更新

- **「リポジトリ構造」セクション**: `nix/` を追加、Phase B 完了時に `Brewfile`, `setup/` 行を削除
- **「Brewfile」セクション**: Phase A 期間中は「Phase B で削除予定」注記、Phase B 完了時に削除
- **「シンボリックリンク管理」セクション**: home-manager が管理することを明記、`setup.zsh` の記述を削除
- **新規セクション「Nix 環境」**: flake 構造、`darwin-rebuild` 運用、棚卸 → triage → 翻訳ワークフローの説明

## 12. スコープ外 / 将来作業

- VM や別 PC でのフルセットアップシミュレーション（Phase A の最終ステップで部分的に検証するが、追加 PC 展開は別 issue）
- `nix/` を repo root に昇格（Phase B 完了後の別検討）
- nix flakes の自動更新 CI（dependabot 的な）
- 各種 GUI アプリの App settings（`~/Library/Application Support/<app>/*`）の Nix 化（多くは TCC/sandbox 制約で困難）
- iCloud / Spotlight / Time Machine の宣言化（system.defaults サポート範囲外）

## 13. 既知のリスクと前提

- nix-darwin の `homebrew` モジュールは **brew CLI 自体は管理しない**。brew インストール手順は別途必要
- macOS のバージョンアップで `defaults` の key が変わる可能性。アップグレード後に `nix flake check` が通っても挙動が変わるリスクあり
- `rtk` のリポジトリは公開リポジトリかつ `flake = false` で source のみ取り込む前提。private repo の場合は flake input の認証設定が必要
- App Store アプリのライセンス・サインイン状態は宣言化不可。初回手動ログインが必要
- TCC（プライバシー許可）/ Full Disk Access はユーザー操作必須で nix-darwin の管理外
