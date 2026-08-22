#!/bin/zsh
# setup/lib/util.zsh
#
# ログ・確認ヘルパー。旧 setup/util.zsh（Nix 移行前）の役割を復元し、
# nix/scripts/migrate-symlinks.zsh の色分けログ（info/warning/action/skip）命名を踏襲する。

util::info()    { echo "\e[32m[setup] ${1}\e[m" }
util::warning() { echo "\e[33m[setup] ${1}\e[m" }
util::error()   { echo "\e[31m[setup] ${1}\e[m" >&2 }
util::action()  { echo "\e[36m[setup] ${1}\e[m" }
util::skip()    { echo "\e[90m[setup] SKIP: ${1}\e[m" }

# util::confirm <message>
#   FORCE=1 なら常に yes 扱い。それ以外は y/N プロンプト。
#   戻り値 0 = yes、4 = no（旧 setup/util.zsh の終了コードを踏襲）
util::confirm() {
    local message="${1}"

    if [[ "${FORCE:-0}" == "1" ]]; then
        return 0
    fi

    echo "${message} (y/N)"
    read confirmation
    if [[ "${confirmation}" == "y" || "${confirmation}" == "Y" ]]; then
        return 0
    fi

    return 4
}
