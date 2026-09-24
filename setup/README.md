# setup/

Tier 1（リアルタイム symlink）・Tier 2（明示的スクリプト実行）・Tier 3（カットオーバー・
ロールバック）の実装。`darwin-rebuild switch` を使わず、このディレクトリの script を実行して
dotfiles を `$HOME` へ配置・適用する。

設計の全体像・Tier 1/Tier 2 の境界・確定した設計判断は
`docs/superpowers/specs/2026-08-21-restore-script-management-inventory.md` を参照。
Tier 2 の実装計画（各スクリプトの詳細仕様・テスト戦略）は
`docs/superpowers/plans/2026-08-22-restore-script-management-tier2.md` を参照。
Tier 3（カットオーバー・ロールバック機構、home-manager 関連 Nix 定義の廃止）の設計は
`docs/superpowers/specs/2026-08-22-restore-script-management-tier3-cutover-design.md` を参照。
Tier を跨いだ実行順序・部分適用の検出/復旧を担う `setup/migrate.zsh` の設計・過去のインシデント
分析は `docs/superpowers/specs/2026-08-22-migrate-orchestrator-recovery-plan.md` を参照。

## 使い方（実機での唯一のエントリポイントは `setup/migrate.zsh`）

Tier 1/2/3 の各スクリプト（`link.zsh`/`languages.zsh`/`defaults.zsh`/`pam.zsh`/
`claude-code.zsh`/`claude-sync.zsh`/`codex-sync.zsh`/`herdr-sync.zsh`/`hermes-sync.zsh`/`notion.zsh`/`cutover.zsh`）を実機で直接実行することは非推奨。
順序管理なしに個別実行すると部分適用インシデントを再現する（過去に実際に発生した）。
実機での実行は必ず `setup/migrate.zsh` からのみ行う:

`git pull` の直後に適用するときは、下の `--apply` を直接実行する。シェルに読み込み済みの
alias・関数に依存しないため、これが標準の入口。

`aliases` は同じ起動の短縮形として `dotfiles-apply` を定義しているが、その定義自体が pull で
更新されるので、pull 直後の既存シェルではまだ未定義のことがある（以後のログインシェル用）。
引数は受け付けない（`--dry-run` を付けても `migrate.zsh` は第 1 引数の `--apply` しか見ないため、
確認のつもりが適用になるのを防いでいる）。

```sh
# 現在の状態と実行計画を確認する（副作用なし。まず確認したいときはこれを実行する）
zsh ${HOME}/.dotfiles/setup/migrate.zsh --dry-run

# 計画を実行する。単一の root 起動で全 Phase (link -> cutover/pam -> languages/defaults/
# claude-code/claude-sync/codex-sync/herdr-sync/hermes-sync/notion) が完結する。sudo が自動設定する SUDO_USER から元ユーザーを
# 特定し、非 root ステップは元ユーザーへ委譲実行する（詳細は
# docs/superpowers/specs/2026-08-22-migrate-orchestrator-recovery-plan.md 参照）
sudo zsh ${HOME}/.dotfiles/setup/migrate.zsh --apply

# 失敗時のロールバック（migrate.zsh は自動では一切呼ばない。人間の判断でのみ実行する）
sudo zsh ${HOME}/.dotfiles/setup/rollback.zsh
```

`migrate.zsh` は各ステップの実行状況を `~/.dotfiles-migrate/manifest.log` に永続化し、既に
success したステップは再実行しない（idempotent）。全ステップが success になるまで `--apply` は
非ゼロ終了コードを返し続ける（部分適用を健全な状態として扱わない）。`SUDO_USER` が特定できない
環境（sudo を介さない直接 root ログイン等）では非 root ステップは blocked のまま止まる。

例外が 2 つある。

1 つ目は `link`（Tier 1 の symlink 配置）で、**manifest に success があっても毎回再実行する**。
`link.zsh` の宣言（`fs::link_file` の並び）は dotfiles の更新で増えるのに、manifest の success は
「いつ時点の宣言に対する success か」を持たない。skip すると、新しく足した symlink が既存 PC では
永久に張られない（実機インシデント 2026-09-24: `claude-model.zsh` 等 4 本の script と
`destructive-command-guard.py` の計 5 本が未適用のまま `--apply` が success を返し続け、
破壊的コマンドブロック hook は `settings.json` 側の `[ -f "$H" ] || exit 0` ガードで黙って
素通りしていた）。`cutover` のような fingerprint 方式は採らない — `link.zsh` は完全に冪等で、
既に正しい symlink は SKIP ログを出して終わるだけ（実行時間も 1 秒未満）なので、skip して得る
ものが無い。`postcondition-unmet` も記録しない（設計上そうしているだけで、postcondition 違反
ではないため）。

2 つ目は `cutover`（`darwin-rebuild switch`）で、manifest の success だけでは skip しない。
必須 Homebrew バイナリ（mise/starship）の実在に加え、直近 success 時に記録した
desired-input fingerprint — `nix/` 配下の構成と `flake.lock`、`/etc/dotfiles-role`、
`~/.config/dotfiles/homebrew.local.nix` — が現在値と一致するかを毎回検証し、変わっていれば
同じ `--apply` の中で再実行する。`git pull` で Homebrew 宣言が変わった端末で `--apply` が
「全部 success 済み」と判断して何も適用しない、という取りこぼしを防ぐため。fingerprint の記録が
無い古い manifest は安全側に 1 度だけ再実行する（その実行で記録され、以降は通常どおり skip
に戻る）。何が再実行されるかは `--dry-run` で事前に確認できる。

個別スクリプトの直接実行はメンテナンス目的（単体テスト・特定ステップだけをデバッグしたい場合等）
でのみ行う:

```sh
zsh ${HOME}/.dotfiles/setup/link.zsh
zsh ${HOME}/.dotfiles/setup/languages.zsh
zsh ${HOME}/.dotfiles/setup/defaults.zsh
zsh ${HOME}/.dotfiles/setup/pam.zsh
zsh ${HOME}/.dotfiles/setup/claude-code.zsh
zsh ${HOME}/.dotfiles/setup/claude-sync.zsh
zsh ${HOME}/.dotfiles/setup/codex-sync.zsh
zsh ${HOME}/.dotfiles/setup/herdr-sync.zsh
zsh ${HOME}/.dotfiles/setup/hermes-sync.zsh
zsh ${HOME}/.dotfiles/setup/notion.zsh
sudo USER=${USER} zsh ${HOME}/.dotfiles/setup/cutover.zsh
```

`setup/link.zsh` は一度実行すれば、以後の repo 編集（`zshrc`/`aliases`/`claude/CLAUDE.md` 等）は
symlink 越しに即座に反映される。再実行が必要なのは「`setup/link.zsh` 自体に新しい対応行を
追加したとき」だけで、それは `migrate.zsh --apply` が毎回 `link` を走らせるので自動的に拾われる
（上記「例外が 2 つある」参照。ここを手で叩く必要は無い）。Tier 2 の各スクリプトは冪等なので、
値を変更した後は該当スクリプトを再実行すれば反映される。

## 安全策（明示関数）

- `fs::link_file`（`lib/fs.zsh`）: symlink 先に既に実体ファイル/ディレクトリがある場合、
  黙って上書きせず `<path>.before-setup` に退避してから symlink を作る。誤って手元の変更を
  失わないための安全策。
- `fs::ensure_realfile`（`lib/fs.zsh`）: `~/.gitconfig` や Claude Code のマーカーファイルなど、
  「dotfiles リポジトリで追跡してはいけない値／状態」を書き込み可能な実体ファイルとして保護する。
  3rd party ツール（coderabbit CLI の machineId 書き込み等）や OAuth token を含む running
  config を壊さないための安全策。symlink のままだと read-only 相当の問題やリポジトリへの
  意図しない値の混入が起きる。
- 変数名は `path` を避ける（`fs::ensure_realfile` 参照）。zsh は `path` を `$PATH` と束縛された
  特殊配列として扱うため、同一スコープ内で `local path=...` すると `mkdir`/`touch` 等の
  コマンド解決が壊れる（実装中に発見。詳細は Tier 1 実装計画の Task 2 注記を参照）。
- `pam.zsh`: 既存の `/etc/pam.d/sudo_local` の内容が想定と異なる場合、`.before-setup` に退避
  してから上書きする。退避先が既に存在する場合はエラーで停止し、既存ファイルには一切触れない
  （`fs::ensure_realfile` と同じ no-data-loss 方針）。書き込み先は `SUDO_LOCAL_PATH` 環境変数で
  上書きできる（テスト用）。
- `defaults.zsh`: 各 domain を初めて書き込む前に `defaults export <domain>
  ~/.dotfiles-defaults-backup/<domain>.plist` で現状のスナップショットを 1 回だけ取る
  （2 回目以降はスキップ）。IME/入力ソースの plist は複製せず `nix/modules/darwin/` を
  単一ソースとして参照する。role は `/etc/dotfiles-role`（`nix/flake.nix` と同じ規約）から
  解決し、テストでは `DOTFILES_ROLE_FILE` で上書きできる。
- `claude-sync.zsh`/`codex-sync.zsh`/`herdr-sync.zsh`: 破壊的な操作を行わない（MCP merge は
  add-only、config.toml は seed-if-absent、skills repo clone は既存ディレクトリを一切変更しない）。
  `herdr-sync.zsh` は primary チェックアウト（`~/.dotfiles`）から実行されたときだけ
  plugin link と設定配置を行う。`herdr plugin link` は渡されたパスをそのまま登録先に
  するため、使い捨ての worktree を登録すると削除時にプラグインと allowlist が同時に壊れる。
  primary 以外から実行された場合は両方まとめてスキップする。登録先パスが既に一致して
  いれば何もせず、`repos.local.json`（マシンローカルの allowlist）は seed-if-absent で
  既存の中身に触れない。
- `hermes-sync.zsh`: Hermes に RTK 連携プラグインを入れる（`rtk init --agent hermes` が
  `~/.hermes/plugins/rtk-rewrite/` を作り、`~/.hermes/config.yaml` の `plugins.enabled` に
  登録する）。生成物も登録先も Hermes 所有の running config なので追跡せず、宣言側で固定
  するのは「rtk を入れること（`homebrew.nix`）」と「その rtk に Hermes 用アダプタを張らせる
  こと（このスクリプト）」だけ。`--auto-patch` を付けるのは、管理下のファイルが既知の
  アダプタと違うときの確認プロンプトで migrate が stdin 待ちのまま止まらないようにするため。
  `RTK_TELEMETRY_DISABLED=1` はこの 1 回の呼び出しに閉じた指定で、`rtk init` の
  テレメトリ同意フローに巻き込まれないようにする（PC の設定は変えない。有効化したく
  なったら人が `rtk telemetry enable` を叩く）。呼び出しはサブシェルで `${HOME}` へ
  移ってから行う。`rtk init` は agent によっては cwd 配下へ project スコープの設定を書く
  作りで、`migrate.zsh` はリポジトリの作業ツリーを cwd にしたまま委譲実行するため。

  スキップ条件は 2 つ。**Hermes が入っていない**（`~/.hermes/config.yaml` が無い）か、
  **rtk が PATH に無い**かで、どちらも fail-open（warning のみで exit 0）。Hermes は
  この dotfiles の宣言対象ではない（`homebrew.nix` にも無い）ので、入っていない PC は
  正常な状態として扱う。判定に `~/.hermes` ディレクトリの有無は使えない — Tier 1 の
  `link.zsh` が SOUL.md を置く時点でこのディレクトリを作るため、Hermes が無い PC でも
  必ず存在する。判定とパスは `setup/lib/hermes.zsh` に寄せてあり、health check も同じ
  定義を引く（`setup/lib/herdr.zsh`・`setup/lib/notion.zsh` と同じ理由）。health check が
  プラグインの実在を要求するのも、この 2 つのスキップ条件が両方とも偽のときだけ。

  Claude Code 側は同じ RTK でもここを通らない。hook は追跡済みの `claude/settings.json` に
  直接宣言してあり、`rtk init -g` は使わない（走らせると Tier 1 の symlink 越しに
  リポジトリの `claude/settings.json` を書き換えてしまう）。

- `claude-code.zsh`: Claude Code CLI をネイティブ版として `${HOME}/.local/bin` へ導入する。
  以前は Homebrew cask (`claude-code`) で管理していたが、cask 版は Claude Code 自身の
  バックグラウンド自動更新が効かず、`brew upgrade` を回した PC だけが新しい版になるため
  複数台で版が食い違う（公式もネイティブ版を推奨）。cask は `homebrew.nix` から削除済み。
  ただし `onActivation.cleanup = "none"` なので、**宣言から外しても実機の cask は消えない**。
  既存 PC では `brew uninstall --cask claude-code` を手動で 1 度だけ実行する。未実行だと
  `/opt/homebrew/bin/claude` が PATH 上でネイティブ版より先に来て cask 版が使われ続ける
  （health check は `${HOME}/.local/bin/claude` の実在しか見ないので、この状態でも通る）。

  その uninstall に **`--zap` を付けてはいけない**。`claude-code` cask の zap stanza は
  `~/.local/bin/claude`・`~/.local/share/claude`・`~/.claude.json*`・`~/.claude` を消す対象に
  していて、ネイティブ版の実体と MCP / 認証設定ごと消える。落とすのは `binary "claude"` の
  symlink と Caskroom エントリだけでよい。

  導入先は環境変数で渡さない・渡せない。公式インストーラ (`https://claude.ai/install.sh`)
  が落としたバイナリの `claude install` が `${HOME}/.local/bin/claude` にランチャーを置き、
  版ごとの実体は `${HOME}/.local/share/claude/` 配下で自身が管理する。パスは
  `setup/lib/claude-code.zsh` に寄せてあり、health check も同じ定義を引く。

  **版は固定しない**（`notion.zsh` と意図的に方針が違う）。インストーラを引数無しで呼んで
  stable を入れ、以降の更新は Claude Code 自身に任せる。自動更新が効くことが cask から
  移行した理由そのものなので、宣言側で版を pin すると更新が走るたびに health check が
  落ちる。したがって health check も版は見ず、`${HOME}/.local/bin/claude` が実行可能な
  ファイルであることだけを **fail-closed** で確認する。

  `${HOME}/.local/bin/claude` が既に実行可能なファイルなら **インストーラを一切呼ばない**
  （自動更新で進んだ既存バイナリを巻き戻さない）。判定は `-x` 単独ではなく `-f && -x`
  （実行ビットの立ったディレクトリを「導入済み」と誤判定しないため。health check も同じ条件）。

  認証は扱わない。トークンの読み書きはせず、ログインは人間が `claude` 側の手順で行う
  （cask からの移行でも `~/.claude` 配下の設定・認証情報はそのまま引き継がれる）。

- `notion.zsh`: Notion CLI (`ntn`) に Homebrew formula が無いため、公式インストーラ
  (`https://ntn.dev/install.sh`) を使う唯一の Tier 2 ステップ。mise の npm backend でも
  導入できるが、グローバル CLI を Node ランタイムに依存させないため公式配布バイナリを
  使う。インストーラには
  2 つの環境変数を渡して導入結果を宣言側で決めきる:
  - `NTN_INSTALL_DIR` = `${HOME}/.local/bin`。インストーラ既定の導入先選択は実行時の PATH の
    形に依存して揺れるため、宣言側で固定して health check と一致させる
  - `NTN_VERSION` = `setup/lib/notion.zsh` の `NTN_PINNED_VERSION`（現在 `0.23.4`）。既定の
    `latest` だと「導入した日」で版が決まり PC ごとに別物が入る。版を上げるのは dotfiles
    側の明示変更で行う

  `${HOME}/.local/bin/ntn` が既に実行可能なファイルなら **インストーラを一切呼ばない**
  （既存バイナリを上書きしない）。判定は `-x` 単独ではなく `-f && -x`（実行ビットの立った
  ディレクトリを「導入済み」と誤判定しないため。health check も同じ条件）。

  この install-if-absent だけだと、宣言の版を上げても既に実体のある PC は古いまま success に
  なり続ける（版が効くのは新規導入時だけ）。そこで `migrate.zsh` の health check が
  `ntn --version` を実行し、`NTN_PINNED_VERSION` と一致しなければ **fail-closed** で落とす。
  自動では差し替えない — 実行中かもしれないバイナリを migrate が黙って置き換えないため、
  人が実体を削除してから `--apply` を再実行する。宣言値とパスは `setup/lib/notion.zsh` に
  寄せてあり、導入する側と確認する側が同じ定義を引く（`setup/lib/herdr.zsh` と同じ理由）。

  この probe は root 起動時に `sudo -u <元ユーザー> -H --` を前置して元ユーザーとして実行する
  （`migrate::ntn_version`）。実体は元ユーザーの `$HOME` 配下にあって本人が書き換えられる
  ファイルなので、検証のために root の権限で走らせる理由が無い。非 root ステップの委譲実行と
  同じ規則で、元ユーザーを特定できないときは probe せず fail-closed に落ちる。

  `curl` は `bash` に直結せず一旦ファイルへ落とす（取得失敗時に空スクリプトを実行して
  「成功」に見えるのを防ぐ）。**初回ダウンロードの失敗は fail-closed** で migrate 全体を
  止める。`ntn` は恒久的に宣言したグローバル必須ツールなので「入らなかったが成功」を健全な
  状態として扱わない。既にバイナリがある PC では一切ネットワークに出ないため、オフラインでも
  `--apply` は通る（ネットワークが要るのは初回導入のときだけ）。

  トークン（`NOTION_API_KEY` 等）は読まない・要求しない・保存しない。導入後の認証は人間が
  `ntn` 側の手順で行う。PATH への `${HOME}/.local/bin` 追加は Tier 1 の `zshenv` が
  append で 1 箇所だけ行う（`zshrc` 側には書かない）。
- `cutover.zsh`: 実行前に `darwin-rebuild --list-generations` の出力を
  `~/.dotfiles-cutover-backup/pre-cutover-generations-<timestamp>.txt` へ記録してから
  `nix build`（副作用なし）で pre-flight 確認し、成功したときだけ `darwin-rebuild switch`
  を実行する。build 失敗時は switch を実行しない。
- `rollback.zsh`: `darwin-rebuild switch --rollback` を実行する前に `$HOME` 配下の
  `*.before-nix` 残骸を検出する。1 件でも見つかれば一覧を出して停止し、`darwin-rebuild` を
  一切呼ばない（home-manager 再活性化時の backupFileExtension 衝突を防ぐため。
  `fs::ensure_realfile` と同じ no-data-loss 方針で、自動退避はしない）。
- `migrate.zsh`: Tier 1/2/3 を跨いだ唯一のオーケストレーター。実行順序は Phase 1
  (`link`) → Phase 2 (`cutover`/`pam`、root 必須) → Phase 3 (`languages`/`defaults`/
  `claude-code`/`claude-sync`/`codex-sync`/`herdr-sync`/`hermes-sync`/`notion`)。`claude-code` を
  `claude-sync` より前に置くのは、`claude-sync.zsh` の plugin 同期が `claude` CLI の実体を要求する
  ため。`languages.zsh` 自身が「mise は darwin-switch で事前導入
  済みが前提」と明記しているため、cutover を languages より先に置く。各ステップの結果は
  `~/.dotfiles-migrate/manifest.log` に永続化し、success 済みステップは再実行しない
  （idempotent な部分適用検出・再開）。ただし `cutover` だけは、必須バイナリの実在と
  desired-input fingerprint の一致（宣言側が変わっていないこと）も満たすときにのみ skip する。権限不足なステップは blocked として記録し、その
  Phase 内の残りは試行を続けるが次の Phase へは進まない（Phase 境界は厳格）。実失敗は
  即座に全体を停止する（fail-closed）。`rollback.zsh` は一切呼ばない（no-automatic-rollback、
  常に人間の明示判断）。全ステップ success 後も、manifest の自己申告を信用せず各ステップの
  実際の効果をファイルシステムから再検証する health check を通らない限り成功とみなさない。
  設計根拠・過去のインシデント分析は
  `docs/superpowers/specs/2026-08-22-migrate-orchestrator-recovery-plan.md` を参照。

## テスト

```sh
bats setup/tests/*.bats
bats herdr/plugins/*/tests/*.bats
```

`setup/tests/` は `setup/**` だけでなく `zshenv`/`zshrc` も検証対象にしている（PATH 宣言を
1 箇所に保つ `zshenv.bats`/`zshrc.bats`）。`.github/workflows/setup-check.yml` の `paths` にも
この 2 ファイルを含めてあるので、`setup/**` を伴わない単独編集でも CI が走る。

`setup/lib/herdr.zsh` は Herdr プラグインの識別子とパス解決だけを持つ共有ライブラリ。
配置する側（`herdr-sync.zsh`）と確認する側（`migrate.zsh` の health check）が別々に
パスを組み立てると、Herdr が設定ディレクトリの位置を変えたときに health check だけが
古い場所を見に行くため、解決ロジックを 1 箇所に寄せている。

配置する条件も両者で揃える。何も配置しないのは **primary チェックアウト
（`~/.dotfiles`）以外からの実行** のときだけなので、health check もその条件でだけ
検証を飛ばす。`herdr` の有無では飛ばさない — herdr が無くても `herdr-sync.zsh` は
既定パスへ allowlist を配置して成功するため、そこを飛ばすと「配置されているのに
検証しない」死角になる。

`herdr::plugin_config_dir` の既知の制約: `herdr plugin config-dir` に問い合わせるのは
**呼び出し元自身のホームを対象にするときだけ**。`migrate.zsh` の health check は root で
走りつつ元ユーザーのホームを検査するため、そこで herdr を呼ぶと root 自身の設定
ディレクトリを答えてしまい、存在しないパスを検査して必ず失敗する。よって別ユーザーの
ホームが対象のとき（および herdr 不在時）は既定パス
`<home>/.config/herdr/plugins/config/<plugin_id>` の組み立てだけを使う。
**この経路は Herdr がレイアウトを変えても追従しない。** 変わった場合は health check が
先に落ちるので、`setup/lib/herdr.zsh` のフォールバックを更新すること
（root から元ユーザー文脈で herdr を呼び直す作りにはしていない。sudo 越しの
委譲実行を health check にまで広げるほどの利得が無いため）。

`fs::link_file`/`fs::ensure_realfile` は関数単位、`link.zsh`/`languages.zsh`/`defaults.zsh`/
`pam.zsh`/`claude-code.zsh`/`claude-sync.zsh`/`codex-sync.zsh`/`herdr-sync.zsh`/`hermes-sync.zsh`/`notion.zsh`/`cutover.zsh`/`rollback.zsh`/
`migrate.zsh` は、
実コマンド（`defaults`/`mise`/`corepack`/`claude`/`herdr`/`rtk`/`git`/`darwin-rebuild`/`nix`）を PATH 上の
stub 実行ファイルに差し替え、`$HOME` を一時ディレクトリに差し替えたサンドボックスでの統合テスト
（実機・実ネットワーク・実パッケージマネージャ・実 `darwin-rebuild switch` には一切触れない）。

公式インストーラを呼ぶ 2 つ（`notion.zsh`/`claude-code.zsh`）だけは `curl` の扱いが 2 通りある。
単体テスト（`setup/tests/notion.bats`・`setup/tests/claude-code.bats`）は `curl` を stub に
差し替えて取得失敗の経路まで見る。`migrate.zsh` 経由の統合テストでは stub を使わず、
`NTN_INSTALLER_URL`／`CLAUDE_INSTALLER_URL` に `file://` の偽インストーラを渡して
**実 `curl` をオフラインで** 走らせる。`migrate.zsh` の委譲実行は Homebrew prefix を PATH 先頭に固定で差し込むため、
そこでの `curl` stub は実機に Homebrew 版 `curl` があると負けて実ネットワークに出てしまう。
`migrate.zsh` のテストは Tier 1 が作る `~/.zshenv` symlink を経由して後続の子 `zsh` プロセスが
実際の zshenv を re-source する（Phase を跨いだ実行を初めて連結するテストのため、単独スクリプトの
テストでは踏まなかった経路）。stub 実行ファイルを `#!/bin/bash` にしているのはこのため
（`#!/bin/zsh` だと stub 自身が `~/.zshenv` を再度 source し、そこでの `mise activate --shims`
がまた `mise` を呼ぶ無限再帰になる）。CI は `.github/workflows/setup-check.yml` が `setup/**`
と `herdr/**` の変更ごとに両方の bats スイートを実行する。

`herdr/plugins/*/tests/*.bats`（Herdr ローカルプラグイン）も同じ workflow が実行する。
`herdr` はスタブに差し替えるが、`git` はサンドボックス内に作った使い捨てリポジトリに対して
実際に実行する（allowlist 判定・base 解決・監査の判定はいずれも git の実挙動が対象のため、
stub では検証にならない）。
