#!/bin/zsh
# 旧 setup.zsh が作成したディレクトリシンボリックリンク (dir-symlink) を検出し、
# proper directory (実ディレクトリ) に変換する。
#
# 背景:
#   setup.zsh は ~/.aliase / ~/.functions 等を dotfiles/ 内ディレクトリへの
#   dir-symlink として配置していた。home-manager の home.file がこれらの
#   ディレクトリ内にファイルを配置しようとすると、dotfiles リポジトリ内に
#   <file>.before-nix バックアップが生成される問題があった (DOT-27)。
#
# 解決策:
#   dir-symlink をいったん削除し、home-manager が proper directory として
#   再生成できる状態にする。スクリプトは idempotent に設計されており、
#   既に proper directory になっている場合は何もしない。
#
# 使い方:
#   zsh ${HOME}/.dotfiles/nix/scripts/migrate-symlinks.zsh [--dry-run]
#
# オプション:
#   --dry-run  実際の変更を行わず、実行予定の操作のみ表示する
#
# 終了コード:
#   0  成功 (または dry-run 完了)
#   1  引数エラー
#
# 注意:
#   このスクリプトは darwin-rebuild switch の「前に」実行すること。
#   実行後に darwin-rebuild switch を行うと、home-manager が proper directory として
#   各ファイルを配置する。
#
# 関連:
#   - Linear: DOT-27
#   - nix/README.md: "既存 PC 移行手順 (dir-symlink → proper directory)" セクション

set -eu

# ---- オプション解析 -------------------------------------------------------

dry_run=false
for arg in "$@"; do
    case "${arg}" in
        --dry-run) dry_run=true ;;
        *)
            echo "Unknown option: ${arg}" >&2
            echo "Usage: $0 [--dry-run]" >&2
            exit 1
            ;;
    esac
done

# ---- ユーティリティ -------------------------------------------------------

util::info()    { echo "\e[32m[migrate-symlinks] ${1}\e[m" }
util::warning() { echo "\e[33m[migrate-symlinks] ${1}\e[m" }
util::action()  { echo "\e[36m[migrate-symlinks] ${1}\e[m" }
util::skip()    { echo "\e[90m[migrate-symlinks] SKIP: ${1}\e[m" }

if [[ "${dry_run}" == true ]]; then
    util::warning "DRY-RUN モード: 実際の変更は行いません"
fi

# ---- dir-symlink の対象リスト -------------------------------------------
#
# 旧 setup.zsh が作成した dir-symlink のうち、home-manager の home.file と
# 衝突する可能性があるもの。
#
# フォーマット: "<symlink_path>:<expected_target>" (期待するターゲットが一致した場合のみ削除)
# expected_target が空文字の場合はターゲットを問わず dir-symlink なら削除する。
#
# .config/* は setup.zsh が file-level で配置していたため、
# dir-symlink は発生しない (config ループが mkdir してからファイルを symlink していた)。
# ただし既存 PC で dir-symlink が残っている場合に備えてリストに含める。

typeset -A dir_symlinks
dir_symlinks=(
    # ~/.aliase -> dotfiles/aliase: home-manager が .aliase/get-gke-credentials.sh を管理
    "${HOME}/.aliase"    "${HOME}/.dotfiles/aliase"
    # ~/.functions -> dotfiles/functions: home-manager が .functions/fzf-history を管理
    "${HOME}/.functions" "${HOME}/.dotfiles/functions"
    # ~/.grip -> dotfiles/grip: home-manager が .grip/settings.py を管理。
    # dir-symlink のまま darwin-rebuild switch すると ~/.grip/settings.py が
    # dir-symlink 越しに dotfiles repo 内のファイルとして見え、
    # home-manager が before-nix バックアップを repo 内に生成してしまう。
    "${HOME}/.grip"      "${HOME}/.dotfiles/grip"
    # ~/.claude/skills -> dotfiles/claude/skills: home-manager が個別 skill を管理。
    # dir-symlink のままだと switch 時に clobber エラー (target が違うため
    # backupFileExtension が効かない) で activation が止まる。
    "${HOME}/.claude/skills" "${HOME}/.dotfiles/claude/skills"
)

# ---- file-symlink の対象リスト ------------------------------------------
#
# 旧 setup.zsh が dotfiles への file-symlink を作成しており、
# home-manager の home.file が nix store 経由の symlink に上書きするもの。
# backupFileExtension により .before-nix が生成されるのを防ぐため、
# darwin-rebuild switch 前に既存の file-symlink を削除する。
#
# フォーマット: "<symlink_path>:<expected_target>"

typeset -A file_symlinks
file_symlinks=(
    "${HOME}/.aliases"          "${HOME}/.dotfiles/aliases"
    "${HOME}/.gitignore_global" "${HOME}/.dotfiles/gitignore_global"
    "${HOME}/.grip/settings.py" "${HOME}/.dotfiles/grip/settings.py"
    "${HOME}/.config/cmux/config.ghostty" "${HOME}/.dotfiles/config/cmux/config.ghostty"
    # starship は旧 setup.zsh が ~/.config/starship/starship.toml を配置。
    # home-manager は ~/.config/starship.toml (サブディレクトリなし) に配置するため
    # パスが異なり直接衝突はしないが、念のため旧 symlink を削除する。
    "${HOME}/.config/starship/starship.toml" "${HOME}/.dotfiles/config/starship/starship.toml"
    # ~/.zshrc / ~/.zshenv は旧 setup.zsh が dotfiles 直下を指す symlink を作成。
    # home-manager が nix store 経由で配置するため、削除して再配置させる。
    "${HOME}/.zshrc"            "${HOME}/.dotfiles/zshrc"
    "${HOME}/.zshenv"           "${HOME}/.dotfiles/zshenv"
    # yazi の keymap.toml も旧 setup.zsh 経路。home.file に宣言されており
    # home-manager 管理対象なので削除して再配置させる。
    "${HOME}/.config/yazi/keymap.toml" "${HOME}/.dotfiles/config/yazi/keymap.toml"
    # yazi の grip-preview.sh は Phase B 対応のため home.file 未宣言。
    # dotfiles への symlink のままとする (削除しない)。
)

# ---- 処理関数 -------------------------------------------------------------

# dir-symlink を削除して proper directory 化を促す
migrate_dir_symlink() {
    local path="${1}"
    local expected_target="${2}"

    if [[ ! -L "${path}" ]]; then
        if [[ -d "${path}" ]]; then
            util::skip "${path} は既に proper directory です (移行済み)"
        else
            util::skip "${path} は存在しません (スキップ)"
        fi
        return 0
    fi

    local actual_target
    actual_target=$(/usr/bin/readlink "${path}")

    # nix store 経由の symlink なら既に home-manager 管理済み
    if [[ "${actual_target}" == /nix/store/* ]]; then
        util::skip "${path} は既に nix store 経由の symlink です (移行済み)"
        return 0
    fi

    # 期待するターゲットと一致する場合のみ削除 (意図しない symlink を誤って削除しない)
    if [[ -n "${expected_target}" ]] && [[ "${actual_target}" != "${expected_target}" ]]; then
        util::warning "${path} のターゲットが期待値と異なります"
        util::warning "  期待: ${expected_target}"
        util::warning "  実際: ${actual_target}"
        util::warning "  手動で確認してください"
        return 0
    fi

    util::action "DIR-SYMLINK 削除: ${path} -> ${actual_target}"
    if [[ "${dry_run}" == false ]]; then
        # `unlink` は /bin/unlink にあるが、非インタラクティブ環境 (Claude bash
        # tool 等) では PATH に /bin が含まれず command not found になる可能性が
        # あるため絶対パスで呼ぶ。`readlink` を /usr/bin/readlink にしているのと
        # 同じ理由。
        /bin/unlink "${path}"
        util::info "削除完了: ${path}"
        util::info "  darwin-rebuild switch 後に home-manager が proper directory として再生成します"
    fi
}

# file-symlink を削除する (home-manager が nix store 経由で上書き配置できるよう)
migrate_file_symlink() {
    local path="${1}"
    local expected_target="${2}"

    if [[ ! -L "${path}" ]]; then
        if [[ -f "${path}" ]]; then
            util::skip "${path} は実ファイルです (home-manager 管理済みの可能性あり)"
        else
            util::skip "${path} は存在しません (スキップ)"
        fi
        return 0
    fi

    local actual_target
    actual_target=$(/usr/bin/readlink "${path}")

    # nix store 経由の symlink なら既に home-manager 管理済み
    if [[ "${actual_target}" == /nix/store/* ]]; then
        util::skip "${path} は既に nix store 経由の symlink です (移行済み)"
        return 0
    fi

    # 期待するターゲットと一致する場合のみ削除
    if [[ -n "${expected_target}" ]] && [[ "${actual_target}" != "${expected_target}" ]]; then
        util::warning "${path} のターゲットが期待値と異なります"
        util::warning "  期待: ${expected_target}"
        util::warning "  実際: ${actual_target}"
        util::warning "  手動で確認してください"
        return 0
    fi

    util::action "FILE-SYMLINK 削除: ${path} -> ${actual_target}"
    if [[ "${dry_run}" == false ]]; then
        # `unlink` 絶対パスの理由は migrate_dir_symlink のコメント参照
        /bin/unlink "${path}"
        util::info "削除完了: ${path}"
        util::info "  darwin-rebuild switch で home-manager が必要に応じて再配置します"
    fi
}

# ---- メイン処理 ----------------------------------------------------------

util::info "=== dir-symlink の検出と proper directory 化 ==="
for path expected_target in "${(@kv)dir_symlinks}"; do
    migrate_dir_symlink "${path}" "${expected_target}"
done

echo ""
util::info "=== file-symlink の検出と削除 (home-manager 再配置のため) ==="
for path expected_target in "${(@kv)file_symlinks}"; do
    migrate_file_symlink "${path}" "${expected_target}"
done

echo ""
if [[ "${dry_run}" == true ]]; then
    util::warning "DRY-RUN 完了。上記の操作を実行するには --dry-run なしで再実行してください。"
else
    util::info "移行完了。次のステップ:"
    util::info "  sudo USER=\${USER} darwin-rebuild switch --flake ~/.dotfiles/nix#default --impure"
    util::info "  (home-manager が proper directory と nix store 経由 symlink を再生成します)"
fi
