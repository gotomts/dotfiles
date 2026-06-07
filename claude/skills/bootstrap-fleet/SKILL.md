---
name: bootstrap-fleet
maintainer: gotomts
description: canonical inject-fleet SessionStart hook を任意リポジトリに敷く再利用形。.claude/hooks/inject-fleet.sh 配置 + settings.json SessionStart 登録 + PR。冪等。
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
---

# Bootstrap Fleet

canonical な `inject-fleet.sh`（Claude Code on the web 用 SessionStart hook）を**対象リポジトリに敷く**。`.claude/hooks/inject-fleet.sh` を配置し、`.claude/settings.json` に SessionStart 登録を行い、ブランチを切って PR を作る。再実行は冪等（差分が無ければ no-op）。

正本（canonical）は dotfiles（public）の `claude/fleet/inject-fleet.sh`。**hook 本文をこのスキル内に固定値で持たず**、実行時に正本を取得してコピーする（drift 防止）。

## 前提

- **対象リポジトリのルート**で実行すること（dotfiles 自身ではない別リポ）。
- `git` 作業ツリーであること。
- `gh` CLI が認証済みであること（PR 作成に使用）。
- `jq` が利用可能であること（settings.json の安全なマージに使用）。
- bootstrap は**ローカル CLI 実行**が前提（クラウドの feature-team 実行では作れない＝鶏卵制約。cloud-setup は fleet 注入の前提なので fleet に依存できない）。

## スコープ・ガードレール

- 触るのは対象リポの **`.claude/hooks/inject-fleet.sh` と `.claude/settings.json` のみ**。
- hook 本文を固定値で持たず、正本を取得する。
- 既存 settings.json は `jq` でマージ（破壊しない）。不正 JSON は clobber せず停止する。

## 実行フロー

### Step 0: 前提チェック・引数

引数は `dry-run`（差分プレビューのみ・書き込み/PR なし）のみ対応する。未知引数は明示エラーで停止する。

```bash
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    dry-run) DRY_RUN=true ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: /bootstrap-fleet [dry-run]" >&2
      exit 1
      ;;
  esac
done

# git 作業ツリーのルートにいるか
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "ERROR: git リポジトリではありません" >&2; exit 1; }
if [ "$ROOT" != "$PWD" ]; then
  echo "ERROR: リポジトリのルートで実行してください（現在: $PWD / ルート: $ROOT）" >&2
  exit 1
fi

# gh 認証
gh auth status >/dev/null 2>&1 || { echo "ERROR: gh が未認証です（gh auth login）" >&2; exit 1; }

# dotfiles 自身でないこと（正本リポには注入不要）
ORIGIN=$(git remote get-url origin 2>/dev/null || echo "")
if printf '%s' "$ORIGIN" | grep -qE 'gotomts/dotfiles(\.git)?$'; then
  echo "ERROR: ここは canonical の正本リポ（gotomts/dotfiles）です。注入は不要です" >&2
  exit 1
fi

echo "対象リポ: $ROOT / dry-run: $DRY_RUN"
```

### Step 1: canonical hook の取得（ローカル優先 → raw フォールバック）

ローカルの dotfiles 作業ツリーを優先し、無ければ public main から fetch する。取得物は壊れた hook を配らないよう検証する。

```bash
LOCAL_CANON="${HOME}/.dotfiles/claude/fleet/inject-fleet.sh"
RAW_URL="https://raw.githubusercontent.com/gotomts/dotfiles/main/claude/fleet/inject-fleet.sh"
CANON="$(mktemp)"

if [ -f "$LOCAL_CANON" ]; then
  cp "$LOCAL_CANON" "$CANON"
  SRC_DESC="local: $LOCAL_CANON"
else
  if ! curl -fsSL "$RAW_URL" -o "$CANON"; then
    echo "ERROR: 正本の取得に失敗（ローカル無 + raw fetch 失敗）: $RAW_URL" >&2
    exit 1
  fi
  SRC_DESC="raw: $RAW_URL"
fi

# 検証: 非空・shebang・inject-fleet マーカー
if [ ! -s "$CANON" ] \
   || ! head -n1 "$CANON" | grep -q '^#!' \
   || ! grep -q 'inject-fleet' "$CANON"; then
  echo "ERROR: 取得した正本が不正です（空 / shebang 無 / マーカー無）: $SRC_DESC" >&2
  exit 1
fi
echo "正本取得 OK（$SRC_DESC）"
```

### Step 2: 冪等判定（変更不要なら no-op）

hook が既に正本と同一内容で、かつ settings.json に inject-fleet の SessionStart 登録が既にあれば、何も変更せず終了する。

```bash
HOOK_DEST=".claude/hooks/inject-fleet.sh"
SETTINGS=".claude/settings.json"

hook_same=false
if [ -f "$HOOK_DEST" ] && cmp -s "$CANON" "$HOOK_DEST"; then
  hook_same=true
fi

session_registered=false
if [ -f "$SETTINGS" ]; then
  if ! jq empty "$SETTINGS" >/dev/null 2>&1; then
    echo "ERROR: $SETTINGS が不正な JSON です。手動で確認してください（clobber しません）" >&2
    exit 1
  fi
  if jq -e 'any(.hooks.SessionStart[]?.hooks[]?; .command | test("inject-fleet"))' "$SETTINGS" >/dev/null 2>&1; then
    session_registered=true
  fi
fi

if [ "$hook_same" = true ] && [ "$session_registered" = true ]; then
  echo "既に bootstrap 済みです（hook 一致 + SessionStart 登録済み）。no-op で終了します。"
  exit 0
fi
```

### Step 3: SessionStart 登録コマンドの決定

対象リポにコミットした hook を指す。`${CLAUDE_PROJECT_DIR}` は Claude Code がリポジトリルートとして全 hook（SessionStart 含む）に渡す公式の placeholder／環境変数。hook は remote-gated（`CLAUDE_CODE_REMOTE != true` で即 `exit 0`）のため、local を含む全環境で登録しても無害。

```bash
HOOK_CMD='bash "${CLAUDE_PROJECT_DIR}/.claude/hooks/inject-fleet.sh"'
```

### Step 4: dry-run の場合は差分プレビューして終了

`dry-run` 指定時は、書き込み・コミットを行わず「何が変わるか」を提示して終了する。

```bash
if [ "$DRY_RUN" = true ]; then
  echo ""
  echo "## dry-run: 適用される変更"
  if [ "$hook_same" = true ]; then
    echo "- $HOOK_DEST: 変更なし（正本と一致）"
  else
    echo "- $HOOK_DEST: 配置 / 更新（正本 $SRC_DESC）"
  fi
  if [ "$session_registered" = true ]; then
    echo "- $SETTINGS: SessionStart 登録済み（変更なし）"
  else
    echo "- $SETTINGS: SessionStart に inject-fleet 登録を追加"
    echo "    command: $HOOK_CMD"
  fi
  echo ""
  echo "dry-run のため書き込み・PR は行いません。"
  rm -f "$CANON"
  exit 0
fi
```

### Step 5: hook 配置 + settings.json マージ

```bash
# hook 配置
mkdir -p .claude/hooks
cp "$CANON" "$HOOK_DEST"
chmod +x "$HOOK_DEST"
rm -f "$CANON"
echo "配置: $HOOK_DEST"

# settings.json マージ / 新規作成
if [ "$session_registered" = true ]; then
  echo "SessionStart は既に登録済み（skip）"
else
  mkdir -p .claude
  TMP_SETTINGS="$(mktemp)"
  if [ -f "$SETTINGS" ]; then
    jq --arg cmd "$HOOK_CMD" '
      .hooks //= {} |
      .hooks.SessionStart //= [] |
      .hooks.SessionStart += [{"hooks":[{"type":"command","command":$cmd}]}]
    ' "$SETTINGS" > "$TMP_SETTINGS"
  else
    jq -n --arg cmd "$HOOK_CMD" '
      {hooks: {SessionStart: [{hooks: [{type:"command", command:$cmd}]}]}}
    ' > "$TMP_SETTINGS"
  fi
  # 出力が valid JSON か確認してから差し替え
  jq empty "$TMP_SETTINGS" || { echo "ERROR: 生成した settings.json が不正です。中断します" >&2; rm -f "$TMP_SETTINGS"; exit 1; }
  mv "$TMP_SETTINGS" "$SETTINGS"
  echo "登録: $SETTINGS の SessionStart に inject-fleet を追加"
fi
```

### Step 6: branch / commit / PR

対象リポの `.claude/` 配下 2 ファイルのみをコミットする。`git add -A` は使わない（無関係ファイルの巻き込み防止）。

```bash
BRANCH="chore/bootstrap-fleet-hook"
git switch -c "$BRANCH" 2>/dev/null || git switch "$BRANCH"

git add "$HOOK_DEST" "$SETTINGS"
git commit -m "chore(claude): canonical inject-fleet SessionStart hook を導入"

git push -u origin "$BRANCH"

gh pr create \
  --title "chore(claude): canonical inject-fleet SessionStart hook を導入" \
  --body "$(cat <<'BODY'
## 概要

canonical な `inject-fleet.sh`（Claude Code on the web 用 SessionStart hook）を本リポに導入する。

- `.claude/hooks/inject-fleet.sh`（dotfiles 正本のコピー）
- `.claude/settings.json` の SessionStart 登録

hook は remote-gated（`CLAUDE_CODE_REMOTE=true` のときのみ動作）・冪等・ローカルでは no-op。

## 生成元

`bootstrap-fleet` スキル（gotomts/dotfiles）。

## 検証

- [ ] hook が実行権付きで配置されている
- [ ] settings.json に SessionStart 登録が入っている
- [ ] 再実行が no-op（冪等）
BODY
)"
```

> auto-merge しない（人レビュー gate）。

### Step 7: 自走ライフサイクル（人レビュー gate で停止）

vault `agent-fleet/design-notes.md`「完了処理の正準」に従う。

1. **coderabbit-review サイクル**: `coderabbit-review` スキルで actionable 指摘を解消 → push → 再レビュー、ゼロになるまで。
2. **CI 監視**: checks が green になるまで。失敗は修正して push。
3. **停止（HITL）**: auto-merge せず、PR URL・CI 状態・指摘解消状況を報告して人のレビュー＆マージ待ちにする。
4. **マージ後**: Linear issue を Done に更新（GitHub 連携が自動遷移。自分でマージした場合は手動）。

要判断 / 解決不能な指摘 / CI 恒常失敗は無理に進めず、状態を添えて停止・報告する。

## 完了前の振り返り・整合

1. 実装が本スキルのスコープ・前提と差異がないか確認。
2. 差異・軌道修正があれば PR 本文に「前提との差異」を明記。
3. issue tracker（Linear 等）管理なら該当チケットも実態に更新。
4. 設計レベルの差異は vault 設計（`agent-fleet/design-notes.md`）の更新対象としてフラグ（vault は真実源。執行 agent は直接編集せず PR で明記）。
