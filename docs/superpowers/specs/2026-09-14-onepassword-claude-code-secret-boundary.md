# 1Password × Claude Code の秘密境界と Service Account 経路設計

ローカルの AI 作業（Claude Code）でインフラ変更を実行するにあたり、秘密を平文ファイル・
リポジトリ・ログへ露出させないための設計。

**この文書が扱うのは「AI が到達し得る秘密の集合をどこまで絞るか」であって、「AI が何を
実行してよいか」ではない。** 後者（`apply` の可否など）は Hermes へのユーザー明示指示と
上位の運用規則が決める。

章立ては次のとおり。

1. **いま入れたもの** — 公式 1Password Claude Code plugin（宣言と同期方法）
2. **その plugin が保証しないこと** — 誤解したまま運用しないための明文化
3. **秘密の取り扱いルール** — ハーネス層で効いている層と効いていない層の切り分け
4. **標準経路** — 用途別 Vault + Service Account + Keychain + `opsa-infra run`
5. **将来オプション** — より強い隔離が要るときの allowlist 型実行ブローカー

## 1. 1Password plugin の宣言と同期

dotfiles の既存方式（`claude/settings.json` を SSOT、`setup/claude-sync.zsh` が同期）に乗せる。
plugin 専用の仕組みは足していない。

- `claude/settings.json` の `extraKnownMarketplaces` に `1password`（`1Password/1password-claude-plugin`）
- `claude/settings.json` の `enabledPlugins` に `1password@1password`
- 反映は `setup/claude-sync.zsh`（Tier 2）。未インストールの plugin だけ `claude plugin install` する
  add-only 同期なので、既存 plugin の版は動かない

plugin が持ち込む機能は公式の数え方どおり 3 つ。telemetry はこのうち hook に付随する補助機構
として扱う（独立した 4 つ目の機能ではない）。

| 構成要素 | 実体 | 有効化の前提 |
| --- | --- | --- |
| PreToolUse hook | `scripts/validate-mounted-env-files.sh`（Bash matcher） | `sqlite3` と 1Password デスクトップアプリ |
| skill | `1password-environments`（Environments の導入手順） | なし |
| MCP server | `.mcp.json` の `1password`（`1password-mcp` コマンド） | デスクトップアプリの Labs → MCP Server |

### hook の補助機構: telemetry

hook は実行のたびに telemetry イベントを detach したサブシェルで扱う。押さえるべき点は 3 つ。

- **opt-in の consent gate がある。** 同意していなければイベントは出ない。既定で送られ始める
  類のものではない。同意状態は 1Password アプリ側の Data Usage 設定で管理し、後から取り消せる。
- **hook 自身はネットワークへ送らない。** hook がするのは **ローカルの JSONL に metadata を
  追記すること**まで。そこから先の ingest と送信は 1Password アプリ側が担う。hook を
  「勝手に外部へ通信するスクリプト」と読むのは誤り。
- **内容は metadata のみ。** 秘密値・Bash コマンドの内容・パス・Environment 名は含まない。

ただし送信内容が最小であることと、**ローカルに痕跡が残らないこと**は別問題である。
hook のイベントログ（`/tmp/1password-claude-code-hooks.log`）と、この **telemetry の
ローカル JSONL** は、いずれもディスク上の露出面として数える。3 章の露出面の項を参照。

### MCP は既定で無効のまま置く

plugin 同梱の MCP（`1password-mcp`）は、変数値をそのまま読み出す API ではなく Environments の
**管理系**（Environment / mount の作成・一覧・設定）である。ただし管理系であることは無害を
意味しない。

- **変数の書き込みを含み得る。** 値を読む経路が無くても、値を置く経路があれば秘密の取り回しに
  関与する。
- **ローカル `.env` mount の作成を含み得る。** これは **AI から見える FS に秘密を出す操作**
  そのものである。管理系の API 一発で、2 章の「AI から見える FS に秘密を置かない」という
  前提が崩れる。

したがって MCP は、読み出し API が無いことを理由に安全視しない。

**現状 `1password-mcp` が PATH 上に無いことは guard ではない。** これは単に今そうであるという
事実で、Labs の実験機能を有効化する・PATH を変える・アプリを更新する、のいずれでも到達可能に
なる。強制力のある機構ではなく約束に依存した状態だと認識しておく。

よって **MCP は、別レビューを経て明示的に設定するまで有効化しない**。レビューでは「どのツールが
AI から見えるか」「そのうち書き込み・mount 作成に相当するものはどれか」を洗い出す。

**後続 TODO:** plugin 同梱の `.mcp.json` を**宣言側（dotfiles）で無効化・上書きする機構**が
あるかを調査する。現状は「有効化しない」という運用上の約束に留まっており、宣言で強制できて
いない。

## 2. この plugin が提供するもの / 提供しないもの

### 提供するもの

Bash 実行の直前に、1Password Environments がローカルへ mount する `.env`（FIFO）が
**期待どおり存在し有効か**を検証する。欠落・無効・不正配置なら Bash を `deny` して理由を返す。

狙いは「秘密を平文で置かずに済む配線（FIFO mount）が壊れたまま作業を続けない」こと。
`.env` を git 追跡させないための運用補助であって、アクセス制御ではない。

**deny は workspace 単位で効く。** mount が壊れていると、その workspace では当該コマンドに
限らず **Bash 呼び出しが軒並み deny される**。`ls` のような無関係なコマンドも通らなくなるため、
「AI が急に何もできなくなった」ときの第一の疑い先になる。復旧は mount を直すことであって、
plugin を外すことではない。

**実行コストも Bash 1 回ごとに乗る。** hook は毎回 1Password の DB を `sqlite3` で引く。
上限 30 秒の timeout が設定されており、通常は軽いが、Bash を高頻度で回すワークロードでは
無視できない固定費が付く。

### 提供しないもの（重要）

- **秘密の非露出を保証しない。** hook は Bash コマンドの *内容* を見て許否を決めない。
  検証が通れば通常のパーミッション設定にそのまま従う。mount された `.env` を `cat` する
  コマンドも、環境変数を外部へ送るコマンドも、hook の関心外。
- **fail-open。** 検証できない状況では hook は **permission decision を出さず、通常の Bash を
  止めない**。これは全ての fail-open 経路に共通する。異なるのは Claude に何が伝わるかで、
  2 種類ある。
  - **warning context を返す経路** — 1Password 未導入・DB にアクセスできない・`sqlite3` が
    無い。検証できなかったことは Claude に伝わるが、実行は止まらない。
  - **静かに skip する経路** — Windows・hook 入力から `cwd` を取れない等。何も伝えずに
    exit 0 する。Claude 側からは hook が動いたことすら分からない。

  いずれにせよ「hook があるから守られている」は成り立たない。とくに後者は、守りが外れた
  ことに気づく手掛かりが残らない。
- **`allow` を返さない設計。** 通過時も無出力なので、既存の permission 設定を弱めない。
  これは安全側の設計だが、裏返すと hook に守りの役割は無いということでもある。
- **出力の redaction をしない。** plan の diff・tfstate・エラーメッセージに秘密が載れば
  そのまま会話ログへ入る。
- **同一 macOS user の壁を越えない。** AI に任意 shell がある限り、その user が読める秘密は
  AI も読める。plugin はこの前提を変えない。

結論として、**1Password Environments の hook / MCP は「秘密をリポジトリに置かない」ための
配線であって、「AI に秘密を渡さない」ための境界ではない**。影響範囲の限定は 4 章の
Vault 分離と最小権限で行う。

### shell plugin（`op plugin init claude`）を採らない理由

公式には `ANTHROPIC_API_KEY` を生体認証で供給する shell plugin もあるが、本環境の Claude Code は
サブスクリプション認証で動いており、管理すべき API キーが無い。導入すると設定だけ増えて
守る対象が無いので採らない。

## 3. 秘密の取り扱いルール

- **平文の秘密をリポジトリに置かない。** 復号済みファイル（SOPS の出力等）を作業ツリーへ
  書き出さない。必要なら `VAR=$(...)` で変数へ渡し、画面にもファイルにも落とさない。
- **`claude/settings.json` の `permissions.deny` を維持する。** `Bash(op *)` / `Bash(sops *)` /
  `Bash(security find-generic-password *)` / `Read(**/*.key)` / `Read(**/secrets/**)` などの
  deny は、plugin を入れた後も外さない。
  plugin は AI に `op` を使わせるためのものではない。
  ただし **これはハーネス層の事故防止であって、セキュリティ境界ではない**。deny は
  Claude Code の設定であり、同一 user 上のプロセスが `op` を実行すること自体は妨げない。
  文字列マッチである以上、別名・ラッパスクリプト・シェル経由の間接実行で回避もできる。
  「うっかり `op` を叩く」を止める用途には有効、「敵対的に振る舞う AI を封じる」用途には
  無効、と読み替えて使う。4 章の `opsa-infra` wrapper も同じ層にあり、境界ではない。
  影響範囲を決めるのは Service Account に付けた Vault scope である。

- **秘密を「読ませない」より前に「読む必要を無くす」。** 値を人も AI も見ないで済む経路
  （シークレットマネージャ参照・`op run` による注入）を先に探す。
- **会話ログを秘密の保管先にしない。** 一度出力された秘密は transcript に残る。ローテーション
  以外に取り消す手段は無い前提で扱う。

### `defaultMode: bypassPermissions` 下で実際に効いている層

本環境の `claude/settings.json` は `permissions.defaultMode` が `bypassPermissions` である。
この前提を踏まえないと、保護の見積もりを誤る。

- **`ask` 層は人間へのプロンプトにならない。** `terraform apply` / `gcloud * delete` などを
  `ask` に並べてあるが、bypass 下では確認として機能することを期待できない。**確認が出る前提で
  設計しない。**
- **hook 通過後に残る保護は実質 `deny` 層が中心。** 1Password の hook は mount の健全性しか
  見ず、通過時は無出力で既定の permission 設定に委ねる（2 章）。その既定が bypass である以上、
  hook を抜けた先で効くのは deny の列挙だけになる。
- **その `deny` も境界ではない**（上記のとおり）。文字列マッチのハーネス層という位置づけは
  変えない。

つまり **「AI 側の設定のどこにも、apply を人間に確認させる信頼できる層が無い」**。
4 章の標準経路もこの層を作らない（4.5 の「`apply` を wrapper で塞がない理由」を参照）。
`apply` の可否は **Hermes へのユーザー明示指示と上位の運用規則**で制御する。機構として
強制したくなった時点で、5 章の out-of-band 承認付きブローカーへ進む。
### 露出面: hook が残すローカルファイル

plugin の hook はディスクに 2 種類の痕跡を残す。いずれも**秘密値を載せない設計**だが、
「何を扱っているか」の metadata は残る。

- **hook のイベントログ** — `/tmp/1password-claude-code-hooks.log`。置き場所が `/tmp` である
  以上、**workspace のパスや mount の metadata（どのプロジェクトでどの `.env` を mount して
  いるか）が world-readable な場所に残り得る**。
- **telemetry のローカル JSONL** — 同意している場合に hook が metadata を追記する先。送信は
  1Password アプリが行うが、**ファイル自体はローカルに残る**。同意そのものは Data Usage 設定で
  管理・取り消しできるので、必要が無ければ同意しないのが最も確実に痕跡を減らす。

単体で致命的ではないが、同一マシンの他ユーザー・他プロセスから「何を扱っているか」が読める
露出面として数える。

この前例から、**ブローカーの監査ログには次を要件とする**（5.3 の受入条件に反映）。

- `/tmp` ではなく **private directory** に置く（`~/.local/state/<broker>/` など）
- ディレクトリ `0700`・ファイル `0600`。作成時に mode を明示し、umask 任せにしない
- **rotation** を持たせる（サイズまたは日次 + 世代上限）。無限に伸ばして古い metadata を
  ディスクへ残し続けない

### GCP: 鍵 JSON を廃止し ADC / Workload Identity へ寄せる

サービスアカウント鍵 JSON はファイルとして存在する時点で「AI が読める秘密」になる。
ローカルは `gcloud auth application-default login` による ADC、CI / 自動実行は
Workload Identity Federation に寄せ、**長期の鍵ファイルをディスクに作らない**。

移行が完了するまでは、鍵 JSON を作業ツリー・`~/.config` 直下・`.env` のいずれにも置かない。
4 章の Vault へ寄せるか、それが無理なら AI から見えない場所に隔離する。

## 4. 標準経路: Claude 専用 Vault + Service Account + Keychain + `opsa-infra run`

AI が個人 Vault や既存の広い秘密群へ届かないようにする。**「AI が理論上どうやっても読めない」
を目指すのではなく**、AI 用に明示的に用意した最小 Vault だけに到達範囲を限定し、通常経路では
値を見ずに注入だけを行う。

### 4.1 かたち

```
Keychain (service: OP_SERVICE_ACCOUNT_TOKEN_INFRA)
      │  コマンド置換で取得し、op run の環境にだけ載せる（呼び出し元では export しない）
      ▼
opsa-infra run -- terraform plan
      │
      └─> op run --env-file ~/.config/opsa-infra/infra.env -- terraform plan
                   │  op:// 参照だけを書いた非追跡テンプレート（0600）
                   ▼
            Vault: "Claude Code Infrastructure - Kissa Soft"（read_items のみ・期限付き）
```

### 4.2 構成要素と宣言場所

| 要素 | 実体 | 層 |
| --- | --- | --- |
| wrapper 本体 | `scripts/opsa-infra.zsh` | SSOT |
| 入口 | `aliases` の `alias opsa-infra=...` | Tier 1（`~/.aliases`） |
| 配置 | `setup/link.zsh` → `~/.scripts/opsa-infra.zsh` | Tier 1 |
| テスト | `setup/tests/opsa-infra.bats` / `setup/tests/claude-settings.bats` | — |
| テンプレート | `~/.config/opsa-infra/infra.env`（`0600`、親 dir `0700`） | **リポジトリ外・非追跡** |
| テンプレートの差し替え | `OPSA_INFRA_ENV_FILE` 環境変数、または `--env-file <path>` | 実行時入力 |
| token | macOS Keychain の generic password（service 名 `OP_SERVICE_ACCOUNT_TOKEN_INFRA`） | **リポジトリ外** |

テンプレートをリポジトリに置かないのは、`op://` 参照そのものが「どの Vault のどの item を
AI に使わせているか」という構成情報だからであり、また復号済みの値を誤って書き込んだときに
公開リポジトリへ載る事故を構造的に避けるためでもある。同じ理由で、wrapper はテンプレートが
**owner 以外から読めない regular file（`0600` 以下・所有者が実行ユーザー）**であることを
実行前に検証し、違えば `op` を起動せずに落ちる。

### 4.3 Vault 構成

Vault は用途で分ける。Service Account は Vault 単位でしか権限を付けられないため、
**Vault の切り方がそのまま「AI が到達し得る秘密の集合」の切り方になる**。

| Vault | 用途 | 状態 |
| --- | --- | --- |
| `Claude Code Infrastructure - Kissa Soft` | Kissa Soft のインフラ変更（Cloudflare DNS / Terraform 等） | 既存（この名前へ改称する前提） |
| `Claude Code Infrastructure - Social Coffee Note` | Social Coffee Note のインフラ変更 | 将来 |
| `Claude Code Development` | 開発・ローカル検証で AI が使ってよい最小の値（プロジェクト横断の共有 Vault） | 将来 |

- **Infrastructure はプロジェクト別に分ける。** 1 つの Service Account が複数プロジェクトの
  インフラ資格情報に届く状態を作らないため。プロジェクトが増えたら Vault と Service Account を
  対で増やす
- **Development は開発用途の最小値だけを置く共有 Vault。** インフラ変更の権限は入れない。
  Infrastructure 側と Service Account を分けることで、ローカル検証の事故がインフラへ波及しない
- **Personal / Private など他の Vault には権限を付けない**（Service Account の `--vault` に
  列挙しない）

### 4.4 Service Account の方針

- **1 Service Account = 1 Vault。** 上の表の Vault ごとに作る。`opsa-infra` が使うのは
  `Claude Code Infrastructure - Kissa Soft` 用の 1 本だけ
- **権限は `read_items` のみ。** `write_items` / `share_items` は必要になるまで付けない
- **期限付き（既定 `--expires-in 90d`）。** 切れたら wrapper が fail-closed で落ちるので、
  放置された長期 token が残らない
- **item は専用に発行し直す。** 既存 item を個人 Vault から移動・共有するのではなく、AI 用の
  資格情報を新規に作って入れる。失効させても人間側の運用が止まらないようにするため
- **token は作成時に 1 度だけ返る。** Keychain 以外にコピーを作らない（ファイル・パスワード
  マネージャの別項目・チャット・transcript のいずれにも残さない）
- **Vault 名は空白を含む。** `op://` 参照と `--vault` 引数では二重引用符で囲う

**2 本目以降は wrapper 側の入口も要る。** 現状の `opsa-infra` は Keychain service 名
`OP_SERVICE_ACCOUNT_TOKEN_INFRA` を 1 つだけ宣言しており、テンプレートだけを `--env-file` で
差し替えても token は Kissa Soft のままである（別 Vault の参照は `op` 側で解決に失敗する）。
2 本目の Vault を使う時点で、token とテンプレートを**対で**選ぶ入口（`--project` 等）を足す。
先回りしては作らない。

### 4.5 wrapper が守るもの / 守らないもの

守るもの（`setup/tests/opsa-infra.bats` で検証している）。

- 通常経路は `op run --env-file <template> -- <command>` の 1 本だけ。`run` 以外のサブコマンドを
  受け付けない（`op read` / `op item` / `op vault` を wrapper 経由で呼ぶ道が無い）
- `--` の直後のコマンドが `op` なら拒否する。macOS の FS は既定で case-insensitive なので、
  `OP` / `Op` のような綴りも小文字化して同じ扱いにする
- テンプレートに `op://` 参照以外の行があれば拒否する（復号済みの値が混ざった状態で実行
  しない）。参照は vault / item / field の 3 段を必須とし、`Claude Code Infrastructure -
  Kissa Soft` のような空白入りの Vault 名と、値を二重引用符で囲った書き方は許す
- テンプレートが owner 以外から読める（`0077` のいずれかのビットが立つ）か、所有者が実行
  ユーザーでなければ拒否する
- Keychain に token が無ければ `op` を起動せずに終了する（fail-closed）
- token を stdout / ファイル / 呼び出し元 shell の環境のいずれにも残さない。前置代入で
  `op run` プロセスの環境にだけ載せる
- 子コマンドの終了コードをそのまま返す（`op run` の結果を握り潰さない）

**守らないもの。**

- **注入した秘密は子孫プロセスへ継承され得る。** `op run` が起動した `terraform` と、それが
  起動する provider や `local-exec` は同じ環境を持つ。`OP_SERVICE_ACCOUNT_TOKEN` もそこに
  含まれ得るため、**子孫が `op` を呼べば Service Account の権限をそのまま使える**。
  これは注入方式そのものの性質であって wrapper の欠陥ではない。標準経路ではこれを
  **残余リスクとして受け入れ、影響範囲を Vault scope で限定する**（その Vault の
  `read_items` 以上のことはできない）。これが許容できない用途なら 5 章のブローカーを選ぶ
- **子コマンドの拒否は argv[0] の名前しか見ない。** 拒否できるのは `opsa-infra run -- op ...`
  の形だけで、`-- env op read ...` / `-- sh -c 'op read ...'` / `-- make plan`（Makefile が
  `op` を呼ぶ）のように 1 段でも挟めば通る。継承された token がそのまま使えるため、
  **これらは「`op` を拒否しているから安全」の反例**として明示しておく
- 同一 macOS user 上の別経路は塞がない。`security find-generic-password` を直接叩く、
  注入後の環境を印字する、のいずれも通る
- `--` の後ろのコマンドの中身を検査しない。`apply` を止める層にはならない（下記）
- 出力の redaction をしない。`op run` の既定マスキングに任せるだけで、plan の diff や
  tfstate に値が載る経路までは見ていない

**したがって wrapper は AI に対する絶対境界ではなく、事故防止のレールである。**
実効的な安全境界は Service Account の Vault scope —「`Claude Code Infrastructure - Kissa Soft`
だけ・`read_items` だけ・期限付き」が、AI が到達し得る秘密の集合そのものを定義する。

#### `apply` を wrapper で塞がない理由

`opsa-infra run -- terraform apply` を文字列マッチで拒否する案は**採らない**。理由は 2 つ。

- **効かない。** `--` の後ろは任意のコマンドであり、`sh -c` / `make` / ラッパスクリプトを
  1 段挟めば素通りする。3 章の deny と同じく、止められるのは「うっかり」だけで、
  止めた気になる分だけ有害である
- **必要な運用を潰す。** ユーザーが明示的に指示した AI からの `apply` まで実行できなくなる。
  `apply` の可否は **Hermes へのユーザー明示指示と上位の運用規則**が決めることで、
  秘密注入の wrapper が決めることではない

`opsa-infra` の責務は「AI が触れる秘密の範囲を Vault scope に限定して注入する」ことに閉じる。
実行内容の承認を機構として強制したくなったら、それは 5 章のブローカー（out-of-band 承認）の
仕事であって、この wrapper を膨らませる話ではない。

### 4.6 ハーネス層の deny（境界ではない）

`claude/settings.json` の `permissions.deny` に、秘密を直接引く 2 経路を並べておく。

- `Bash(op *)` — 1Password CLI の直接実行
- `Bash(security find-generic-password *)` — Keychain からの直接読み出し
- `Bash(sops *)` — 既存の SOPS 経路

`opsa-infra` はコマンド名が別なので、この deny に掛からずに通る（`Bash(op *)` は「`op` +
空白」で始まるコマンドに掛かる glob であり、`opsa-infra ...` は一致しない）。Claude Code の
permission 判定は **Bash ツールへ渡すコマンド文字列**を見るだけで、スクリプトが内部で起動する
子プロセスまでは辿らない。したがって wrapper が内部で呼ぶ `security` / `op` は deny の対象外に
なる。この 2 点は `setup/tests/claude-settings.bats` で固定している。

**deny は 3 章のとおり境界ではない。** 別名・ラッパ・shell 経由で回避できる文字列マッチであり、
「うっかり直接叩く」を止めるための事故防止のレールとして置く。

### 4.7 runbook（今回は実行しない）

値を画面に出さない形で書く。**この節のコマンドは今回実行しない。** 実行時はフラグの綴りを
`op service-account create --help` で確認してから使う（秘密は関与しない）。

1. Vault `Claude Code Infrastructure - Kissa Soft` は 1Password 側で用意する（既存 Vault の
   改称）。存在確認のために `op vault list` を叩く必要は無い（叩けば他の Vault 名も一覧に
   出るため、確認目的では叩かない）。

2. AI に使わせる資格情報を、この Vault に**新規発行して**入れる（既存 item の移動ではない）。

3. Service Account を作り、返ってきた token をその場で Keychain へ流し込む。Vault 名に空白が
   あるので `--vault` の値は引用符で囲う。

   ```sh
   op service-account create claude-code-ro \
     --expires-in 90d \
     --vault "Claude Code Infrastructure - Kissa Soft:read_items" \
     --raw \
   | { IFS= read -r token
       printf 'add-generic-password -U -s %s -a %s -w %s\n' \
         OP_SERVICE_ACCOUNT_TOKEN_INFRA "${USER}" "${token}" | security -i ; }
   ```

   `security add-generic-password -w <token>` と直に書かないのは、token が argv に載って
   実行中 `ps` から見えるため。`security -i` は標準入力からコマンド行を読むので argv に
   残らず、`printf` は shell builtin なので同様に argv を作らない。

4. 保存できたことだけを、値を出さずに確認する。

   ```sh
   security find-generic-password -s OP_SERVICE_ACCOUNT_TOKEN_INFRA >/dev/null && echo stored
   ```

5. テンプレートを非追跡の場所に作る。item の id は
   `op item list --vault "Claude Code Infrastructure - Kissa Soft"` で確認する（値は出ない）。

   ```sh
   mkdir -p ~/.config/opsa-infra && chmod 700 ~/.config/opsa-infra
   cat > ~/.config/opsa-infra/infra.env <<'EOF'
   CLOUDFLARE_API_TOKEN="op://Claude Code Infrastructure - Kissa Soft/<item-id>/credential"
   EOF
   chmod 600 ~/.config/opsa-infra/infra.env
   ```

   **参照は二重引用符で囲う形に統一する。** Vault 名に空白があるため、囲まない書き方は
   env-file の parser 実装に依存する。`opsa-infra` はどちらも受け付けるが、runbook としては
   曖昧さの無い側だけを示す。`op run` が空白入りの Vault 名を解決できない場合は、Vault 名の
   代わりに Vault の id を書く（id は手順 5 の `op item list` 出力から取れる。秘密値は出ない）。

   親ディレクトリ `0700` とファイル `0600` は必須。`opsa-infra` は実行前にこれを検証し、
   owner 以外から読める配置なら `op` を起動せずに落ちる。

6. 値を表示せずに注入を確認する。

   ```sh
   opsa-infra run -- sh -c 'test -n "${CLOUDFLARE_API_TOKEN}"' && echo injected
   ```

7. 以後の通常利用。

   ```sh
   opsa-infra run -- terraform plan
   ```

### 4.8 更新・失効

- **期限切れ・ローテーション** — 4.7 の手順 3 を再実行する。`security add-generic-password -U` が
  既存エントリを置き換えるので、削除の手間は要らない
- **失効** — 1Password 側で Service Account を revoke し、`security delete-generic-password
  -s OP_SERVICE_ACCOUNT_TOKEN_INFRA` で Keychain からも落とす
- **`claude/settings.json` の deny（`Bash(op *)` / `Bash(security find-generic-password *)`）は
  外さない。** wrapper は別名なので deny に触れずに通る（4.6）。deny を外す理由がこの設計には
  無い

### 4.9 今回やらないこと

Vault の作成・改称、Service Account 作成、token の Keychain 保存、`op signin`、vault / item の
一覧、秘密の取得、実 Terraform の `plan` / `apply`。いずれも 4.7 の runbook に沿って別途行う。
**存在確認のための参照・一覧も行っていない**（この設計は名前を宣言するだけで、1Password の
状態を読みにいかない）。

**既存 SOPS 管理の秘密の移行も、この設計には含めない。** 再読・復号・移動・一覧化のいずれも
行わない。どの値を `Claude Code Development` や各 Infrastructure Vault へ移すかの棚卸しは、
**秘密値を表示しない手順**を別途レビューしたうえで実施する。

## 5. 将来オプション: allowlist 型の実行ブローカー

4 章の標準経路は、AI が到達し得る秘密の集合を Vault scope で絞る。だが同一 macOS user 内に
留まる以上、T1・T2（AI が `op` や Keychain を直接叩く / 注入済みの環境を読む）は塞げず、
`apply` を人間に確認させる層も持たない。

**この 2 点が実際に問題になったときに限り**、別の実行主体（別 macOS user または隔離プロセス）
としてブローカーを立てる。以下は着手する場合の仕様であって、現時点の実装予定ではない。
標準経路を置き換えるものでもない（ブローカーを立てても、秘密の供給元は 4 章の Vault のまま）。

### 5.1 位置づけ

AI は「何をしたいか」を言うだけで、実際に秘密へ触れるのはブローカーだけにする。
AI ⇄ 1Password を直結させない。

```
Claude Code ──(構造化リクエスト)──> broker ──(op / ADC)──> クラウド
     ^                                  |
     └────────(redact 済み出力)─────────┘
```

### 5.2 脅威モデル

| ID | 脅威 | 対策 |
| --- | --- | --- |
| T1 | AI が `op` / `gcloud` を直接叩いて vault や credential を引く | ブローカーだけが credential を持つ。AI 側の `Bash(op *)` deny は補助（境界ではない、3 章参照） |
| T2 | AI が mount 済み `.env` や鍵ファイルを読む | 秘密をブローカーのプロセス境界内にだけ展開する。AI から見える FS に置かない |
| T3 | Terraform の `local-exec` / `remote-exec` / `external` provider で任意コード実行 | 実行前に静的検査して該当があれば拒否。root だけでなくローカル子モジュールまで再帰的に見る |
| T3b | 静的検査を通さない外部コードを module / provider として引き込む | remote / registry module と provider は lockfile の許可済み digest と provider allowlist に限定 |
| T4 | plan / apply の出力や tfstate に秘密が載って会話ログへ残る | 出力の redaction を通してから返す |
| T5 | 引数注入（`-chdir=`・`-var-file=../../`・追加フラグ）で allowlist を迂回 | 引数は厳密 allowlist。パスは realpath 正規化して allowlist 配下を必須にする |
| T5b | 引数以外の経路で Terraform の挙動を注入する（`TF_CLI_ARGS*`・`TF_VAR_*`・`-backend-config`・`TF_DATA_DIR` 等） | ブローカーが子プロセスの環境を構築し直す。継承した Terraform 系変数は scrub、明示指定は拒否 |
| T6 | AI が `apply` を自発的に実行して本番を変更 | AI 経路の外で発行された承認トークンをブローカーが検証する。AI が付けられるフラグでは通さない |
| T7 | ブローカー自体の濫用（大量実行・別 repo への横滑り） | 監査ログ（誰が・どの repo の・どの dir で・何を）を常時記録 |

前提として、**AI が同一 macOS user で任意 shell を持つ限り T1・T2 は完全には塞げない**。
ブローカーを別の実行主体（別ユーザーまたは隔離プロセス）に置いて初めて境界になる。
同一 user 内に留める暫定構成では「事故の防止」までで、「敵対的な AI への防御」にはならない。
この差を運用者が認識していることを前提にする。

### 5.3 受入条件

1. リクエストは構造化（repo / terraform ディレクトリ / サブコマンド / 変数名）で受け取り、
   自由テキストの shell コマンドは一切受け付けない
2. repo と terraform ディレクトリは allowlist に載っているものだけ。realpath 正規化後に
   allowlist 配下であることを検証する（symlink 経由の脱出を防ぐ）
3. 受理するサブコマンドは `fmt` / `validate` / `plan` / `apply` と、明示的に allowlist した
   `init` のみ。それ以外は拒否。`init` は module / provider を取得する副作用があるため、
   他と同列に常時許可はせず、条件付きで個別に許可する。条件は 2 つ。
   - 6 の digest 検証を通ること
   - **実行の前後で `.terraform.lock.hcl` の hash が一致すること。** 一致しなければ失敗として
     扱い、結果を破棄する。`init` が lockfile を書き換えた（= 許可済み digest の集合が
     変わった）状態を、成功として通さない
4. **`apply` はユーザー明示承認トークンの検証をもって受理する。** AI が付けられるフラグや
   リクエスト内のブール値では通さない（AI 自身が生成できる根拠は根拠にならない）。
   ブローカーは **AI 経路の外で発行・検証できる承認**（対話端末での確認、短命でリクエスト内容に
   束縛された one-time token など）を要求する。トークンは対象 repo・ディレクトリ・plan の
   同一性に紐付け、使い回しと差し替えを防ぐ。
   AI 側の `ask` パーミッションは `bypassPermissions` 下で確認にならないため（3 章）、
   この out-of-band 承認は代替不能な必須要件である
5. `local-exec` / `remote-exec` / `external` データソースの静的検査は、**root モジュールだけでなく
   `source` が相対パスのローカル子モジュールを再帰的に辿って**行う。1 つでも該当すれば
   サブコマンドを問わず拒否する。検査できない（読めない・解析に失敗する）場合も拒否
6. remote / registry module と provider は静的検査の対象外になるため、**`.terraform.lock.hcl` の
   許可済み digest に一致するもの**だけを使う。provider は別途 allowlist（source address 単位）を
   持ち、未登録の provider を含む構成は拒否する。lockfile の更新は AI 経路では行わせない
7. **Terraform の挙動を外から注入する経路を塞ぐ。** ブローカーは子プロセスの環境を継承ではなく
   構築で作り、`TF_CLI_ARGS` / `TF_CLI_ARGS_*` / `TF_VAR_*` / `TF_DATA_DIR` / `TF_WORKSPACE` /
   `TF_LOG*` などの Terraform 系変数を scrub する。リクエスト側からの `-backend-config` /
   `-var-file` / `-var` の直接指定も拒否し、変数はブローカーが名前 allowlist に従って組み立てる
8. 標準出力・標準エラーは redaction を通してから返す。既知の秘密値・`sensitive` 属性の
   出力・鍵らしきパターンをマスクする
9. 秘密は環境変数としてブローカーの子プロセスにだけ渡す。ファイルへ書かない。AI へ返す
   応答にも含めない
10. 全リクエストを監査ログに残す（受理・拒否の別と理由を含む）。ログは private directory
    （`~/.local/state/<broker>/` 等）へ、ディレクトリ `0700` / ファイル `0600` を明示 mode で
    作成し、rotation（サイズまたは日次 + 世代上限）を持たせる。`/tmp` には書かない
11. ブローカーが落ちた場合は fail-closed。判定できないなら実行しない

### 5.4 テスト計画

- **単体** — 引数パーサ: 未知フラグ・`-chdir`・`--` 以降の追加引数を拒否する
- **単体** — パス正規化: `../` 混入・symlink 経由・allowlist 外の絶対パスを拒否する
- **単体** — サブコマンド allowlist: `destroy` / `import` / `state rm` などを拒否する。
  `init` は allowlist 未登録なら拒否、登録時のみ受理する
- **単体** — HCL 静的検査: `local-exec` / `remote-exec` / `external` を含む fixture を拒否する。
  **root は clean だがローカル子モジュール（さらにその子）に含む fixture** も拒否することを、
  再帰の各段で確認する
- **単体** — module / provider 制限: lockfile の digest に無い module、allowlist 外の provider を
  含む構成を拒否する。lockfile 欠落・digest 不一致も拒否する
- **単体** — `init` の lockfile 不変性: 偽の `terraform` に `.terraform.lock.hcl` を書き換えさせ、
  **実行前後の hash 不一致を失敗として扱い結果を破棄する**ことを確認する。書き換えが無い
  ケースは正常に受理されることも併せて確認する
- **単体** — 環境 scrub: `TF_CLI_ARGS` / `TF_VAR_*` / `TF_DATA_DIR` などを親環境に仕込んだ状態で
  起動し、子プロセスの環境に残らないことを確認する。`-backend-config` / `-var-file` / `-var` の
  直接指定を拒否する
- **単体** — redaction: 既知の秘密値とよくある鍵パターンが出力から消えることを確認する
- **単体** — `apply` 承認: 承認トークン無し・期限切れ・他リクエスト向けのトークン・
  **リクエスト側（AI）が自称する承認フラグ**のいずれも拒否し、正規のトークンだけ受理する
- **単体** — 監査ログ: 新規作成したディレクトリが `0700`、ファイルが `0600` であること、
  rotation が世代上限で古いファイルを落とすことを確認する
- **結合** — 偽の `terraform` を PATH に置き、受理経路で正しい引数と環境が渡り、拒否経路では
  一度も起動されないことを確認する
- **結合** — fail-closed: allowlist 設定が読めないときに全リクエストが拒否されることを確認する
- **否定** — 監査ログに秘密値が書かれないことを確認する

テストは既存方式（`setup/tests/*.bats`）に合わせて bats で書く。

### 5.5 着手するまでやらないこと

ブローカーの実装、別実行主体の用意、out-of-band 承認機構。4 章の標準経路で足りている間は
着手しない。
