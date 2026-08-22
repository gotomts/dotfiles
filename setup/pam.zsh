#!/bin/zsh
# setup/pam.zsh
#
# Tier 2: Touch ID for sudo (/etc/pam.d/sudo_local)。
# nix-darwin の security.pam.services.sudo_local.touchIdAuth = true が生成する内容を
# 1:1 で移植する。reattach (tmux/cmux 内での Touch ID) は Phase A の決定通り含めない
# (nix/modules/darwin/pam.nix のコメント参照)。
#
# 書き込み先は ${SUDO_LOCAL_PATH:-/etc/pam.d/sudo_local}（テストでオーバーライド可能）。
#
# 使い方:
#   zsh ${HOME}/.dotfiles/setup/pam.zsh   # 実際にはこの後 sudo が必要になる
#
# 終了コード:
#   0  成功（新規作成・冪等スキップ・上書きのいずれか）
#   1  <path>.before-setup が既に存在するため退避できず停止

set -eu

SETUP_DIR="${0:A:h}"
source "${SETUP_DIR}/lib/util.zsh"

TARGET="${SUDO_LOCAL_PATH:-/etc/pam.d/sudo_local}"

# 期待コンテンツ。pam.nix の touchIdAuth=true が /etc/pam.d/sudo_local に書く内容と同義。
EXPECTED_CONTENT="# Managed by dotfiles setup/pam.zsh (Touch ID for sudo)
auth       sufficient     pam_tid.so"

util::info "=== Tier 2: Touch ID for sudo (${TARGET}) ==="

if [[ -e "${TARGET}" ]]; then
    current_content="$(<"${TARGET}")"
    if [[ "${current_content}" == "${EXPECTED_CONTENT}" ]]; then
        util::skip "${TARGET} は既に想定コンテンツです"
        exit 0
    fi

    backup="${TARGET}.before-setup"
    if [[ -e "${backup}" ]]; then
        util::error "${backup} が既に存在するため ${TARGET} を退避できません（既存ファイルには触れていません）"
        exit 1
    fi

    util::warning "${TARGET} の内容が異なります。${backup} に退避してから書き換えます"
    /bin/mv "${TARGET}" "${backup}"
fi

mkdir -p "${TARGET:h}"
print -r -- "${EXPECTED_CONTENT}" > "${TARGET}"
util::info "${TARGET} に Touch ID for sudo を設定しました"
