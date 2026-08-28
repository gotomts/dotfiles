#!/bin/zsh
# setup/herdr-sync.zsh
#
# Tier 2: Herdr のローカルプラグイン同期。
#   1. herdr/plugins/safe-worktree を local plugin として link する（未登録時のみ）
#   2. allowlist の SSOT (config/repos.json) を HERDR_PLUGIN_CONFIG_DIR へ symlink する
#   3. マシンローカル用の repos.local.json を seed-if-absent で置く
#
# plugin の登録先 (~/.config/herdr/plugins.json) は Herdr が動的に書き換える running config
# なので symlink・追跡しない。~/.claude.json や ~/.codex/config.toml と同種の扱い。
# plugin 本体はリポジトリの working tree を直接指すため、link 後の編集は再実行なしで反映される。
#
# 非公開リポジトリを allowlist に入れたい場合は repos.json ではなく
# ${HERDR_PLUGIN_CONFIG_DIR}/repos.local.json に書く（公開リポジトリに非公開リポジトリの
# 名前を載せないため。nix/modules/darwin/homebrew.nix の homebrew.local.nix と同じ方針）。
#
# 使い方:
#   zsh ${HOME}/.dotfiles/setup/herdr-sync.zsh
#
# 終了コード: 常に 0（fail-open。herdr 未インストールの新規 PC で環境構築全体が止まる方が
# 害が大きいため、claude-sync.zsh / codex-sync.zsh と同じ設計判断を踏襲する）

SETUP_DIR="${0:A:h}"
DOTFILES_ROOT="${SETUP_DIR:h}"
source "${SETUP_DIR}/lib/util.zsh"
source "${SETUP_DIR}/lib/fs.zsh"
source "${SETUP_DIR}/lib/herdr.zsh"

# 呼び出し元 (migrate.zsh の委譲実行など) の PATH を信用しない。
# 理由は util::ensure_homebrew_path のコメント参照。
util::ensure_homebrew_path

util::info "=== Tier 2: Herdr plugin sync ==="

SWT_PLUGIN_ID="${HERDR_SWT_PLUGIN_ID}"
SWT_PLUGIN_SRC="$(herdr::plugin_src "${DOTFILES_ROOT}")"

# ---------------------------------------------------------------------------
# 0. primary チェックアウトからの実行かを確認する
#
#   `herdr plugin link` は渡されたパスをそのまま登録先として保存し、プラグインは
#   以後そのパスから実行される。linked worktree や一時 clone を登録すると、
#   その worktree を消した時点でプラグイン本体と allowlist の symlink が同時に壊れる。
#   worktree は使い捨てなので、消える前提の場所を登録先にしてはいけない。
#
#   そのため primary (${HOME}/.dotfiles) 以外から実行された場合は、link も設定配置も
#   両方まとめて何もしない。片方だけ実行すると、登録されているプラグインとは別の場所の
#   allowlist を指す symlink が残り、どちらが効いているのか分からなくなる。
# ---------------------------------------------------------------------------
if ! herdr::is_primary_root "${DOTFILES_ROOT}"; then
    util::warning "primary チェックアウト以外からの実行のため、plugin link と設定配置をスキップします"
    util::warning "  実行元  : ${DOTFILES_ROOT}"
    util::warning "  primary : $(herdr::primary_dotfiles_root)"
    util::warning "  使い捨ての worktree を登録すると、削除時に plugin と allowlist が同時に壊れます"
    util::info "=== Tier 2: Herdr plugin sync 完了（スキップ） ==="
    exit 0
fi

# ---------------------------------------------------------------------------
# 1. local plugin の link（未登録時のみ / 登録済みでもパスが違えば張り替え）
# ---------------------------------------------------------------------------
herdr-sync::link_plugin() {
    if ! command -v herdr &>/dev/null; then
        util::warning "herdr CLI 未インストール、plugin link をスキップ"
        return 0
    fi

    if [[ ! -f "${SWT_PLUGIN_SRC}/herdr-plugin.toml" ]]; then
        util::warning "${SWT_PLUGIN_SRC}/herdr-plugin.toml 不在、plugin link をスキップ"
        return 0
    fi

    local listed registered_root
    listed="$(herdr plugin list --json 2>/dev/null)"
    if [[ -n "${listed}" ]]; then
        registered_root="$(printf '%s' "${listed}" \
            | jq -r --arg id "${SWT_PLUGIN_ID}" \
                '.result.plugins[]? | select(.plugin_id == $id) | .plugin_root' 2>/dev/null)"
    fi

    if [[ -n "${registered_root}" ]]; then
        # link 時に Herdr 側でパスが正規化される（/tmp → /private/tmp 等）ため、
        # 実パス同士で比較する
        if [[ "${registered_root:A}" == "${SWT_PLUGIN_SRC:A}" ]]; then
            util::skip "plugin ${SWT_PLUGIN_ID} は既に ${registered_root} で登録済みです"
            return 0
        fi
        util::action "plugin ${SWT_PLUGIN_ID} の登録先を張り替えます (${registered_root} -> ${SWT_PLUGIN_SRC})"
        herdr plugin unlink "${SWT_PLUGIN_ID}" &>/dev/null \
            || util::warning "plugin ${SWT_PLUGIN_ID} の unlink に失敗"
    fi

    if herdr plugin link "${SWT_PLUGIN_SRC}" &>/dev/null; then
        util::info "plugin ${SWT_PLUGIN_ID}: linked (${SWT_PLUGIN_SRC})"
    else
        util::warning "plugin ${SWT_PLUGIN_ID}: link 失敗"
    fi
}

# ---------------------------------------------------------------------------
# 2. allowlist SSOT の symlink + 3. マシンローカル分の seed-if-absent
# ---------------------------------------------------------------------------
herdr-sync::sync_config() {
    local decl="${SWT_PLUGIN_SRC}/config/repos.json"
    if [[ ! -f "${decl}" ]]; then
        util::warning "${decl} 不在、allowlist の配置をスキップ"
        return 0
    fi

    local config_dir
    config_dir="$(herdr::plugin_config_dir)"
    fs::ensure_dir "${config_dir}"

    fs::link_file "${decl}" "${config_dir}/repos.json" \
        || util::warning "allowlist の symlink 作成に失敗: ${config_dir}/repos.json"

    local local_file="${config_dir}/repos.local.json"
    if [[ -e "${local_file}" ]]; then
        util::skip "${local_file} は既に存在します（中身は変更しません）"
        return 0
    fi
    print -r -- '{"version": 1, "repos": []}' > "${local_file}" \
        && util::info "マシンローカル allowlist を作成しました: ${local_file}" \
        || util::warning "${local_file} の作成に失敗"
}

herdr-sync::link_plugin
herdr-sync::sync_config

util::info "=== Tier 2: Herdr plugin sync 完了 ==="
exit 0
