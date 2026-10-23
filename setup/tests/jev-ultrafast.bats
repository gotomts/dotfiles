#!/usr/bin/env bats
# setup/tests/jev-ultrafast.bats
#
# サンドボックス統合テスト。実ネットワーク・実 uv には触れない: `uv` を PATH 上のスタブに
# 差し替え、uv tool install が venv に残す成果物（PEP 610 の direct_url.json と python）だけを
# 模して置く。

SETUP_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

# uv の契約のうち、このスクリプトが依存する部分だけを模す: `uv tool install ... <req>` は
# UV_TOOL_DIR/<tool>/ に venv を作り、requirement の @<rev> を direct_url.json に記録する。
_install_uv_stub() {
    cat > "${STUB_BIN}/uv" <<'EOF'
#!/bin/bash
echo "argv:$* UV_TOOL_DIR=${UV_TOOL_DIR:-} UV_TOOL_BIN_DIR=${UV_TOOL_BIN_DIR:-}" >> "${UV_LOG}"
[[ "${UV_EXIT:-0}" == "0" ]] || exit "${UV_EXIT}"
if [[ "$1 $2" == "tool install" ]]; then
    req="${@: -1}"
    rev="${UV_INSTALL_REV_OVERRIDE:-${req##*@}}"
    venv="${UV_TOOL_DIR}/jev-ultrafast"
    site="${venv}/lib/python3.14/site-packages/jev_ultrafast-0.1.0.dist-info"
    rm -rf "${venv}"
    mkdir -p "${site}" "${venv}/bin" "${UV_TOOL_BIN_DIR}"
    printf '{"url":"x","vcs_info":{"vcs":"git","commit_id":"%s"}}' "${rev}" > "${site}/direct_url.json"
    printf '#!/bin/sh\nexit 0\n' > "${venv}/bin/python"
    chmod +x "${venv}/bin/python"
fi
exit 0
EOF
    chmod +x "${STUB_BIN}/uv"
}

# _preinstall <rev>  導入済みの PC を模す
_preinstall() {
    local site="${HOME}/.local/share/uv/tools/jev-ultrafast/lib/python3.14/site-packages/jev_ultrafast-0.1.0.dist-info"
    mkdir -p "${site}" "${HOME}/.local/share/uv/tools/jev-ultrafast/bin"
    printf '{"url":"x","vcs_info":{"vcs":"git","commit_id":"%s"}}' "${1}" > "${site}/direct_url.json"
    printf '#!/bin/sh\nexit 0\n' > "${HOME}/.local/share/uv/tools/jev-ultrafast/bin/python"
    chmod +x "${HOME}/.local/share/uv/tools/jev-ultrafast/bin/python"
}

setup() {
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}"
    STUB_BIN="${BATS_TEST_TMPDIR}/stub-bin"
    mkdir -p "${STUB_BIN}"
    export UV_LOG="${BATS_TEST_TMPDIR}/uv.log"
    : > "${UV_LOG}"
    _install_uv_stub
    export PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"
    # util::ensure_homebrew_path が実機の /opt/homebrew/bin（実 uv）を前置しないようにする。
    export HOMEBREW_PATH_PREFIX_OVERRIDE="${STUB_BIN}"
    # 宣言はスクリプトが読むのと同じ場所から 1 回だけ読む（ここで値を書き写すと次の bump で
    # ずれる）。
    EXPECTED_REV="$(zsh -c "source '${SETUP_DIR}/lib/jev-ultrafast.zsh'; echo \${JEV_ULTRAFAST_REV}")"
    EXPECTED_REQ="$(zsh -c "source '${SETUP_DIR}/lib/jev-ultrafast.zsh'; jev_ultrafast::requirement")"
}

@test "zsh -n syntax check passes" {
    run zsh -n "${SETUP_DIR}/jev-ultrafast.zsh"
    [ "${status}" -eq 0 ]
}

@test "declares a full commit SHA from the upstream repository, not a moving branch" {
    [[ "${EXPECTED_REV}" =~ ^[0-9a-f]{40}$ ]]
    [ "${EXPECTED_REQ}" = "git+https://github.com/browser-use/jev-ultrafast@${EXPECTED_REV}" ]
}

@test "installs the pinned revision into the declared user-scope tool dir" {
    run zsh "${SETUP_DIR}/jev-ultrafast.zsh"
    [ "${status}" -eq 0 ]
    run cat "${UV_LOG}"
    [[ "${output}" == *"argv:tool install ${EXPECTED_REQ} "* ]]
    [[ "${output}" == *"UV_TOOL_DIR=${HOME}/.local/share/uv/tools "* ]]
    [[ "${output}" == *"UV_TOOL_BIN_DIR=${HOME}/.local/bin"* ]]
    [ -x "${HOME}/.local/share/uv/tools/jev-ultrafast/bin/python" ]
}

@test "never overwrites other tools' executables or touches the browser-use tool" {
    # --force は他 tool が所有する同名の実行ファイルを上書きする。uninstall/upgrade は
    # jev-ultrafast 以外の tool を巻き込み得る。どちらも呼ばないことを固定する。
    _preinstall "0000000000000000000000000000000000000000"
    run zsh "${SETUP_DIR}/jev-ultrafast.zsh"
    [ "${status}" -eq 0 ]
    [ -s "${UV_LOG}" ]
    run cat "${UV_LOG}"
    [[ "${output}" != *"--force"* ]]
    # uv の呼び出しは 1 行残らず「jev-ultrafast の requirement を install する」だけ
    run grep -cvF "argv:tool install --reinstall ${EXPECTED_REQ} " "${UV_LOG}"
    [ "${output}" -eq 0 ]
}

@test "does not call uv when the declared revision is already installed (idempotent)" {
    _preinstall "${EXPECTED_REV}"
    run zsh "${SETUP_DIR}/jev-ultrafast.zsh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"SKIP"* ]]
    [ ! -s "${UV_LOG}" ]
}

@test "converges an older installed revision to the declared one" {
    _preinstall "0000000000000000000000000000000000000000"
    run zsh "${SETUP_DIR}/jev-ultrafast.zsh"
    [ "${status}" -eq 0 ]
    run cat "${UV_LOG}"
    [[ "${output}" == *"argv:tool install --reinstall ${EXPECTED_REQ} "* ]]
    run zsh -c "source '${SETUP_DIR}/lib/jev-ultrafast.zsh'; jev_ultrafast::installed_rev '${HOME}'"
    [ "${output}" = "${EXPECTED_REV}" ]
}

@test "creates the dedicated browser profile and harness home owner-only" {
    run zsh "${SETUP_DIR}/jev-ultrafast.zsh"
    [ "${status}" -eq 0 ]
    for dir in "${HOME}/.local/state/jev-ultrafast" \
               "${HOME}/.local/state/jev-ultrafast/chrome-profile" \
               "${HOME}/.local/state/jev-ultrafast/browser-harness"; do
        [ -d "${dir}" ]
        [ "$(stat -f '%Lp' "${dir}")" = "700" ]
    done
}

@test "fails when uv is not available" {
    export HOMEBREW_PATH_PREFIX_OVERRIDE="${BATS_TEST_TMPDIR}/empty"
    mkdir -p "${HOMEBREW_PATH_PREFIX_OVERRIDE}"
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" run zsh "${SETUP_DIR}/jev-ultrafast.zsh"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"uv"* ]]
}

@test "fails when uv tool install fails" {
    UV_EXIT=2 run zsh "${SETUP_DIR}/jev-ultrafast.zsh"
    [ "${status}" -eq 1 ]
}

@test "fails when the installed revision still differs after install" {
    UV_INSTALL_REV_OVERRIDE="1111111111111111111111111111111111111111" run zsh "${SETUP_DIR}/jev-ultrafast.zsh"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"1111111111111111111111111111111111111111"* ]]
}

@test "never reads the API keys" {
    # 秘密は実行時に CLI が環境変数として受け取るだけで、導入スクリプトの責務外。
    run bash -c "grep -vE '^[[:space:]]*#' '${SETUP_DIR}/jev-ultrafast.zsh' | grep -cE 'TYPESAFE_API_KEY|TEXT_MODEL_API_KEY'"
    [ "${status}" -eq 1 ]
    [ "${output}" -eq 0 ]
}
