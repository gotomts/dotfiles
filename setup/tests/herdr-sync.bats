#!/usr/bin/env bats
# setup/tests/herdr-sync.bats
#
# 実際の herdr は呼ばない。HOMEBREW_PATH_PREFIX_OVERRIDE で PATH の先頭を
# スタブディレクトリに差し替え、herdr-sync.zsh から見える `herdr` を偽物にする
# （util::ensure_homebrew_path が /opt/homebrew/bin を先頭に足すため、
# PATH に足すだけでは本物が優先されてしまう）。

SETUP_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
REPO_ROOT="$(cd "${SETUP_DIR}/.." && pwd)"
PLUGIN_SRC="${REPO_ROOT}/herdr/plugins/safe-worktree"

setup() {
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}"
    STUB_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${STUB_BIN}"
    export HERDR_STUB_LOG="${BATS_TEST_TMPDIR}/herdr.log"
    CONFIG_DIR="${HOME}/.config/herdr/plugins/config/dotfiles.safe-worktree"
    # 本物のチェックアウトを primary として扱う（primary 以外からの実行は
    # link も設定配置もしないため、既定のままでは全テストが skip 経路に入る）
    export DOTFILES_PRIMARY_ROOT="${REPO_ROOT}"
}

# stub_herdr <registered_plugin_root>
#   引数が空なら「未登録」を返すスタブ、非空ならそのパスで登録済みを返すスタブを置く。
stub_herdr() {
    local registered="${1:-}"
    cat > "${STUB_BIN}/herdr" <<STUB
#!/bin/zsh
print -r -- "\$*" >> "${HERDR_STUB_LOG}"
case "\${1} \${2}" in
    "plugin config-dir") print -r -- "${CONFIG_DIR}" ;;
    "plugin list")
        if [[ -n "${registered}" ]]; then
            jq -n --arg root "${registered}" \\
                '{result: {plugins: [{plugin_id: "dotfiles.safe-worktree", plugin_root: \$root}]}}'
        else
            print -r -- '{"result": {"plugins": []}}'
        fi
        ;;
    *) : ;;
esac
exit 0
STUB
    chmod +x "${STUB_BIN}/herdr"
    # 2 系統ふさぐ。util::ensure_homebrew_path を通る herdr-sync.zsh 本体は
    # HOMEBREW_PATH_PREFIX_OVERRIDE で、lib/herdr.zsh だけを source する
    # 直接呼び出しは PATH 先頭で。どちらか一方だと実 herdr に届く経路が残る
    # （実際に初版のテストが実 herdr へ `plugin link` を発行した）。
    export HOMEBREW_PATH_PREFIX_OVERRIDE="${STUB_BIN}"
    export PATH="${STUB_BIN}:${PATH}"
}

# assert_no_real_herdr  実 herdr のパスがテストから見えていないこと
assert_no_real_herdr() {
    [ "$(command -v herdr)" = "${STUB_BIN}/herdr" ]
}

# jq はスタブディレクトリ経由では見えないため、PATH 上の本物をそのまま使う
# （HOMEBREW_PATH_PREFIX_OVERRIDE は先頭に足すだけで既存 PATH を消さない）

@test "zsh -n syntax check passes" {
    run zsh -n "${SETUP_DIR}/herdr-sync.zsh"
    [ "${status}" -eq 0 ]
}

@test "links the plugin when it is not registered yet" {
    stub_herdr ""
    run zsh "${SETUP_DIR}/herdr-sync.zsh"
    [ "${status}" -eq 0 ]
    grep -q "plugin link ${PLUGIN_SRC}" "${HERDR_STUB_LOG}"
}

@test "does not relink when the registered path already matches" {
    stub_herdr "${PLUGIN_SRC}"
    run zsh "${SETUP_DIR}/herdr-sync.zsh"
    [ "${status}" -eq 0 ]
    run grep -q "plugin link" "${HERDR_STUB_LOG}"
    [ "${status}" -ne 0 ]
    [[ "${output}" != *"plugin unlink"* ]]
}

@test "relinks when the plugin is registered from a different path" {
    stub_herdr "${BATS_TEST_TMPDIR}/somewhere-else"
    run zsh "${SETUP_DIR}/herdr-sync.zsh"
    [ "${status}" -eq 0 ]
    grep -q "plugin unlink dotfiles.safe-worktree" "${HERDR_STUB_LOG}"
    grep -q "plugin link ${PLUGIN_SRC}" "${HERDR_STUB_LOG}"
}

@test "symlinks the tracked allowlist into the plugin config directory" {
    stub_herdr ""
    run zsh "${SETUP_DIR}/herdr-sync.zsh"
    [ "${status}" -eq 0 ]
    [ -L "${CONFIG_DIR}/repos.json" ]
    [ "$(readlink "${CONFIG_DIR}/repos.json")" = "${PLUGIN_SRC}/config/repos.json" ]
}

@test "seeds the machine-local allowlist only when absent" {
    stub_herdr ""
    run zsh "${SETUP_DIR}/herdr-sync.zsh"
    [ "${status}" -eq 0 ]
    run jq -e '.repos == []' "${CONFIG_DIR}/repos.local.json"
    [ "${status}" -eq 0 ]

    echo '{"version":1,"repos":[{"label":"mine","origin":"https://example.com/o/r"}]}' \
        > "${CONFIG_DIR}/repos.local.json"
    run zsh "${SETUP_DIR}/herdr-sync.zsh"
    [ "${status}" -eq 0 ]
    run jq -r '.repos[0].label' "${CONFIG_DIR}/repos.local.json"
    [ "${output}" = "mine" ]
}

@test "stays fail-open and still places the allowlist when herdr is missing" {
    # herdr だけが居ない PATH を作る。jq は Homebrew prefix にあり、そこには herdr も
    # 居るため、ディレクトリごと通すのではなく必要な実行体だけを symlink する。
    minimal="${BATS_TEST_TMPDIR}/minimal-bin"
    mkdir -p "${minimal}"
    ln -s "$(command -v jq)" "${minimal}/jq"
    export HOMEBREW_PATH_PREFIX_OVERRIDE="${minimal}"

    run env PATH="${minimal}:/usr/bin:/bin" zsh "${SETUP_DIR}/herdr-sync.zsh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"herdr CLI 未インストール"* ]]
    [ -L "${CONFIG_DIR}/repos.json" ]
}

@test "migrate.zsh runs herdr-sync as part of phase 3" {
    grep -q 'PHASE3_STEPS=(languages defaults claude-sync codex-sync herdr-sync)' \
        "${SETUP_DIR}/migrate.zsh"
}

@test "migrate health check verifies the allowlist symlink" {
    grep -q 'herdr-sync: .* が symlink ではありません' "${SETUP_DIR}/migrate.zsh"
}

# --- primary チェックアウト以外からの実行 (H1) ------------------------------

@test "skips both link and config placement when run from a non-primary checkout" {
    stub_herdr ""
    # primary を実在する別ディレクトリに向け、リポジトリ自身を非 primary にする
    export DOTFILES_PRIMARY_ROOT="${BATS_TEST_TMPDIR}/elsewhere"
    mkdir -p "${DOTFILES_PRIMARY_ROOT}"

    run zsh "${SETUP_DIR}/herdr-sync.zsh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"primary チェックアウト以外"* ]]

    # plugin を登録していない
    run grep -q "plugin link" "${HERDR_STUB_LOG}"
    [ "${status}" -ne 0 ]
    # 設定も置いていない（片方だけ実行して不整合を残さない）
    [ ! -e "${CONFIG_DIR}/repos.json" ]
    [ ! -e "${CONFIG_DIR}/repos.local.json" ]
}

@test "skips when the primary checkout does not exist at all" {
    stub_herdr ""
    export DOTFILES_PRIMARY_ROOT="${BATS_TEST_TMPDIR}/missing"

    run zsh "${SETUP_DIR}/herdr-sync.zsh"
    [ "${status}" -eq 0 ]
    [ ! -e "${CONFIG_DIR}/repos.json" ]
}

@test "relinks a plugin that is registered from a disposable worktree path" {
    # 使い捨て worktree のパスで登録済みの状態から、primary へ張り替わること
    stub_herdr "${BATS_TEST_TMPDIR}/herdr-worktrees/.dotfiles/feat-x/herdr/plugins/safe-worktree"
    run zsh "${SETUP_DIR}/herdr-sync.zsh"
    [ "${status}" -eq 0 ]
    grep -q "plugin unlink dotfiles.safe-worktree" "${HERDR_STUB_LOG}"
    grep -q "plugin link ${PLUGIN_SRC}" "${HERDR_STUB_LOG}"
}

# --- health check とパス解決の共有 (H3) -------------------------------------

@test "migrate health check resolves the allowlist path through setup/lib/herdr.zsh" {
    grep -q 'herdr::allowlist_link' "${SETUP_DIR}/migrate.zsh"
    run grep -q "\.config/herdr/plugins/config/dotfiles.safe-worktree/repos.json" "${SETUP_DIR}/migrate.zsh"
    [ "${status}" -ne 0 ]
}

@test "herdr-sync and the health check agree on the allowlist path" {
    stub_herdr ""
    assert_no_real_herdr
    run zsh "${SETUP_DIR}/herdr-sync.zsh"
    [ "${status}" -eq 0 ]

    run zsh -c "source '${SETUP_DIR}/lib/util.zsh'
        source '${SETUP_DIR}/lib/herdr.zsh'
        herdr::allowlist_link '${HOME}'"
    [ "${status}" -eq 0 ]
    [ -L "${output}" ]
    [ "${output}" = "${CONFIG_DIR}/repos.json" ]
}

@test "plugin config dir falls back to the given home when herdr is unavailable" {
    minimal="${BATS_TEST_TMPDIR}/minimal-bin"
    mkdir -p "${minimal}"
    run env PATH="${minimal}:/usr/bin:/bin" zsh -c "source '${SETUP_DIR}/lib/util.zsh'
        source '${SETUP_DIR}/lib/herdr.zsh'
        herdr::allowlist_link '/tmp/other-home'"
    [ "${status}" -eq 0 ]
    [ "${output}" = "/tmp/other-home/.config/herdr/plugins/config/dotfiles.safe-worktree/repos.json" ]
}

@test "repos.local.json inside the repository is gitignored" {
    run git -C "${REPO_ROOT}" check-ignore -q "herdr/plugins/safe-worktree/config/repos.local.json"
    [ "${status}" -eq 0 ]
}

# --- 別ユーザーの home を対象にした解決 (指摘 1) ------------------------------

@test "plugin config dir does not consult herdr when resolving another user's home" {
    stub_herdr ""
    assert_no_real_herdr
    # スタブは常に「呼ばれた側の」設定ディレクトリを返す。別ユーザーの home を
    # 渡したときにそれを採用してしまうと、root で走る health check が root 自身の
    # 設定ディレクトリを検査してしまう。
    run zsh -c "source '${SETUP_DIR}/lib/util.zsh'
        source '${SETUP_DIR}/lib/herdr.zsh'
        herdr::allowlist_link '/Users/someone-else'"
    [ "${status}" -eq 0 ]
    [ "${output}" = "/Users/someone-else/.config/herdr/plugins/config/dotfiles.safe-worktree/repos.json" ]
    # herdr は一度も呼ばれていない
    [ ! -s "${HERDR_STUB_LOG}" ]
}

@test "plugin config dir does consult herdr for the caller's own home" {
    stub_herdr ""
    assert_no_real_herdr
    run zsh -c "source '${SETUP_DIR}/lib/util.zsh'
        source '${SETUP_DIR}/lib/herdr.zsh'
        herdr::plugin_config_dir '${HOME}'"
    [ "${status}" -eq 0 ]
    [ "${output}" = "${CONFIG_DIR}" ]
    grep -q "plugin config-dir dotfiles.safe-worktree" "${HERDR_STUB_LOG}"
}

# --- primary 条件を health check と揃える (指摘 2) ---------------------------

@test "migrate health check gates the allowlist requirement on the primary condition only" {
    grep -q 'herdr::is_primary_root "${dotfiles_root}" "${home_dir}"' "${SETUP_DIR}/migrate.zsh"
    # herdr の有無では gate しない。herdr が無くても herdr-sync.zsh は allowlist を
    # 配置して成功するので、そこで飛ばすと「配置されているのに検証しない」死角になる
    run grep -q 'migrate::command_available herdr' "${SETUP_DIR}/migrate.zsh"
    [ "${status}" -ne 0 ]
}

@test "herdr-sync still places the allowlist when herdr is missing, so the check must not skip" {
    minimal="${BATS_TEST_TMPDIR}/minimal-bin"
    mkdir -p "${minimal}"
    ln -s "$(command -v jq)" "${minimal}/jq"
    export HOMEBREW_PATH_PREFIX_OVERRIDE="${minimal}"

    run env PATH="${minimal}:/usr/bin:/bin" zsh "${SETUP_DIR}/herdr-sync.zsh"
    [ "${status}" -eq 0 ]
    [ -L "${CONFIG_DIR}/repos.json" ]

    # health check が見に行くパスと一致していること（herdr 不在でも検証対象になる）
    run env PATH="${minimal}:/usr/bin:/bin" zsh -c "source '${SETUP_DIR}/lib/util.zsh'
        source '${SETUP_DIR}/lib/herdr.zsh'
        herdr::allowlist_link '${HOME}'"
    [ "${output}" = "${CONFIG_DIR}/repos.json" ]
    [ -L "${output}" ]
}

@test "is_primary_root honours an explicitly passed home directory" {
    unset DOTFILES_PRIMARY_ROOT
    other_home="${BATS_TEST_TMPDIR}/other-home"
    mkdir -p "${other_home}/.dotfiles"

    run zsh -c "unset DOTFILES_PRIMARY_ROOT
        source '${SETUP_DIR}/lib/util.zsh'
        source '${SETUP_DIR}/lib/herdr.zsh'
        herdr::is_primary_root '${other_home}/.dotfiles' '${other_home}'"
    [ "${status}" -eq 0 ]

    run zsh -c "unset DOTFILES_PRIMARY_ROOT
        source '${SETUP_DIR}/lib/util.zsh'
        source '${SETUP_DIR}/lib/herdr.zsh'
        herdr::is_primary_root '${REPO_ROOT}' '${other_home}'"
    [ "${status}" -ne 0 ]
}
