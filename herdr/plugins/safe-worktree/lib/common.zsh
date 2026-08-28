#!/bin/zsh
# herdr/plugins/safe-worktree/lib/common.zsh
#
# allowlist 判定・base 解決・監査ログの共通プリミティブ。
# 呼び出し側は set -eu / setopt を自分で設定すること。
#
# 依存: zsh / git / jq / herdr CLI（いずれも nix/modules/darwin/homebrew.nix で宣言済み）

# ---- 終了コード（呼び出し側・テストが分岐に使う） --------------------------
SWT_EXIT_OK=0
SWT_EXIT_ERROR=1        # git / herdr の実行失敗
SWT_EXIT_USAGE=2        # 引数・設定ファイルの不備
SWT_EXIT_NOT_ALLOWED=3  # origin URL が allowlist に無い
SWT_EXIT_BAD_BASE=4     # base として受け付けない ref
SWT_EXIT_BRANCH_EXISTS=5 # 既存ブランチでの新規作成要求
SWT_EXIT_VERIFY=6       # 作成結果の照合失敗

# 絶対パスで /usr/bin/* を呼ぶ理由は setup/lib/fs.zsh と同じ。一部の非対話実行環境は
# PATH に /usr/bin を含まないことがあり、素の `shasum`/`awk` が command not found になる。

# swt::print_header_comment <file>
#   シバンの次から、最初の非コメント行の手前までを usage として出す。
#   行番号を決め打ちすると、ヘッダーが伸縮したときに黙って途中で切れる。
swt::print_header_comment() {
    local line first=1
    while IFS= read -r line; do
        if (( first )); then
            first=0
            continue
        fi
        [[ "${line}" == "#"* ]] || break
        print -r -- "${${line#\#}# }"
    done < "${1}"
}

swt::log()   { print -r -- "[safe-worktree] ${1}" }
swt::warn()  { print -r -- "[safe-worktree] WARN: ${1}" >&2 }
swt::error() { print -r -- "[safe-worktree] ERROR: ${1}" >&2 }

# swt::die <exit_code> <message>
swt::die() {
    swt::error "${2}"
    exit "${1}"
}

# swt::herdr_bin  herdr 実行体のパス。plugin 実行時は Herdr が HERDR_BIN_PATH を注入する。
#   テストでは SWT_HERDR_BIN でスタブに差し替える。
swt::herdr_bin() {
    print -r -- "${SWT_HERDR_BIN:-${HERDR_BIN_PATH:-herdr}}"
}

# swt::config_dir  設定ディレクトリ。plugin 実行時は Herdr が注入する。
swt::config_dir() {
    print -r -- "${SWT_CONFIG_DIR:-${HERDR_PLUGIN_CONFIG_DIR:-${HOME}/.config/herdr/plugins/config/dotfiles.safe-worktree}}"
}

# swt::state_dir  状態ディレクトリのパスを返すだけの getter。
#   読み取り専用の呼び出し（監査ログの参照など）が副作用でディレクトリを作らないよう、
#   作成は swt::ensure_state_dir に分けてある。
swt::state_dir() {
    print -r -- "${SWT_STATE_DIR:-${HERDR_PLUGIN_STATE_DIR:-${HOME}/.local/state/herdr/plugins/dotfiles.safe-worktree}}"
}

# swt::ensure_state_dir  書き込み前に呼ぶ。Herdr が作るディレクトリだが、
#   plugin を link した直後の初回実行ではまだ存在しないことがある。
swt::ensure_state_dir() {
    local dir
    dir="$(swt::state_dir)"
    if [[ ! -d "${dir}" ]] && ! mkdir -p "${dir}" 2>/dev/null; then
        # print の終了ステータスで成功が上書きされないよう、ここで打ち切る。
        # 呼び出し側はこの戻り値を見て worktree を作る前に停止する。
        return 1
    fi
    print -r -- "${dir}"
}

# ---------------------------------------------------------------------------
# allowlist
# ---------------------------------------------------------------------------

# swt::load_allowlist
#   設定ディレクトリの repos.json（dotfiles 追跡分の symlink）と repos.local.json
#   （マシンローカル分の実ファイル）を結合して 1 つの JSON として stdout に出す。
#   repos.json が無い場合は fail-closed。setup/herdr-sync.zsh 未実行の状態で
#   「allowlist が空だから全部拒否」ではなく「設定が壊れている」と報告するため。
swt::load_allowlist() {
    local dir tracked local_file
    dir="$(swt::config_dir)"
    tracked="${dir}/repos.json"
    local_file="${dir}/repos.local.json"

    if [[ ! -e "${tracked}" ]]; then
        swt::error "設定が見つかりません: ${tracked}"
        swt::error "zsh \${HOME}/.dotfiles/setup/herdr-sync.zsh を実行してください"
        return "${SWT_EXIT_USAGE}"
    fi

    local -a inputs
    inputs=("${tracked}")
    [[ -e "${local_file}" ]] && inputs+=("${local_file}")

    if ! jq -s '
        {
          version: 1,
          defaults: (map(.defaults // {}) | add // {}),
          repos: (map(.repos // []) | add)
        }
    ' "${inputs[@]}" 2>/dev/null; then
        swt::error "設定の解析に失敗しました: ${inputs[*]}"
        return "${SWT_EXIT_USAGE}"
    fi
}

# swt::normalize_origin <url>
#   git のリモート URL を「ホスト/パス」の正規形に落とす。
#   scheme と userinfo と port と末尾の .git は意図的に無視する:
#   https 経由と ssh 経由で同じリポジトリを別物として扱わないため
#   （allowlist が守るのは「どのリポジトリか」であって「どの転送路か」ではない）。
#   ローカルパス（file:// / 絶対パス / 相対パス）は symlink 解決後の実パスで同一性を見る。
swt::normalize_origin() {
    local url="${1}"
    [[ -n "${url}" ]] || return 1

    local rest="${url}"
    local scheme=""

    if [[ "${rest}" == *"://"* ]]; then
        scheme="${rest%%://*}"
        rest="${rest#*://}"
        scheme="${scheme:l}"
    fi

    if [[ "${scheme}" == "file" ]]; then
        print -r -- "file:${rest:A}"
        return 0
    fi
    # scheme 無しで ':' も無ければローカルパス（scp 形式は host:path なので必ず ':' を含む）
    if [[ -z "${scheme}" && "${rest}" != *:* ]]; then
        print -r -- "file:${rest:A}"
        return 0
    fi
    # scp 形式 [user@]host:path → host/path に寄せる
    if [[ -z "${scheme}" ]]; then
        rest="${rest%%:*}/${rest#*:}"
    fi

    local host_part="${rest%%/*}"
    local path_part=""
    [[ "${rest}" == */* ]] && path_part="${rest#*/}"

    host_part="${host_part##*@}"   # userinfo を落とす
    host_part="${host_part%%:*}"   # port を落とす
    host_part="${host_part:l}"

    path_part="${path_part#/}"
    path_part="${path_part%/}"
    path_part="${path_part%.git}"

    [[ -n "${host_part}" && -n "${path_part}" ]] || return 1
    print -r -- "${host_part}/${path_part}"
}

# swt::origins_match <url_a> <url_b>
#   2 つのリモート URL が同じリポジトリを指すかを判定する。
#   どちらか一方でも正規化に失敗したら「不一致」として扱う (M3)。
#   正規化の戻り値を見ずに文字列比較すると、両方が失敗して空文字列同士になったときに
#   一致と誤判定し、allowlist をすり抜ける。
swt::origins_match() {
    local norm_a norm_b
    norm_a="$(swt::normalize_origin "${1}")" || return 1
    norm_b="$(swt::normalize_origin "${2}")" || return 1
    [[ -n "${norm_a}" && -n "${norm_b}" ]] || return 1
    [[ "${norm_a}" == "${norm_b}" ]]
}

# swt::match_repo <allowlist_json> <repo_root>
#   repo_root のリモート URL が allowlist のどのエントリと一致するかを調べる。
#   一致すればタブ区切りで "<remote>\t<url>\t<entry_json>" を stdout に出し、
#   一致しなければ非 0（呼び出し側が SWT_EXIT_NOT_ALLOWED で落とす）。
#
#   エントリごとに remote 名が違いうるので、先に remote を 1 つに固定してから
#   URL を引くことはできない。エントリを回しながらそのエントリの remote を引く。
swt::match_repo() {
    local allowlist="${1}"
    local repo_root="${2}"

    local -a candidates
    candidates=("${(@f)$(printf '%s' "${allowlist}" | jq -c '.repos[]')}")

    local candidate candidate_origin candidate_remote candidate_url
    for candidate in "${candidates[@]}"; do
        [[ -n "${candidate}" ]] || continue
        candidate_origin="$(printf '%s' "${candidate}" | jq -r '.origin // empty')"
        [[ -n "${candidate_origin}" ]] || continue
        candidate_remote="$(swt::remote_name "${allowlist}" "${candidate}")"
        candidate_url="$(git -C "${repo_root}" remote get-url "${candidate_remote}" 2>/dev/null)" || continue
        if swt::origins_match "${candidate_url}" "${candidate_origin}"; then
            printf '%s\t%s\t%s\n' "${candidate_remote}" "${candidate_url}" "${candidate}"
            return 0
        fi
    done
    return 1
}

# swt::expand_home <path>
#   先頭の "~" だけを ${HOME} に展開する。${~var} を使わないのは、二重引用符の中では
#   filename generation が抑止されて展開されず、引用符を外すと今度はパスに含まれる空白や
#   glob 文字で壊れるため。設定ファイル由来の値なので、意図した 1 種類の展開だけを行う。
swt::expand_home() {
    local raw="${1}"
    case "${raw}" in
        "~")   print -r -- "${HOME}" ;;
        "~/"*) print -r -- "${HOME}/${raw#\~/}" ;;
        *)     print -r -- "${raw}" ;;
    esac
}

# swt::repo_root_from_label <allowlist_json> <label>
#   allowlist の label から作業ツリーのパスを引く（先頭の "~" は展開する）。
swt::repo_root_from_label() {
    local allowlist="${1}"
    local label="${2}"

    local root
    root="$(printf '%s' "${allowlist}" \
        | jq -r --arg l "${label}" '.repos[] | select(.label == $l) | .root // empty' \
        | head -n 1)"
    [[ -n "${root}" ]] || return 1
    swt::expand_home "${root}"
}

# swt::remote_name <allowlist_json> <entry_json>
#   エントリ固有の remote → defaults.remote → "origin" の順で解決する。
swt::remote_name() {
    local allowlist="${1}"
    local entry="${2}"

    local name
    name="$(printf '%s' "${entry}" | jq -r '.remote // empty')"
    [[ -n "${name}" ]] || name="$(printf '%s' "${allowlist}" | jq -r '.defaults.remote // empty')"
    [[ -n "${name}" ]] || name="origin"
    print -r -- "${name}"
}

# ---------------------------------------------------------------------------
# git
# ---------------------------------------------------------------------------

# swt::git_toplevel <path>  path を含む作業ツリーのルート
swt::git_toplevel() {
    git -C "${1}" rev-parse --show-toplevel 2>/dev/null
}

# swt::main_worktree_root <path>
#   path が属するリポジトリの「メイン作業ツリー」の絶対パスを返す。
#
#   linked worktree の中から呼ばれても、そこではなく親リポジトリを返す必要がある。
#   理由は 2 つある:
#     1. Herdr の worktree create/open は linked worktree からの実行を
#        `linked_worktree_source` エラーで拒否する（実機確認済み）
#     2. worktree.created イベントの repo_root は常にメイン作業ツリーを指すため、
#        作成側がここを揃えないと pending マーカーのキーが一致せず、
#        plugin 経由の作成が「直接作成」として誤検出される
#
#   `git worktree list --porcelain` の先頭エントリが必ずメイン作業ツリーになる。
swt::main_worktree_root() {
    # 変数名に path を使わない。zsh は path を $PATH と束縛された特殊配列として扱うため、
    # local でスカラーを代入すると同一スコープ内のコマンド解決 (git 等) が壊れる
    # (setup/lib/fs.zsh の fs::ensure_realfile と同じ理由)。
    local target="${1}"
    local listing first
    listing="$(git -C "${target}" worktree list --porcelain 2>/dev/null)"
    first="${listing%%$'\n'*}"
    if [[ "${first}" == "worktree "* ]]; then
        print -r -- "${${first#worktree }:A}"
        return 0
    fi
    # worktree list が使えない場合の保険（bare 相当など）
    local top
    top="$(swt::git_toplevel "${target}")" || return 1
    print -r -- "${top:A}"
}

# swt::remote_default_branch <repo_root> <remote>
#   リモートの HEAD が指すブランチ名を「その場で」問い合わせる。
#   ローカルの refs/remotes/<remote>/HEAD をキャッシュとして使わないのは、
#   既定ブランチが上流で付け替えられた（v2 → main 等）ときに自動追従させるため。
swt::remote_default_branch() {
    local repo_root="${1}"
    local remote="${2}"

    local symref
    symref="$(git -C "${repo_root}" ls-remote --symref "${remote}" HEAD 2>/dev/null \
        | /usr/bin/awk '$1 == "ref:" && $3 == "HEAD" { print $2; exit }')"
    [[ -n "${symref}" ]] || return 1
    print -r -- "${symref#refs/heads/}"
}

# swt::fetch_branch <repo_root> <remote> <branch>
#   refs/remotes/<remote>/<branch> を更新する。FETCH_HEAD ではなく
#   remote-tracking ref を明示更新するのは、監査フック（audit-created.zsh）が
#   ネットワーク無しで base の妥当性を判定できるようにするため。
swt::fetch_branch() {
    local repo_root="${1}"
    local remote="${2}"
    local branch="${3}"

    git -C "${repo_root}" fetch --quiet "${remote}" \
        "+refs/heads/${branch}:refs/remotes/${remote}/${branch}"
}

# swt::set_remote_head <repo_root> <remote> <branch>
#   refs/remotes/<remote>/HEAD を現在の既定ブランチに合わせる。
#   `git remote set-head` と同じ範囲の更新で、作業ツリーやローカルブランチには触れない。
swt::set_remote_head() {
    local repo_root="${1}"
    local remote="${2}"
    local branch="${3}"

    git -C "${repo_root}" symbolic-ref "refs/remotes/${remote}/HEAD" \
        "refs/remotes/${remote}/${branch}" 2>/dev/null
}

# swt::branch_exists <repo_root> <branch>  ローカルブランチが存在するか
swt::branch_exists() {
    git -C "${1}" show-ref --verify --quiet "refs/heads/${2}"
}

# swt::remote_branch_exists <repo_root> <remote> <branch>
#   リモートに同名ブランチがあるかを ls-remote で直接問い合わせる。
#
#   ローカルの refs/remotes/<remote>/<branch> を見ないのは、それ自体が古くなりうるため。
#   「fetch していないので気づかなかった」が、この plugin が防ごうとしている事故そのもの。
#   ローカルに同名ブランチが無くてもリモートに既にあるなら、base から作った時点で
#   同じ名前の別履歴が 2 つできる。
#   戻り値は三値。ネットワーク障害を「存在しない」と読み替えないため。
#     0 = リモートに存在する
#     1 = リモートに存在しない（ls-remote が --exit-code で 2 を返した）
#     2 = 問い合わせ自体に失敗した（判定不能）
swt::remote_branch_exists() {
    git -C "${1}" ls-remote --exit-code --heads "${2}" "refs/heads/${3}" >/dev/null 2>&1
    local rc=$?
    case "${rc}" in
        0) return 0 ;;
        2) return 1 ;;
        *) return 2 ;;
    esac
}

# swt::valid_branch_name <name>  git のブランチ名として妥当か
swt::valid_branch_name() {
    [[ -n "${1}" ]] || return 1
    git check-ref-format --branch "${1}" >/dev/null 2>&1
}

# swt::resolve_commit <repo_root> <rev>  rev が指すコミット SHA（存在しなければ非 0）
swt::resolve_commit() {
    git -C "${1}" rev-parse --verify --quiet "${2}^{commit}" 2>/dev/null
}

# ---------------------------------------------------------------------------
# base の受理判定
# ---------------------------------------------------------------------------

# swt::classify_base <base>
#   受理する形だけを分類する。分類できない形は "reject" を返す。
#     remote  : <remote>/<branch> 形式（fetch してから SHA に解決する）
#     sha     : 7 文字以上の 16 進（リポジトリ内に存在することを別途確認する）
#     reject  : HEAD / @ / ローカルブランチ名 / タグ / 相対指定（HEAD~1 等）
#
#   ローカル ref を一律に拒否するのは、Herdr 標準の worktree create が
#   `--base main` をローカルの main として黙って解決してしまうため。
#   「ローカルが古いことに気づかないまま古い base で作る」事故がこの plugin の防御対象。
swt::classify_base() {
    # 16 進 SHA の桁数判定に (#c7,40) を使うため、この関数内だけ extendedglob を有効にする
    setopt local_options extended_glob
    local base="${1}"

    [[ -n "${base}" ]] || { print -r -- "reject"; return 0 }

    if [[ "${base}" == "HEAD" || "${base}" == "@" || "${base}" == HEAD[~^]* ]]; then
        print -r -- "reject"
        return 0
    fi
    # 相対指定は解決タイミングで意味が変わるため受け付けない
    if [[ "${base}" == *[~^]* ]]; then
        print -r -- "reject"
        return 0
    fi
    if [[ "${base}" == */* ]]; then
        print -r -- "remote"
        return 0
    fi
    if [[ "${base}" == [0-9a-fA-F](#c7,40) ]]; then
        print -r -- "sha"
        return 0
    fi
    print -r -- "reject"
}

# ---------------------------------------------------------------------------
# 監査マーカー
# ---------------------------------------------------------------------------

# マーカーの有効期間（秒）。worktree.created はコマンド応答の直後に飛ぶので、
# 実運用では数秒あれば足りる。取りこぼしに余裕を持たせつつ、古い残骸を
# 「plugin 経由の作成」として誤認させない上限として 120 秒を既定にする。
SWT_PENDING_TTL_SECONDS="${SWT_PENDING_TTL_SECONDS:-120}"

# swt::pending_dir  マーカー置き場（作成はしない）
swt::pending_dir() {
    print -r -- "$(swt::state_dir)/pending"
}

# swt::pending_key <repo_root> <branch>
#   「この plugin が今から作ろうとしている worktree」を示すマーカーのファイル名。
#   作成前に create.zsh が置き、worktree.created フックが拾って消す。
#   キーに使えるのはイベント側でも取れる値（repo_root と branch）だけ。
#   Herdr がチェックアウト先パスを決めるので、パスは作成前には確定していない。
swt::pending_key() {
    # symlink 経由のパス（/var と /private/var 等）で別キーにならないよう実パスへ寄せる。
    # 作成側は git の toplevel、イベント側は Herdr の repo_root と、出所が違うため。
    local repo_root="${1:A}"
    local branch="${2}"
    local digest
    digest="$(printf '%s\0%s' "${repo_root}" "${branch}" | /usr/bin/shasum -a 256)"
    print -r -- "${digest%% *}"
}

# swt::pending_gc
#   TTL を過ぎたマーカーを消す。create.zsh の開始時と監査フックの両方から呼ぶ。
#
#   古いマーカーを残したままにすると、あとから同じ repo + branch で「直接」作られた
#   worktree が plugin 経由の作成として誤って承認される。時間切れのマーカーは
#   一切信用しない（fail-closed）。
swt::pending_gc() {
    local dir
    dir="$(swt::pending_dir)"
    [[ -d "${dir}" ]] || return 0

    local now marker
    now="$(date -u +%s)"
    for marker in "${dir}"/*.json(N); do
        if ! swt::pending_is_fresh "${marker}" "${now}"; then
            rm -f "${marker}"
        fi
    done
}

# swt::pending_is_fresh <marker_path> [now_epoch]
swt::pending_is_fresh() {
    local marker="${1}"
    local now="${2:-$(date -u +%s)}"

    [[ -f "${marker}" ]] || return 1

    local created
    created="$(jq -r '.created_epoch // empty' "${marker}" 2>/dev/null)"
    [[ -n "${created}" ]] || return 1
    (( now - created >= 0 && now - created <= SWT_PENDING_TTL_SECONDS ))
}

# swt::pending_write <repo_root> <branch> <base_sha> <base_desc>
#   作成直前に期待値を書き出す。書き出しは herdr へ渡す前に行う必要がある
#   （worktree.created は create コマンドの応答より先に飛びうるため）。
swt::pending_write() {
    local repo_root="${1}" branch="${2}" base_sha="${3}" base_desc="${4}"

    local dir
    dir="$(swt::pending_dir)"
    if [[ ! -d "${dir}" ]] && ! mkdir -p "${dir}" 2>/dev/null; then
        return 1
    fi
    swt::pending_gc

    local marker="${dir}/$(swt::pending_key "${repo_root}" "${branch}").json"
    if ! jq -n \
        --arg repo_root "${repo_root}" \
        --arg branch "${branch}" \
        --arg base_sha "${base_sha}" \
        --arg base_desc "${base_desc}" \
        --arg created_at "$(date -u +%FT%TZ)" \
        --argjson created_epoch "$(date -u +%s)" \
        '{repo_root: $repo_root, branch: $branch, base_sha: $base_sha,
          base_desc: $base_desc, created_at: $created_at, created_epoch: $created_epoch}' \
        > "${marker}" 2>/dev/null; then
        # 中途半端なマーカーを残さない。マーカーが無いまま作成すると監査上は
        # 直接作成として鳴るだけだが、壊れたマーカーは誤って承認されうる。
        rm -f "${marker}" 2>/dev/null
        return 1
    fi
    print -r -- "${marker}"
}

# swt::pending_take <repo_root> <branch>
#   マーカーがあり、かつ TTL 内なら中身を stdout に出して消す（消費）。
#   無い / 期限切れなら非 0 を返し、期限切れのものはその場で捨てる。
swt::pending_take() {
    local repo_root="${1}" branch="${2}"

    swt::pending_gc

    local marker
    marker="$(swt::pending_dir)/$(swt::pending_key "${repo_root}" "${branch}").json"
    swt::pending_is_fresh "${marker}" || return 1

    local content
    content="$(cat "${marker}")"
    rm -f "${marker}"
    print -r -- "${content}"
}

# ---------------------------------------------------------------------------
# 監査ログ
# ---------------------------------------------------------------------------

# 1 世代だけ残して切り替える閾値（バイト）。監査ログは 1 件 400 バイト程度なので、
# 1 MiB でおよそ 2500 件分。これ以上を無期限に伸ばす価値はない。
SWT_AUDIT_MAX_BYTES="${SWT_AUDIT_MAX_BYTES:-1048576}"

# swt::rotate_audit_log <path>
#   閾値を超えていたら <path>.1 へ 1 世代だけ退避する。
#
#   ローテーション自体は mkdir のアトミック性でロックする。worktree.created が
#   連続したときに 2 プロセスが同時に mv すると、片方のログが失われる。
#   ロックが取れなければ今回は見送る（次の書き込みで再挑戦すればよい）。
#
#   追記そのものはロックしない。1 行が PIPE_BUF (4096) より十分短く、
#   O_APPEND の write は単一 write に収まる限りアトミックなため。
swt::rotate_audit_log() {
    local log="${1}"
    [[ -f "${log}" ]] || return 0

    local size
    size="$(/usr/bin/stat -f %z "${log}" 2>/dev/null || print -r -- 0)"
    (( size > SWT_AUDIT_MAX_BYTES )) || return 0

    local lock="${log}.rotate.lock"
    mkdir "${lock}" 2>/dev/null || return 0

    # ロック待ちの間に別プロセスが切り替えている可能性があるので、もう一度測る
    size="$(/usr/bin/stat -f %z "${log}" 2>/dev/null || print -r -- 0)"
    if (( size > SWT_AUDIT_MAX_BYTES )); then
        mv -f "${log}" "${log}.1"
    fi
    rmdir "${lock}" 2>/dev/null
}

# swt::pending_drop <repo_root> <branch>
#   マーカーを即座に捨てる。「worktree が作られていないと確認できた」場合にだけ呼ぶ。
#   イベントが飛びうる状況で呼ぶと、フックが正当なマーカーを読む前に奪う競合になる。
swt::pending_drop() {
    rm -f "$(swt::pending_dir)/$(swt::pending_key "${1}" "${2}").json"
}
