#!/bin/zsh
# setup/lib/fs.zsh
#
# symlink 配置の安全プリミティブ。「既存の実体ファイル/ディレクトリを黙って上書きしない」ことを
# 最優先する。呼び出し規約: 各関数は ${HOME} 等の環境変数を直接読まず、引数で受け取る。
# lib/util.zsh（util::info 等）が事前に source 済みであることを前提とする。
#
# 絶対パスで /bin/unlink 等を呼ぶ理由: 一部の非対話実行環境（Claude Code の bash tool 等）は
# PATH に /bin を含まないことがあり、素の `unlink` が command not found になる場合がある。

# fs::ensure_dir <path>
#   ディレクトリが無ければ作成する（mkdir -p の薄いラッパ）
fs::ensure_dir() {
    local dir="${1}"
    [[ -d "${dir}" ]] || mkdir -p "${dir}"
}

# fs::link_file <target> <link_path>
#   ${link_path} を ${target} への symlink にする。
#   - 既に ${target} を指す symlink → 何もしない（skip）
#   - 別の場所を指す symlink（nix store 経由の旧 symlink 等）→ unlink して張り直す
#   - 実体ファイル/ディレクトリが既にある → ${link_path}.before-setup に退避してから symlink 作成
#     （home-manager の backupFileExtension = "before-nix" と同じ思想の安全策）
#   - 親ディレクトリが無ければ作成する
fs::link_file() {
    local target="${1}"
    local link_path="${2}"

    if [[ ! -e "${target}" ]]; then
        util::error "リンク元が存在しません: ${target}"
        return 1
    fi

    fs::ensure_dir "${link_path:h}"

    if [[ -L "${link_path}" ]]; then
        local current_target
        current_target="$(/usr/bin/readlink "${link_path}")"
        if [[ "${current_target}" == "${target}" ]]; then
            util::skip "${link_path} は既に ${target} を指しています"
            return 0
        fi
        util::action "symlink 張り替え: ${link_path} (${current_target} -> ${target})"
        /bin/unlink "${link_path}"
    elif [[ -e "${link_path}" ]]; then
        local backup="${link_path}.before-setup"
        util::warning "${link_path} は既に実体があります。${backup} に退避します"
        /bin/mv "${link_path}" "${backup}"
    fi

    ln -sfv "${target}" "${link_path}"
}

# fs::ensure_realfile <path>
#   ${path} を「symlink ではない書き込み可能な実体ファイル」にする。
#   3rd party ツール（coderabbit 等）が ~/.gitconfig に書き込む場合や、Claude Code の
#   .i-have-adhd-always マーカーのように、dotfiles リポジトリで追跡してはいけない値/状態を
#   安全に置くための保護策。
#   - symlink が既にある → unlink してから空の実体ファイルを作る（中身は復元しない。
#     PC 固有の値は各マシンでツールが再生成する前提）
#   - 実体ファイルが既にある → 何もしない（中身を上書きしない）
#   - 何もない → touch で空ファイルを作る
fs::ensure_realfile() {
    # 変数名は `path` を避ける。zsh は `path` を $PATH と束縛された特殊配列として扱うため、
    # local でスカラーを代入すると同一スコープ内でコマンド解決 (mkdir/touch 等) が壊れる。
    local realfile_path="${1}"

    fs::ensure_dir "${realfile_path:h}"

    if [[ -L "${realfile_path}" ]]; then
        util::warning "${realfile_path} は symlink です。unlink して実体ファイルに変換します"
        /bin/unlink "${realfile_path}"
    fi

    if [[ -e "${realfile_path}" ]]; then
        util::skip "${realfile_path} は既に実体ファイルです（中身は変更しません）"
        return 0
    fi

    touch "${realfile_path}"
    util::info "空の実体ファイルを作成しました: ${realfile_path}"
}
