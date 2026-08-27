#!/bin/zsh
# setup/languages.zsh
#
# Tier 2: mise で言語ランタイム (node/go/ruby/rust/python/dart) を install し、
# mise 管理下の node に対して corepack を有効化し (pnpm/yarn グローバル供給)、
# バージョンを固定する必要がある CLI tool を mise で供給する。
#
# 旧 setup/install/{04_node,05_go,06_ruby,07_rust,08_python,09_dart}.zsh
# （Nix 移行で削除済み）の役割を復元する。node だけ `lts` を使う理由は corepack 同梱版の
# 安定性を優先するため。他言語は旧スクリプトの `@latest` 慣行をそのまま復元する。
#
# ここで宣言するものはすべて `mise use --global` なので role (default / sub-1) に依らず
# 共通に効く。role 別の出し分けが要るものは Homebrew (homebrew.nix) 側で宣言すること。
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

# 呼び出し元 (migrate.zsh の委譲実行など) の PATH を信用しない。詳細は
# util::ensure_homebrew_path のコメント参照。
util::ensure_homebrew_path

if ! command -v mise &>/dev/null; then
    util::error "mise が見つかりません。'darwin-switch' で Homebrew 経由の導入を先に済ませてください"
    exit 1
fi

util::info "=== Tier 2: 言語ランタイム install (mise) ==="

# mise::pin <tool> <version>
#   mise install <tool>@<version> → mise use --global <tool>@<version> の順で呼ぶ。
#   <tool> には backend 接頭辞付きの指定 (例: aqua:dolthub/dolt) もそのまま渡せる。
mise::pin() {
    local tool="${1}"
    local version="${2}"

    util::action "${tool}@${version} を install"
    mise install "${tool}@${version}"

    util::action "${tool}@${version} を --global に設定"
    mise use --global "${tool}@${version}"
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

# ---- バージョン固定 CLI --------------------------------------------------------
# 版を固定する必要がある CLI tool だけは Homebrew ではなく mise で供給する。Homebrew
# formula は任意バージョンの pin を表現できず (`dolt@2.2` のような versioned formula は
# 存在しない)、nix-darwin の homebrew.brews にも version フィールドが無いため、宣言的に
# 版を固定できる経路が mise しかないことによる。
#
# dolt: beads の server / shared-server モードは PATH 上の standalone `dolt` を
# exec.LookPath で解決する。beads は 2.2.0 を pin しており、2.3.0/2.3.1 は
# CALL DOLT_RESET('--hard') が新規 DB の数 % で恒久破損する回帰を持つ (upstream 実測:
# 2.2.0 0/60、2.3.0 3/60、2.3.1 3/100)。Homebrew の `beads` formula が依存として引き込む
# dolt 2.3.x は削除しない (beads の依存なので zap 対象外)。実行体が mise 側に寄るのは
# PATH 順序による:
#   - non-interactive shell (beads が spawn する dolt sql-server はこちら): zshenv の
#     `mise activate --shims` が shims を PATH 先頭に置き、`brew shellenv` は走らない
#   - interactive shell: zshrc の `mise activate zsh` が `brew shellenv` より後に走る
util::info "=== Tier 2: バージョン固定 CLI install (mise) ==="

mise::pin aqua:dolthub/dolt 2.2.0

util::info "=== Tier 2: 言語ランタイム / バージョン固定 CLI install 完了 ==="
