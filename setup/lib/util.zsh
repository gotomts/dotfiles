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

# util::ensure_homebrew_path  Homebrew の bin/sbin (Apple Silicon + Intel 両 prefix) を
#   PATH の先頭に明示的に足す。
#
#   nix-darwin が生成する /etc/zshenv（repo 管理外、$HOME/.dotfiles には存在しない）は、
#   全 zsh 起動のたびに無条件で PATH を Homebrew を含まない固定リストへ上書きする
#   (`$HOME/.nix-profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:
#   /usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`)。これは ~/.zshenv より先に走るため、
#   呼び出し元 (migrate.zsh の sudo -u <user> -H env PATH=... 委譲実行など) がどんな PATH を
#   渡しても、この zsh プロセス自身の起動時点で消えてしまう（実機インシデントで確認済み、
#   2026-08-22: mise は Homebrew 経由で正しく install 済みだったにも関わらず、委譲実行された
#   languages.zsh の command -v mise が失敗した）。
#   mise/corepack/starship 等、Homebrew 経由でインストールする実行体に依存するスクリプトは、
#   呼び出し元の PATH を信用せず、自分自身の先頭でこれを呼ぶこと。
#   テストでは HOMEBREW_PATH_PREFIX_OVERRIDE で差し替える（実在しない /opt/homebrew 等の
#   絶対パスに依存させないため）。
util::ensure_homebrew_path() {
    local prefix="${HOMEBREW_PATH_PREFIX_OVERRIDE:-/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin}"
    export PATH="${prefix}:${PATH}"
}

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
