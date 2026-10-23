#!/usr/bin/env bats
# setup/tests/jev-ultrafast-cli.bats
#
# scripts/jev-ultrafast.zsh（Claude Code / Hermes 共通の CLI）のテスト。実 Chrome・実 API には
# 触れない: open / lsof / ps / curl を PATH 上のスタブに差し替え、uv tool の venv の python も
# 呼ばれ方（argv・環境）を記録するだけのスタブにする。
#
# 秘密値の代役（STUB_SECRET）は出力・ログへ値として書かない。スタブは「届いたか」の真偽だけを
# 記録する。

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/jev-ultrafast.zsh"
LIB="${REPO_ROOT}/setup/lib/jev-ultrafast.zsh"

setup() {
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}"
    STUB_BIN="${BATS_TEST_TMPDIR}/stub-bin"
    export STATE="${BATS_TEST_TMPDIR}/browser-state"
    export OPEN_LOG="${BATS_TEST_TMPDIR}/open.log"
    export PY_LOG="${BATS_TEST_TMPDIR}/python.log"
    mkdir -p "${STUB_BIN}" "${STATE}"
    : > "${OPEN_LOG}"
    : > "${PY_LOG}"

    PROFILE="$(zsh -c "source '${LIB}'; jev_ultrafast::profile_dir '${HOME}'")"
    HARNESS="$(zsh -c "source '${LIB}'; jev_ultrafast::harness_home '${HOME}'")"
    CDP_URL="$(zsh -c "source '${LIB}'; jev_ultrafast::cdp_url")"
    PORT="$(zsh -c "source '${LIB}'; echo \${JEV_ULTRAFAST_CDP_PORT}")"
    REV="$(zsh -c "source '${LIB}'; echo \${JEV_ULTRAFAST_REV}")"
    PYTHON="$(zsh -c "source '${LIB}'; jev_ultrafast::python '${HOME}'")"
    export PROFILE PORT

    # lsof: listen 中の pid（STATE/listening）を返す。誰も listen していなければ exit 1。
    cat > "${STUB_BIN}/lsof" <<'EOF'
#!/bin/bash
[[ -f "${STATE}/listening" ]] || exit 1
cat "${STATE}/listening"
EOF
    # ps -o command= -p <pid>: listen 中のプロセスのコマンドライン
    cat > "${STUB_BIN}/ps" <<'EOF'
#!/bin/bash
cat "${STATE}/cmd"
EOF
    # open -na <app> --args ...: Chrome を起動したことにする（OPEN_STARTS_BROWSER=0 なら
    # 起動に失敗して誰も listen しない）。
    cat > "${STUB_BIN}/open" <<'EOF'
#!/bin/bash
echo "$*" >> "${OPEN_LOG}"
[[ "${OPEN_STARTS_BROWSER:-1}" == "1" ]] || exit 0
args=()
seen=0
for a in "$@"; do
    if [[ "${seen}" == "1" ]]; then args+=("${a}"); fi
    [[ "${a}" == "--args" ]] && seen=1
done
echo 4242 > "${STATE}/listening"
echo "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome ${args[*]}" > "${STATE}/cmd"
EOF
    # curl: DevTools endpoint は誰かが listen していれば応答する
    cat > "${STUB_BIN}/curl" <<'EOF'
#!/bin/bash
[[ -f "${STATE}/listening" ]] || exit 7
echo '{"webSocketDebuggerUrl":"ws://127.0.0.1/devtools/browser/x"}'
EOF
    chmod +x "${STUB_BIN}"/*

    # uv tool の venv を模す: python は呼ばれ方だけを記録する。
    mkdir -p "${PYTHON%/*}"
    cat > "${PYTHON}" <<'EOF'
#!/bin/bash
code="$3"
case "${code}" in
    *ensure_daemon*) kind=daemon ;;
    *"Agent("*)      kind=agent ;;
    *)               kind=other ;;
esac
{
    echo "call"
    echo "kind:${kind}"
    echo "flags:$1 $2"
    echo "argv:${*:4}"
    echo "BU_CDP_URL=${BU_CDP_URL-<unset>}"
    echo "BU_CDP_WS=${BU_CDP_WS-<unset>}"
    echo "BU_NAME=${BU_NAME-<unset>}"
    echo "BH_HOME=${BH_HOME-<unset>}"
    echo "BH_CONFIG_DIR=${BH_CONFIG_DIR-<unset>}"
    echo "BH_TELEMETRY=${BH_TELEMETRY-<unset>}"
    echo "TEXT_MODEL_BASE_URL=${TEXT_MODEL_BASE_URL-<unset>}"
    echo "TEXT_MODEL=${TEXT_MODEL-<unset>}"
    [[ -n "${TYPESAFE_API_KEY:-}" && "${TYPESAFE_API_KEY}" == "${STUB_SECRET}" ]] && echo "typesafe:present" || echo "typesafe:absent"
    [[ -n "${TEXT_MODEL_API_KEY:-}" && "${TEXT_MODEL_API_KEY}" == "${STUB_SECRET}" ]] && echo "text:present" || echo "text:absent"
} >> "${PY_LOG}"
[[ "${kind}" == "agent" ]] && exit "${PY_AGENT_EXIT:-0}"
exit 0
EOF
    chmod +x "${PYTHON}"
    local site="${PYTHON%/bin/python}/lib/python3.14/site-packages/jev_ultrafast-0.1.0.dist-info"
    mkdir -p "${site}"
    printf '{"url":"x","vcs_info":{"vcs":"git","commit_id":"%s"}}' "${REV}" > "${site}/direct_url.json"

    export PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"
    export STUB_SECRET="stub-secret-value-not-real"
    export TYPESAFE_API_KEY="${STUB_SECRET}"
    export TEXT_MODEL_API_KEY="${STUB_SECRET}"
    unset BU_CDP_WS BU_CDP_URL BU_NAME BH_HOME BH_CONFIG_DIR TEXT_MODEL_BASE_URL TEXT_MODEL TEXT_MODEL_REASONING
    export JEV_ULTRAFAST_START_TIMEOUT=2
}

# _dedicated_running  専用 profile の Chrome が既に listen している状態を作る
_dedicated_running() {
    echo 4242 > "${STATE}/listening"
    echo "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --user-data-dir=${PROFILE} --remote-debugging-port=${PORT}" > "${STATE}/cmd"
}

@test "zsh -n syntax check passes" {
    run zsh -n "${SCRIPT}"
    [ "${status}" -eq 0 ]
}

@test "--help lists the subcommands and points at the shared usage policy" {
    run zsh "${SCRIPT}" --help
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"run"* ]]
    [[ "${output}" == *"browser"* ]]
    [[ "${output}" == *"doctor"* ]]
    [[ "${output}" == *"claude/jev-ultrafast.md"* ]]
    [ -f "${REPO_ROOT}/claude/jev-ultrafast.md" ]
}

@test "unknown subcommand exits non-zero" {
    run zsh "${SCRIPT}" nope
    [ "${status}" -eq 2 ]
}

@test "browser launches Chrome only with the dedicated profile and port" {
    run zsh "${SCRIPT}" browser
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"${CDP_URL}"* ]]
    run cat "${OPEN_LOG}"
    [[ "${output}" == "-na /Applications/Google Chrome.app --args --user-data-dir=${PROFILE} --remote-debugging-port=${PORT} "* ]]
    [ "$(wc -l < "${OPEN_LOG}" | tr -d ' ')" -eq 1 ]
    [ -d "${PROFILE}" ]
}

@test "browser reuses an already running dedicated Chrome (idempotent)" {
    _dedicated_running
    run zsh "${SCRIPT}" browser
    [ "${status}" -eq 0 ]
    [ ! -s "${OPEN_LOG}" ]
}

@test "refuses a port held by a browser without the dedicated profile" {
    echo 999 > "${STATE}/listening"
    echo "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port=${PORT}" > "${STATE}/cmd"
    run zsh "${SCRIPT}" run --url https://example.com --goal "x"
    [ "${status}" -eq 1 ]
    [ ! -s "${OPEN_LOG}" ]
    [ ! -s "${PY_LOG}" ]
}

@test "refuses a look-alike profile path (prefix match is not ownership)" {
    echo 999 > "${STATE}/listening"
    echo "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --user-data-dir=${PROFILE}-other --remote-debugging-port=${PORT}" > "${STATE}/cmd"
    run zsh "${SCRIPT}" browser
    [ "${status}" -eq 1 ]
    [ ! -s "${OPEN_LOG}" ]
}

@test "fails when the dedicated Chrome never starts listening" {
    OPEN_STARTS_BROWSER=0 run zsh "${SCRIPT}" browser
    [ "${status}" -eq 1 ]
}

@test "run requires the API keys and names only the missing variable" {
    unset TYPESAFE_API_KEY
    run zsh "${SCRIPT}" run --url https://example.com --goal "x"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"TYPESAFE_API_KEY"* ]]
    [ ! -s "${PY_LOG}" ]
    [ ! -s "${OPEN_LOG}" ]
}

@test "run connects browser-harness to the dedicated browser only" {
    export BU_CDP_WS="ws://127.0.0.1:9222/devtools/browser/someone-else"
    export BH_CONFIG_DIR="${BATS_TEST_TMPDIR}/shared-config"
    run zsh "${SCRIPT}" run --url https://example.com --goal "find x"
    [ "${status}" -eq 0 ]
    run cat "${PY_LOG}"
    [[ "${output}" == *"BU_CDP_URL=${CDP_URL}"* ]]
    [[ "${output}" == *"BU_CDP_WS=<unset>"* ]]
    [[ "${output}" == *"BU_NAME=jev-ultrafast"* ]]
    [[ "${output}" == *"BH_HOME=${HARNESS}"* ]]
    [[ "${output}" == *"BH_CONFIG_DIR=<unset>"* ]]
    [[ "${output}" == *"BH_TELEMETRY=0"* ]]
    [[ "${output}" == *"argv:--url https://example.com --goal find x"* ]]
    # cwd に置かれた python モジュールを拾わない
    [[ "${output}" == *"flags:-I -c"* ]]
}

@test "the long-lived browser-harness daemon never inherits the API keys" {
    run zsh "${SCRIPT}" run --url https://example.com --goal "x"
    [ "${status}" -eq 0 ]
    run awk '/^kind:/{k=$0} /^typesafe:|^text:/{print k" "$0}' "${PY_LOG}"
    [[ "${output}" == *"kind:daemon typesafe:absent"* ]]
    [[ "${output}" == *"kind:daemon text:absent"* ]]
    [[ "${output}" == *"kind:agent typesafe:present"* ]]
    [[ "${output}" == *"kind:agent text:present"* ]]
}

@test "run applies upstream's documented text-model defaults, and the environment wins" {
    run zsh "${SCRIPT}" run --url https://example.com --goal "x"
    [ "${status}" -eq 0 ]
    run grep -F "TEXT_MODEL_BASE_URL=https://openrouter.ai/api/v1" "${PY_LOG}"
    [ "${status}" -eq 0 ]

    : > "${PY_LOG}"
    TEXT_MODEL_BASE_URL="https://llm.example.invalid/v1" TEXT_MODEL="example/model" \
        run zsh "${SCRIPT}" run --url https://example.com --goal "x"
    [ "${status}" -eq 0 ]
    run grep -F "TEXT_MODEL_BASE_URL=https://llm.example.invalid/v1" "${PY_LOG}"
    [ "${status}" -eq 0 ]
    run grep -F "TEXT_MODEL=example/model" "${PY_LOG}"
    [ "${status}" -eq 0 ]
}

@test "run propagates the agent's exit status" {
    _dedicated_running
    PY_AGENT_EXIT=3 run zsh "${SCRIPT}" run --url https://example.com --goal "x"
    [ "${status}" -eq 3 ]
}

@test "doctor reports revision, paths and key presence without printing values" {
    _dedicated_running
    run zsh "${SCRIPT}" doctor
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"${REV}"* ]]
    [[ "${output}" == *"${PROFILE}"* ]]
    [[ "${output}" == *"${CDP_URL}"* ]]
    [[ "${output}" == *"TYPESAFE_API_KEY: set"* ]]
    [[ "${output}" != *"${STUB_SECRET}"* ]]
    [ ! -s "${OPEN_LOG}" ]
}

@test "doctor fails when the installed revision differs from the declaration" {
    local f
    f="$(ls "${PYTHON%/bin/python}"/lib/python3.14/site-packages/jev_ultrafast-0.1.0.dist-info/direct_url.json)"
    printf '{"url":"x","vcs_info":{"vcs":"git","commit_id":"%s"}}' "0000000000000000000000000000000000000000" > "${f}"
    unset TEXT_MODEL_API_KEY
    run zsh "${SCRIPT}" doctor
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"TEXT_MODEL_API_KEY: unset"* ]]
}

@test "secret values never reach stdout or stderr" {
    run zsh "${SCRIPT}" run --url https://example.com --goal "x"
    [[ "${output}" != *"${STUB_SECRET}"* ]]
    unset TYPESAFE_API_KEY
    run zsh "${SCRIPT}" run --url https://example.com --goal "x"
    [[ "${output}" != *"${STUB_SECRET}"* ]]
}

@test "never references the everyday Chrome profile or Hermes' real-profile snapshot" {
    run bash -c "grep -vE '^[[:space:]]*#' '${SCRIPT}' '${LIB}' | grep -cE 'Application Support/Google/Chrome|Profile 6|real_profile|9222|9223'"
    [ "${status}" -eq 1 ]
    [ "${output}" -eq 0 ]
}
