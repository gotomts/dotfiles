---
name: pick-next
description: 「次に何をやるか」を対話で決定する。既存 active issue（Linear / GitHub）の優先度推奨、新規テーマの候補出しと 3 軸スコア比較、判断結果に応じて Issue 作成・既存 Issue 選定・保留の 3 分岐に振り分ける。「次に何やる？」「Linear/GitHub 確認して」「優先度教えて」「次の開発内容を相談したい」と聞かれたら必ず使う。引数なし or 任意のヒント文字列で起動。
argument-hint: '[hint] [--epic <issue-id>] [--all] [--axes <カスタム軸>]'
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - Write
  - TaskCreate
  - TaskUpdate
  - ToolSearch
  - Skill
---

# pick-next

「次に何をやるか」を対話で決定する。Step 0〜7 を順に実行し、最後に 3 つの分岐（既存 Issue 選定 / 新規テーマ作成 / 保留）のいずれかに到達する。

## 対話プロトコル概要

詳細は references を参照しながら、各 Step を順に実行する:

- Step 0: 環境検出 + handover → `references/environment-detection.md`
- Step 1: 既存 active issue 取得 & ランク付け → `references/ranking-signals.md`
- Step 2: ヒアリング & 新規候補引き出し
- Step 3: 候補統合（既存 + 新規 + 推測）
- Step 4: 3 軸スコア & 比較 → `references/score-axes.md`
- Step 5: 1 つ選定 & 分岐判定
- Step 6A: 既存 Issue 確定（issue-dev 起動を案内）
- Step 6B: spec/plan 書き出し → create-issue 呼び出し → `references/spec-template.md` `references/plan-template.md` `references/decomposition-guide.md`
- Step 6C: 保留（判断ログ任意）→ `references/decision-log-template.md`
- Step 7: 完了報告

本ファイルは Task 9 で本文を完成させる。
