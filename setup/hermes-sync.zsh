#!/bin/zsh
# setup/hermes-sync.zsh
#
# Tier 2: Hermes Agent の RTK 連携プラグインを導入する。
#   `rtk init --agent hermes` が ~/.hermes/plugins/rtk-rewrite/ を作り、
#   ~/.hermes/config.yaml の plugins.enabled に登録する。
#
# なぜ Tier 1 (symlink) ではないか:
#   ~/.hermes/config.yaml は Hermes が動的に書き換える running config なので symlink・追跡
#   しない (AGENTS.md「Hermes Agent 設定」)。プラグイン実体も rtk のバージョンに対応した
#   生成物であって、リポジトリが持つべき原本ではない。宣言側で固定できるのは
#   「rtk を入れること (homebrew.nix)」と「その rtk に Hermes 用アダプタを張らせること
#   (このスクリプト)」の 2 つで、そこだけを追跡する。
#
# Claude Code 側は同じ RTK でもここを通らない。Claude Code の hook は追跡済みの
# claude/settings.json に直接宣言してあり、`rtk init -g` は使わない (走らせると Tier 1 の
# symlink 越しに dotfiles の作業ツリーを書き換えてしまう)。
#
# Context Mode は Claude Code だけに入れる。Hermes へは入れない。
#
# 冪等性: `rtk init` はアダプタが既に最新なら書き換えない。毎回呼ぶのは、rtk を上げた
# ときにアダプタだけ古いまま取り残されるのを防ぐため。--auto-patch は「管理下のファイルが
# 既知の RTK アダプタと違う」ときの確認プロンプトを自動承認する (対話プロンプトで migrate が
# 止まらないようにする)。
#
# テレメトリ: RTK のテレメトリは既定で無効かつ明示的な opt-in が要る。このスクリプトは
# `rtk init` の同意フローに巻き込まれないよう RTK_TELEMETRY_DISABLED=1 を明示して呼ぶ
# (この 1 回の呼び出しに閉じた指定で、PC の設定は変えない)。有効化したくなったら人間が
# `rtk telemetry enable` を叩く。
#
# 使い方:
#   zsh ${HOME}/.dotfiles/setup/hermes-sync.zsh
#
# 終了コード: 常に 0（fail-open。rtk 未インストール・Hermes 未導入の PC で環境構築全体が
# 止まる方が害が大きいため、claude-sync.zsh / codex-sync.zsh / herdr-sync.zsh と同じ設計
# 判断を踏襲する）

SETUP_DIR="${0:A:h}"
source "${SETUP_DIR}/lib/util.zsh"
source "${SETUP_DIR}/lib/hermes.zsh"

# 呼び出し元 (migrate.zsh の委譲実行など) の PATH を信用しない。rtk は Homebrew 経由で
# 入る。理由は util::ensure_homebrew_path のコメント参照。
util::ensure_homebrew_path

util::info "=== Tier 2: Hermes RTK plugin sync ==="

hermes-sync::sync_rtk_plugin() {
    if ! hermes::is_installed "${HOME}"; then
        util::skip "$(hermes::config "${HOME}") が無いため Hermes 未導入とみなします"
        return 0
    fi

    if ! command -v rtk &>/dev/null; then
        util::warning "rtk 未インストール、Hermes plugin の導入をスキップ (nix/modules/darwin/homebrew.nix で宣言済み。darwin-rebuild switch 後に再実行してください)"
        return 0
    fi

    local plugin_dir
    plugin_dir="$(hermes::rtk_plugin_dir "${HOME}")"

    util::action "rtk init --agent hermes を実行します (生成先: ${plugin_dir})"
    # ${HOME} へ移ってから呼ぶ。`rtk init` は agent によっては cwd 配下へ project スコープの
    # 設定を書く。Hermes 向けは ~/.hermes だけを触る作りだが、migrate.zsh はリポジトリの
    # 作業ツリーを cwd にしたまま委譲実行するので、万一書かれても追跡対象を汚さない位置で
    # 走らせる。サブシェルなので呼び出し元の cwd は変えない。
    if ! (cd "${HOME}" && RTK_TELEMETRY_DISABLED=1 rtk init --agent hermes --auto-patch &>/dev/null); then
        util::warning "rtk init --agent hermes に失敗"
        return 0
    fi

    if [[ -d "${plugin_dir}" ]]; then
        util::info "Hermes plugin ${HERMES_RTK_PLUGIN_ID}: ${plugin_dir}"
    else
        util::warning "rtk init は成功しましたが ${plugin_dir} が作られていません"
    fi
}

hermes-sync::sync_rtk_plugin

util::info "=== Tier 2: Hermes RTK plugin sync 完了 ==="
exit 0
