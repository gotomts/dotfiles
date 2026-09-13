#!/usr/bin/env bats
# setup/tests/notion.bats
#
# サンドボックス統合テスト。実ネットワーク・実インストーラには一切触れない:
# `curl` を PATH 上のスタブに差し替え、インストーラ本体もスタブが生成する
# （ntn の実バイナリを落とさない）。

SETUP_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

# 公式インストーラの契約のうち、このスクリプトが依存する部分だけを模したスタブを
# curl の出力として書き出す: NTN_INSTALL_DIR へ ntn を置く。
_install_curl_stub() {
    cat > "${STUB_BIN}/curl" <<'EOF'
#!/bin/bash
echo "$*" >> "${CURL_LOG}"
if [[ "${CURL_EXIT:-0}" != "0" ]]; then
    exit "${CURL_EXIT}"
fi
out=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        *)  shift ;;
    esac
done
cat > "${out}" <<'INSTALLER'
#!/usr/bin/env bash
set -euo pipefail
echo "${NTN_VERSION:-<unset>}" > "${NTN_VERSION_LOG}"
mkdir -p "${NTN_INSTALL_DIR}"
# 実インストーラと同じく、要求された版を報告するバイナリを置く。
printf '#!/bin/sh\necho "ntn %s"\n' "${NTN_VERSION}" > "${NTN_INSTALL_DIR}/ntn"
chmod +x "${NTN_INSTALL_DIR}/ntn"
INSTALLER
exit 0
EOF
    chmod +x "${STUB_BIN}/curl"
}

setup() {
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}"
    STUB_BIN="${BATS_TEST_TMPDIR}/stub-bin"
    mkdir -p "${STUB_BIN}"
    export CURL_LOG="${BATS_TEST_TMPDIR}/curl.log"
    export NTN_VERSION_LOG="${BATS_TEST_TMPDIR}/ntn-version.log"
    : > "${CURL_LOG}"
    : > "${NTN_VERSION_LOG}"
    _install_curl_stub
    export PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"
    export NTN_INSTALLER_URL="https://example.invalid/install.sh"
    # The single declaration of the pinned version, read from where notion.zsh
    # reads it. Hardcoding it here would let the two drift on the next bump.
    NTN_EXPECTED_VERSION="$(zsh -c "source '${SETUP_DIR}/lib/notion.zsh'; echo \${NTN_PINNED_VERSION}")"
}

@test "zsh -n syntax check passes" {
    run zsh -n "${SETUP_DIR}/notion.zsh"
    [ "${status}" -eq 0 ]
}

@test "installs ntn into ~/.local/bin when absent" {
    run zsh "${SETUP_DIR}/notion.zsh"
    [ "${status}" -eq 0 ]
    [ -x "${HOME}/.local/bin/ntn" ]
    run cat "${CURL_LOG}"
    [[ "${output}" == *"https://example.invalid/install.sh"* ]]
}

@test "pins the installer's destination to ~/.local/bin via NTN_INSTALL_DIR" {
    # インストーラ既定の導入先選択は PATH の現状に依存して揺れるため、宣言側で
    # 固定していることを実効果（置かれた場所）で確認する。
    run zsh "${SETUP_DIR}/notion.zsh"
    [ "${status}" -eq 0 ]
    [ -x "${HOME}/.local/bin/ntn" ]
    [ ! -e "${HOME}/bin/ntn" ]
}

@test "does not invoke the installer when ntn is already executable (idempotent)" {
    mkdir -p "${HOME}/.local/bin"
    printf '#!/bin/sh\necho "ntn 9.9.9-preexisting"\n' > "${HOME}/.local/bin/ntn"
    chmod +x "${HOME}/.local/bin/ntn"

    run zsh "${SETUP_DIR}/notion.zsh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"SKIP"* ]]
    # curl は一度も呼ばれない = 既存バイナリを上書きしない
    [ ! -s "${CURL_LOG}" ]
    run "${HOME}/.local/bin/ntn"
    [[ "${output}" == *"9.9.9-preexisting"* ]]
}

@test "fails when the installer download fails (no silent success from an empty script)" {
    CURL_EXIT=22 run zsh "${SETUP_DIR}/notion.zsh"
    [ "${status}" -eq 1 ]
    [ ! -e "${HOME}/.local/bin/ntn" ]
}

@test "fails when the installer exits 0 without producing the binary" {
    cat > "${STUB_BIN}/curl" <<'EOF'
#!/bin/bash
out=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        *)  shift ;;
    esac
done
printf '#!/usr/bin/env bash\nexit 0\n' > "${out}"
exit 0
EOF
    chmod +x "${STUB_BIN}/curl"

    run zsh "${SETUP_DIR}/notion.zsh"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"実行可能になっていません"* ]]
}

@test "never reads or writes a Notion token" {
    # 認証情報はこのスクリプトの責務外。コメントでの言及は許すが、実行される行に
    # トークン参照や認証コマンドが現れないことを固定する（漏洩経路を作らせない）。
    run bash -c "grep -vE '^[[:space:]]*#' '${SETUP_DIR}/notion.zsh' | grep -cE 'NOTION_API_KEY|NOTION_TOKEN|ntn (auth|login)'"
    [ "${status}" -eq 1 ]
    [ "${output}" -eq 0 ]
}

@test "pins the installed version instead of letting the installer pick latest" {
    # latest のままだと「導入した日」で版が決まり PC ごとに別物が入る。宣言側の
    # NTN_PINNED_VERSION がそのまま NTN_VERSION としてインストーラに届くことを、
    # インストーラ側が観測した値で確認する。
    [ -n "${NTN_EXPECTED_VERSION}" ]
    run zsh "${SETUP_DIR}/notion.zsh"
    [ "${status}" -eq 0 ]
    run cat "${NTN_VERSION_LOG}"
    [ "${output}" = "${NTN_EXPECTED_VERSION}" ]
    # ...and it is a concrete version, never the installer's own default.
    [ "${NTN_EXPECTED_VERSION}" != "latest" ]
}

@test "treats an executable directory at the install path as not installed" {
    # -x だけで判定するとディレクトリを「導入済み」と読んでインストーラを呼ばず、
    # health check だけが後から落ちる。ここで導入を走らせきることを固定する。
    mkdir -p "${HOME}/.local/bin/ntn"
    run zsh "${SETUP_DIR}/notion.zsh"
    # 既存ディレクトリが邪魔でバイナリを置けないので、黙って成功せず失敗すること。
    [ "${status}" -eq 1 ]
    [[ "${output}" != *"SKIP"* ]]
}
