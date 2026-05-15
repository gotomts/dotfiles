# environment-detection

`pick-next` の Step 0 で実行する環境検出と grace degrade の仕様。

## 並列実行コマンド

どれか失敗しても他は続行する。失敗時は対応する候補ソースを「不在」として扱う。

```bash
# 現在のリポジトリ・ブランチ・未コミット変更
git rev-parse --show-toplevel 2>/dev/null
git branch --show-current 2>/dev/null
git status --porcelain 2>/dev/null | head -10

# 直近コミット（文脈把握用）
git log --oneline -20 2>/dev/null

# プロジェクト設定（tracker タイプ判定）
cat .claude/project.yml 2>/dev/null || true

# handover 未消費メモ（現プロジェクト・現ブランチ）
eval "$(${HOME}/.claude/skills/handover/scripts/resolve-path.sh)" 2>/dev/null
${HOME}/.claude/skills/handover/scripts/list-active.sh "${PROJECT_HASH}" "${BRANCH}" 2>/dev/null

# 中断再開検出: pick-next 由来の spec/plan があるか
find docs/superpowers/specs -name '*-design.md' -exec grep -l '^pick-next: true' {} \; 2>/dev/null | head -5
```

## tracker タイプ判定

`.claude/project.yml` を yq でパースする（yq が無ければ簡易 grep）。

```bash
TRACKER_TYPE=$(yq -r '.tracker.type' .claude/project.yml 2>/dev/null \
  || grep -E '^[[:space:]]+type:' .claude/project.yml 2>/dev/null | head -1 | awk '{print $2}')
```

得られる値: `linear` / `github` / 空（未設定）。

## Grace Degrade ルール

| 条件 | 挙動 |
|------|------|
| repo 外で起動 | コードベース読込みスキップ、対話続行 |
| `.claude/project.yml` 未存在 / `tracker.type` 空 | 既存候補ゼロで続行（新規候補のみ）、Step 6B 選択時に「`.claude/project.yml` を設定してから `/create-issue <spec> <plan>` を手動実行」と案内 |
| Linear MCP 認証エラー（`mcp__linear-server__list_issues` 呼び出しで失敗） | 「Linear MCP がエラー (xxx)。`/mcp` で接続確認、もしくは `linear auth login` の再実行が必要かも」と提示、既存候補ゼロで続行 |
| GitHub `gh auth status` NG | 「`gh auth login` が必要」と提示、既存候補ゼロで続行 |
| handover scripts 未存在（`~/.claude/skills/handover/scripts/list-active.sh` が無い） | handover 連携をスキップ、警告は出さない |

## 中断再開検出

`docs/superpowers/specs/*-design.md` のフロントマターに `pick-next: true` を含むファイルが見つかった場合:

1. 検出したファイルの `title` と `date` を一覧表示する
2. ユーザーに「続きから再開する？破棄して新規？」を確認
3. 「再開」→ 該当 spec/plan を読み込んで、対応する Step（Step 5 の選定済みテーマ）から続行
4. 「破棄」→ 何もしない（既存ファイルは残す、ユーザーが手動削除）

## 出力

Step 0 の終わりに、以下を Step 1 以降の判断材料として保持する:

- `REPO_ROOT`: リポジトリルート（または空）
- `BRANCH`: 現在のブランチ名
- `TRACKER_TYPE`: `linear` / `github` / 空
- `HANDOVER_NOTES`: 未消費 handover の一覧（issue 名・ブランチ名を含む文字列群）
- `RECENT_COMMITS`: `git log --oneline -20` の出力
- `RESUMING_SPEC`: 中断再開対象の spec パス（または空）
