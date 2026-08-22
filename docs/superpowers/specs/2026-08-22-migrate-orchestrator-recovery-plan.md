# migrate.zsh: 単一エントリポイント設計と部分適用インシデントの復旧計画

**ステータス**: 実装済み（本ドキュメントと同一 PR）。実機への適用は別途、人間の明示判断で行う。
**スコープ境界**: 本 PR はサンドボックス検証のみ。実機（sudo/darwin-rebuild/brew/defaults/PAM/mise の
実行）には一切触れない。

関連ドキュメント:
- `docs/superpowers/specs/2026-08-21-restore-script-management-inventory.md`
- `docs/superpowers/specs/2026-08-22-restore-script-management-tier3-cutover-design.md`
- `setup/README.md`

## 1. 背景（インシデント）

Tier 1（`setup/link.zsh`、PR #53）・Tier 2（`setup/*.zsh`、PR #54）・Tier 3
（`setup/cutover.zsh`/`setup/rollback.zsh` + home-manager 関連 Nix 定義の削除、PR #56）は、
いずれも「個別に明示実行する独立したスクリプト」として設計・実装された。Tier 3 の設計ドキュメント
自身が「Tier 1/2 のスクリプト自体はオーケストレーションしない（責務を混ぜない）」と明記しており、
実機での実行順序・進捗管理は**人間の記憶と手順書だけに依存していた**。

この状態で実機に対して Tier スクリプト群が部分的に適用される事故が発生した。原因は個々のスクリプトの
バグではなく、**「どのスクリプトをどの順で実行し終えたか」を追跡する仕組みが最初から存在しなかった**
という構造的な欠落である。

**本ドキュメントおよび本 PR の立場**: 部分適用は「動いているように見えるなら許容できる中間状態」では
なく、それ自体がインシデントである。`migrate.zsh` は部分適用を検出したら常に非ゼロ終了コードを返し、
「健全」「一旦様子見でよい」という言い回しを一切用いない。全ステップが success になるまで未完了として
扱い続ける。

## 2. 既存スクリプトを跨いで見えた、壊れていた／見落とされていた前提

個々の Tier スクリプトはそれぞれ単体では正しく（idempotent に）動作するが、それらを**連結して**
実行しようとして初めて見える前提の破れが複数あった。

1. **クロス Tier の状態追跡が存在しない**
   `fs::link_file` 等の idempotency はスクリプト単体のものであり、「Tier 1 は今日実行済みか」を
   記録する仕組みはどこにも無かった。実行順序の正しさは完全に人間の記憶に依存していた。これが
   インシデントの直接原因。

2. **`languages.zsh` 自身が「mise は Homebrew 経由で事前に導入されている」ことを前提にしている**
   `languages.zsh` は `command -v mise` が失敗すると次のメッセージで exit 1 する:
   > 「mise が見つかりません。'darwin-switch' で Homebrew 経由の導入を先に済ませてください」
   これは **cutover（darwin-rebuild switch）が languages.zsh より先に必要な場合がある**ことを
   スクリプト自身が示している。ところが Tier 1/2/3 の番号順（実装順）をそのまま実行順だと
   誤解すると、Tier 2 の `languages.zsh` を Tier 3 の `cutover.zsh` より先に実行してしまい、
   mise 未導入で必ず失敗する。**Tier の実装順（1→2→3）と実機での依存順は同一ではない。**

3. **root 権限の要否がスクリプトごとに異なり、一度の実行では揃わない**
   `pam.zsh`（`/etc/pam.d/sudo_local` への書き込み）と `cutover.zsh`（`darwin-rebuild switch`）は
   root が必須。一方 `link.zsh`/`languages.zsh`/`defaults.zsh`/`claude-sync.zsh`/`codex-sync.zsh`
   は `$HOME` 配下を操作するため **root で実行してはいけない**（root 所有物が `$HOME` に紛れ込む、
   あるいは `sudo` の `env_reset` で `$HOME` が `/var/root` に化けるリスク）。両者は同じ `sudo`
   セッション内で安全に両立できないため、単一のシェル実行では完結しない。

4. **`rollback.zsh` の安全網は時間とともに縮小する**
   home-manager を含む世代へ戻す唯一の経路は、**その実機に現存する nix 世代**である。
   `nix/home.nix` 等は既に repo から削除済みのため、git からは再現できない。世代が
   ガベージコレクトされれば、この経路は永久に失われる（Tier 3 設計ドキュメント §8.3 に既知の
   前提として記載されているが、時間経過で悪化する一方向のリスクである点は明示されていなかった）。

5. **「switch が成功したように見える」ことは実効果の証拠にならない**
   過去に `darwin-rebuild switch` が activation script の途中で無言で abort していた実例がある
   （`/etc/zshrc` の Unexpected files エラー等）。個々のスクリプトの exit code 0 だけを信頼すると
   同種の見落としを再現しかねない。

## 3. `migrate.zsh` の設計

### 3.1 実行順序（3 Phase）

```
Phase 1: link                                        (非 root)
Phase 2: cutover, pam                                 (root 必須)
Phase 3: languages, defaults, claude-sync, codex-sync  (非 root)
```

Phase 2 が Phase 3 より前にあるのは §2-2 の発見（mise は cutover が導入する）に対応するため。
Phase 2 内の 2 ステップは両方 root 必須なので同じ Phase にまとめ、sudo プロンプトを 1 回に集約する。
`rollback.zsh` はどの Phase にも含まれない（§3.4 参照）。

Phase 境界は厳格：ある Phase の全ステップが success にならない限り次の Phase には進まない。
Phase **内**では、権限不足で blocked になったステップがあっても同じ Phase の残りのステップは
試行を続ける（例: 非 root 実行中に pam が blocked でも、それより前の cutover が既に success なら
気にせず進む、等）。実失敗（スクリプトが非ゼロ終了）は Phase 境界に関係なく即座に全体を停止する。

### 3.2 persistent manifest（`~/.dotfiles-migrate/manifest.log`）

各ステップの `start`/`success`/`fail`/`blocked` を追記専用ログとして記録する。apply 実行のたびに
このログを読み、あるステップの最新の終端状態が `success` ならスキップする。これにより：

- 「今どこまで終わっているか」を実行のたびに問い合わせずに一貫して答えられる
- root/非 root で 2〜3 回に分けて実行しても、既に終わったステップを再実行しない
- 部分適用済みの実機に対して安全に「続きから」再開できる

dry-run はこの manifest を読むだけで、一切書き込まない（副作用ゼロを保証する）。

### 3.3 権限ガード（fail-closed）

各ステップの実行前に、現在の実行コンテキストがそのステップの権限要件を満たすか確認する。
満たさなければ `blocked` として記録し、決してそのステップを試行しない（sudo を自分で呼ばない。
`cutover.zsh`/`pam.zsh` 自身の「スクリプト自身は sudo を内部で呼ばない」規約を `migrate.zsh` も
継承する）。root 実行時に非 root 専用ステップを誤って実行しようとする事故（`$HOME` への
root 所有物混入）も同じ仕組みで防ぐ。

### 3.4 no-automatic-rollback

`migrate.zsh` は `rollback.zsh` を一切呼ばない（grep で静的に検証済み、`setup/tests/migrate.bats`
参照）。ロールバックは常に人間が明示的に判断する別作業。理由:

- ロールバック可否の判定材料（§2-4 の世代 GC リスク等）は自動判断させるには重すぎる
- fail-closed の思想（`fs::ensure_realfile`/`rollback.zsh` の `.before-nix` ガード等、このリポジトリ
  全体の一貫した設計判断）を踏襲する: 失敗時に「賢く」何かを試みるより、止まって人間に委ねる方が
  安全

### 3.5 health check（manifest の自己申告を信用しない）

全 Phase が success になった後、`migrate.zsh` は各ステップの**実際の効果**を改めてファイルシステム
から確認する（symlink の実在、`~/.claude.json`/`~/.codex/config.toml` の実在、
`~/.dotfiles-cutover-backup/` の世代バックアップの実在、`mise` の PATH 解決、等）。1 件でも欠けて
いれば、たとえ全ステップの exit code が 0 だったとしても apply 全体を失敗として報告する
（§2-5 の教訓への直接対応）。

### 3.6 モード

- `--dry-run`: 現在の計画・状態を表示するだけ。副作用ゼロ（manifest も書かない、スクリプトも
  一切実行しない）。
- `--apply`: 計画を実行する。
- 引数なし: 使い方を表示して exit 1（どちらのモードで動くかを常に明示させる）。

## 4. 実機での復旧手順（このセッションでは実行しない）

### 4.1 現状把握（read-only、いつでも安全に実行できる）

```sh
readlink ~/.zshrc ~/.zshenv                      # Tier 1 が適用済みか
ls -la /etc/pam.d/sudo_local                     # Tier 2 pam が適用済みか
darwin-rebuild --list-generations                # Tier 3 cutover が適用済みか
ls ~/.dotfiles-cutover-backup/ 2>/dev/null        # cutover の実行履歴
ls ~/.dotfiles-migrate/manifest.log 2>/dev/null   # migrate.zsh 自身の実行履歴（本 PR 後）
find ~ -maxdepth 3 \( -name '*.before-nix*' -o -name '*.before-setup' \) 2>/dev/null
```

### 4.2 本 PR マージ後の復旧フロー

1. `zsh ~/.dotfiles/setup/migrate.zsh --dry-run` で現在の状態を確認する（副作用なし）
2. 表示された計画に従い `--apply` を実行する。root が必要な Phase に到達したら、指示された
   とおり `sudo` を付けて再実行する（§3.1 のとおり最大 3 回の呼び出しになりうる）
3. 最終的に「全ステップ success で完了しました」かつ health check 通過が表示されるまで、
   `--apply` を安全に何度でも再実行してよい（idempotent）
4. 途中で `fail`（blocked ではなく実失敗）が出た場合は停止し、`setup/rollback.zsh` を使うかどうか
   を含めて人間が判断する（自動では一切ロールバックしない）

## 5. 将来のユーザー向け唯一のエントリポイント

`setup/migrate.zsh` 以外の Tier スクリプト（`link.zsh`/`languages.zsh`/`defaults.zsh`/`pam.zsh`/
`claude-sync.zsh`/`codex-sync.zsh`/`cutover.zsh`）は内部実装として残るが、実機での直接実行は
今後非推奨とする（メンテナンス目的でのみ直接実行してよい）。`setup/README.md` を参照。
