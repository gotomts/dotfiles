#!/bin/zsh
# claude.ai のチャット / Code を独立 Chrome ウィンドウ (--app) で開き、
# 「このコマンドで開いた新規ウィンドウだけ」をメインディスプレイのグリッドに整列する。
# 既存のウィンドウ (調べ物・手で開いた会話など) には一切触れない。
#
# 配置は column-major (列優先): 先頭群の new が左の列を上下に埋め、後続の code が
# 右側の列へ回る。デフォルト (new2 / code4) では次のようになる:
#   [new ][code][code]
#   [new ][code][code]
#
# 仕組み: ウィンドウを 1 個ずつ開き、その都度「増えた id」をその場で所定セルへ配置する。
# Chrome の id 列挙順は z-order 依存で「開いた順」と一致しないため、逐次に対応づけることで
# 「URL リストの i 番目 = グリッドの i 番目セル」を保証する。id は z-order に依らず不変なので、
# 配置中にフォーカスが他ウィンドウへ移っても取り違えない。
#
# 使い方: claude-board [チャット数=2] [Code 数=4]

emulate -L zsh
setopt no_unset

local chat_n=${1:-2}
local code_n=${2:-4}

# 引数は非負整数のみ許容 (<-> は zsh の数値グロブ)
local n
for n in "${chat_n}" "${code_n}"; do
  if [[ "${n}" != <-> ]]; then
    print -u2 "claude-board: 個数は 0 以上の整数で指定してください (指定値: ${n})"
    return 1
  fi
done

# 開く URL を並べる (new → code の順。column-major 配置で new が左列に来る)
local -a urls=()
local i
for (( i = 0; i < chat_n; i++ )); do urls+=("https://claude.ai/new"); done
for (( i = 0; i < code_n; i++ )); do urls+=("https://claude.ai/code"); done

local total=${#urls[@]}
if (( total == 0 )); then
  print -u2 "claude-board: 開くウィンドウがありません (チャット数=${chat_n}, Code 数=${code_n})"
  return 1
fi

# Chrome の全ウィンドウ id を改行区切りで返す。
# ウィンドウ皆無や一過性の接続エラー (-609) 時は空を返す。
_cb_window_ids() {
  osascript -e 'tell application "Google Chrome" to get id of every window' 2>/dev/null \
    | tr ',' '\n' | tr -d ' '
}

# メインディスプレイ解像度を取得 (Finder desktop の bounds = {0, 0, W, H})
local desktop_bounds
desktop_bounds=$(osascript -e 'tell application "Finder" to get bounds of window of desktop')
local -a wh=( ${(s:, :)desktop_bounds} )
local screen_w=${wh[3]}
local screen_h=${wh[4]}

# グリッドのセル寸法を算出 (3 列固定・行は総数から / メニューバー分だけ上を空ける)
local cols=3
local menubar=25
local rows=$(( (total + cols - 1) / cols ))
local cell_w=$(( screen_w / cols ))
local cell_h=$(( (screen_h - menubar) / rows ))

# 既知 (= 新規でない) id。ループ内で開いた分を順次足し、差分から除外していく
local -a known_ids
known_ids=( ${(f)"$(_cb_window_ids)"} )

local idx url col row left top right bottom new_id waited tries
local -a cur diff
for (( idx = 0; idx < total; idx++ )); do
  url=${urls[idx + 1]}
  open -na "Google Chrome" --args --app="${url}"

  # このコマンドが今開いた 1 個 (known に無い id) が現れるまで最大 ~10 秒待つ
  new_id=""
  waited=0
  while (( waited < 50 )); do
    cur=( ${(f)"$(_cb_window_ids)"} )
    diff=( ${cur:|known_ids} )
    if (( ${#diff[@]} >= 1 )); then
      new_id=${diff[1]}
      break
    fi
    sleep 0.2
    (( waited += 1 ))
  done
  [[ -z "${new_id}" ]] && continue
  known_ids+=("${new_id}")

  # column-major: col は rows ごとに繰り上がる (先頭の new が左列を上下に埋める)
  col=$(( idx / rows ))
  row=$(( idx % rows ))
  left=$(( col * cell_w ))
  top=$(( menubar + row * cell_h ))
  right=$(( left + cell_w ))
  bottom=$(( top + cell_h ))

  # 生成直後は set も一過性 (-609) に失敗しうるため数回リトライする
  tries=0
  while (( tries < 5 )); do
    osascript -e "tell application \"Google Chrome\" to set bounds of (first window whose id is ${new_id}) to {${left}, ${top}, ${right}, ${bottom}}" 2>/dev/null && break
    sleep 0.2
    (( tries += 1 ))
  done
done
