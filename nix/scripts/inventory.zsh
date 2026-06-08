#!/bin/zsh
# nix/scripts/inventory.zsh
# 現マシンの macOS 設定を自動ダンプし、人間 triage 用チェックリストを生成する。
# 出力先: ~/.dotfiles/docs/inventory/<hostname>-<YYYY-MM-DD>.md
#
# 刷新: defaults export | python3 plistlib ベース
#   旧実装の "defaults read を行単位で flatten" を廃止。
#   plistlib で構造化解析し、bookmark バイナリ・構造記号・機械的 metadata を除去。
#   出力行数を 5,000+ 行 → 300 行以下に圧縮。

setopt ERR_EXIT NOUNSET PIPE_FAIL

# メッセージユーティリティ
util::info()    { echo -e "\e[32m${1}\e[m" }
util::warning() { echo -e "\e[33m${1}\e[m" }
util::error()   { echo -e "\e[31m${1}\e[m" }

# --help フラグの処理
if [[ "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage: inventory.zsh [--help]

現マシンの macOS 設定を自動ダンプし、人間 triage 用の Markdown チェックリストを
~/.dotfiles/docs/inventory/<hostname>-<YYYY-MM-DD>.md に生成します。

収集項目:
  - macOS defaults (既知ドメイン) — defaults export | plistlib ベース
  - mas アプリ一覧
  - launchctl user-scope エージェント
  - /etc/sudoers.d/ エントリ
  - Brewfile diff (brew bundle dump との差分)
  - カスタムフォント / Fonts (fc-list :family)

defaults セクションは plistlib で構造化抽出し、bookmark バイナリ・構造記号・
機械的 metadata をノイズ除去することで triage 単位を人間判断可能な粒度に圧縮します。
Dock persistent-apps は bundle-id / file-label のアプリ一覧サマリに変換されます。

各項目は Markdown チェックリスト形式で出力され、
<!-- nix化 / 無視 / 検討 --> プレースホルダが付与されます。

Options:
  --help    このヘルプを表示して終了
EOF
    exit 0
fi

# ----------------------------------------------------------------
# 設定
# ----------------------------------------------------------------

# 既知 macOS defaults ドメイン配列
readonly -a DEFAULTS_DOMAINS=(
    "com.apple.dock"
    "com.apple.finder"
    "com.apple.menuextra.clock"
    "NSGlobalDomain"
    "com.apple.controlcenter"
    "com.apple.universalaccess"
    "com.apple.HIToolbox"
    "com.apple.screencapture"
    "com.apple.trackpad"
    "com.apple.AppleMultitouchTrackpad"
)

readonly HOSTNAME="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
if [[ -z "${HOSTNAME}" ]]; then
    util::error "ホスト名取得失敗"
    exit 1
fi

readonly TODAY="$(date +%Y-%m-%d)"

# スクリプトの位置から相対解決するため SCRIPT_DIR を OUTPUT_DIR より先に定義する
# (`${0:A}` で symlink 解決後の絶対パス。`:h` で親ディレクトリ)
readonly SCRIPT_DIR="${0:A:h}"
readonly PLIST_EXTRACT="${SCRIPT_DIR}/lib/plist_extract.py"

# OUTPUT_DIR: SCRIPT_DIR の親の親 (= dotfiles repo ルート) 配下 docs/inventory
# worktree 内で実行した時に、その worktree の docs/inventory に出力されることを保証する
# INVENTORY_OUTPUT_DIR env 変数で override 可能 (主に bats テスト用)
readonly OUTPUT_DIR="${INVENTORY_OUTPUT_DIR:-${SCRIPT_DIR}/../../docs/inventory}"
readonly OUTPUT_FILE="${OUTPUT_DIR}/${HOSTNAME}-${TODAY}.md"
readonly BREWFILE_DUMP="/tmp/Brewfile.dump.$$"
readonly DOTFILES_BREWFILE="${HOME}/.dotfiles/Brewfile"

# ----------------------------------------------------------------
# 前処理
# ----------------------------------------------------------------

if ! mkdir -p "${OUTPUT_DIR}"; then
    util::error "出力ディレクトリの作成に失敗しました: ${OUTPUT_DIR}"
    exit 1
fi

if [[ -f "${OUTPUT_FILE}" ]]; then
    util::warning "出力ファイルが既に存在します: ${OUTPUT_FILE}"
    util::warning "上書きして続行します。"
fi

if [[ ! -f "${PLIST_EXTRACT}" ]]; then
    util::error "plist_extract.py が見つかりません: ${PLIST_EXTRACT}"
    exit 1
fi

util::info "棚卸スクリプトを開始します: ${HOSTNAME} / ${TODAY}"

# 一時ファイルのクリーンアップ
trap 'rm -f "${BREWFILE_DUMP}"' EXIT INT TERM

# ----------------------------------------------------------------
# ヘルパー関数
# ----------------------------------------------------------------

# 文字列を Markdown チェックリスト行に変換する
_format_checklist_line() {
    local line="${1}"
    echo "- [ ] ${line}  <!-- nix化 / 無視 / 検討 -->"
}

# ----------------------------------------------------------------
# セクション出力関数
# ----------------------------------------------------------------

_dump_defaults() {
    echo "## defaults"
    echo ""
    echo "> plistlib ベースで抽出。bookmark バイナリ・構造記号・機械的 metadata はノイズ除去済み。"
    echo ""

    /usr/bin/python3 "${PLIST_EXTRACT}" "${DEFAULTS_DOMAINS[@]}"
}

_dump_mas() {
    echo "## mas"
    echo ""

    if ! command -v mas > /dev/null 2>&1; then
        util::warning "mas コマンドが見つかりません。スキップします。" >&2
        echo "<!-- mas コマンドが見つかりません -->"
        echo ""
        return 0
    fi

    local mas_output
    mas_output="$(mas list 2>/dev/null)" || true

    if [[ -n "${mas_output}" ]]; then
        local line app_id app_name
        while IFS= read -r line; do
            [[ -z "${line}" ]] && continue
            # mas list の出力例: "539883307  LINE   (13.0.1)"
            app_id="$(echo "${line}" | awk '{print $1}')"
            app_name="$(echo "${line}" | awk '{$1=""; print $0}' | sed 's/^ *//')"
            _format_checklist_line "${app_name} (id: ${app_id})"
        done <<< "${mas_output}"
    else
        echo "<!-- mas list の出力が空です -->"
    fi
    echo ""
}

_dump_launchctl() {
    echo "## launchctl (user — non-Apple agents)"
    echo ""
    echo "> com.apple.* は OS 標準のため除外。ユーザーアプリ起動エージェントのみ表示。"
    echo ""

    # com.apple.* を除いたユーザー追加エージェントのみ triage 対象
    local launchctl_output
    launchctl_output="$(launchctl list 2>/dev/null | awk '$3 ~ /^(com\.|user\.)/' | grep -v 'com\.apple\.')" || true

    if [[ -n "${launchctl_output}" ]]; then
        local line label
        while IFS= read -r line; do
            [[ -z "${line}" ]] && continue
            label="$(echo "${line}" | awk '{print $3}')"
            [[ "${label}" == "-" ]] && continue
            _format_checklist_line "${label}"
        done <<< "${launchctl_output}"
    else
        echo "<!-- launchctl list に該当エージェントがありません -->"
    fi
    echo ""
}

_dump_sudoers() {
    echo "## sudoers.d"
    echo ""

    local sudoers_list
    if ! sudoers_list="$(sudo ls /etc/sudoers.d/ 2>/dev/null)"; then
        util::warning "sudo ls /etc/sudoers.d/ に失敗しました。スキップします。" >&2
        echo "<!-- sudo 権限が必要なためスキップ -->"
        echo ""
        return 0
    fi

    if [[ -z "${sudoers_list}" ]]; then
        echo "<!-- /etc/sudoers.d/ は空です -->"
        echo ""
        return 0
    fi

    local entry content cline
    while IFS= read -r entry; do
        [[ -z "${entry}" ]] && continue
        _format_checklist_line "/etc/sudoers.d/${entry}"
        # ファイル内容をコードブロックで展開
        if content="$(sudo cat "/etc/sudoers.d/${entry}" 2>/dev/null)"; then
            echo "  \`\`\`"
            while IFS= read -r cline; do
                echo "  ${cline}"
            done <<< "${content}"
            echo "  \`\`\`"
        fi
    done <<< "${sudoers_list}"
    echo ""
}

_dump_brewfile_diff() {
    echo "## Brewfile diff (現環境のみ / Brewfile 未記載)"
    echo "> Brewfile 未記載パッケージのみ triage 対象。Brewfile のみは Nix 移行中のため件数のみ。"
    echo ""

    if ! command -v brew > /dev/null 2>&1; then
        util::error "brew コマンドが見つかりません。Brewfile diff をスキップします。" >&2
        echo "<!-- brew コマンドが見つかりません -->"
        echo ""
        return 0
    fi

    if ! brew bundle dump --no-restart --file="${BREWFILE_DUMP}" > /dev/null 2>&1; then
        util::warning "brew bundle dump に失敗しました。スキップします。" >&2
        echo "<!-- brew bundle dump に失敗しました -->"
        echo ""
        return 0
    fi

    if [[ ! -f "${DOTFILES_BREWFILE}" ]]; then
        util::warning "Brewfile が見つかりません: ${DOTFILES_BREWFILE}" >&2
        echo "<!-- ~/.dotfiles/Brewfile が見つかりません -->"
        echo ""
        return 0
    fi

    local diff_output
    diff_output="$(diff "${DOTFILES_BREWFILE}" "${BREWFILE_DUMP}" 2>/dev/null)" || true

    if [[ -z "${diff_output}" ]]; then
        echo "<!-- Brewfile と現環境の差分はありません -->"
    else
        # 現環境のみ (brew bundle dump にあり Brewfile 未記載) → triage 対象
        local extra_lines missing_count pkg
        extra_lines="$(echo "${diff_output}" | grep '^>' | sed 's/^> //')" || true
        missing_count="$(echo "${diff_output}" | grep -c '^<')" || true

        # Brewfile のみ (現環境にない) は件数のみサマリ
        [[ "${missing_count}" -gt 0 ]] && \
            echo "<!-- Brewfile のみ: ${missing_count} 件 (Nix 移行中 / triage 不要) -->"

        # 現環境のみ → triage 対象 (tap/brew/cask/mas のみ。go/cargo/npm は Nix 管理外)
        local brew_extra_lines
        brew_extra_lines="$(echo "${extra_lines}" | grep -E '^(tap|brew|cask|mas) ')" || true
        if [[ -n "${brew_extra_lines}" ]]; then
            while IFS= read -r pkg; do
                [[ -z "${pkg}" ]] && continue
                _format_checklist_line "${pkg}"
            done <<< "${brew_extra_lines}"
        else
            echo "<!-- 現環境に Brewfile 未記載のパッケージはありません -->"
        fi
    fi
    echo ""
}

_dump_fonts() {
    echo "## Fonts (custom)"
    echo ""
    echo "> /Library/Fonts/ のみ対象（ユーザー追加フォント）。/System/ 配下はシステム標準のため除外。"
    echo ""

    if ! command -v fc-list > /dev/null 2>&1; then
        util::warning "fc-list コマンドが見つかりません。スキップします。" >&2
        echo "<!-- fc-list コマンドが見つかりません -->"
        echo ""
        return 0
    fi

    # /Library/Fonts/ のみ対象 (ユーザー追加フォント)
    # /System/Library/ 配下はシステムフォントで宣言管理不要なため除外
    local font_output
    font_output="$(fc-list --format="%{family}\t%{file}\n" 2>/dev/null \
        | grep $'\t'/Library/Fonts/ \
        | awk -F'\t' '{print $1}' \
        | sort -u)" || true

    if [[ -n "${font_output}" ]]; then
        local font family
        while IFS= read -r font; do
            [[ -z "${font}" ]] && continue
            # カンマ区切りのファミリー名から最初のものを取得
            family="$(echo "${font}" | cut -d',' -f1 | sed 's/^ *//;s/ *$//')"
            [[ -n "${family}" ]] && _format_checklist_line "${family}"
        done <<< "${font_output}"
    else
        echo "<!-- /Library/Fonts/ にユーザー追加フォントはありません -->"
    fi
    echo ""
}

# ----------------------------------------------------------------
# レポート生成
# ----------------------------------------------------------------

_generate_report() {
    echo "# Inventory Report — ${HOSTNAME} — ${TODAY}"
    echo ""
    echo "> 生成コマンド: \`nix/scripts/inventory.zsh\`"
    echo "> 各項目の右コメントを \`nix化\` / \`無視\` / \`検討\` のいずれかに書き換えてください。"
    echo ""

    _dump_defaults
    _dump_mas
    _dump_launchctl
    _dump_sudoers
    _dump_brewfile_diff
    _dump_fonts
}

# ----------------------------------------------------------------
# エントリポイント
# ----------------------------------------------------------------

_generate_report > "${OUTPUT_FILE}"

util::info "棚卸完了: ${OUTPUT_FILE}"
