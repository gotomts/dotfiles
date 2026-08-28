#!/bin/zsh
# herdr/plugins/safe-worktree/bin/create.zsh
#
# allowlist 済みリポジトリで、リモートの実 SHA を base に linked worktree を作る。
#
# Herdr 標準の `herdr worktree create --base <ref>` は ref をローカルで解決するため、
# `--base main` はローカルの（古いかもしれない）main を、`--base HEAD` は現在の
# チェックアウトを黙って使う。ここでは base を必ず「リモートから取得した直後の SHA」
# に固定し、作成後に実際の HEAD と突き合わせてから成功を報告する。
#
# 使い方:
#   create.zsh [--repo <label|path>] [--branch <name>] [--base <remote/branch|sha>]
#              [--label <text>] [--reuse] [--yes] [--focus|--no-focus]
#
#   --repo    対象リポジトリ。設定の label か作業ツリーのパス。
#             省略時は Herdr の呼び出しコンテキスト → カレントディレクトリの順で解決する。
#   --branch  作成するブランチ名。省略時は対話で尋ねる（TTY が無ければエラー）。
#   --base    省略時はリモートの既定ブランチ（毎回 ls-remote で解決するので v2 → main の
#             付け替えに自動追従する）。明示する場合は <remote>/<branch> か存在する SHA のみ。
#   --reuse   ブランチが既にある場合に、新規作成の代わりに `herdr worktree open` で開く。
#
# 終了コード: lib/common.zsh の SWT_EXIT_* を参照

set -u

SWT_ROOT="${0:A:h:h}"
source "${SWT_ROOT}/lib/common.zsh"

# ---------------------------------------------------------------------------
# 引数
# ---------------------------------------------------------------------------
repo_arg=""
branch=""
base_arg=""
label=""
reuse=0
assume_yes=0
focus_flag="--no-focus"

# 値を取るオプションで値が無いまま `shift 2` すると、zsh は shift を失敗させるだけで
# 停止しない。$# が減らないまま while が回り続けるので、明示的に検査して落とす。
require_value() {
    (( $# >= 2 )) || swt::die "${SWT_EXIT_USAGE}" "${1} には値が必要です"
    [[ "${2}" != -* ]] || swt::die "${SWT_EXIT_USAGE}" "${1} の値が指定されていません (${2} が続いています)"
}

while (( $# > 0 )); do
    case "${1}" in
        --repo)   require_value "$@"; repo_arg="${2}"; shift 2 ;;
        --branch) require_value "$@"; branch="${2}";   shift 2 ;;
        --base)   require_value "$@"; base_arg="${2}"; shift 2 ;;
        --label)  require_value "$@"; label="${2}";    shift 2 ;;
        --reuse)  reuse=1;           shift ;;
        --yes|-y) assume_yes=1;      shift ;;
        --focus)     focus_flag="--focus";    shift ;;
        --no-focus)  focus_flag="--no-focus"; shift ;;
        -h|--help)
            swt::print_header_comment "${0:A}"
            exit "${SWT_EXIT_OK}"
            ;;
        *) swt::die "${SWT_EXIT_USAGE}" "不明な引数: ${1}" ;;
    esac
done

interactive=0
[[ -t 0 && -t 1 ]] && interactive=1

herdr_bin="$(swt::herdr_bin)"

# popup から起動された場合、結果を読む前に窓が閉じないように最後で入力待ちする
swt::finish() {
    local code="${1}"
    if (( interactive )); then
        print -r -- ""
        print -r -- "Enter で閉じます。"
        read -r _ || true
    fi
    exit "${code}"
}

swt::abort() {
    swt::error "${2}"
    swt::finish "${1}"
}

# ---------------------------------------------------------------------------
# 設定の読み込み
# ---------------------------------------------------------------------------
allowlist="$(swt::load_allowlist)" || swt::finish "${SWT_EXIT_USAGE}"

# ---------------------------------------------------------------------------
# 対象リポジトリの決定
#   --repo（label / パス） → Herdr の呼び出しコンテキスト → カレントディレクトリ
#
#   コンテキストを無条件に信用しないのは、`herdr plugin action invoke` を CLI から
#   呼ぶと「UI 側でフォーカスされているワークスペース」が渡るため。呼び出し元の
#   意図と一致する保証が無いので、解決結果は必ず表示してから使う。
# ---------------------------------------------------------------------------
repo_root=""
if [[ -n "${repo_arg}" ]]; then
    if repo_root="$(swt::repo_root_from_label "${allowlist}" "${repo_arg}")"; then
        :
    else
        repo_root="${repo_arg}"
    fi
elif [[ -n "${HERDR_PLUGIN_CONTEXT_JSON:-}" ]]; then
    repo_root="$(printf '%s' "${HERDR_PLUGIN_CONTEXT_JSON}" \
        | jq -r '.worktree.repo_root // empty')"
fi
[[ -n "${repo_root}" ]] || repo_root="${PWD}"

repo_root="$(swt::expand_home "${repo_root}")"
[[ -d "${repo_root}" ]] || swt::abort "${SWT_EXIT_USAGE}" "リポジトリが見つかりません: ${repo_root}"

# linked worktree の中を渡されてもメイン作業ツリーへ寄せる。Herdr は linked worktree からの
# worktree create を linked_worktree_source エラーで拒否し、worktree.created イベントの
# repo_root も常にメイン作業ツリーを指すため、ここで揃えておかないと
# 「作成できない」か「plugin 経由の作成が直接作成として誤検出される」のどちらかになる。
repo_root="$(swt::main_worktree_root "${repo_root}")" \
    || swt::abort "${SWT_EXIT_USAGE}" "git 作業ツリーではありません: ${repo_root}"

# ---------------------------------------------------------------------------
# allowlist 判定（fail-closed）
#   エントリごとに「そのエントリが使う remote」の URL を読んで突き合わせる。
#   remote 名がエントリ依存なので、先に remote を固定してから引くことができない。
# ---------------------------------------------------------------------------
entry=""
remote=""
matched_url=""
if matched="$(swt::match_repo "${allowlist}" "${repo_root}")"; then
    remote="${matched%%$'\t'*}"
    matched="${matched#*$'\t'}"
    matched_url="${matched%%$'\t'*}"
    entry="${matched#*$'\t'}"
fi

if [[ -z "${entry}" ]]; then
    default_remote="$(swt::remote_name "${allowlist}" '{}')"
    actual_url="$(git -C "${repo_root}" remote get-url "${default_remote}" 2>/dev/null || print -r -- '(取得できず)')"
    swt::error "allowlist に無いリポジトリです。worktree は作成しません。"
    swt::error "  repo   : ${repo_root}"
    swt::error "  ${default_remote} : ${actual_url}"
    swt::error "  設定   : $(swt::config_dir)/repos.json（マシンローカル分は repos.local.json）"
    swt::finish "${SWT_EXIT_NOT_ALLOWED}"
fi

repo_label="$(printf '%s' "${entry}" | jq -r '.label // "(no label)"')"
swt::log "リポジトリ: ${repo_label} (${repo_root})"
swt::log "リモート  : ${remote} ${matched_url}"

# ---------------------------------------------------------------------------
# ブランチ名
# ---------------------------------------------------------------------------
if [[ -z "${branch}" ]]; then
    if (( interactive )); then
        print -rn -- "作成するブランチ名: "
        read -r branch || true
    fi
fi
[[ -n "${branch}" ]] || swt::abort "${SWT_EXIT_USAGE}" "--branch が必要です"

if ! swt::valid_branch_name "${branch}"; then
    swt::abort "${SWT_EXIT_USAGE}" "ブランチ名として不正です: ${branch}"
fi

# ---------------------------------------------------------------------------
# 既存ブランチの扱い
#   ローカルに同名ブランチがあれば「新規作成」は拒否する。再利用したい場合だけ
#   --reuse で open に回す。`herdr worktree open` は worktree.created を発火しない
#   ことを実機で確認済みなので、この経路は監査ログにも通知にも現れない。
#
#   リモートにだけ同名ブランチがある場合は --reuse でも拒否する。ローカルにその
#   ブランチが無い状態で base から作ると、同じ名前で既に進んでいるリモート側と
#   黙って分岐する。これはまさにこの plugin が防ごうとしている事故なので、
#   自動で解決せず人間に返す。
# ---------------------------------------------------------------------------
if swt::branch_exists "${repo_root}" "${branch}"; then
    if (( reuse )); then
        swt::log "ブランチ ${branch} は既に存在します。--reuse 指定のため open で開きます（base は解決しません）。"
        if ! open_response="$("${herdr_bin}" worktree open --cwd "${repo_root}" --branch "${branch}" ${focus_flag} 2>&1)"; then
            swt::error "worktree open に失敗しました:"
            swt::error "${open_response}"
            swt::finish "${SWT_EXIT_ERROR}"
        fi
        # .result.worktree.path は公式スキーマ上 worktree_opened の必須フィールド。
        # .result.workspace.worktree は null を取りうるので、そちらは使わない。
        open_path="$(printf '%s' "${open_response}" | jq -r '.result.worktree.path // empty')"
        open_already="$(printf '%s' "${open_response}" | jq -r '.result.already_open // false')"
        if [[ "${open_already}" == "true" ]]; then
            swt::log "既に開いていました: ${open_path:-${branch}}"
        else
            swt::log "開きました: ${open_path:-${branch}}"
        fi
        swt::finish "${SWT_EXIT_OK}"
    fi
    swt::error "ブランチ ${branch} は既に存在します。新規作成はしません。"
    swt::error "  再利用するなら: ${0:A} --repo ${repo_root} --branch ${branch} --reuse"
    swt::finish "${SWT_EXIT_BRANCH_EXISTS}"
fi

swt::remote_branch_exists "${repo_root}" "${remote}" "${branch}"
remote_branch_rc=$?
case "${remote_branch_rc}" in
    0)
        swt::error "${remote}/${branch} が既に存在します。新規作成はしません。"
        swt::error "  ローカルに ${branch} が無い状態で base から作ると、リモートの同名ブランチと分岐します。"
        swt::error "  続きをやるなら先に取り込んでください: git -C ${repo_root} switch -c ${branch} --track ${remote}/${branch}"
        swt::finish "${SWT_EXIT_BRANCH_EXISTS}"
        ;;
    2)
        # 「問い合わせに失敗した」を「存在しない」と読み替えない。ネットワーク障害のたびに
        # リモート側の同名ブランチを見落として作成すると、この plugin の意味が無くなる。
        swt::error "${remote} に問い合わせできず、${branch} がリモートに存在するか判定できません。"
        swt::error "  判定できないまま作ると、リモートの同名ブランチと分岐する可能性があります。"
        swt::error "  接続を確認してから再実行してください: git -C ${repo_root} ls-remote --heads ${remote}"
        swt::finish "${SWT_EXIT_ERROR}"
        ;;
esac

# ---------------------------------------------------------------------------
# base の解決
#   いずれの経路でも「fetch した直後の remote-tracking ref / 存在確認済み SHA」まで
#   落としてから herdr へ渡す。ローカル ref をそのまま渡すことはしない。
# ---------------------------------------------------------------------------
base_sha=""
base_desc=""

if [[ -z "${base_arg}" ]]; then
    default_branch="$(swt::remote_default_branch "${repo_root}" "${remote}")" \
        || swt::abort "${SWT_EXIT_ERROR}" "${remote} の既定ブランチを解決できませんでした（ls-remote 失敗）"
    swt::log "既定ブランチ: ${remote}/${default_branch}（今この場でリモートに問い合わせた値）"

    swt::fetch_branch "${repo_root}" "${remote}" "${default_branch}" \
        || swt::abort "${SWT_EXIT_ERROR}" "fetch に失敗しました: ${remote} ${default_branch}"
    swt::set_remote_head "${repo_root}" "${remote}" "${default_branch}" || true

    base_sha="$(swt::resolve_commit "${repo_root}" "refs/remotes/${remote}/${default_branch}")" \
        || swt::abort "${SWT_EXIT_ERROR}" "fetch 後も ${remote}/${default_branch} を解決できませんでした"
    base_desc="${remote}/${default_branch}"
else
    kind="$(swt::classify_base "${base_arg}")"
    case "${kind}" in
        remote)
            base_remote="${base_arg%%/*}"
            base_branch="${base_arg#*/}"
            if [[ "${base_remote}" != "${remote}" ]]; then
                swt::abort "${SWT_EXIT_BAD_BASE}" \
                    "base のリモートが設定と異なります: ${base_remote}（このリポジトリの remote は ${remote}）"
            fi
            # ブランチ部分を git の ref 規則で検証する。ここを素通しすると
            # `origin/` や `origin/..` のような値がそのまま fetch の refspec に混ざる。
            if ! swt::valid_branch_name "${base_branch}"; then
                swt::abort "${SWT_EXIT_BAD_BASE}" "base のブランチ名として不正です: ${base_branch}"
            fi
            swt::fetch_branch "${repo_root}" "${remote}" "${base_branch}" \
                || swt::abort "${SWT_EXIT_BAD_BASE}" "fetch に失敗しました: ${remote} ${base_branch}"
            base_sha="$(swt::resolve_commit "${repo_root}" "refs/remotes/${remote}/${base_branch}")" \
                || swt::abort "${SWT_EXIT_BAD_BASE}" "fetch 後も ${base_arg} を解決できませんでした"
            base_desc="${base_arg}"
            ;;
        sha)
            if ! base_sha="$(swt::resolve_commit "${repo_root}" "${base_arg}")"; then
                # ローカルに無い SHA は、既定ブランチを 1 回だけ取り直してから再確認する
                if default_branch="$(swt::remote_default_branch "${repo_root}" "${remote}")"; then
                    swt::fetch_branch "${repo_root}" "${remote}" "${default_branch}" || true
                fi
                base_sha="$(swt::resolve_commit "${repo_root}" "${base_arg}")" \
                    || swt::abort "${SWT_EXIT_BAD_BASE}" \
                        "このリポジトリに存在しないコミットです: ${base_arg}"
            fi
            base_desc="${base_arg}"
            ;;
        *)
            swt::error "base として受け付けない指定です: ${base_arg}"
            swt::error "  受け付けるのは <${remote}>/<branch> 形式か、存在するコミット SHA だけです。"
            swt::error "  HEAD やローカルブランチ名は、ローカルが古いまま作成される事故を防ぐため拒否します。"
            swt::finish "${SWT_EXIT_BAD_BASE}"
            ;;
    esac
fi

swt::log "base: ${base_desc} = ${base_sha}"

# ---------------------------------------------------------------------------
# 確認
# ---------------------------------------------------------------------------
if (( interactive )) && (( ! assume_yes )); then
    print -r -- ""
    print -r -- "  repo   : ${repo_label} (${repo_root})"
    print -r -- "  branch : ${branch}"
    print -r -- "  base   : ${base_desc} = ${base_sha}"
    print -rn -- "この内容で作成しますか? (y/N) "
    read -r answer || true
    if [[ "${answer}" != "y" && "${answer}" != "Y" ]]; then
        swt::log "中止しました。"
        swt::finish "${SWT_EXIT_OK}"
    fi
fi

# ---------------------------------------------------------------------------
# 作成
#   worktree.created イベントフックが「この plugin 経由の作成」を識別できるよう、
#   期待値をマーカーとして先に置く。マーカーが無い作成は直接作成として監査される。
#
#   マーカーの後始末は「worktree が作られていないと言い切れるか」で分ける。
#     - herdr を呼ぶ前に落ちた         → 作られていない。即削除
#     - herdr が構造化エラーを返した   → 要求が拒否されただけで作られていない。即削除
#     - それ以外の失敗・応答の解釈失敗 → 作られたかどうか分からない。TTL に任せる
#
#   最後のケースで消しに行かないのは、worktree.created が create の応答より先に飛びうるため。
#   失敗と判断した側が消すと、フックが正当なマーカーを読む前に奪う競合になる。
#   残ったマーカーは SWT_PENDING_TTL_SECONDS で自然に失効する。
# ---------------------------------------------------------------------------
create_args=(worktree create --cwd "${repo_root}" --branch "${branch}" --base "${base_sha}" "${focus_flag}")
[[ -n "${label}" ]] && create_args+=(--label "${label}")

if ! swt::ensure_state_dir >/dev/null; then
    swt::abort "${SWT_EXIT_ERROR}" "状態ディレクトリを作成できませんでした: $(swt::state_dir)"
fi
if ! swt::pending_write "${repo_root}" "${branch}" "${base_sha}" "${base_desc}" >/dev/null; then
    swt::abort "${SWT_EXIT_ERROR}" "監査マーカーを書けませんでした: $(swt::pending_dir)"
fi

if ! response="$("${herdr_bin}" "${create_args[@]}" 2>&1)"; then
    # Herdr が JSON のエラーを返したなら、要求は受理されず worktree も作られていない。
    # この場合だけイベントとの競合が無いので即座にマーカーを捨てる。
    if [[ -n "$(printf '%s' "${response}" | jq -r '.error.code // empty' 2>/dev/null)" ]]; then
        swt::pending_drop "${repo_root}" "${branch}"
    fi
    swt::error "worktree create に失敗しました:"
    swt::error "${response}"
    swt::finish "${SWT_EXIT_ERROR}"
fi

# 公式スキーマ上、worktree_created の必須フィールドは type/workspace/tab/root_pane/worktree。
# チェックアウト先は .result.worktree.path（WorktreeInfo の必須フィールド）から取る。
# .result.workspace.worktree は WorkspaceInfo 上 nullable なので依存しない。
created_path="$(printf '%s' "${response}" | jq -r '.result.worktree.path // empty')"
created_branch="$(printf '%s' "${response}" | jq -r '.result.worktree.branch // empty')"
created_workspace="$(printf '%s' "${response}" | jq -r '.result.workspace.workspace_id // empty')"

if [[ -z "${created_path}" ]]; then
    swt::error "worktree create の応答を解釈できませんでした:"
    swt::error "${response}"
    swt::finish "${SWT_EXIT_ERROR}"
fi

# ---------------------------------------------------------------------------
# 作成結果の照合
#   ここが失敗しても worktree は消さない（削除・自動修復はこの plugin の責務外）。
#   何がどうずれているかを報告して、判断は人間に返す。
# ---------------------------------------------------------------------------
actual_sha="$(swt::resolve_commit "${created_path}" HEAD || true)"
actual_branch="$(git -C "${created_path}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"

mismatch=0
[[ "${actual_sha}" == "${base_sha}" ]]      || mismatch=1
[[ "${actual_branch}" == "${branch}" ]]     || mismatch=1
[[ "${created_branch}" == "${branch}" ]]    || mismatch=1

if (( mismatch )); then
    swt::error "作成結果が期待と一致しません（worktree はそのまま残します）:"
    swt::error "  path            : ${created_path}"
    swt::error "  branch 期待/実際 : ${branch} / ${actual_branch}"
    swt::error "  SHA    期待/実際 : ${base_sha} / ${actual_sha}"
    swt::finish "${SWT_EXIT_VERIFY}"
fi

swt::log "作成しました:"
swt::log "  workspace : ${created_workspace}"
swt::log "  path      : ${created_path}"
swt::log "  branch    : ${branch}"
swt::log "  base      : ${base_desc} = ${base_sha}"
swt::finish "${SWT_EXIT_OK}"
