#!/bin/zsh
# setup/hermes-sync.zsh
#
# Tier 2: Hermes Agent 側の宣言を running config へ同期する。互いに独立した 2 つを持つ。
#   1. RTK 連携プラグイン: `rtk init --agent hermes` が ~/.hermes/plugins/rtk-rewrite/ を作り、
#      ~/.hermes/config.yaml の plugins.enabled に登録する。
#   2. Sentry 公式 MCP server: `hermes config set mcp_servers.sentry <JSON>` で登録する
#      (Claude Code 側の claude/mcp-servers.json に対応する Hermes 側の宣言。詳細は
#      hermes-sync::sync_sentry_mcp のコメント)。
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

# hermes 本体は ${HOME}/.local/bin に入る (公式インストーラ)。
util::ensure_local_bin_path

util::info "=== Tier 2: Hermes sync ==="

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

# Hermes 側の Sentry MCP 宣言。Claude Code 側 (claude/mcp-servers.json) とは設定の形が違う
# (Hermes は auth: oauth を明示する) ため、あちらから生成せず独立に持つ。
HERMES_SENTRY_MCP_JSON='{"url":"https://mcp.sentry.dev/mcp","auth":"oauth","enabled":true}'

# hermes-sync::sync_sentry_mcp
#   mcp_servers.sentry だけを Hermes 公式 CLI で書く。config.yaml を直接編集しないのは、
#   running config の整形・他キー (discord_admin / linear 等の既存 server) の保持を Hermes
#   自身に任せるため。OAuth token は config.yaml の外に Hermes が持ち、ここでは触らない。
#
#   既存値の扱い:
#     - 未設定 (get が exit 1 かつ stderr が `Config key not set: mcp_servers.sentry`) → 宣言値を書く
#     - 取得失敗・空・不正な値 → 既存状態が読めていないので warning だけで何も書かない
#     - 宣言値と同じ (キー順は無視) → 何もしない
#     - 宣言値と違う → 黙って上書きしない。人間が意図して変えた可能性があるので warning を
#       出して止める (解消は人間が `hermes config set` / `unset` で行う)
#     warning に既存値・宣言値・CLI の stderr は出さない (URL や認証値が混ざりうるため)。
#
#   HERMES_HOME を明示するのは、判定 (hermes::is_installed) と書き込み先を同じ
#   ${HOME}/.hermes に揃えるため。呼び出し元の環境に別の HERMES_HOME があっても追従しない。
hermes-sync::sync_sentry_mcp() {
    if ! hermes::is_installed "${HOME}"; then
        util::skip "$(hermes::config "${HOME}") が無いため Sentry MCP の同期をスキップします"
        return 0
    fi

    if ! command -v hermes &>/dev/null; then
        util::warning "hermes コマンドが見つからないため Sentry MCP の同期をスキップします"
        return 0
    fi
    if ! command -v jq &>/dev/null; then
        util::warning "jq 未インストール、Sentry MCP の同期をスキップ (nix/modules/darwin/homebrew.nix で宣言済み)"
        return 0
    fi

    local hermes_home current get_err get_rc err_file
    hermes_home="$(hermes::home "${HOME}")"

    # stdout (値) と stderr (未設定の判定材料) を分けて受ける。どちらも既存設定の中身を含み
    # うるので、ログには決して出さない。
    err_file="$(mktemp)"
    current="$(HERMES_HOME="${hermes_home}" hermes config get --json mcp_servers.sentry 2>"${err_file}")"
    get_rc=$?
    get_err="$(<"${err_file}")"
    rm -f "${err_file}"

    if (( get_rc != 0 )); then
        # 「未設定」と確定できるのは Hermes CLI のこの応答だけ。それ以外の失敗
        # (config.yaml の破損・CLI の仕様変更など) で set すると既存値を潰しうるので書かない。
        if (( get_rc != 1 )) || [[ "${get_err}" != "Config key not set: mcp_servers.sentry" ]]; then
            util::warning "hermes config get mcp_servers.sentry が想定外の失敗 (exit ${get_rc})。Sentry MCP は変更しません"
            return 0
        fi
    else
        # 成功したのに値が空・JSON オブジェクトでない場合も、既存状態が読めていないので書かない。
        if ! jq -e 'type == "object"' <<< "${current}" &>/dev/null; then
            util::warning "hermes config get mcp_servers.sentry の結果を解釈できません。Sentry MCP は変更しません"
            return 0
        fi
        if [[ "$(jq -S -c . <<< "${current}")" == "$(jq -S -c . <<< "${HERMES_SENTRY_MCP_JSON}")" ]]; then
            util::skip "Hermes MCP sentry は宣言どおり設定済み"
        else
            # 現在値は URL や認証値を含みうるので表示しない。
            util::warning "Hermes MCP sentry が宣言と異なるため上書きしません (確認: hermes config get mcp_servers.sentry)"
        fi
        return 0
    fi

    util::action "Hermes MCP sentry を登録します"
    if ! HERMES_HOME="${hermes_home}" hermes config set mcp_servers.sentry "${HERMES_SENTRY_MCP_JSON}" &>/dev/null; then
        util::warning "hermes config set mcp_servers.sentry に失敗"
        return 0
    fi
    util::info "Hermes MCP sentry を登録しました。OAuth 認可は人間が \`hermes mcp login sentry\` で行ってください"
}

hermes-sync::sync_rtk_plugin
hermes-sync::sync_sentry_mcp

util::info "=== Tier 2: Hermes sync 完了 ==="
exit 0
