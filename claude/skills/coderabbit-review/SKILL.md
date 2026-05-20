---
name: coderabbit-review
description: PR の CodeRabbit インラインコメントを確認し、指摘への対応・リプライを行う。
argument-hint: <PR番号 or PR URL>
allowed-tools:
  - Bash
---

# CodeRabbit Review

PR に対する CodeRabbit のインラインコメントを確認し、指摘への修正・反論・保留を仕分けてリプライを実行する。

## 前提

- `gh` CLI が認証済みであること
- 対象リポジトリのワーキングディレクトリにいること

### `.coderabbit.yaml` の事前確認

ポーリング開始前にリポジトリ直下の `.coderabbit.yaml` を確認する。

```bash
test -f .coderabbit.yaml && cat .coderabbit.yaml || echo "(no .coderabbit.yaml — defaults)"
```

確認ポイント:
- **`reviews.path_filters`**: `!**/*.yaml` / `!**/*.md` / `!**/*.lock` 等が宣言されている場合、それらの拡張子のみで構成される PR は CodeRabbit が自動レビューしない。タイムアウト判定 (section 1) で除外検出に使う
- **`reviews.profile: assertive`**: nitpick も含めて積極的に指摘する設定。nitpick の扱い方針 (section 3-1) をユーザーに確認する

ファイルが存在しない、または読み出せない場合はデフォルト挙動 (除外なし / プロファイル未指定) として進める。

## コンテキスト検出

```bash
gh repo view --json owner,name -q '{owner: .owner.login, repo: .name}'
```

取得する値:
- `OWNER`: リポジトリオーナー
- `REPO`: リポジトリ名

引数が PR 番号の場合はそのまま使用。PR URL の場合は番号を抽出する。

## 実行フロー

```
PR 指定
  │
  ├─ .coderabbit.yaml チェック (path_filters / profile)
  │
  ├─ コメント待機 (actual review ポーリング)
  │     │
  │     ├─ タイムアウト
  │     │     ├─ issues/<N>/comments に "No actionable comments..." → ✅ 完了 (指摘なし)
  │     │     ├─ 変更ファイルが path_filters で除外 → 除外通知して終了
  │     │     └─ それ以外 → 未設定 / 遅延の可能性をユーザー確認
  │     │
  │     └─ レビュー検出 → コメント収集 (3 経路: inline root / inline reply / issues comments)
  │           │
  │           ├─ unresolved 0 件 + issues comments も walkthrough のみ → 完了 (指摘なし)
  │           └─ unresolved あり or issues comments に「その他」あり → 対応サイクル
  │                 │
  │                 ├─ 仕分け: 修正 / 反論 / 保留
  │                 ├─ 各コメントにインラインリプライ
  │                 ├─ 修正コミットを push (修正があった場合)
  │                 └─ `@coderabbitai review` 一般コメントで再レビュー要求
  │                       │
  │                       ├─ 新規コメントなし → 完了
  │                       └─ 新規コメントあり (2 回目) → ユーザー確認
  │
  └─ 完了報告
```

## 1. コメント待機

CodeRabbit のレビューフローは 2 段階に分かれる:

- **Step A (walkthrough)**: PR 作成直後に `issues/<N>/comments` へ「processing in progress」コメントが投稿される
- **Step B (actual review)**: 数分後に `pulls/<N>/reviews` へ actionable comments を含む正式レビューが投稿される

このスキルは **Step B (actual review)** を待つ。`gh pr view --json reviews` は walkthrough だけで埋まる瞬間があり判定がブレるため、`gh api .../pulls/<N>/reviews` を直接叩いて `coderabbitai[bot]` 投稿の有無で判定する。

```bash
# Step B (actual review) を 30 秒間隔・最大 5 分でポーリング
OWNER=<owner>; REPO=<repo>; PR=<number>
DEADLINE=$(($(date +%s) + 300))
LATEST_REVIEW_ID=0
while [ "$(date +%s)" -lt "${DEADLINE}" ]; do
  LATEST_REVIEW_ID=$(gh api "repos/${OWNER}/${REPO}/pulls/${PR}/reviews" \
    --jq '[.[] | select(.user.login=="coderabbitai[bot]")] | (last // {}).id // 0' 2>/dev/null)
  [ "${LATEST_REVIEW_ID}" != "0" ] && break
  sleep 30
done
```

⚠️ bot 識別子は `coderabbitai[bot]` (suffix 付き)。`gh api` 系では `user.login` がこの値になる。素の `coderabbitai` でフィルタすると 0 件になるので注意。

### タイムアウト判定

5 分待っても `LATEST_REVIEW_ID == 0` の場合、PR の変更ファイルが `.coderabbit.yaml` の `path_filters` で除外されている可能性を切り分ける。

```bash
gh pr diff "${PR}" --name-only
```

- 変更ファイル群がすべて `path_filters` の除外パターン (例: `**/*.yaml` / `**/*.yml` / `**/*.md` / `**/*.lock`) に該当 → 「path_filters により CodeRabbit が自動レビューから除外されている可能性が高い」と報告して完了 (結果: `⏭️ Excluded by path_filters`)
- 該当しない → 「CodeRabbit 未設定 or 遅延の可能性」としてユーザーに継続待機 / 終了を確認

単に「CodeRabbit 未設定」と片付けず、除外設定との突合を先に行う。

### no-issues シグナルの先行検出

`pulls/<N>/reviews` 側がタイムアウトしても、`issues/<N>/comments` に CodeRabbit から `No actionable comments were generated` が投稿されているケースがある (Step B が review でなく一般コメントで終端する経路)。タイムアウト前に以下も並行チェックする:

```bash
gh api "repos/${OWNER}/${REPO}/issues/${PR}/comments" \
  --jq 'any(.[]; .user.login == "coderabbitai[bot]" and (.body | test("No actionable comments were generated")))'
```

`true` が返れば結果 `✅ No issues` として完了報告へ。

## 2. CodeRabbit コメント収集 (3 経路)

CodeRabbit のコメントは 2 つの API endpoint に分散し、さらに `pulls/<N>/comments` 内には root (in_reply_to_id == null) と reply (in_reply_to_id != null) が混在する。3 経路として漏れなく集約する。

### 2-1. inline スレッド (pulls/<N>/comments)

```bash
gh api "repos/${OWNER}/${REPO}/pulls/${PR}/comments" --paginate > /tmp/cr_inline.json
```

このエンドポイントには root と reply が混在する。スレッド単位で **最新発話者** と `<!-- <review_comment_addressed> -->` マーカーを見て resolved / unresolved を判定する:

```bash
jq '
  # CodeRabbit が立てた root とその reply だけをスレッド化
  group_by(.in_reply_to_id // .id)
  | map(select((sort_by(.created_at) | .[0].user.login) == "coderabbitai[bot]"))
  | map({
      root_id:       (.[0].in_reply_to_id // .[0].id),
      path:          .[0].path,
      line:          .[0].line,
      root_body:     .[0].body,
      latest_author: (sort_by(.created_at) | last | .user.login),
      latest_body:   (sort_by(.created_at) | last | .body)
    })
  | map(. + {
      resolved: (
        (.latest_author != "coderabbitai[bot]")
        or (.latest_body | test("<!-- <review_comment_addressed> -->"))
      )
    })
  | map(select(.resolved | not))
' /tmp/cr_inline.json
```

判定ロジック:

| 状態 | シグナル | 扱い |
|---|---|---|
| 最新発話者 = user (自分) | `latest_author != "coderabbitai[bot]"` | ✅ resolved (返信済み) |
| 最新発話者 = CodeRabbit, addressed マーカーあり | body に `<!-- <review_comment_addressed> -->` | ✅ resolved (対応確認済) |
| 最新発話者 = CodeRabbit, addressed マーカーなし | 上記いずれでもない | ⚠️ unresolved (要対応) |

CodeRabbit は inline reply で「ありがとう」返信 + `<!-- <review_comment_addressed> -->` を残すため、これを resolved シグナルとして信頼する。

### 2-2. PR 一般コメント (issues/<N>/comments)

```bash
gh api "repos/${OWNER}/${REPO}/issues/${PR}/comments" --paginate \
  --jq '[.[] | select(.user.login == "coderabbitai[bot]") | {id, body, created_at}]'
```

CodeRabbit が `/issues/<N>/comments` に投稿するコメントは本文パターンで仕分ける:

| 種別 | シグナル | アクション |
|---|---|---|
| **walkthrough (no-issues)** | `No actionable comments were generated` を含む | ✅ 終端シグナル。section 1 のポーリング完了判定にも使う |
| **auto-reply (Analysis chain)** | `<details>` 内に `Analysis chain` を含む | ℹ informational。サマリ表示のみ。リプライ不要 |
| **その他** | 上記いずれにも該当しない | 内容を確認し section 3 の仕分けに含める |

### 2-3. 本文プレビュー時の `<details>` 除去

raw body には Analysis chain などの `<details>` ブロックがそのまま含まれ、仕分けの S/N 比が悪化する。**プレビュー表示時のみ** sed で除去する (raw body は反論時の根拠引用用に保持):

```bash
echo "${BODY}" | sed -E '/<details>/,/<\/details>/d'
```

### 2-4. 集計結果

3 経路をマージし、unresolved 件数で次工程を分岐:

- inline unresolved 0 件 + issues comments も walkthrough のみ → 完了 (指摘なし)
- inline unresolved 0 件 + issues comments に「その他」あり → 内容確認して仕分け
- inline unresolved あり → section 3 の対応サイクルへ

## 3. 対応サイクル

1 回自動対応を試み、2 回目の指摘が残った場合にユーザーへ判断を仰ぐ。

### 3-1. コメント分析・仕分け

各インラインコメントを以下の 3 カテゴリに仕分ける。

| カテゴリ | 判断基準 | アクション |
|---|---|---|
| **(a) 修正** | 指摘が妥当でコード変更で解決可能 | コード修正 → リプライで対応内容を返す |
| **(b) 反論** | 誤検知・誤指摘の可能性、または意図的な設計判断 | 実機検証で根拠を集め、リプライで反証 |
| **(c) 保留** | 別 PR で扱うべき範囲、本 PR スコープ外 | 別 issue/PR を起票し、リプライで理由とリンクを返す |

**反論 (b) の進め方**:
- 「ライブラリに X が無い」「コンテナに Y が含まれない」等の事実主張系の指摘は、実機で確認してから反論する
  - 例: `docker run --rm <image> ls <path>` / 該当 API の dry-run / `bun test --bail` 等
- 反論リプライには検証コマンドと出力を必ず含めること。根拠なしの反論は通らない
- CodeRabbit は学習機能を持つため、根拠付きで反論すると Learnings に追加され、以降の誤指摘が減る
- 意図的な設計判断 (パフォーマンス vs 可読性、後方互換性の都合等) もこのカテゴリで扱う

**保留 (c) の進め方**:
- 別 issue / PR の番号を取得してからリプライする (リプライ本文に番号を含める)
- スコープ外と判断した理由を明示 (例: 「本 PR は X に閉じるため、Y のリファクタは別 issue #N で対応」)

**Nitpick の扱い**:
`.coderabbit.yaml` の `reviews.profile: assertive` 下では nitpick も多く含まれる。デフォルトは「対応する」 (assertive を選んだ意図 = 軽微でも拾う、に従う)。ただし時間的制約がある場合はユーザーに方針を確認する:

```
nitpick 指摘が <N> 件含まれています。対応方針を選択してください:
1. 🔧 nitpick も含めてすべて対応
2. ⏩ Critical / Major のみ対応、nitpick はスキップ (リプライで「nitpick は別途検討」と返す)
```

### 3-2. 対応内容をリプライ

各コメントに対し、カテゴリに応じたリプライを返す。

```bash
gh api "repos/${OWNER}/${REPO}/pulls/${PR}/comments/<COMMENT_ID>/replies" \
  -f body="@coderabbitai <対応内容の説明>

---
🤖 *via Claude Code*"
```

文面の方針:
- **修正**: 「修正コミット \`<sha>\` で対応しました。<簡潔な説明>」
- **反論**: 「実機検証 (\`<コマンド>\`) で \`<観測結果>\` を確認しました。指摘は誤検知の可能性があります」
- **保留**: 「本 PR スコープ外のため、別 issue #<N> で対応します」

末尾に `🤖 *via Claude Code*` を付与し、自動対応であることを明示する。

### 3-3. 再プッシュ・再レビュー要求 (3 点セット)

CodeRabbit はインライン返信や push 単独では再レビューが trigger されない場合がある。**3 点セット** を必ず実行する。

#### (1) 修正コミットを push

```bash
git add <修正ファイル>
git commit -m "fix: CodeRabbit の指摘を修正"
git push
```

#### (2) 各インライン指摘にリプライ

section 3-2 のリプライを送信する。push 後に SHA を含めて再送する必要はないが、コミット SHA をリプライ本文に含めておくと CodeRabbit が修正コミットと対応関係を把握しやすい。

#### (3) PR 一般コメントで明示再レビュー要求

```bash
gh pr comment "${PR}" --body "@coderabbitai review

修正概要:
- <ファイル>:<行> — <対応内容>
- ...

---
🤖 *via Claude Code*"
```

なぜ必要か: 修正コミット push のみだと再レビューが confirm されないケースを実体験している。インライン返信だけでも trigger されない場合がある。`@coderabbitai review` を一般コメントで明示するのが最も確実。

**修正が無く反論・保留のみの場合**: 再レビュー要求の必要性が低い。投稿するかをユーザーに確認するか、スキップしてよい。

#### 再レビュー待機

(1) の push と (3) のコメント投稿後、再度 section 1 のポーリングで actual review を待機する。

- 新規コメントなし → 完了報告へ
- 新規コメントあり (2 回目) → ユーザーに報告し判断を仰ぐ:

```
## ⚠️ CodeRabbit レビュー指摘 (2 回目)

### 残存するインラインコメント
- <ファイルパス>:<行番号> — <指摘内容>
- ...

### 試行した対応
1. 1 回目: <修正 / 反論 / 保留 の内訳と結果>
2. 2 回目: <内訳と結果>

### 選択肢
1. 🔧 修正を続行
2. ⏩ 指摘を残したまま続行
3. 🛑 中断する
```

## 4. 完了報告

```
CodeRabbit レビュー対応完了:
- PR: <PR URL>
- 結果: ✅ No issues / 🔧 Fixed (<N>件修正) / 💬 Disputed (<N>件反論) / 📅 Deferred (<N>件保留) / ⚠️ Issues remaining / ⏭️ Excluded by path_filters / ⏭️ Not configured
- inline unresolved: <N> 件 (うち修正 <a> / 反論 <b> / 保留 <c>)
- issues comments: walkthrough <X> 件 / informational <Y> 件 / その他 <Z> 件
- リプライ済みコメント: <N> 件
- 再レビュー要求: ✅ 投稿済み / —
```
