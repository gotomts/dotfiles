#!/bin/zsh
# Claude Code のモデルを fzf で選んでからセッションを開始する。
#
# アカウント既定のモデルはセッション単位の --model で上書きされるため、
# 「今回だけ別モデル」を選ぶ用途に使う。通常の `claude` はラップしないので、
# モデル選択を挟みたいときだけ claudem を使う。
# 追加の引数はそのまま claude へ渡す (例: claudem -c / claudem --resume)。
#
# --model は resume 時の解決順で最優先 (transcript のモデルより上) なので、
# 1M context を使いたいモデルには [1m] サフィックスを明示する。付け忘れると
# claudem --resume で 1M セッションを 200K に落としてしまう。
#
# 使い方: claudem [claude に渡す引数...]

emulate -L zsh
setopt no_unset

local cmd
for cmd in claude fzf; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    print -u2 "claudem: ${cmd} コマンドが見つかりません"
    return 1
  fi
done

# 確認済みのモデル候補と完全な ID の SSOT。「表示ラベル<TAB>モデル ID」の一覧で、
# 世代ごとに新しいものから並べ、アカウント既定のものに (既定) を付ける。並び順と既定は
# 一致しないことがある (既定を上げるのは claude/settings.json の model を変える別の判断)。
# Hermes が Claude Code セッションへ渡す「確認済みの最新 Opus / 最新 Sonnet /
# 曖昧なときの fallback」もこの一覧から解決する (規範は claude/hermes/SOUL.md)。
# 新しい世代を実際に確認できたときだけここを更新し、未確認の ID は足さない。
local -a models=(
  "Opus 5.5 (既定) — 最新世代 / 1M context\tclaude-opus-5-5[1m]"
  "Opus 5 — 前世代 / 1M context\tclaude-opus-5[1m]"
  "Fable 5 — 速度と性能のバランス\tclaude-fable-5"
  "Sonnet 5 — 日常作業向け\tclaude-sonnet-5"
  "Haiku 4.5 — 軽量・高速\tclaude-haiku-4-5-20251001"
)

# --with-nth=1 でモデル ID を隠し、ラベルだけを見せて選ばせる
local selected
selected=$(print -l -- "${models[@]}" \
  | fzf --prompt='model> ' --header='Claude Code のモデルを選択' \
        --delimiter='\t' --with-nth=1) || {
  print -u2 "claudem: 選択をキャンセルしました"
  return 130
}

# ラベル部を落として ID だけ取り出す
local model=${selected#*$'\t'}
if [[ -z "${model}" || "${model}" == "${selected}" ]]; then
  print -u2 "claudem: モデル ID を取得できませんでした (選択値: ${selected})"
  return 1
fi

# alias が `zsh <script>` で別プロセスを起こすため、exec が置き換えるのはこの子 zsh だけで、
# 対話シェルは残る。中間 zsh を挟まないぶん claude が直接 TTY とシグナルを受け取れる。
exec claude --model "${model}" "$@"
