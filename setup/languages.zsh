#!/bin/zsh
# setup/languages.zsh
#
# Tier 2: mise で言語ランタイム (node/go/ruby/rust/python/dart) を install し、
# mise 管理下の node に対して corepack を有効化する (pnpm/yarn グローバル供給)。
#
# 旧 setup/install/{04_node,05_go,06_ruby,07_rust,08_python,09_dart}.zsh
# （Nix 移行で削除済み）の役割を復元する。node だけ `lts` を使う理由は corepack 同梱版の
# 安定性を優先するため。他言語は旧スクリプトの `@latest` 慣行をそのまま復元する。
#
# 前提: `mise` は Homebrew (nix/modules/darwin/homebrew.nix の coreBrews) で導入される。
# このスクリプトはパッケージマネージャを呼ばない (mise 自体の install は担当しない)。
#
# 使い方:
#   zsh ${HOME}/.dotfiles/setup/languages.zsh
#
# 終了コード:
#   0  成功
#   1  mise が PATH 上に見つからない

set -eu

SETUP_DIR="${0:A:h}"
source "${SETUP_DIR}/lib/util.zsh"

if ! command -v mise &>/dev/null; then
    util::error "mise が見つかりません。'darwin-switch' で Homebrew 経由の導入を先に済ませてください"
    exit 1
fi

util::info "=== Tier 2: 言語ランタイム install (mise) ==="

# mise::pin <lang> <version>
#   mise install <lang>@<version> → mise use --global <lang>@<version> の順で呼ぶ
mise::pin() {
    local lang="${1}"
    local version="${2}"

    util::action "${lang}@${version} を install"
    mise install "${lang}@${version}"

    util::action "${lang}@${version} を --global に設定"
    mise use --global "${lang}@${version}"
}

mise::pin node lts
mise::pin go latest
mise::pin ruby latest
mise::pin rust latest
mise::pin python latest
mise::pin dart latest

# ---- corepack (pnpm/yarn グローバル供給) --------------------------------------
# mise が管理する node の実行ファイルパスから、同じ bin ディレクトリに同梱されている
# corepack を有効化する。COREPACK_HOME/PATH の環境変数設定自体は Tier 1 の zshenv が
# 既に行っているため、ここでは shim の生成のみを行う。
util::info "=== corepack 有効化 ==="

local node_bin
node_bin="$(mise which node)"

if [[ -z "${node_bin}" ]]; then
    util::error "mise which node が node の実行ファイルパスを返しませんでした"
    exit 1
fi

local corepack_bin="${node_bin:h}/corepack"
local corepack_install_dir="${HOME}/.local/share/corepack/bin"

mkdir -p "${corepack_install_dir}"
"${corepack_bin}" enable --install-directory "${corepack_install_dir}"

util::info "=== Tier 2: 言語ランタイム install 完了 ==="
