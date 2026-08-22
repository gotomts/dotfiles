#!/bin/zsh
# setup/codex-sync.zsh
#
# Tier 2: Codex CLI の config.toml を seed-if-absent する。
# nix/modules/home/codex.nix の home.activation.syncCodexConfig を移植したもの。
# ~/.codex/config.toml は Codex / ChatGPT desktop アプリが動的に書き換える running
# config (絶対パス/marketplaces/plugins/trust_level 等) のため、既存ファイルには一切
# 触れない。不在のときだけ codex/config.base.toml を cp する。
#
# 使い方:
#   zsh ${HOME}/.dotfiles/setup/codex-sync.zsh
#
# 終了コード: 常に 0（fail-open。config.base.toml 不在時も warning のみで継続）

SETUP_DIR="${0:A:h}"
DOTFILES_ROOT="${SETUP_DIR:h}"
source "${SETUP_DIR}/lib/util.zsh"

util::info "=== Tier 2: Codex config seed ==="

TARGET="${HOME}/.codex/config.toml"
BASE="${DOTFILES_ROOT}/codex/config.base.toml"

if [[ ! -f "${BASE}" ]]; then
    util::warning "config.base.toml 不在、config seed をスキップ"
    exit 0
fi

if [[ -e "${TARGET}" ]]; then
    util::skip "${TARGET} は既に存在します（アプリ所有の running config、触れません）"
    exit 0
fi

mkdir -p "${TARGET:h}"
cp "${BASE}" "${TARGET}"
chmod 600 "${TARGET}"
util::info "${TARGET} を config.base.toml から seed しました"
