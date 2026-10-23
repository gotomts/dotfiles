#!/bin/zsh
# setup/lib/jev-ultrafast.zsh
#
# Jev Ultrafast (browser-use/jev-ultrafast) の宣言値とパス解決だけを持つ共有ライブラリ。
# 導入する側 (setup/jev-ultrafast.zsh)・確認する側 (setup/migrate.zsh の health check)・
# 使う側 (scripts/jev-ultrafast.zsh) が同じ定義を引くためにここへ寄せている
# （setup/lib/notion.zsh と同じ理由。別々に書くと revision を上げたときに片方だけ古い値を
# 見に行く）。

# 導入元と revision。upstream はタグもリリースも切っておらず main が動き続けるため、
# commit SHA（40 桁）で固定する。上げるときはここを書き換え、`zsh setup/jev-ultrafast.zsh`
# を再実行する（導入済みの revision と食い違えば入れ替えて収束させる）。
JEV_ULTRAFAST_REPO_URL="https://github.com/browser-use/jev-ultrafast"
JEV_ULTRAFAST_REV="1231850a0bf1a0c0341fe408ef1668dbbfdfac46"

# uv tool としての名前（= upstream の package 名）。uv tool は tool ごとに別の venv を持つので、
# 既存の browser-use tool（とその中の browser-harness）とは混ざらない。
JEV_ULTRAFAST_TOOL="jev-ultrafast"

# 専用 Chrome の remote debugging port。browser-harness が既定 profile 探索の後に総当たりする
# 9222/9223 を避ける（そこに普段の Chrome が居ても拾わないため）。
JEV_ULTRAFAST_CDP_PORT="9339"
JEV_ULTRAFAST_CHROME_APP="/Applications/Google Chrome.app"

# browser-harness の daemon 名（BU_NAME）。socket・pid・log がこの名前で分かれるので、
# 他の利用者の default daemon を再利用・停止しない。
JEV_ULTRAFAST_DAEMON_NAME="jev-ultrafast"

# jev_ultrafast::requirement  uv tool install に渡す requirement
jev_ultrafast::requirement() {
    print -r -- "git+${JEV_ULTRAFAST_REPO_URL}@${JEV_ULTRAFAST_REV}"
}

# jev_ultrafast::uv_tool_dir <home>  uv tool の venv 置き場（UV_TOOL_DIR として明示的に渡す）
jev_ultrafast::uv_tool_dir() {
    print -r -- "${1}/.local/share/uv/tools"
}

# jev_ultrafast::uv_tool_bin_dir <home>  uv tool の実行ファイル置き場（UV_TOOL_BIN_DIR）
jev_ultrafast::uv_tool_bin_dir() {
    print -r -- "${1}/.local/bin"
}

# jev_ultrafast::python <home>  jev-ultrafast の venv の python。CLI はこれで upstream の
#   library を呼ぶ（upstream の `jev` 実行ファイルはデモ用 inspector で、agent からは使わない）。
jev_ultrafast::python() {
    print -r -- "$(jev_ultrafast::uv_tool_dir "${1}")/${JEV_ULTRAFAST_TOOL}/bin/python"
}

# jev_ultrafast::installed_rev <home>  導入済みの commit SHA を返す。未導入なら空文字列。
#   uv が書く PEP 610 の direct_url.json をファイルとして読む（実行しないので、root で走る
#   migrate.zsh の health check からも元ユーザーへ委譲せずに読める）。
jev_ultrafast::installed_rev() {
    local -a found
    found=("$(jev_ultrafast::uv_tool_dir "${1}")/${JEV_ULTRAFAST_TOOL}"/lib/python*/site-packages/jev_ultrafast-*.dist-info/direct_url.json(N))
    (( ${#found[@]} == 1 )) || return 0
    sed -n 's/.*"commit_id": *"\([0-9a-f]*\)".*/\1/p' "${found[1]}"
}

# jev_ultrafast::state_dir <home>  Jev 専用の状態置き場（profile・browser-harness の作業領域）
jev_ultrafast::state_dir() {
    print -r -- "${1}/.local/state/jev-ultrafast"
}

# jev_ultrafast::profile_dir <home>  専用 Chrome の --user-data-dir。普段の Chrome の
#   profile（~/Library/Application Support/Google/Chrome）とも、Hermes の real-profile
#   snapshot とも別の場所に置く。remote debugging を有効にするのはこの profile だけ。
jev_ultrafast::profile_dir() {
    print -r -- "$(jev_ultrafast::state_dir "${1}")/chrome-profile"
}

# jev_ultrafast::harness_home <home>  browser-harness の BH_HOME。既定の
#   ~/.config/browser-harness（他の利用者と共有され得る .env・設定を持つ）を読ませない。
jev_ultrafast::harness_home() {
    print -r -- "$(jev_ultrafast::state_dir "${1}")/browser-harness"
}

# jev_ultrafast::cdp_url  専用 Chrome の DevTools HTTP endpoint（browser-harness の BU_CDP_URL）
jev_ultrafast::cdp_url() {
    print -r -- "http://127.0.0.1:${JEV_ULTRAFAST_CDP_PORT}"
}
