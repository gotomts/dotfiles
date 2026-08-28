#!/usr/bin/env bats
# herdr/plugins/safe-worktree/tests/safe-worktree.bats
#
# 実際の herdr は一切呼ばない。worktree の作成は stub が `git worktree add` に
# 読み替えて実行し、Herdr の応答 JSON だけを模す。

PLUGIN_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

# --- ヘルパー -------------------------------------------------------------

swt_run() {
    zsh -c "source '${PLUGIN_DIR}/lib/common.zsh'; $*"
}

# abspath <path>  symlink を解決した絶対パス。
#   bats は bash で動くので、zsh の ${var:A} は使えない。/var と /private/var のような
#   symlink 差でテストが落ちるのを防ぐ。
abspath() {
    ( cd "${1}" >/dev/null 2>&1 && pwd -P )
}

# with_limit <秒> <コマンド...>
#   引数解析が無限ループに戻る回帰を、テストのハングではなく失敗として検出するための上限。
#   macOS には GNU coreutils の timeout が無いので、perl の alarm を使う。
with_limit() {
    local secs="${1}"
    shift
    perl -e 'alarm shift; exec @ARGV or exit 127' "${secs}" "$@"
}

# stub_herdr  worktree create/open を git worktree に読み替える herdr スタブを作る。
#   応答 JSON は `herdr api schema` の success_response / ResponseResult に定義された
#   worktree_created・worktree_opened の必須フィールドに合わせる（推測で組まない）。
#     worktree_created: type, workspace, tab, root_pane, worktree
#     worktree_opened : 上記 + already_open
#   チェックアウト先は WorktreeInfo の必須フィールド .worktree.path から取れる。
#   .workspace.worktree は WorkspaceInfo 上 nullable なので、スタブでも意図的に null にし、
#   本体がそちらに依存していないことを常に検査する。
stub_herdr() {
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    cat > "${BATS_TEST_TMPDIR}/bin/herdr" <<'STUB'
#!/bin/zsh
print -r -- "$*" >> "${STUB_HERDR_LOG:-/dev/null}"
cwd=""; branch=""; base=""; sub="${2:-}"
shift 2 2>/dev/null || true
while (( $# > 0 )); do
    case "${1}" in
        --cwd)    cwd="${2}";    shift 2 ;;
        --branch) branch="${2}"; shift 2 ;;
        --base)   base="${2}";   shift 2 ;;
        --label)  shift 2 ;;
        *) shift ;;
    esac
done
if [[ -n "${STUB_ERROR_CODE:-}" ]]; then
    jq -n --arg c "${STUB_ERROR_CODE}" '{error: {code: $c, message: "stubbed"}}'
    exit 1
fi
checkout="${STUB_WORKTREE_DIR}/${branch//\//-}"
already=false
if [[ "${sub}" == "create" ]]; then
    # STUB_CREATE_AT が設定されていたら、要求された base ではなくそちらで作る。
    # create.zsh の作成後照合が本当に効いているかを検査するため。
    git -C "${cwd}" worktree add --quiet -b "${branch}" "${checkout}" "${STUB_CREATE_AT:-${base}}" >&2 || exit 1
elif [[ "${sub}" == "open" ]]; then
    if [[ -d "${checkout}" ]]; then
        already=true
    else
        git -C "${cwd}" worktree add --quiet "${checkout}" "${branch}" >&2 || exit 1
    fi
fi
jq -n --arg p "${checkout}" --arg b "${branch}" --argjson already "${already}" \
    '{result: {
        type: "worktree_created",
        workspace: {workspace_id: "w1", number: 1, label: $b, focused: false,
                    pane_count: 1, tab_count: 1, active_tab_id: "w1:t1",
                    agent_status: "unknown", worktree: null},
        tab: {workspace_id: "w1", tab_id: "w1:t1", label: "1", number: 1,
              pane_count: 1, focused: false, agent_status: "unknown"},
        root_pane: {pane_id: "w1:p1", tab_id: "w1:t1", workspace_id: "w1", cwd: $p},
        worktree: {path: $p, branch: $b, is_bare: false, is_detached: false,
                   is_prunable: false, is_linked_worktree: true, label: "repo"},
        already_open: $already
    }}'
STUB
    chmod +x "${BATS_TEST_TMPDIR}/bin/herdr"
    export SWT_HERDR_BIN="${BATS_TEST_TMPDIR}/bin/herdr"
    export STUB_WORKTREE_DIR="${BATS_TEST_TMPDIR}/worktrees"
    export STUB_HERDR_LOG="${BATS_TEST_TMPDIR}/herdr-calls.log"
    mkdir -p "${STUB_WORKTREE_DIR}"
}

# make_repo  origin 付きのローカルリポジトリ一式を作る。
#   upstream を bare で作り、既定ブランチを v2 にしておく（v2 -> main の付け替え検証用）。
make_repo() {
    UPSTREAM="${BATS_TEST_TMPDIR}/upstream.git"
    REPO="${BATS_TEST_TMPDIR}/repo"
    git init --bare -q -b v2 "${UPSTREAM}"
    git init -q -b v2 "${REPO}"
    git -C "${REPO}" config user.email t@e.st
    git -C "${REPO}" config user.name test
    echo a > "${REPO}/a.txt"
    git -C "${REPO}" add .
    git -C "${REPO}" commit -qm first
    git -C "${REPO}" remote add origin "${UPSTREAM}"
    git -C "${REPO}" push -q origin v2
    git -C "${UPSTREAM}" symbolic-ref HEAD refs/heads/v2
}

# advance_remote  ローカルに反映せずリモートだけ 1 コミット進める
advance_remote() {
    local clone="${BATS_TEST_TMPDIR}/pusher"
    rm -rf "${clone}"
    git clone -q "${UPSTREAM}" "${clone}"
    git -C "${clone}" config user.email t@e.st
    git -C "${clone}" config user.name test
    echo "${RANDOM}" > "${clone}/b.txt"
    git -C "${clone}" add .
    git -C "${clone}" commit -qm second
    git -C "${clone}" push -q origin HEAD
}

write_config() {
    mkdir -p "${SWT_CONFIG_DIR}"
    jq -n --arg origin "${UPSTREAM}" --arg root "${REPO}" \
        '{version: 1, defaults: {remote: "origin"},
          repos: [{label: "scratch", origin: $origin, root: $root}]}' \
        > "${SWT_CONFIG_DIR}/repos.json"
}

teardown() {
    # 書き込み不可にしたディレクトリを戻さないと BATS_TEST_TMPDIR の後片付けが失敗する
    [[ -n "${LOCKED_DIR:-}" && -d "${LOCKED_DIR}" ]] && chmod u+w "${LOCKED_DIR}"
    return 0
}

setup() {
    export SWT_CONFIG_DIR="${BATS_TEST_TMPDIR}/config"
    export SWT_STATE_DIR="${BATS_TEST_TMPDIR}/state"
    export GIT_CONFIG_GLOBAL="${BATS_TEST_TMPDIR}/gitconfig"
    export GIT_CONFIG_NOSYSTEM=1
    : > "${GIT_CONFIG_GLOBAL}"
}

# --- 構文 -----------------------------------------------------------------

@test "zsh -n syntax check passes for every script" {
    for f in "${PLUGIN_DIR}"/lib/*.zsh "${PLUGIN_DIR}"/bin/*.zsh; do
        run zsh -n "${f}"
        [ "${status}" -eq 0 ]
    done
}

@test "manifest declares the action, pane and worktree.created hook" {
    grep -q 'id = "dotfiles.safe-worktree"' "${PLUGIN_DIR}/herdr-plugin.toml"
    grep -q 'on = "worktree.created"' "${PLUGIN_DIR}/herdr-plugin.toml"
    grep -q 'placement = "popup"' "${PLUGIN_DIR}/herdr-plugin.toml"
}

@test "tracked allowlist is valid json" {
    run jq -e '.repos | type == "array"' "${PLUGIN_DIR}/config/repos.json"
    [ "${status}" -eq 0 ]
}

# --- normalize_origin -----------------------------------------------------

@test "normalize_origin treats ssh, scp and https forms of one repo as equal" {
    a="$(swt_run 'swt::normalize_origin git@github.com:o/r.git')"
    b="$(swt_run 'swt::normalize_origin ssh://git@github.com/o/r.git')"
    c="$(swt_run 'swt::normalize_origin https://github.com/o/r')"
    d="$(swt_run 'swt::normalize_origin https://GitHub.com:443/o/r.git')"
    [ "${a}" = "github.com/o/r" ]
    [ "${a}" = "${b}" ]
    [ "${a}" = "${c}" ]
    [ "${a}" = "${d}" ]
}

@test "normalize_origin keeps different repos distinct" {
    a="$(swt_run 'swt::normalize_origin https://github.com/o/r')"
    b="$(swt_run 'swt::normalize_origin https://github.com/o/other')"
    c="$(swt_run 'swt::normalize_origin https://gitlab.com/o/r')"
    [ "${a}" != "${b}" ]
    [ "${a}" != "${c}" ]
}

# --- classify_base --------------------------------------------------------

@test "classify_base rejects HEAD, bare local branch names and relative revisions" {
    for base in HEAD @ main develop 'HEAD~1' 'main^' 'v1.0' ''; do
        [ "$(swt_run "swt::classify_base '${base}'")" = "reject" ]
    done
}

@test "classify_base accepts remote-qualified refs and hex shas" {
    [ "$(swt_run 'swt::classify_base origin/main')" = "remote" ]
    [ "$(swt_run 'swt::classify_base 60acd0e153e7648b5b126e48cb329c6e7013d4ef')" = "sha" ]
    [ "$(swt_run 'swt::classify_base 60acd0e')" = "sha" ]
}

# --- load_allowlist -------------------------------------------------------

@test "load_allowlist fails closed when the tracked config is missing" {
    run zsh -c "source '${PLUGIN_DIR}/lib/common.zsh'; swt::load_allowlist"
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"herdr-sync.zsh"* ]]
}

@test "load_allowlist merges the machine-local allowlist" {
    mkdir -p "${SWT_CONFIG_DIR}"
    echo '{"version":1,"defaults":{"remote":"origin"},"repos":[{"label":"a","origin":"https://github.com/o/a"}]}' \
        > "${SWT_CONFIG_DIR}/repos.json"
    echo '{"version":1,"repos":[{"label":"b","origin":"https://github.com/o/b"}]}' \
        > "${SWT_CONFIG_DIR}/repos.local.json"
    run zsh -c "source '${PLUGIN_DIR}/lib/common.zsh'; swt::load_allowlist | jq -r '.repos[].label' | sort | tr '\n' ' '"
    [ "${status}" -eq 0 ]
    [ "${output}" = "a b " ]
}

# --- create.zsh -----------------------------------------------------------

@test "create refuses a repository whose origin is not on the allowlist" {
    make_repo
    write_config
    stub_herdr
    other="${BATS_TEST_TMPDIR}/other"
    git init -q "${other}"
    git -C "${other}" remote add origin https://example.com/nope.git

    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo "${other}" --branch feat/x
    [ "${status}" -eq 3 ]
    [[ "${output}" == *"allowlist に無いリポジトリ"* ]]
    [ ! -d "${STUB_WORKTREE_DIR}/feat-x" ]
}

@test "create refuses HEAD and bare local branch names as base" {
    make_repo
    write_config
    stub_herdr

    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch --branch feat/x --base HEAD
    [ "${status}" -eq 4 ]
    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch --branch feat/x --base v2
    [ "${status}" -eq 4 ]
    [ ! -d "${STUB_WORKTREE_DIR}/feat-x" ]
}

@test "create refuses a base pointing at a remote other than the configured one" {
    make_repo
    write_config
    stub_herdr

    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch --branch feat/x --base upstream/v2
    [ "${status}" -eq 4 ]
}

@test "create refuses a sha that does not exist in the repository" {
    make_repo
    write_config
    stub_herdr

    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch --branch feat/x \
        --base deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
    [ "${status}" -eq 4 ]
}

@test "create uses the freshly fetched remote tip, not the stale local branch" {
    make_repo
    write_config
    stub_herdr
    advance_remote

    stale="$(git -C "${REPO}" rev-parse v2)"
    remote_tip="$(git -C "${REPO}" ls-remote origin refs/heads/v2 | cut -f1)"
    [ "${stale}" != "${remote_tip}" ]

    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch --branch feat/fresh
    [ "${status}" -eq 0 ]
    [ "$(git -C "${STUB_WORKTREE_DIR}/feat-fresh" rev-parse HEAD)" = "${remote_tip}" ]
}

@test "create follows a renamed remote default branch without local reconfiguration" {
    make_repo
    write_config
    stub_herdr
    # 上流の既定ブランチを v2 から main へ付け替える
    git -C "${UPSTREAM}" branch -m v2 main
    git -C "${UPSTREAM}" symbolic-ref HEAD refs/heads/main

    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch --branch feat/renamed
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"origin/main"* ]]
}

@test "create refuses to create on an existing branch and points at --reuse" {
    make_repo
    write_config
    stub_herdr
    git -C "${REPO}" branch feat/exists

    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch --branch feat/exists
    [ "${status}" -eq 5 ]
    [[ "${output}" == *"--reuse"* ]]
}

@test "create --reuse opens the existing branch instead of creating it" {
    make_repo
    write_config
    stub_herdr
    git -C "${REPO}" branch feat/exists

    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch --branch feat/exists --reuse
    [ "${status}" -eq 0 ]
    [ -d "${STUB_WORKTREE_DIR}/feat-exists" ]
}

@test "create leaves a pending marker that the audit hook consumes" {
    make_repo
    write_config
    stub_herdr

    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch --branch feat/marker
    [ "${status}" -eq 0 ]
    [ "$(ls -1 "${SWT_STATE_DIR}/pending" | wc -l | tr -d ' ')" = "1" ]
}

# --- audit-created.zsh ----------------------------------------------------

# emit_event  worktree.created のイベント JSON を組み立てて監査フックへ渡す
run_audit() {
    local checkout="${1}" branch="${2}"
    HERDR_PLUGIN_EVENT_JSON="$(jq -n \
        --arg repo "${REPO}" --arg co "${checkout}" --arg br "${branch}" \
        '{data: {workspace: {workspace_id: "w1", worktree: {repo_root: $repo}},
                 worktree: {path: $co, branch: $br}}}')" \
        SWT_HERDR_BIN="${BATS_TEST_TMPDIR}/bin/true-stub" \
        SWT_PENDING_TTL_SECONDS="${SWT_PENDING_TTL_SECONDS:-120}" \
        zsh "${PLUGIN_DIR}/bin/audit-created.zsh"
}

# run_audit_no_workspace_worktree  .data.workspace.worktree が null のイベントを流す。
#   公式スキーマ上 WorkspaceInfo.worktree は nullable なので、repo_root が取れない
#   ケースでもチェックアウト先から自力で解決できることを検査する。
run_audit_no_workspace_worktree() {
    local checkout="${1}" branch="${2}"
    HERDR_PLUGIN_EVENT_JSON="$(jq -n \
        --arg co "${checkout}" --arg br "${branch}" \
        '{data: {workspace: {workspace_id: "w1", worktree: null},
                 worktree: {path: $co, branch: $br}}}')" \
        SWT_HERDR_BIN="${BATS_TEST_TMPDIR}/bin/true-stub" \
        zsh "${PLUGIN_DIR}/bin/audit-created.zsh"
}

# setup_notify_stub  監査フックが呼ぶ herdr を、引数を記録するだけのスタブに差し替える。
#   「通知しない」を検証するには、成功して終わるだけのスタブでは足りない
#   （何も検査していないのと同じになる）。呼び出しを数える。
setup_notify_stub() {
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    export NOTIFY_LOG="${BATS_TEST_TMPDIR}/notify.log"
    : > "${NOTIFY_LOG}"
    cat > "${BATS_TEST_TMPDIR}/bin/true-stub" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >> "${NOTIFY_LOG}"
exit 0
STUB
    chmod +x "${BATS_TEST_TMPDIR}/bin/true-stub"
}

notify_count() {
    grep -c 'notification show' "${NOTIFY_LOG}" 2>/dev/null || true
}

last_verdict() {
    tail -n 1 "${SWT_STATE_DIR}/audit.jsonl" | jq -r '.verdict'
}

@test "audit records a plugin-created worktree as ok and consumes the marker" {
    make_repo
    write_config
    stub_herdr
    setup_notify_stub

    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch --branch feat/audited
    [ "${status}" -eq 0 ]

    run_audit "${STUB_WORKTREE_DIR}/feat-audited" feat/audited
    [ "$(last_verdict)" = "plugin_ok" ]
    [ "$(ls -1 "${SWT_STATE_DIR}/pending" | wc -l | tr -d ' ')" = "0" ]
    # plugin 経由で期待どおりなら通知しない
    [ "$(notify_count)" = "0" ]
}

@test "audit flags a direct creation made from a stale base" {
    make_repo
    write_config
    stub_herdr
    setup_notify_stub
    advance_remote
    git -C "${REPO}" fetch -q origin '+refs/heads/v2:refs/remotes/origin/v2'
    git -C "${REPO}" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/v2

    # plugin を経由せず、古いローカル v2 から直接 worktree を作る
    direct="${BATS_TEST_TMPDIR}/direct"
    git -C "${REPO}" worktree add --quiet -b feat/direct "${direct}" v2

    run_audit "${direct}" feat/direct
    [ "$(last_verdict)" = "direct_create_stale_base" ]
    # allowlist 対象で plugin_ok 以外なら通知する（上の「通知しない」ケースとの対）
    [ "$(notify_count)" = "1" ]
}

@test "audit flags a direct creation whose base is outside the remote default history" {
    make_repo
    write_config
    stub_herdr
    setup_notify_stub
    git -C "${REPO}" fetch -q origin '+refs/heads/v2:refs/remotes/origin/v2'
    git -C "${REPO}" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/v2

    git -C "${REPO}" checkout -q --orphan unrelated
    git -C "${REPO}" commit -q --allow-empty -m unrelated
    unrelated_sha="$(git -C "${REPO}" rev-parse HEAD)"
    git -C "${REPO}" checkout -q v2

    direct="${BATS_TEST_TMPDIR}/direct"
    git -C "${REPO}" worktree add --quiet -b feat/unrelated "${direct}" "${unrelated_sha}"

    run_audit "${direct}" feat/unrelated
    [ "$(last_verdict)" = "direct_create_unexpected_base" ]
}

@test "audit never removes or rewrites the worktree it flags" {
    make_repo
    write_config
    stub_herdr
    setup_notify_stub
    git -C "${REPO}" fetch -q origin '+refs/heads/v2:refs/remotes/origin/v2'
    git -C "${REPO}" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/v2

    direct="${BATS_TEST_TMPDIR}/direct"
    git -C "${REPO}" worktree add --quiet -b feat/keep "${direct}" v2
    before="$(git -C "${direct}" rev-parse HEAD)"

    run_audit "${direct}" feat/keep
    [ -d "${direct}" ]
    [ "$(git -C "${direct}" rev-parse HEAD)" = "${before}" ]
}

@test "expand_home expands a leading tilde and leaves other paths alone" {
    [ "$(swt_run 'swt::expand_home "~/x"')" = "${HOME}/x" ]
    [ "$(swt_run 'swt::expand_home "~"')" = "${HOME}" ]
    [ "$(swt_run 'swt::expand_home "/abs/p"')" = "/abs/p" ]
    [ "$(swt_run 'swt::expand_home "rel/p"')" = "rel/p" ]
}

@test "create resolves a repo root written with a leading tilde in the allowlist" {
    make_repo
    stub_herdr
    # allowlist の root を "~/<相対パス>" 形式にして、展開されることを確かめる。
    # git は GIT_CONFIG_GLOBAL / GIT_CONFIG_NOSYSTEM で HOME から切り離してあるので、
    # ここで HOME をサンドボックスへ差し替えても副作用はない。
    export HOME="${BATS_TEST_TMPDIR}"
    mkdir -p "${SWT_CONFIG_DIR}"
    rel="${REPO#${HOME}/}"
    [ "${rel}" != "${REPO}" ]
    jq -n --arg origin "${UPSTREAM}" --arg root "~/${rel}" \
        '{version: 1, defaults: {remote: "origin"},
          repos: [{label: "scratch", origin: $origin, root: $root}]}' \
        > "${SWT_CONFIG_DIR}/repos.json"

    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch --branch feat/tilde
    [ "${status}" -eq 0 ]
}

# --- 複数エントリの allowlist ---------------------------------------------

# write_multi_config  実在しない repo を前後に挟んだ 3 エントリの allowlist を書く。
#   実例に架空のリポジトリを使うのは、このリポジトリが公開されており、非公開
#   リポジトリ名をテストへ焼き込めないため（AGENTS.md「公開リポジトリでの参照ポリシー」）。
write_multi_config() {
    mkdir -p "${SWT_CONFIG_DIR}"
    jq -n --arg origin "${UPSTREAM}" --arg root "${REPO}" \
        '{version: 1, defaults: {remote: "origin"},
          repos: [
            {label: "before", origin: "https://github.com/example/before.git", root: "~/ghq/github.com/example/before"},
            {label: "scratch", origin: $origin, root: $root},
            {label: "after",  origin: "git@github.com:example/after.git",      root: "~/ghq/github.com/example/after"}
          ]}' \
        > "${SWT_CONFIG_DIR}/repos.json"
}

@test "match_repo picks the right entry out of several allowlisted repositories" {
    make_repo
    write_multi_config
    run zsh -c "source '${PLUGIN_DIR}/lib/common.zsh'
        allowlist=\"\$(swt::load_allowlist)\"
        swt::match_repo \"\${allowlist}\" '${REPO}' | cut -f3 | jq -r .label"
    [ "${status}" -eq 0 ]
    [ "${output}" = "scratch" ]
}

@test "match_repo rejects a repository that matches none of several entries" {
    make_repo
    write_multi_config
    other="${BATS_TEST_TMPDIR}/other"
    git init -q "${other}"
    git -C "${other}" remote add origin https://github.com/example/unlisted.git

    run zsh -c "source '${PLUGIN_DIR}/lib/common.zsh'
        allowlist=\"\$(swt::load_allowlist)\"
        swt::match_repo \"\${allowlist}\" '${other}'"
    [ "${status}" -ne 0 ]
    [ -z "${output}" ]
}

@test "match_repo accepts an ssh remote against an https entry and the reverse" {
    make_repo
    mkdir -p "${SWT_CONFIG_DIR}"

    ssh_repo="${BATS_TEST_TMPDIR}/ssh-side"
    git init -q "${ssh_repo}"
    git -C "${ssh_repo}" remote add origin ssh://git@github.com/example/mixed.git

    https_repo="${BATS_TEST_TMPDIR}/https-side"
    git init -q "${https_repo}"
    git -C "${https_repo}" remote add origin https://github.com/example/mixed.git

    # 設定は https 表記、リモートは ssh 表記
    echo '{"version":1,"defaults":{"remote":"origin"},"repos":[{"label":"mixed","origin":"https://github.com/example/mixed.git"}]}' \
        > "${SWT_CONFIG_DIR}/repos.json"
    run zsh -c "source '${PLUGIN_DIR}/lib/common.zsh'
        allowlist=\"\$(swt::load_allowlist)\"
        swt::match_repo \"\${allowlist}\" '${ssh_repo}' | cut -f3 | jq -r .label"
    [ "${status}" -eq 0 ]
    [ "${output}" = "mixed" ]

    # 設定は scp 形式、リモートは https 表記
    echo '{"version":1,"defaults":{"remote":"origin"},"repos":[{"label":"mixed","origin":"git@github.com:example/mixed.git"}]}' \
        > "${SWT_CONFIG_DIR}/repos.json"
    run zsh -c "source '${PLUGIN_DIR}/lib/common.zsh'
        allowlist=\"\$(swt::load_allowlist)\"
        swt::match_repo \"\${allowlist}\" '${https_repo}' | cut -f3 | jq -r .label"
    [ "${status}" -eq 0 ]
    [ "${output}" = "mixed" ]
}

@test "repo_root_from_label resolves each label to its own tilde-written root" {
    make_repo
    write_multi_config
    run zsh -c "source '${PLUGIN_DIR}/lib/common.zsh'
        allowlist=\"\$(swt::load_allowlist)\"
        swt::repo_root_from_label \"\${allowlist}\" before
        swt::repo_root_from_label \"\${allowlist}\" after"
    [ "${status}" -eq 0 ]
    [ "${lines[0]}" = "${HOME}/ghq/github.com/example/before" ]
    [ "${lines[1]}" = "${HOME}/ghq/github.com/example/after" ]
}

@test "repo_root_from_label fails on a label that is not in the allowlist" {
    make_repo
    write_multi_config
    run zsh -c "source '${PLUGIN_DIR}/lib/common.zsh'
        allowlist=\"\$(swt::load_allowlist)\"
        swt::repo_root_from_label \"\${allowlist}\" nope"
    [ "${status}" -ne 0 ]
}

@test "create resolves the middle entry of a multi-entry allowlist by label" {
    make_repo
    write_multi_config
    stub_herdr

    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch --branch feat/multi
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"リポジトリ: scratch"* ]]
    [ -d "${STUB_WORKTREE_DIR}/feat-multi" ]
}

# --- H2: linked worktree からの呼び出し -------------------------------------

@test "main_worktree_root returns the parent checkout when called inside a linked worktree" {
    make_repo
    linked="${BATS_TEST_TMPDIR}/linked"
    git -C "${REPO}" worktree add --quiet -b feat/linked "${linked}"

    [ "$(swt_run "swt::git_toplevel '${linked}'")" = "$(abspath "${linked}")" ]
    [ "$(swt_run "swt::main_worktree_root '${linked}'")" = "$(abspath "${REPO}")" ]
    [ "$(swt_run "swt::main_worktree_root '${REPO}'")" = "$(abspath "${REPO}")" ]
}

@test "create normalizes a linked worktree path to the parent checkout" {
    make_repo
    write_config
    stub_herdr
    linked="${BATS_TEST_TMPDIR}/linked"
    git -C "${REPO}" worktree add --quiet -b feat/linked "${linked}"

    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo "${linked}" --branch feat/from-linked
    [ "${status}" -eq 0 ]
    # herdr へ渡した --cwd が親チェックアウトになっている
    grep -q -- "--cwd $(abspath "${REPO}") " "${STUB_HERDR_LOG}"
    run grep -q -- "--cwd $(abspath "${linked}") " "${STUB_HERDR_LOG}"
    [ "${status}" -ne 0 ]
}

@test "marker written from a linked worktree matches the event repo root" {
    make_repo
    write_config
    stub_herdr
    setup_notify_stub
    linked="${BATS_TEST_TMPDIR}/linked"
    git -C "${REPO}" worktree add --quiet -b feat/linked "${linked}"

    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo "${linked}" --branch feat/keyed
    [ "${status}" -eq 0 ]

    # イベント側は常にメイン作業ツリーを repo_root として渡してくる
    run_audit "${STUB_WORKTREE_DIR}/feat-keyed" feat/keyed
    [ "$(last_verdict)" = "plugin_ok" ]
}

# --- M1: pending marker の TTL / 順序 ---------------------------------------

@test "audit ignores a marker that has outlived its ttl and reports a direct creation" {
    make_repo
    write_config
    stub_herdr
    setup_notify_stub
    git -C "${REPO}" fetch -q origin '+refs/heads/v2:refs/remotes/origin/v2'
    git -C "${REPO}" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/v2

    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch --branch feat/stale-marker
    [ "${status}" -eq 0 ]
    [ "$(ls -1 "${SWT_STATE_DIR}/pending" | wc -l | tr -d ' ')" = "1" ]

    # TTL を 0 にすると、直前に書いたマーカーも期限切れ扱いになる
    SWT_PENDING_TTL_SECONDS=-1 run_audit "${STUB_WORKTREE_DIR}/feat-stale-marker" feat/stale-marker
    [[ "$(last_verdict)" == direct_create_* ]]
    # 期限切れマーカーはその場で捨てられる
    [ "$(ls -1 "${SWT_STATE_DIR}/pending" | wc -l | tr -d ' ')" = "0" ]
}

@test "pending_gc drops expired markers and keeps fresh ones" {
    make_repo
    run zsh -c "source '${PLUGIN_DIR}/lib/common.zsh'
        swt::pending_write /a/b feat/fresh sha1 origin/main >/dev/null
        SWT_PENDING_TTL_SECONDS=-1 swt::pending_gc
        ls -1 \"\$(swt::pending_dir)\" | wc -l | tr -d ' '"
    [ "${status}" -eq 0 ]
    [ "${output}" = "0" ]

    run zsh -c "source '${PLUGIN_DIR}/lib/common.zsh'
        swt::pending_write /a/b feat/fresh sha1 origin/main >/dev/null
        swt::pending_gc
        ls -1 \"\$(swt::pending_dir)\" | wc -l | tr -d ' '"
    [ "${output}" = "1" ]
}

@test "create keeps the marker when herdr fails so the event hook can still resolve it" {
    make_repo
    write_config
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    printf '#!/bin/sh\nexit 1\n' > "${BATS_TEST_TMPDIR}/bin/herdr"
    chmod +x "${BATS_TEST_TMPDIR}/bin/herdr"
    export SWT_HERDR_BIN="${BATS_TEST_TMPDIR}/bin/herdr"

    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch --branch feat/failed
    [ "${status}" -eq 1 ]
    # 失敗側がマーカーを消しに行くと、イベントフックが読む前に奪う競合になる。
    # 使われなかったマーカーは TTL で失効させる。
    [ "$(ls -1 "${SWT_STATE_DIR}/pending" | wc -l | tr -d ' ')" = "1" ]
}

# --- M2: worktree open はイベントを発火しない --------------------------------

@test "reuse path writes no pending marker (worktree open does not emit worktree.created)" {
    # 実機確認: herdr 0.8.2 で `herdr worktree open` は worktree.created を発火せず、
    # 監査ログにも plugin log にも現れない。よって --reuse は監査経路に乗らない。
    # 仮に将来のバージョンで発火するようになっても、マーカーが無い以上
    # direct_create_* として鳴る（黙って plugin 経由と誤認するより安全側）。
    make_repo
    write_config
    stub_herdr
    git -C "${REPO}" branch feat/reused

    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch --branch feat/reused --reuse
    [ "${status}" -eq 0 ]
    [ ! -d "${SWT_STATE_DIR}/pending" ] || \
        [ "$(ls -1 "${SWT_STATE_DIR}/pending" | wc -l | tr -d ' ')" = "0" ]
    grep -q "worktree open" "${STUB_HERDR_LOG}"
}

@test "reuse reports already_open from the open response" {
    make_repo
    write_config
    stub_herdr
    git -C "${REPO}" branch feat/reused

    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch --branch feat/reused --reuse
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"開きました"* ]]

    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch --branch feat/reused --reuse
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"既に開いていました"* ]]
}

# --- M3: 正規化できない URL は不一致 ----------------------------------------

@test "origins_match treats an unnormalizable url as a mismatch" {
    # どちらも正規化に失敗する。戻り値を見ずに空文字列同士を比べると一致してしまう
    run swt_run 'swt::origins_match "https://" "https://"'
    [ "${status}" -ne 0 ]
    run swt_run 'swt::origins_match "https://github.com/o/r" "https://"'
    [ "${status}" -ne 0 ]
    run swt_run 'swt::origins_match "https://github.com/o/r" "git@github.com:o/r.git"'
    [ "${status}" -eq 0 ]
}

@test "create refuses a repo whose origin url cannot be normalized" {
    make_repo
    mkdir -p "${SWT_CONFIG_DIR}"
    echo '{"version":1,"defaults":{"remote":"origin"},"repos":[{"label":"broken","origin":"https://"}]}' \
        > "${SWT_CONFIG_DIR}/repos.json"
    stub_herdr

    broken="${BATS_TEST_TMPDIR}/broken"
    git init -q "${broken}"
    git -C "${broken}" remote add origin "https://"

    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo "${broken}" --branch feat/x
    [ "${status}" -eq 3 ]
}

# --- M4: 値なし引数 ---------------------------------------------------------

@test "options that take a value exit 2 instead of looping forever when the value is missing" {
    make_repo
    write_config
    stub_herdr
    for opt in --repo --branch --base --label; do
        run with_limit 10 zsh "${PLUGIN_DIR}/bin/create.zsh" "${opt}"
        [ "${status}" -eq 2 ]
        [[ "${output}" == *"値が必要です"* ]]
    done
}

@test "an option followed by another option is rejected rather than swallowing it" {
    make_repo
    write_config
    stub_herdr
    run with_limit 10 zsh "${PLUGIN_DIR}/bin/create.zsh" --repo --branch feat/x
    [ "${status}" -eq 2 ]
}

# --- 追加採用: remote branch の検出 / base branch 名の検証 --------------------

@test "create refuses when the branch already exists on the remote" {
    make_repo
    write_config
    stub_herdr
    # リモートにだけ存在するブランチを作る（ローカルには置かない）
    git -C "${REPO}" push -q origin "HEAD:refs/heads/feat/remote-only"

    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch --branch feat/remote-only
    [ "${status}" -eq 5 ]
    [[ "${output}" == *"origin/feat/remote-only"* ]]
    [ ! -d "${STUB_WORKTREE_DIR}/feat-remote-only" ]
}

@test "create refuses a remote-existing branch even with --reuse" {
    make_repo
    write_config
    stub_herdr
    git -C "${REPO}" push -q origin "HEAD:refs/heads/feat/remote-only"

    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch --branch feat/remote-only --reuse
    [ "${status}" -eq 5 ]
    [ ! -d "${STUB_WORKTREE_DIR}/feat-remote-only" ]
}

@test "create rejects a malformed branch name in the base" {
    make_repo
    write_config
    stub_herdr
    for bad in "origin/" "origin/.." "origin/a..b" "origin/-x"; do
        run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch --branch feat/x --base "${bad}"
        [ "${status}" -eq 4 ]
    done
}

# --- 監査ログの rotation ----------------------------------------------------

@test "audit log rotates a single generation once it passes the size threshold" {
    make_repo
    mkdir -p "${SWT_STATE_DIR}"
    log="${SWT_STATE_DIR}/audit.jsonl"
    /usr/bin/head -c 200 /dev/zero | tr '\0' 'x' > "${log}"

    run zsh -c "source '${PLUGIN_DIR}/lib/common.zsh'
        SWT_AUDIT_MAX_BYTES=100 swt::rotate_audit_log '${log}'"
    [ "${status}" -eq 0 ]
    [ -f "${log}.1" ]
    [ ! -f "${log}" ]

    # 閾値以下では切り替えない
    printf 'x' > "${log}"
    run zsh -c "source '${PLUGIN_DIR}/lib/common.zsh'
        SWT_AUDIT_MAX_BYTES=100 swt::rotate_audit_log '${log}'"
    [ -f "${log}" ]
}

@test "state_dir is a pure getter and ensure_state_dir is what creates it" {
    export SWT_STATE_DIR="${BATS_TEST_TMPDIR}/not-yet"
    run swt_run 'swt::state_dir'
    [ "${output}" = "${SWT_STATE_DIR}" ]
    [ ! -d "${SWT_STATE_DIR}" ]

    run swt_run 'swt::ensure_state_dir'
    [ "${status}" -eq 0 ]
    [ -d "${SWT_STATE_DIR}" ]
}

@test "audit resolves the repo root itself when the event omits workspace.worktree" {
    # 公式スキーマ上 WorkspaceInfo.worktree は nullable。repo_root が取れないイベントでも
    # チェックアウト先からメイン作業ツリーを引き直して、マーカーと突き合わせられること。
    make_repo
    write_config
    stub_herdr
    setup_notify_stub

    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch --branch feat/nullws
    [ "${status}" -eq 0 ]

    run_audit_no_workspace_worktree "${STUB_WORKTREE_DIR}/feat-nullws" feat/nullws
    [ "$(last_verdict)" = "plugin_ok" ]
    [ "$(tail -n 1 "${SWT_STATE_DIR}/audit.jsonl" | jq -r .repo_root)" = "$(abspath "${REPO}")" ]
}

# --- 指摘 4: リモート問い合わせ失敗は fail-closed ----------------------------

@test "remote_branch_exists distinguishes absent from unreachable" {
    make_repo
    # 存在しない
    run swt_run "swt::remote_branch_exists '${REPO}' origin nope"
    [ "${status}" -eq 1 ]
    # 存在する
    git -C "${REPO}" push -q origin "HEAD:refs/heads/there"
    run swt_run "swt::remote_branch_exists '${REPO}' origin there"
    [ "${status}" -eq 0 ]
    # 問い合わせ自体が失敗する（リモートが消えている）
    rm -rf "${UPSTREAM}"
    run swt_run "swt::remote_branch_exists '${REPO}' origin there"
    [ "${status}" -eq 2 ]
}

@test "create refuses when the remote cannot be queried instead of assuming the branch is free" {
    make_repo
    write_config
    stub_herdr
    # base 解決を通すために先に fetch させてから、リモートを落とす
    git -C "${REPO}" fetch -q origin '+refs/heads/v2:refs/remotes/origin/v2'
    mv "${UPSTREAM}" "${UPSTREAM}.gone"

    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch --branch feat/offline
    [ "${status}" -ne 0 ]
    [ "${status}" -ne 5 ]
    [ ! -d "${STUB_WORKTREE_DIR}/feat-offline" ]
}

# --- 指摘 5: マーカーの後始末を場合分けする ---------------------------------

@test "create drops the marker immediately when herdr rejects the request with a structured error" {
    make_repo
    write_config
    stub_herdr
    export STUB_ERROR_CODE="linked_worktree_source"

    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch --branch feat/rejected
    [ "${status}" -eq 1 ]
    # 要求が拒否された = worktree は作られていない = イベントも飛ばない。競合しないので即消す
    [ "$(ls -1 "${SWT_STATE_DIR}/pending" 2>/dev/null | wc -l | tr -d ' ')" = "0" ]
}

@test "create keeps the marker when the failure shape is unknown" {
    make_repo
    write_config
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    printf '#!/bin/sh\necho "boom" >&2\nexit 3\n' > "${BATS_TEST_TMPDIR}/bin/herdr"
    chmod +x "${BATS_TEST_TMPDIR}/bin/herdr"
    export SWT_HERDR_BIN="${BATS_TEST_TMPDIR}/bin/herdr"

    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch --branch feat/unknown-failure
    [ "${status}" -eq 1 ]
    # 作られたか分からないので TTL に任せる
    [ "$(ls -1 "${SWT_STATE_DIR}/pending" | wc -l | tr -d ' ')" = "1" ]
}

@test "create keeps the marker when the response cannot be parsed" {
    make_repo
    write_config
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    printf '#!/bin/sh\necho "not json"\nexit 0\n' > "${BATS_TEST_TMPDIR}/bin/herdr"
    chmod +x "${BATS_TEST_TMPDIR}/bin/herdr"
    export SWT_HERDR_BIN="${BATS_TEST_TMPDIR}/bin/herdr"

    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch --branch feat/unparsable
    [ "${status}" -eq 1 ]
    [ "$(ls -1 "${SWT_STATE_DIR}/pending" | wc -l | tr -d ' ')" = "1" ]
}

# --- 指摘 6: --help の出力範囲 ----------------------------------------------

@test "--help prints the whole header comment and stops at the first code line" {
    run zsh "${PLUGIN_DIR}/bin/create.zsh" --help
    [ "${status}" -eq 0 ]
    # 先頭付近と末尾付近の両方が出ている（行番号決め打ちだと片方が落ちる）
    [[ "${output}" == *"allowlist 済みリポジトリ"* ]]
    [[ "${output}" == *"終了コード"* ]]
    # コード行は混ざらない
    [[ "${output}" != *"set -u"* ]]
    [[ "${output}" != *"SWT_ROOT="* ]]
}

# --- 作成後照合の失敗 (exit 6) ----------------------------------------------

@test "create reports a verification failure when the worktree lands on a different commit" {
    make_repo
    write_config
    stub_herdr
    advance_remote
    # 要求した base（リモート先端）ではなく 1 つ前で作られる状況を作る
    stale="$(git -C "${REPO}" rev-parse v2)"
    export STUB_CREATE_AT="${stale}"

    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch --branch feat/mismatch
    [ "${status}" -eq 6 ]
    [[ "${output}" == *"作成結果が期待と一致しません"* ]]
    # 照合に失敗しても worktree は消さない（削除・自動修復はしない）
    [ -d "${STUB_WORKTREE_DIR}/feat-mismatch" ]
}

# --- 残りの verdict ---------------------------------------------------------

@test "audit records a direct creation that sits exactly on the known remote tip" {
    make_repo
    write_config
    setup_notify_stub
    git -C "${REPO}" fetch -q origin '+refs/heads/v2:refs/remotes/origin/v2'
    git -C "${REPO}" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/v2

    direct="${BATS_TEST_TMPDIR}/direct"
    git -C "${REPO}" worktree add --quiet -b feat/at-tip "${direct}" refs/remotes/origin/v2

    run_audit "${direct}" feat/at-tip
    [ "$(last_verdict)" = "direct_create_at_known_tip" ]
}

@test "audit reports unverified when the remote head has never been fetched" {
    make_repo
    write_config
    setup_notify_stub
    # refs/remotes/origin/HEAD を一度も作っていない状態

    direct="${BATS_TEST_TMPDIR}/direct"
    git -C "${REPO}" worktree add --quiet -b feat/unverified "${direct}"

    run_audit "${direct}" feat/unverified
    [ "$(last_verdict)" = "direct_create_unverified" ]
}

@test "audit records a creation in a repository outside the allowlist without notifying" {
    make_repo
    write_config
    setup_notify_stub
    # allowlist に無いリポジトリを別に用意する
    other="${BATS_TEST_TMPDIR}/other"
    git init -q -b main "${other}"
    git -C "${other}" config user.email t@e.st
    git -C "${other}" config user.name test
    git -C "${other}" commit -q --allow-empty -m first
    git -C "${other}" remote add origin https://github.com/example/unlisted.git

    HERDR_PLUGIN_EVENT_JSON="$(jq -n --arg repo "${other}" --arg co "${other}" \
        '{data: {workspace: {workspace_id: "w1", worktree: {repo_root: $repo}},
                 worktree: {path: $co, branch: "main"}}}')" \
        SWT_HERDR_BIN="${BATS_TEST_TMPDIR}/bin/true-stub" \
        zsh "${PLUGIN_DIR}/bin/audit-created.zsh"

    [ "$(tail -n 1 "${SWT_STATE_DIR}/audit.jsonl" | jq -r .allowlisted)" = "false" ]
    # 監査ログには残すが通知はしない（管理対象外のリポジトリで作るたびに鳴らすと、
    # 通知そのものが読まれなくなる）
    [ "$(notify_count)" = "0" ]
}

# --- 設定欠落 / 非対話 ------------------------------------------------------

@test "create exits 2 when the tracked allowlist has not been placed yet" {
    make_repo
    stub_herdr
    # repos.json を置かないまま実行する
    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch --branch feat/x
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"herdr-sync.zsh"* ]]
}

@test "create exits 2 rather than prompting when no branch is given without a tty" {
    make_repo
    write_config
    stub_herdr
    run with_limit 10 zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch < /dev/null
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"--branch が必要です"* ]]
}

@test "create runs to completion without a tty and never waits for confirmation" {
    make_repo
    write_config
    stub_herdr
    # --yes を付けずとも、TTY が無ければ確認プロンプトには入らない
    run with_limit 20 zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch --branch feat/noninteractive < /dev/null
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"作成しますか"* ]]
    [[ "${output}" != *"Enter で閉じます"* ]]
    [ -d "${STUB_WORKTREE_DIR}/feat-noninteractive" ]
}

# --- popup を開くアクション -------------------------------------------------

@test "the action entrypoint opens the create pane through herdr" {
    stub_herdr
    HERDR_PLUGIN_ID=dotfiles.safe-worktree \
        run zsh "${PLUGIN_DIR}/bin/open-create-pane.zsh"
    [ "${status}" -eq 0 ]
    grep -q "plugin pane open --plugin dotfiles.safe-worktree --entrypoint create" "${STUB_HERDR_LOG}"
}

# --- state dir が使えないときの fail-fast ------------------------------------

@test "ensure_state_dir and pending_write report failure instead of succeeding silently" {
    LOCKED_DIR="${BATS_TEST_TMPDIR}/locked"
    mkdir -p "${LOCKED_DIR}"
    chmod u-w "${LOCKED_DIR}"

    run zsh -c "source '${PLUGIN_DIR}/lib/common.zsh'
        SWT_STATE_DIR='${LOCKED_DIR}/state' swt::ensure_state_dir"
    [ "${status}" -ne 0 ]

    run zsh -c "source '${PLUGIN_DIR}/lib/common.zsh'
        SWT_STATE_DIR='${LOCKED_DIR}/state' swt::pending_write /a/b feat/x sha origin/main"
    [ "${status}" -ne 0 ]
}

@test "pending_write fails when the marker itself cannot be written" {
    LOCKED_DIR="${BATS_TEST_TMPDIR}/state-ro"
    mkdir -p "${LOCKED_DIR}/pending"
    chmod u-w "${LOCKED_DIR}/pending"

    run zsh -c "source '${PLUGIN_DIR}/lib/common.zsh'
        SWT_STATE_DIR='${LOCKED_DIR}' swt::pending_write /a/b feat/x sha origin/main"
    [ "${status}" -ne 0 ]
    chmod u+w "${LOCKED_DIR}/pending"
    [ "$(ls -1 "${LOCKED_DIR}/pending" | wc -l | tr -d ' ')" = "0" ]
    LOCKED_DIR=""
}

@test "create fails before touching the repository when the state dir is not writable" {
    make_repo
    write_config
    stub_herdr

    LOCKED_DIR="${BATS_TEST_TMPDIR}/locked-state"
    mkdir -p "${LOCKED_DIR}"
    chmod u-w "${LOCKED_DIR}"
    export SWT_STATE_DIR="${LOCKED_DIR}/state"

    run zsh "${PLUGIN_DIR}/bin/create.zsh" --repo scratch --branch feat/no-state
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"監査マーカー"* || "${output}" == *"状態ディレクトリ"* ]]
    # worktree もブランチも作られていない
    [ ! -d "${STUB_WORKTREE_DIR}/feat-no-state" ]
    run git -C "${REPO}" show-ref --verify --quiet "refs/heads/feat/no-state"
    [ "${status}" -ne 0 ]
    # herdr は一度も呼ばれていない
    run grep -q "worktree create" "${STUB_HERDR_LOG}"
    [ "${status}" -ne 0 ]
}

@test "audit exits quietly and writes nothing when the state dir cannot be created" {
    make_repo
    write_config
    setup_notify_stub

    LOCKED_DIR="${BATS_TEST_TMPDIR}/locked-audit"
    mkdir -p "${LOCKED_DIR}"
    chmod u-w "${LOCKED_DIR}"
    export SWT_STATE_DIR="${LOCKED_DIR}/state"

    direct="${BATS_TEST_TMPDIR}/direct"
    git -C "${REPO}" worktree add --quiet -b feat/no-audit-state "${direct}"

    run run_audit "${direct}" feat/no-audit-state
    [ "${status}" -eq 0 ]
    # state_dir が空のまま "/audit.jsonl" を書きに行っていないこと
    [ ! -e "/audit.jsonl" ]
    [ ! -e "${SWT_STATE_DIR}" ]
    [ "$(notify_count)" = "0" ]
    # 監査できなくても worktree はそのまま
    [ -d "${direct}" ]
}
