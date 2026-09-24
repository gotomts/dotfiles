#!/usr/bin/env bats
# setup/tests/claude-code.bats
#
# サンドボックス統合テスト。実ネットワーク・実インストーラには一切触れない:
# `curl` を PATH 上のスタブに差し替え、インストーラ本体もスタブが生成する
# （claude の実バイナリを落とさない）。

SETUP_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

# 公式インストーラの契約のうち、このスクリプトが依存する部分だけを模したスタブを
# curl の出力として書き出す: ${HOME}/.local/bin へ claude ランチャーを置く。
# 導入先は環境変数で渡さない（実インストーラも受け付けない）ので、スタブも HOME から
# 組み立てる。
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
#!/bin/bash
set -euo pipefail
# 実インストーラと同じく、渡された引数（無し = stable）を観測できるようにする。
printf '%s' "$*" > "${CLAUDE_TARGET_LOG}"
mkdir -p "${HOME}/.local/bin"
printf '#!/bin/sh\necho "9.9.9 (Claude Code)"\n' > "${HOME}/.local/bin/claude"
chmod +x "${HOME}/.local/bin/claude"
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
    export CLAUDE_TARGET_LOG="${BATS_TEST_TMPDIR}/claude-target.log"
    : > "${CURL_LOG}"
    : > "${CLAUDE_TARGET_LOG}"
    _install_curl_stub
    export PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"
    export CLAUDE_INSTALLER_URL="https://example.invalid/install.sh"
}

@test "zsh -n syntax check passes" {
    run zsh -n "${SETUP_DIR}/claude-code.zsh"
    [ "${status}" -eq 0 ]
}

@test "lib/claude-code.zsh passes zsh -n and resolves the launcher path" {
    run zsh -n "${SETUP_DIR}/lib/claude-code.zsh"
    [ "${status}" -eq 0 ]

    run zsh -c "source '${SETUP_DIR}/lib/claude-code.zsh'; claude_code::bin /tmp/somehome"
    [ "${status}" -eq 0 ]
    [ "${output}" = "/tmp/somehome/.local/bin/claude" ]
}

@test "installs claude into ~/.local/bin when absent" {
    run zsh "${SETUP_DIR}/claude-code.zsh"
    [ "${status}" -eq 0 ]
    [ -x "${HOME}/.local/bin/claude" ]
    run cat "${CURL_LOG}"
    [[ "${output}" == *"https://example.invalid/install.sh"* ]]
}

@test "invokes the installer with no version argument (stable, not pinned)" {
    # 版を固定しないという宣言側の判断は「引数を渡さない」ことで表現される。ここが
    # 具体版になると Claude Code 自身の自動更新と宣言が競合する。
    run zsh "${SETUP_DIR}/claude-code.zsh"
    [ "${status}" -eq 0 ]
    run cat "${CLAUDE_TARGET_LOG}"
    [ "${output}" = "" ]
}

@test "does not invoke the installer when claude is already executable (idempotent)" {
    mkdir -p "${HOME}/.local/bin"
    printf '#!/bin/sh\necho "0.0.1-preexisting"\n' > "${HOME}/.local/bin/claude"
    chmod +x "${HOME}/.local/bin/claude"

    run zsh "${SETUP_DIR}/claude-code.zsh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"SKIP"* ]]
    # curl は一度も呼ばれない = 自動更新で進んだ既存バイナリを巻き戻さない
    [ ! -s "${CURL_LOG}" ]
    run "${HOME}/.local/bin/claude"
    [[ "${output}" == *"0.0.1-preexisting"* ]]
}

@test "fails when the installer download fails (no silent success from an empty script)" {
    CURL_EXIT=22 run zsh "${SETUP_DIR}/claude-code.zsh"
    [ "${status}" -eq 1 ]
    [ ! -e "${HOME}/.local/bin/claude" ]
}

@test "fails when the installer exits 0 without producing the launcher" {
    cat > "${STUB_BIN}/curl" <<'EOF'
#!/bin/bash
out=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        *)  shift ;;
    esac
done
printf '#!/bin/bash\nexit 0\n' > "${out}"
exit 0
EOF
    chmod +x "${STUB_BIN}/curl"

    run zsh "${SETUP_DIR}/claude-code.zsh"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"実行可能になっていません"* ]]
}

@test "never reads or writes a Claude credential" {
    # 認証情報はこのスクリプトの責務外。コメントでの言及は許すが、実行される行に
    # トークン参照や認証コマンドが現れないことを固定する（漏洩経路を作らせない）。
    run bash -c "grep -vE '^[[:space:]]*#' '${SETUP_DIR}/claude-code.zsh' | grep -cE 'ANTHROPIC_API_KEY|CLAUDE_CODE_OAUTH_TOKEN|claude (setup-token|login)'"
    [ "${status}" -eq 1 ]
    [ "${output}" -eq 0 ]
}

@test "treats an executable directory at the install path as not installed" {
    # -x だけで判定するとディレクトリを「導入済み」と読んでインストーラを呼ばず、
    # health check だけが後から落ちる。ここで導入を走らせきることを固定する。
    mkdir -p "${HOME}/.local/bin/claude"
    run zsh "${SETUP_DIR}/claude-code.zsh"
    # 既存ディレクトリが邪魔でバイナリを置けないので、黙って成功せず失敗すること。
    [ "${status}" -eq 1 ]
    [[ "${output}" != *"SKIP"* ]]
}

@test "does not pipe curl straight into a shell" {
    # 取得失敗時に空スクリプトを実行して「成功」に見える経路を作らせない。
    run bash -c "grep -vE '^[[:space:]]*#' '${SETUP_DIR}/claude-code.zsh' | grep -cE 'curl[^|]*\\|[[:space:]]*(ba)?sh'"
    [ "${status}" -eq 1 ]
    [ "${output}" -eq 0 ]
}
