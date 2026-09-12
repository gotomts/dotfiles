#!/bin/zsh
# setup/notion.zsh
#
# Tier 2: Notion CLI (ntn) を ${HOME}/.local/bin へ導入する。
#
# Homebrew formula が存在しないため homebrew.nix では宣言できない。npm 版もあるが、
# グローバルツールを Node ランタイムに依存させないため公式配布バイナリを使う。公式
# インストーラ (https://ntn.dev/install.sh) に次の 2 つを渡して、導入結果を宣言側で
# 決めきる:
#   - NTN_INSTALL_DIR: 導入先を ${HOME}/.local/bin に固定する（インストーラ既定の
#     導入先選択は実行時の PATH の形に依存して揺れ、health check と食い違うため）
#   - NTN_VERSION: 下の NTN_PINNED_VERSION に固定する（既定の latest だと「導入した
#     日」で版が決まり、PC ごとに別物が入る）。版を上げるのは dotfiles 側の明示変更
# PATH への ${HOME}/.local/bin の追加は Tier 1 の zshenv が担当する。
#
# 冪等性: 既に ntn が実行可能なら何もしない。NTN_PINNED_VERSION を上げても既存バイナリは
# 入れ替えない（実行中のバイナリを黙って差し替えないため）。入れ替えるときは実体を消して
# から再実行する。
#
# fail-closed: ntn は恒久的に宣言したグローバル必須ツールなので、初回ダウンロードの
# 失敗は migrate 全体の失敗として扱う（「入らなかったが成功」を健全な状態にしない）。
# 既にバイナリがある PC では一切ネットワークに出ないため、オフラインでも --apply は通る。
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
# 宣言する版。上げるときはここを書き換える（更新は dotfiles 側の明示変更で行う）。
NTN_PINNED_VERSION="0.23.4"
# テストではサンドボックス内のスタブを指す URL に差し替える（実ネットワークに触れない）。
NTN_INSTALLER_URL="${NTN_INSTALLER_URL:-https://ntn.dev/install.sh}"

util::info "=== Tier 2: Notion CLI (ntn) ==="

# -f も見る: -x だけだとディレクトリ（実行ビットが立っている）を「導入済み」と
# 誤判定し、インストーラを呼ばないまま成功して抜けてしまう。
if [[ -f "${NTN_BIN}" && -x "${NTN_BIN}" ]]; then
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

util::action "ntn ${NTN_PINNED_VERSION} を ${NTN_INSTALL_DIR} へ導入します"
mkdir -p "${NTN_INSTALL_DIR}"
# インストーラは bash 前提（#!/usr/bin/env bash）なので zsh では実行しない。
if ! NTN_INSTALL_DIR="${NTN_INSTALL_DIR}" NTN_VERSION="${NTN_PINNED_VERSION}" bash "${installer}"; then
    util::error "インストーラの実行に失敗しました"
    exit 1
fi

if [[ ! -f "${NTN_BIN}" || ! -x "${NTN_BIN}" ]]; then
    util::error "インストーラは成功しましたが ${NTN_BIN} が実行可能になっていません"
    exit 1
fi

util::info "${NTN_BIN} (${NTN_PINNED_VERSION}) を導入しました"
