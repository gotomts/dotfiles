#!/bin/zsh
# setup/jev-ultrafast.zsh
#
# Tier 2: Jev Ultrafast (browser-use/jev-ultrafast) を uv tool としてユーザー scope に導入し、
# 専用ブラウザ用の状態ディレクトリを用意する。
#
# 宣言値（導入元・commit SHA・導入先・専用 profile のパス）は setup/lib/jev-ultrafast.zsh に
# 集約してある。ここではそれを uv に渡すだけ:
#   - requirement: git+<repo>@<commit SHA>。upstream の moving main には依存しない
#   - UV_TOOL_DIR / UV_TOOL_BIN_DIR: 導入先を明示する（uv 既定の XDG 解決に揺らさない）
# uv tool は tool ごとに別の venv を持つので、既存の browser-use tool（とその中の
# browser-harness）とは混ざらない。--force は付けない — 他 tool が所有する同名の実行ファイルを
# 上書きしてしまうため、衝突したら uv の失敗として止める。
#
# 冪等性と収束: 導入済みの revision（venv 内の direct_url.json）が宣言と一致すれば uv を
# 呼ばない。一致しなければ --reinstall で宣言の revision へ入れ替える（ntn と違って実行中の
# 単一バイナリを差し替えるわけではなく、venv ごと作り直すだけなので自動で収束させる）。
# migrate.zsh は success 済みのステップを再実行しないため、revision を上げた既存 PC では
# health check が不一致を報告する。そのときはこのスクリプトを直接再実行する。
#
# 専用ブラウザ: ここでは Chrome を起動しない（GUI の副作用を migrate に持ち込まない）。
# --user-data-dir に使う profile と browser-harness の BH_HOME を owner だけが読めるように
# 作るところまでを持つ。起動と接続は scripts/jev-ultrafast.zsh（`jev-ultrafast browser`）が
# 都度、宣言値どおりに行う。
#
# 秘密は扱わない: API key はこのスクリプトでは読まない・要求しない・保存しない。
#
# 使い方:
#   zsh ${HOME}/.dotfiles/setup/jev-ultrafast.zsh
#
# 終了コード:
#   0  成功（宣言の revision が既に入っていて skip した場合も含む）
#   1  uv 不在、uv tool install の失敗、または導入後も revision が宣言と一致しない

set -eu

SETUP_DIR="${0:A:h}"
source "${SETUP_DIR}/lib/util.zsh"
source "${SETUP_DIR}/lib/jev-ultrafast.zsh"

# uv は Homebrew 経由で入る。呼び出し元（migrate.zsh の委譲実行など）の PATH を信用しない。
util::ensure_homebrew_path

util::info "=== Tier 2: Jev Ultrafast ==="

jev-ultrafast::ensure_private_dirs() {
    local dir
    for dir in "$(jev_ultrafast::state_dir "${HOME}")" \
               "$(jev_ultrafast::profile_dir "${HOME}")" \
               "$(jev_ultrafast::harness_home "${HOME}")"; do
        mkdir -p "${dir}"
        chmod 700 "${dir}"
    done
}

installed_rev="$(jev_ultrafast::installed_rev "${HOME}")"
python_bin="$(jev_ultrafast::python "${HOME}")"

if [[ "${installed_rev}" == "${JEV_ULTRAFAST_REV}" && -x "${python_bin}" ]]; then
    util::skip "${JEV_ULTRAFAST_TOOL} ${JEV_ULTRAFAST_REV} は導入済みです（uv を呼びません）"
    jev-ultrafast::ensure_private_dirs
    exit 0
fi

if ! command -v uv &>/dev/null; then
    util::error "uv が見つかりません。${JEV_ULTRAFAST_TOOL} の導入をスキップせず失敗として扱います"
    exit 1
fi

install_args=(tool install)
if [[ -n "${installed_rev}" ]]; then
    util::action "${JEV_ULTRAFAST_TOOL} を ${installed_rev} から ${JEV_ULTRAFAST_REV} へ入れ替えます"
    install_args+=(--reinstall)
else
    util::action "${JEV_ULTRAFAST_TOOL} ${JEV_ULTRAFAST_REV} を導入します"
fi
install_args+=("$(jev_ultrafast::requirement)")

if ! UV_TOOL_DIR="$(jev_ultrafast::uv_tool_dir "${HOME}")" \
     UV_TOOL_BIN_DIR="$(jev_ultrafast::uv_tool_bin_dir "${HOME}")" \
     uv "${install_args[@]}"; then
    util::error "uv tool install に失敗しました"
    exit 1
fi

installed_rev="$(jev_ultrafast::installed_rev "${HOME}")"
if [[ "${installed_rev}" != "${JEV_ULTRAFAST_REV}" || ! -x "${python_bin}" ]]; then
    util::error "導入後の revision が宣言と一致しません（宣言: ${JEV_ULTRAFAST_REV} / 実体: ${installed_rev:-取得できませんでした}）"
    exit 1
fi

jev-ultrafast::ensure_private_dirs
util::info "${JEV_ULTRAFAST_TOOL} ${JEV_ULTRAFAST_REV} を導入しました"
