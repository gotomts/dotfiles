#!/bin/zsh
# setup/notion.zsh
#
# Tier 2: Notion CLI (ntn) を ${HOME}/.local/bin へ導入する。
#
# Homebrew formula が存在しないため homebrew.nix では宣言できない。公式インストーラ
# (https://ntn.dev/install.sh) が置く単一バイナリを、NTN_INSTALL_DIR で導入先を
# ${HOME}/.local/bin に固定したうえで使う（インストーラ既定の導入先選択は PATH の
# 現状に依存して揺れるため、宣言側で固定して health check と一致させる）。
# PATH への ${HOME}/.local/bin の追加は Tier 1 の zshenv が担当する。
#
# 冪等性: 既に ntn が実行可能なら何もしない。バージョン更新はこのスクリプトの責務では
# ない（更新したいときは実体を消してから再実行するか、ntn 自身の更新手順に従う）。
#
# 認証は扱わない: NOTION_API_KEY 等のトークンをこのスクリプトは読まない・要求しない・
# 保存しない。導入後の認証は人間が ntn 側の手順で行う。
#
# 使い方:
#   zsh ${HOME}/.dotfiles/setup/notion.zsh
#
# 終了コード:
#   0  成功（既に導入済みで skip した場合も含む）
#   1  curl 不在、インストーラの取得/実行の失敗、または実行後に ntn が現れなかった

set -eu

SETUP_DIR="${0:A:h}"
source "${SETUP_DIR}/lib/util.zsh"

NTN_INSTALL_DIR="${HOME}/.local/bin"
NTN_BIN="${NTN_INSTALL_DIR}/ntn"
# テストではサンドボックス内のスタブを指す URL に差し替える（実ネットワークに触れない）。
NTN_INSTALLER_URL="${NTN_INSTALLER_URL:-https://ntn.dev/install.sh}"

util::info "=== Tier 2: Notion CLI (ntn) ==="

if [[ -x "${NTN_BIN}" ]]; then
    util::skip "${NTN_BIN} は既に実行可能です（インストーラを呼びません）"
    exit 0
fi

if ! command -v curl &>/dev/null; then
    util::error "curl が見つかりません。ntn の導入をスキップせず失敗として扱います"
    exit 1
fi

installer="$(mktemp)"
trap '/bin/rm -f "${installer}"' EXIT

util::action "公式インストーラを取得します: ${NTN_INSTALLER_URL}"
# curl を pipe で bash に直結しない。取得失敗時に空スクリプトを実行して「成功」に
# 見えてしまうのを防ぐため、ファイルへ落として取得の exit code を確かめる。
if ! curl -fsSL -o "${installer}" "${NTN_INSTALLER_URL}"; then
    util::error "インストーラの取得に失敗しました: ${NTN_INSTALLER_URL}"
    exit 1
fi

util::action "ntn を ${NTN_INSTALL_DIR} へ導入します"
mkdir -p "${NTN_INSTALL_DIR}"
# インストーラは bash 前提（#!/usr/bin/env bash）なので zsh では実行しない。
if ! NTN_INSTALL_DIR="${NTN_INSTALL_DIR}" bash "${installer}"; then
    util::error "インストーラの実行に失敗しました"
    exit 1
fi

if [[ ! -x "${NTN_BIN}" ]]; then
    util::error "インストーラは成功しましたが ${NTN_BIN} が実行可能になっていません"
    exit 1
fi

util::info "${NTN_BIN} を導入しました"
