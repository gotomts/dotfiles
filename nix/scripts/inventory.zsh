#!/bin/zsh
# nix/scripts/inventory.zsh
# 現マシンの macOS 設定を自動ダンプし、人間 triage 用チェックリストを生成する。
# 出力先: ~/.dotfiles/docs/inventory/<hostname>-<YYYY-MM-DD>.md

setopt ERR_EXIT NOUNSET PIPE_FAIL

# util.zsh が存在する場合のみ読み込む
readonly UTIL_ZSH="${HOME}/.dotfiles/setup/util.zsh"
if [[ -f "${UTIL_ZSH}" ]]; then
    source "${UTIL_ZSH}"
else
    # util.zsh が無い場合はフォールバック定義
    util::info()    { echo "[INFO] $1" }
    util::warning() { echo "[WARN] $1" }
    util::error()   { echo "[ERROR] $1" }
fi

# --help フラグの処理
if [[ "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage: inventory.zsh [--help]

現マシンの macOS 設定を自動ダンプし、人間 triage 用の Markdown チェックリストを
~/.dotfiles/docs/inventory/<hostname>-<YYYY-MM-DD>.md に生成します。

収集項目:
  - macOS defaults (既知ドメイン)
  - mas アプリ一覧
  - launchctl user-scope エージェント
  - /etc/sudoers.d/ エントリ
  - Brewfile diff (brew bundle dump との差分)
  - カスタムフォント / Fonts (fc-list :family)

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

readonly HOSTNAME="$(scutil --get LocalHostName)"
readonly TODAY="$(date +%Y-%m-%d)"
readonly OUTPUT_DIR="${HOME}/.dotfiles/docs/inventory"
readonly OUTPUT_FILE="${OUTPUT_DIR}/${HOSTNAME}-${TODAY}.md"
readonly BREWFILE_DUMP="/tmp/Brewfile.dump.$$"
readonly DOTFILES_BREWFILE="${HOME}/.dotfiles/Brewfile"

# ----------------------------------------------------------------
# 前処理
# ----------------------------------------------------------------

mkdir -p "${OUTPUT_DIR}"

if [[ -f "${OUTPUT_FILE}" ]]; then
    util::warning "出力ファイルが既に存在します: ${OUTPUT_FILE}"
    util::warning "上書きして続行します。"
fi

util::info "棚卸スクリプトを開始します: ${HOSTNAME} / ${TODAY}"

# 一時ファイルのクリーンアップ
trap 'rm -f "${BREWFILE_DUMP}"' EXIT INT TERM

# ----------------------------------------------------------------
# ヘルパー関数
# ----------------------------------------------------------------

# key=value ペアを Markdown チェックリスト行に変換する
# 入力: key = value 形式の文字列
_format_checklist_line() {
    local line="$1"
    echo "- [ ] ${line}  <!-- nix化 / 無視 / 検討 -->"
}

# defaults read の出力を key = value 行に変換して整形する
_format_defaults_output() {
    local domain="$1"
    local output
    output="$(defaults read "${domain}" 2>/dev/null)" || return 1

    # 各行を整形してチェックリスト行に
    while IFS= read -r line; do
        # 空行とブレースのみの行はスキップ
        [[ -z "${line}" ]] && continue
        [[ "${line}" =~ ^[[:space:]]*[\{\}][[:space:]]*$ ]] && continue
        # インデントを除去
        local trimmed="${line#"${line%%[! ]*}"}"
        [[ -n "${trimmed}" ]] && echo "- [ ] ${trimmed}  <!-- nix化 / 無視 / 検討 -->"
    done <<< "${output}"
}

# ----------------------------------------------------------------
# 出力生成
# ----------------------------------------------------------------

{
    echo "# Inventory Report — ${HOSTNAME} — ${TODAY}"
    echo ""
    echo "> 生成コマンド: \`nix/scripts/inventory.zsh\`"
    echo "> 各項目の右コメントを \`nix化\` / \`無視\` / \`検討\` のいずれかに書き換えてください。"
    echo ""

    # ================================================================
    # 1. macOS defaults
    # ================================================================
    echo "## defaults"
    echo ""

    for domain in "${DEFAULTS_DOMAINS[@]}"; do
        echo "### ${domain}"
        echo ""

        if defaults read "${domain}" > /dev/null 2>&1; then
            _format_defaults_output "${domain}"
        else
            util::warning "defaults: ドメインが存在しません: ${domain}" >&2
            echo "<!-- ドメインが存在しないためスキップ: ${domain} -->"
        fi
        echo ""
    done

    # ================================================================
    # 2. mas アプリ
    # ================================================================
    echo "## mas"
    echo ""

    if command -v mas > /dev/null 2>&1; then
        local mas_output
        mas_output="$(mas list 2>/dev/null)" || true

        if [[ -n "${mas_output}" ]]; then
            while IFS= read -r line; do
                [[ -z "${line}" ]] && continue
                # mas list の出力例: "539883307  LINE   (13.0.1)"
                local app_id app_name
                app_id="$(echo "${line}" | awk '{print $1}')"
                app_name="$(echo "${line}" | awk '{$1=""; print $0}' | sed 's/^ *//')"
                echo "- [ ] ${app_name} (id: ${app_id})  <!-- nix化 / 無視 / 検討 -->"
            done <<< "${mas_output}"
        else
            echo "<!-- mas list の出力が空です -->"
        fi
    else
        util::warning "mas コマンドが見つかりません。スキップします。" >&2
        echo "<!-- mas コマンドが見つかりません -->"
    fi
    echo ""

    # ================================================================
    # 3. launchctl user-scope エージェント
    # ================================================================
    echo "## launchctl (user)"
    echo ""

    local launchctl_output
    launchctl_output="$(launchctl list 2>/dev/null | awk '$3 ~ /^(com\.|user\.)/' )" || true

    if [[ -n "${launchctl_output}" ]]; then
        while IFS= read -r line; do
            [[ -z "${line}" ]] && continue
            local label
            label="$(echo "${line}" | awk '{print $3}')"
            [[ "${label}" == "-" ]] && continue
            echo "- [ ] ${label}  <!-- nix化 / 無視 / 検討 -->"
        done <<< "${launchctl_output}"
    else
        echo "<!-- launchctl list に該当エージェントがありません -->"
    fi
    echo ""

    # ================================================================
    # 4. /etc/sudoers.d/
    # ================================================================
    echo "## sudoers.d"
    echo ""

    local sudoers_list
    if sudoers_list="$(sudo ls /etc/sudoers.d/ 2>/dev/null)"; then
        if [[ -n "${sudoers_list}" ]]; then
            while IFS= read -r entry; do
                [[ -z "${entry}" ]] && continue
                echo "- [ ] /etc/sudoers.d/${entry}  <!-- nix化 / 無視 / 検討 -->"
                # ファイル内容をコードブロックで展開
                local content
                if content="$(sudo cat "/etc/sudoers.d/${entry}" 2>/dev/null)"; then
                    echo "  \`\`\`"
                    while IFS= read -r cline; do
                        echo "  ${cline}"
                    done <<< "${content}"
                    echo "  \`\`\`"
                fi
            done <<< "${sudoers_list}"
        else
            echo "<!-- /etc/sudoers.d/ は空です -->"
        fi
    else
        util::warning "sudo ls /etc/sudoers.d/ に失敗しました。スキップします。" >&2
        echo "<!-- sudo 権限が必要なためスキップ -->"
    fi
    echo ""

    # ================================================================
    # 5. Brewfile diff (brew bundle dump との比較)
    # ================================================================
    echo "## Brewfile diff (vs \`brew bundle dump\`)"
    echo ""

    if command -v brew > /dev/null 2>&1; then
        if brew bundle dump --no-restart --file="${BREWFILE_DUMP}" > /dev/null 2>&1; then
            if [[ -f "${DOTFILES_BREWFILE}" ]]; then
                local diff_output
                diff_output="$(diff "${DOTFILES_BREWFILE}" "${BREWFILE_DUMP}" 2>/dev/null)" || true
                if [[ -z "${diff_output}" ]]; then
                    echo "<!-- Brewfile と現環境の差分はありません -->"
                else
                    echo "\`\`\`diff"
                    echo "# < ~/.dotfiles/Brewfile  > brew bundle dump (現環境)"
                    echo "${diff_output}"
                    echo "\`\`\`"
                    echo ""
                    # 現環境にあるが Brewfile にない項目をチェックリスト化
                    echo "### 現環境にあるが Brewfile 未記載のパッケージ"
                    echo ""
                    local extra_lines
                    extra_lines="$(echo "${diff_output}" | grep '^>' | sed 's/^> //')" || true
                    if [[ -n "${extra_lines}" ]]; then
                        while IFS= read -r pkg; do
                            [[ -z "${pkg}" ]] && continue
                            echo "- [ ] ${pkg}  <!-- nix化 / 無視 / 検討 -->"
                        done <<< "${extra_lines}"
                    else
                        echo "<!-- 差分なし -->"
                    fi
                fi
            else
                util::warning "Brewfile が見つかりません: ${DOTFILES_BREWFILE}" >&2
                echo "<!-- ~/.dotfiles/Brewfile が見つかりません -->"
            fi
        else
            util::warning "brew bundle dump に失敗しました。スキップします。" >&2
            echo "<!-- brew bundle dump に失敗しました -->"
        fi
    else
        util::warning "brew コマンドが見つかりません。スキップします。" >&2
        echo "<!-- brew コマンドが見つかりません -->"
    fi
    echo ""

    # ================================================================
    # 6. カスタムフォント
    # ================================================================
    echo "## Fonts (custom)"
    echo ""

    if command -v fc-list > /dev/null 2>&1; then
        local font_output
        font_output="$(fc-list :family 2>/dev/null | sort -u)" || true

        if [[ -n "${font_output}" ]]; then
            while IFS= read -r font; do
                [[ -z "${font}" ]] && continue
                # カンマ区切りのファミリー名から最初のものを取得
                local family
                family="$(echo "${font}" | cut -d',' -f1 | sed 's/^ *//;s/ *$//')"
                [[ -n "${family}" ]] && echo "- [ ] ${family}  <!-- nix化 / 無視 / 検討 -->"
            done <<< "${font_output}"
        else
            echo "<!-- fc-list の出力が空です -->"
        fi
    else
        util::warning "fc-list コマンドが見つかりません。スキップします。" >&2
        echo "<!-- fc-list コマンドが見つかりません -->"
    fi
    echo ""

} > "${OUTPUT_FILE}"

util::info "棚卸完了: ${OUTPUT_FILE}"
