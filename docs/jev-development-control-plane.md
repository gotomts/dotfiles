# jev-development-control-plane 運用メモ

`scripts/jev-development-control-plane.py`（alias `jev-dev`）は、通常の開発 lane の
「状態照合・次 gate 候補」を TypeSafe Jev に型付きで提案させる global scope の補助 CLI。

## shadow-mode

- Claude / Hermes の既存判断・実行権限を **置換しない**。この CLI が返すのは提案だけで、
  結果 JSON は常に `automatic_action: false` を持つ。
- Jev の提案は **実行根拠ではない**。commit / rebase / PR / close を自動化する入力に使わない。
  人間または既存の agent が判断し、その判断に責任を持つ。
- answer の confidence が 0.85 未満の提案は `state: "uncertain"` かつ
  `usable_for_action: false` になる。unknown な選択肢は `invalid`、欠落は `missing`。
  いずれも行動に使わない。
- 外部 API は `TYPESAFE_API_KEY` が設定されているときだけ呼ぶ。既定（key 無し）では
  `local_only` を返して通信しない。構造だけ確認したいときは `--dry-run`。

## API 契約

`POST /v1/systemone` の body は `state` / `model` / `questions`。4 つの原子的な質問を
同じ request に入れる。payload は `state` としてのみ送る。

```json
{
  "state": { "lane_id": "...", "evidence": ["..."], "...": "..." },
  "model": "jev-1.13.0",
  "questions": {
    "next_gate": {
      "type": "choice",
      "instructions": "この lane が次に通すべき gate はどれか。",
      "criteria": { "continue_work": "...", "commit_or_rebase": "..." }
    }
  }
}
```

応答は `answers`。choice answer は
`{"type": "choice", "choice": <選択肢>, "probabilities": {...}, "confidence": <number>}`。
normalization はこの公式 shape だけを受け入れ、それ以外（欠落・型違い・未知の選択肢・
confidence 不在）は fail closed で `missing` / `uncertain` / `invalid` に落とす。

## 入力最小化

stdin に渡すのは明示的な開発制御面データだけ。

| フィールド | 型 | 内容 |
| --- | --- | --- |
| `lane_id` | string | 対象 lane の識別子 |
| `source` | string | 観測元（agent 名など） |
| `observed_at` | string | 観測時刻 |
| `agent_state` | string | 現在の状態の要約 |
| `acceptance_conditions` | string[] | 受入条件 |
| `evidence` | string[] | 実行済み検証とその結果 |
| `summary` | string | 照合したい論点 |

- 未知のフィールドは拒否する。raw transcript・git diff・ソースファイル内容の持ち込み口を
  作らないため、スキーマは allowlist で閉じている。
- 入力は最大 12,000 文字。超過は API へ出さずに拒否する。
- 秘密らしい鍵名（api key / token / password / secret / private key / authorization）や
  値（`Bearer ...`、`-----BEGIN ... PRIVATE KEY-----`、既知の token 接頭辞、`KEY=<値>` 形式）を
  含む入力も、API へ出さずに拒否する。
- API の request / response 本文と API key はログに残さない。`--dry-run` が返すのも
  request の構造（method / url / ヘッダ名 / body のキー / Choice の選択肢 / state のフィールド名）
  だけで、state 本文と Authorization の値は含まない。

## 秘密の注入

`TYPESAFE_API_KEY` は 1Password の Development 専用 Vault から `op run` で子プロセスへ
注入する。値・Vault item 名・非公開の環境名はこのリポジトリに書かない。

- インフラ用の既存 wrapper（`scripts/opsa-infra.zsh`）は **流用も変更もしない**。
  Development 用途と Service Account の境界を混ぜないため、`op run` は開発側の
  env-file template（非追跡）で別に用意する。
- CLI 側は環境変数を読むだけで、秘密を復号・表示・リポジトリへ書く経路を持たない。

### 正式な注入経路

Development 用の注入は `scripts/opsa-development.zsh`（alias `opsa-development`）だけを通す。

```sh
opsa-development run [--env-file <path>] -- <command> [args...]
```

- token は Development 専用の macOS Keychain entry から取り、`op run` の子プロセスの環境に
  だけ載せる。呼び出し元の shell へ export せず、stdout / stderr にも出さない。Keychain の
  service 名・Vault 名・item 名・具体的な `op://` 参照は runbook 側で管理し、このリポジトリ
  には書かない。
- env-file template の既定は `${HOME}/.config/opsa-development/development.env`（非追跡）。
  `OPSA_DEVELOPMENT_ENV_FILE` または `--env-file` で上書きできる。
- template は fail-closed で検証する。現在の user が所有する通常ファイルで、owner 以外から
  読めない（0600 以下）ことと、空行・コメント以外が `NAME=op://vault/item/field` 形式の参照
  だけであることを要求する。復号済みの literal 値が混ざっていれば実行しない。
- `op` 自身を子コマンドにする（`opsa-development run -- op read ...` のような）呼び出しは
  拒否する。値の直接取得・管理は AI 経路の外で行う。
- `op run` が起動したコマンドとその子孫は同じ環境を継承し得る。これは標準経路の残余リスク
  として受け入れ、Development 専用 Vault の scope（read_items だけ・期限付き）で影響範囲を
  限定する。wrapper は事故防止のレールであって、AI に対する絶対境界ではない。

## 予算

- 台帳は private state directory `~/.local/state/jev-development-control-plane`（0700）の
  SQLite に置く。リポジトリには何も書かない。
- 月次 hard cap は `JEV_MONTHLY_USD_CAP`（既定 `50.00` USD）。呼出し前に最大
  6,000 input tokens 分を `BEGIN IMMEDIATE` で予約し、cap を超えるなら外部 API を呼ばずに
  `budget_exhausted` を返す。成功時は API の `usage.input_tokens` で確定精算し、失敗時は
  予約を取り消す。429 / 529 に限り短い backoff で最大 1 回だけリトライする。
- 入力単価は公式の **$0.042 / 1,000,000 input tokens**（`USD_PER_INPUT_TOKEN`）。
  1 回の予約額は 6,000 tokens 分で $0.000252。
- 意図は月 ¥10,000 以下。script の hard cap $50 は、直前に確認した為替
  **157.055093 JPY/USD** では約 **¥7,853** で、意図の上限 ¥10,000 の **内側**に収まる。
- 為替の安全余白: $50 が ¥10,000 に達するのは 200.0 JPY/USD。上記レートに対して
  約 27% の円安余白がある。これを超える水準が続くなら `JEV_MONTHLY_USD_CAP` を
  下げること（cap は USD 建てなので、円建ての上限は為替で動く）。
- 実測 usage は台帳に残る。月次で確認し、必要なら cap を締める。

## 使い方

```sh
# 構造とローカル判断だけ確認する（外部通信なし）
jev-dev --dry-run < payload.json

# 実際に問い合わせる（key がある場合のみ。注入は wrapper 経由の 1 本だけ）
opsa-development run -- jev-dev < payload.json
```

テスト用の上書き: `JEV_ENDPOINT` / `JEV_TIMEOUT_SECONDS` / `JEV_STATE_DIR`。
model は既定で `jev-1.13.0` に pin し、`JEV_MODEL` で明示上書きできる。

## テスト

```sh
python3 scripts/jev-development-control-plane.test.py
bats setup/tests/opsa-development.bats setup/tests/link.bats setup/tests/aliases.bats
```
