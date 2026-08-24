# merge-permit 運用フロー

merge（`git merge` / `gh pr merge` / GitHub REST・GraphQL の merge API 経由 /
`mcp__github__merge_pull_request` tool / GitHub 純正 stacked pull requests の
stack merge 操作）は、グローバル PreToolUse hook
(`~/.dotfiles/claude/hooks/merge-permit/guard.py`) が無許可の実行を機械的にブロックする。
実行を通すには、有効な **merge-permit**（1 回限りの許可券）が必要。

このドキュメントは permit の発行・確認・取り消しの操作手順。ルールそのもの
（いつ許可を得るべきか）は `claude/rules/core.md`（不可逆な操作）と
`claude/rules/orchestrator.md`（merge permit の発行）が SSOT。

## 誰が permit を発行するか

**Hermes/orchestrator だけが発行する。** ユーザーから当該ターンでの明示許可を
得た直後に、Hermes 自身が CLI を実行して permit を発行し、そのうえで
Claude Code へ「permit を発行したので今すぐ merge してよい」と伝える。

- profile 既定値・過去の承認・スタックの既定挙動・推論された意図は permit 発行の根拠にならない
- Claude Code が自分自身の merge のために自分で permit を発行することは規約違反（[既知の限界](#既知の限界)を参照）

## CLI

本体: `~/.dotfiles/claude/hooks/merge-permit/merge-permit-cli.zsh`

```sh
# 発行 (gh pr merge 用、PR番号指定)
merge-permit-cli.zsh create --action gh-pr-merge --target 123 --actor hermes \
  --reason "user approved merging PR #123 in this turn"

# 発行 (git merge 用、ブランチ名指定)
merge-permit-cli.zsh create --action git-merge --target feature/foo --actor hermes

# 発行 (現在ブランチに紐づく PR に対して。--target current)
merge-permit-cli.zsh create --action gh-pr-merge --target current --actor hermes

# 発行 (承認された stack を GitHub 純正の stack merge 操作でまとめて merge する用。
# --target には実際に `gh stack merge` に渡す stack番号 or PR番号と同じ値を指定する)
merge-permit-cli.zsh create --action gh-stack-merge --target 128 --actor hermes \
  --reason "user approved merging the whole stack up to PR #128 in this turn"

# 一覧 (有効な permit のみ。--all で消費済み/失効済みも表示)
merge-permit-cli.zsh list [--all]

# 個別確認
merge-permit-cli.zsh inspect --id mp_xxxxxxxxxxxx

# 取り消し (未消費のものを即失効させる)
merge-permit-cli.zsh revoke --id mp_xxxxxxxxxxxx

# 古い消費済み/失効済みファイルの掃除 (既定: 7日超)
merge-permit-cli.zsh gc [--older-than-days N]
```

`--repo-path`（既定 cwd）から `git remote get-url origin` を解決して repo
識別子にする。origin が無い/別ホストの場合は `--repo-identity` で直接指定できる
(`owner/repo` のように host を省略した場合は `github.com/` を補って正規化する。
コマンド側の `--repo`/`-R` フラグ抽出と同じ正規化を通すため、`--repo-identity
owner/repo` は `gh ... --repo owner/repo` と同じ repo 識別子になる)。

## permit の性質

- **repo + action + target に紐づく**: repo（origin の正規化識別子）・action
  （`gh-pr-merge` / `git-merge` / `graphql-merge` / `gh-stack-merge`）・target
  （PR番号 or ブランチ名 or stack merge の対象番号）が実行時のコマンドと完全一致
  しないと使えない。別リポジトリ・別 PR・別ブランチ・別 stack には流用できない
- **短命**: 既定 TTL は 300 秒（5分）。`--ttl` で延長できるが上限 900 秒（15分）でクランプされる
- **1 回限り**: 消費（実行が通った）と同時に即座に使用不能になる。ファイルロックで同時実行時の二重消費も防ぐ
- **秘密情報を含まない**: `~/.claude/merge-permits/<id>.json` に平文 JSON で保存する。中身は
  repo 識別子・action・target・作成/失効時刻・発行者・理由のみ

## stacked PR の作成 (`gh stack`)

`gh-stack`（GitHub 純正 CLI 拡張、`github` org 直下）はこのマシンにグローバル
導入済み:

```sh
gh extension install github/gh-stack
gh extension list
# gh stack	github/gh-stack	v0.1.0
```

`gh stack --help` で確認できる実際の subcommand（発明していない、すべて
`--help` 出力に存在するもののみ）:

```
Stack management: add, checkout, init, modify, unstack, view
Remote operations: link, merge, push, rebase, submit, sync
Navigation:        bottom, down, switch, top, trunk, up
```

### worktree との組み合わせ方（実機検証済み）

`gh stack` はカレントディレクトリの branch を checkout しながらレイヤー間を
移動するツールで、状態は repo の共有 `.git`（`git rev-parse --git-common-dir`）
配下の `gh-stack` ファイルに保存される。**複数 worktree にまたがっては動かない**
ことを実機で確認した:

- 同じ stack の branch を worktree A で checkout した状態で worktree B から
  `git checkout <same-branch>` すると git 自体が拒否する
  （`fatal: '<branch>' is already used by worktree at ...`）
- `gh stack checkout <branch>` を別 worktree から実行しても
  `✗ no locally tracked stack found for "<branch>"` になり、共有 `.git` に
  記録済みの stack でも見つけられない

したがって:

- **stack 全体を 1 つの Herdr-linked worktree に割り当てる**（main / 他タスクの
  worktree からの隔離という既存規約の目的は満たしたまま、stack 1 つ = worktree
  1 つとして扱う。レイヤーごとに別 worktree には分割しない）
- 手順:
  1. `gh stack init <first-layer-branch>`（既存 branch 群を渡せば adopt もできる）
  2. 実装・commit → `gh stack add <next-layer-branch>` で次のレイヤーへ。
     同じ worktree 内でレイヤー数ぶん繰り返す
  3. `gh stack submit`（非対話なら `--auto`）で全 branch を push し、
     各 dependent PR を親 PR の head branch を base にして作成・更新する
- 同じ stack の異なるレイヤーを別々の worktree/セッションへ並列委譲することは
  **サポートされない**。指示された場合は手動 base 指定などに迂回せず、
  サポート外である旨を blocker として報告する（`claude/rules/orchestrator.md`）

## stacked pull request の merge（GitHub 純正機能）

GitHub の stacked pull requests は 2026-07-30 に public preview として提供開始
された純正機能（[Changelog](https://github.blog/changelog/2026-07-30-stacked-pull-requests-are-now-in-public-preview/)、
[About stacked pull requests](https://docs.github.com/en/pull-requests/get-started/about-stacked-prs)）。
一次情報で確認できた事実（**public preview のため仕様変更の可能性あり**）:

- stack の底（bottom）の PR は trunk（既定ブランチ）を base にし、各後続 PR は
  「その 1 つ下の PR の branch」を base にする。branch の祖先関係だけでは
  stacked PR として扱われない（`claude/rules/core.md` のルールはこれに対応）
- **merge は 1 回の atomic 操作**: 「選択した PR と、その下の未マージ PR すべてが
  1 回の操作でまとめて base branch に着地する」（[Merging stacked pull requests](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/merging-stacked-pull-requests)）。
  個々の PR を順番に merge するのではないため、依存待ちの PR ごとに CI が
  再トリガーされることはない
- **legacy の同期 merge では stack を merge できない**。REST の非同期 merge
  エンドポイントが必須:
  `PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge-async`
  （[REST API reference](https://docs.github.com/en/rest/pulls/pulls?apiVersion=2026-03-10#merge-a-pull-request-asynchronously)）。
  レスポンスは非同期（202 Accepted、`status: pending|merged|enqueued|failed` を
  `GET .../pulls/{pull_number}/merge-async/{uuid}` でポーリング）
- GraphQL は stack について read-only（stack 用の mutation は存在しない。
  [Stacked pull requests in the REST and GraphQL APIs](https://docs.github.com/en/pull-requests/reference/stacked-pull-requests-rest-and-graphql-apis)）。
  GraphQL 経由で stack を merge することはできない
- 公式 CLI 拡張は `gh-stack`（`gh extension install github/gh-stack`、
  `github` org 直下。[github/gh-stack](https://github.com/github/gh-stack)）。
  実マージ subcommand は `gh stack merge [<stack-number> | <pr-number>]`
  （`gh stack merge --help` で実機確認済み。flags: `--yes`/`-y` で非対話実行、
  `--merge-method {merge|squash|rebase}` または `--merge`/`--squash`/`--rebase`
  で方式指定。番号省略時はカレント branch の stack が対象）。
  core の `gh pr merge` に stack 対応の記載は確認できなかった
- auto-merge は stacked PR では未対応

**標準経路は `gh stack merge`。** 承認された stack に対して Claude Code が実行する
のはこのコマンド 1 回のみで、merge-permit の `gh-stack-merge` action もこれを前提に
1 回の呼び出しだけを許可する。API を直接叩く `PUT .../pulls/{番号}/merge-async`
は `gh stack` 拡張自体の内部実装が使っている経路であり、hook はどちらの経路で
呼ばれても同じ `gh-stack-merge` action として扱う（`claude/hooks/merge-permit/lib.py`）。
`gh pr merge` を stack の PR に対して個別に繰り返し呼ぶ運用はしない
（`claude/rules/core.md` / `claude/rules/orchestrator.md`）。

## `--auto` / merge queue の permit 意味論

- **`gh stack submit --auto`**: これは merge ではなく PR **作成/更新**操作
  なので merge-permit の対象外（`gh-stack-merge` 等どの action にも該当しない）。
  gate になるのは `claude/rules/core.md` の既存ルール「PR 作成はその時点の
  メッセージでの明示許可なしに行わない」の方であり、merge-permit とは別の
  承認経路。`--auto` はインタラクティブな PR 編集画面を省略して自動生成の
  タイトルで PR を作るだけで、既定では draft になる (`--open` を付けない限り
  ready for review にはならない、`gh stack submit --help` で確認済み)。
  つまり `--auto --open` を使うと人間のレビュー無しで ready な PR が量産され
  得るため、そのケースは通常の PR 作成同様に当該メッセージでの明示許可を
  得てから使うこと。安全なユーザー承認モデルを別途実装するまでは、
  merge-permit 側で `--auto`/`--open` を検出してブロックする機構は
  **持たせていない**（PR 作成と merge は別レイヤーの承認対象であり、
  スコープを混同しないため）。
- **merge queue**: `gh stack merge --help` の記載どおり「base branch が
  merge queue を使っている場合、stack はキューに追加され、キューが処理した
  時点で merge される」。つまり merge-permit の消費 (= コマンド実行の許可)
  と、実際に GitHub 上で merge が完了するタイミングは**一致しない**ことが
  ある。permit の TTL (既定 300 秒、上限 900 秒) はあくまで「コマンドを
  発行してよい猶予」であり、キュー処理待ちで実際の merge がそれより後に
  完了しても permit の消費自体は正常（既に許可された 1 回の呼び出しを
  使い切っただけ）。REST 非同期エンドポイントの `merge_action=merge_queue`
  ボディパラメータを検出して個別ブロックする実装は**持たせていない**
  (curl のボディはファイル/heredoc/`--input -` 経由のことが多く、コマンド
  文字列だけからの静的検出が信頼できないため)。安全なユーザー承認モデル
  (例: キュー処理完了まで人間に通知して再確認する仕組み) を実装するまでは、
  この非同期性を運用者が認識したうえで permit を発行する運用とする。

## ブロック時の挙動

permit が無い/失効/消費済み/repo・target 不一致のいずれかであれば、hook は
exit code 2 で該当コマンドをブロックし、理由を stderr に返す
（`AGENTS.md` の hook 規約どおり、ブロックは exit 2 のみを使う）。

`git merge --abort` は新規 merge を発生させないため常に許可される。それ以外の
`git merge` バリエーション（`--continue` を含む）は permit が必要。

## 独立レビューで修正した項目 (2026-08-22)

独立レビューが実機 PoC で確認した 4 件のクリティカルなガード回避を修正した。
各修正には `claude/hooks/merge-permit/tests/test_guard.py` に `test_poc_*` の
回帰テストがある。

1. **malformed/missing hook event の fail-open**: event を解析できない
   (tool_name 不明・必須フィールド欠落) 場合に許可していたのを、
   fail-closed (block) に変更した (`guard.py` の `_Malformed`)
2. **`-R`/`--repo` の見落としと不整合な正規化**: `-R` (短縮形) を検出して
   おらず、`--repo owner/repo` (host 省略) も `git remote get-url origin`
   由来の識別子と異なる文字列になっていたため、別リポジトリ向けの操作が
   カレント repo 用の permit で通ってしまう余地があった。両方検出し、
   `host/owner/repo` へ一貫して正規化する
3. **`cd` による repo 束縛の回避**: hook イベントの静的な cwd だけを見ており、
   コマンド文字列内で `cd /other-repo && ...` してから merge すると
   static cwd 基準の permit が別リポジトリへ転用できた。merge 呼び出し
   手前の `cd`/`pushd` を追跡し、静的に解決できない cd (変数展開・pipe・
   subshell 越境等) は ambiguous として block する
4. **git global option によるバイパス**: `git -c key=value merge x` のように
   `-C` 以外のグローバルオプションが挟まると、旧実装の正規表現が
   マッチせず検出そのものが素通りしていた。git のサブコマンドをトークン単位
   で正しく特定する方式に置き換えた

これに伴い決定的な整理も行った: `gh stack merge` に存在しない `--repo`/`-R`
ハンドリングを除去（実機の `gh stack merge --help` に無い）、gh-pr-merge の
target 決定ロジックにあった死んだ分岐 (数字判定しても両分岐が同じ結果を
返していた) を削除、repo identity の正規化経路を 1 箇所 (`normalize_repo_
identity_from_url`) に統一。

## 「単純な形」だけを permit 照合の対象にする設計 (最終レビューによる転換)

上記 1〜4 の修正後も、独立レビューは 3 回にわたって「コマンド開始位置の許可
リストが特定の文脈 (subshell/brace group/否定/シェルキーワード/backtick/
redirection/環境変数代入/wrapper コマンド) を見落とす」回帰を発見した
(3 回目・4 回目のレビュー)。さらに 5 回目のレビューで「redirect が対象引数
より前に来ると target 抽出が空になり `branch:HEAD` に化ける」バグが、
最終レビューで「複合 ampersand redirect (`2>&1`/`&>`/`>&`) を含む形は
`_GIT_STATEMENT_END` の文区切り判定が `&` 単体で打ち切ってしまい、後続の
`>` を見落とす」バグが見つかった。

これらはすべて同じ根本原因を持つ: **「あらゆるシェルの形を正確にパースして
repo/target を抽出したうえで permit と照合する」という設計方針そのものが、
シェル構文のバリエーションに対して構造的に脆い。** 個別のバリエーションを
都度塞いでも次のバリエーションが見つかるモグラ叩きになる。

最終レビューでの設計転換: **「正確に抽出できる」ことを目指すのをやめ、
「単純で疑いようのない形かどうか」だけを判定する**
(`lib.py` の `_is_simple_supported_form`)。判定は 2 条件のみ:

1. merge 呼び出しの直前の実行コンテキストが「文字列先頭」または
   `;`/`&`/`|`/改行 のみ (`_is_simple_leading_context`)。subshell・brace
   group・否定・backtick・command substitution・環境変数代入・wrapper
   コマンド・シェルキーワードの直後はすべて該当しない
2. 呼び出し位置から次の疑いようのない文区切り (`;`/改行/`)`/`}`/backtick/
   `&&`/`||`) までの範囲に `<`/`<` が一切含まれない (redirect の複合演算子
   を個別に区別する必要を無くすため、1 文字でもあれば単純とみなさない)

**この 2 条件を満たさない (`unsafe_form=True`) 場合、repo/target がどれだけ
正確に抽出できていても、明示的な `-C`/PR番号があっても、permit の有無を
一切確認せず常に block する。** 複雑な形は「正しく解析して許可する」のでは
なく「一律拒否する」。安全なユーザー承認モデルを別途実装するまでは、
redirect/wrapper/command substitution を伴う merge は運用上「単純な形に
書き直してから実行する」ことが前提になる。

## 既知の限界

- **Claude Code の自己発行は技術的には防げない**: CLI 自体には実行者が
  Hermes か Claude Code かを区別する仕組みが無い。このガードは「うっかり /
  自律的な merge」の事故防止が目的であり、規約を無視して意図的に自己発行する
  行為までは防げない。抑止力は「permit 発行という明示的な追加ステップを
  踏まないと merge できない」という摩擦と、permit ファイルに残る監査証跡
  （`created_by` / `reason`）
- **GraphQL 経由の `mergePullRequest` mutation は粗い binding**: node ID から
  owner/repo/PR番号を静的に復元できないため、repo 識別は実行時の cwd の
  origin に委ねる。target は固定文字列 `graphql-mutation` で、PR 単位の
  絞り込みはできない
- **検出はシェルの完全なパースをしていない**: `&&` / `;` / `|` / 改行での
  分割は正規表現ベース。「単純な形」判定 (`_is_simple_supported_form`) の
  対象外になったコマンド (redirect/wrapper/代入/command substitution 経由)
  は正確な抽出を試みず一律 block するため、複雑な形の細部を誤って解釈する
  リスクは無くなったが、その代わり複雑な形は permit があっても一切通らない
  (「複雑な形は解析して許可するのではなく一律拒否する」節を参照)。`cd` 追跡
  も、pipe や subshell をまたぐケース・変数展開/コマンド置換を含む cd 対象は
  ambiguous として block する (guess しない)。gh pr merge 等の検出は単純な
  正規表現のままで、無関係な文字列に偶然マッチする false positive はあり
  得る。誤検出の方向は over-block (無関係な文字列に反応してブロックする)
  寄りに倒してあり、見逃しより誤ブロックを優先する
- **カバー範囲は `Bash` tool と `mcp__github__merge_pull_request` tool のみ**:
  将来 GitLab / Bitbucket 等の別 MCP merge tool が追加された場合、この hook
  では捕捉できない。matcher の追加が必要
- **`~/.claude/merge-permits/` はローカルマシン単位**: 同じリポジトリで
  複数マシン/複数 Hermes インスタンスが並行稼働する場合、permit は発行元の
  マシンでしか有効にならない
- **stack merge は public preview 機能**: GitHub 側の仕様変更（エンドポイント名・
  CLI コマンド名・挙動）に追従できていない可能性がある。実行前に
  [Merging stacked pull requests](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/merging-stacked-pull-requests)
  を確認すること。merge queue 対応は本ドキュメント作成時点で順次展開中だった
- **`gh stack merge <番号>` は stack番号 と PR番号 のどちらも受け付ける**が、
  hook 側はコマンド文字列からどちらの種別かを判別できない。permit の
  `--target` には実行するコマンドに渡すのと同じ生の値を指定すること
  （種別を取り違えると repo/target 不一致でブロックされる）
- **`gh stack` は単一 worktree 内でしか stack を追跡・操作できない**（実機検証
  済み、上記「worktree との組み合わせ方」参照）。同じ stack の複数レイヤーを
  並列委譲することはできず、それが必要な指示は blocker として扱う
