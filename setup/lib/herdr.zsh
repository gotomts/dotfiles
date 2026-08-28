#!/bin/zsh
# setup/lib/herdr.zsh
#
# Herdr プラグインの識別子とパス解決。setup/herdr-sync.zsh（配置する側）と
# setup/migrate.zsh の health check（配置されたことを確認する側）が同じ答えを出す
# 必要があるため、解決ロジックをここ 1 箇所に置く。
#
# 既知の制約: herdr CLI に問い合わせられるのは呼び出し元自身のホームについてだけ。
# 別ユーザーのホームが対象のときは既定パスの組み立てにフォールバックするので、
# Herdr が設定ディレクトリのレイアウトを変えてもその経路は追従しない
# (herdr::plugin_config_dir のコメント参照)。
#
# lib/util.zsh が事前に source 済みであることを前提とする。

HERDR_SWT_PLUGIN_ID="dotfiles.safe-worktree"

# herdr::plugin_src <dotfiles_root>  リポジトリ内のプラグイン本体のパス
herdr::plugin_src() {
    print -r -- "${1}/herdr/plugins/safe-worktree"
}

# herdr::primary_dotfiles_root [home_dir]
#   プラグインの登録先として唯一許可する dotfiles チェックアウト。
#   テストでは DOTFILES_PRIMARY_ROOT で差し替える。
herdr::primary_dotfiles_root() {
    print -r -- "${DOTFILES_PRIMARY_ROOT:-${1:-${HOME}}/.dotfiles}"
}

# herdr::is_primary_root <dotfiles_root> [home_dir]
#   引数が primary チェックアウトと同一実体なら 0。
#   linked worktree や一時 clone から実行された場合は 1 を返す。
herdr::is_primary_root() {
    local candidate="${1}"
    local primary
    primary="$(herdr::primary_dotfiles_root "${2:-${HOME}}")"
    [[ -d "${candidate}" && -d "${primary}" ]] || return 1
    [[ "${candidate:A}" == "${primary:A}" ]]
}

# herdr::plugin_config_dir [home_dir]
#   プラグイン設定ディレクトリの絶対パス。
#   herdr CLI が使えるならそちらに聞く（パスの決め方は Herdr 側の都合で変わりうるため）。
#   使えない場合だけ現行の既定パスへフォールバックする。
#   home_dir を渡すとフォールバック先をそのホーム基準にする（root から
#   元ユーザーのホームを検査する migrate の health check 用）。
herdr::plugin_config_dir() {
    local home_dir="${1:-${HOME}}"

    # herdr CLI に聞けるのは「自分自身のホームについて尋ねるとき」だけ。
    # migrate の health check は root で走りつつ元ユーザーのホームを対象にするため、
    # そこで herdr を呼ぶと root 自身の設定ディレクトリを答えてしまい、
    # 存在しないパスを検査して必ず失敗する。別ユーザーのホームが対象のときは
    # 既定パスの組み立てだけを使う。
    if [[ "${home_dir:A}" == "${HOME:A}" ]] && command -v herdr &>/dev/null; then
        local dir
        dir="$(herdr plugin config-dir "${HERDR_SWT_PLUGIN_ID}" 2>/dev/null)"
        if [[ -n "${dir}" && "${dir}" == /* ]]; then
            print -r -- "${dir}"
            return 0
        fi
    fi
    print -r -- "${home_dir}/.config/herdr/plugins/config/${HERDR_SWT_PLUGIN_ID}"
}

# herdr::allowlist_link <home_dir>  追跡分 allowlist が置かれるべきパス
herdr::allowlist_link() {
    print -r -- "$(herdr::plugin_config_dir "${1:-${HOME}}")/repos.json"
}
