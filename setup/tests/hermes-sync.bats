#!/usr/bin/env bats
# setup/tests/hermes-sync.bats

SETUP_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

# The one external command hermes-sync.zsh calls. Records its argv and models
# the only contract hermes-sync.zsh depends on: `rtk init --agent hermes`
# materializes ~/.hermes/plugins/rtk-rewrite/.
_install_rtk_stub() {
    cat > "${STUB_BIN}/rtk" <<'EOF'
#!/bin/bash
echo "$*" >> "${RTK_LOG}"
if [[ "${RTK_EXIT:-0}" -ne 0 ]]; then
    exit "${RTK_EXIT}"
fi
if [[ "$1" == "init" ]]; then
    mkdir -p "${HOME}/.hermes/plugins/rtk-rewrite"
fi
exit 0
EOF
    chmod +x "${STUB_BIN}/rtk"
}

# Hermes's own running config. Its presence is what marks the machine as one
# where Hermes actually runs -- the ~/.hermes directory alone does not, because
# Tier 1 (setup/link.zsh) creates it just to place SOUL.md.
_install_hermes() {
    mkdir -p "${HOME}/.hermes"
    : > "${HOME}/.hermes/config.yaml"
}

setup() {
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}"

    STUB_BIN="${BATS_TEST_TMPDIR}/stub-bin"
    mkdir -p "${STUB_BIN}"
    export RTK_LOG="${BATS_TEST_TMPDIR}/rtk.log"
    : > "${RTK_LOG}"
    export PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"
    # hermes-sync.zsh calls util::ensure_homebrew_path, which prepends the real
    # /opt/homebrew paths unless overridden. Point it at the stub dir so this
    # machine's real rtk (if installed) can never win.
    export HOMEBREW_PATH_PREFIX_OVERRIDE="${STUB_BIN}"
    # Same for ${HOME}/.local/bin, where the real hermes is installed.
    export LOCAL_BIN_PATH_OVERRIDE="${STUB_BIN}"
    # An inherited HERMES_HOME must never be followed (see sync_sentry_mcp).
    export HERMES_HOME="${BATS_TEST_TMPDIR}/inherited-hermes-home"
}

@test "zsh -n syntax check passes" {
    run zsh -n "${SETUP_DIR}/hermes-sync.zsh"
    [ "${status}" -eq 0 ]
}

@test "installs the RTK plugin when both Hermes and rtk are present" {
    _install_hermes
    _install_rtk_stub

    run zsh "${SETUP_DIR}/hermes-sync.zsh"
    [ "${status}" -eq 0 ]
    [ -d "${HOME}/.hermes/plugins/rtk-rewrite" ]

    run cat "${RTK_LOG}"
    [[ "${output}" == *"init --agent hermes"* ]]
    # Non-interactive: the confirmation prompt for a divergent managed file
    # must be pre-approved, otherwise migrate.zsh would block on stdin.
    [[ "${output}" == *"--auto-patch"* ]]
}

@test "does not opt in to telemetry" {
    _install_hermes
    # Record the env this invocation sees instead of its argv: the telemetry
    # switch is an environment variable, not a flag.
    cat > "${STUB_BIN}/rtk" <<'EOF'
#!/bin/bash
echo "RTK_TELEMETRY_DISABLED=${RTK_TELEMETRY_DISABLED:-unset}" >> "${RTK_LOG}"
exit 0
EOF
    chmod +x "${STUB_BIN}/rtk"

    run zsh "${SETUP_DIR}/hermes-sync.zsh"
    [ "${status}" -eq 0 ]
    run cat "${RTK_LOG}"
    [[ "${output}" == "RTK_TELEMETRY_DISABLED=1" ]]
}

@test "does nothing when Hermes is not installed on this machine" {
    _install_rtk_stub
    # The directory exists (Tier 1 puts SOUL.md there) but Hermes never ran,
    # so there is no config.yaml. This is the shape the directory check got
    # wrong, so assert it explicitly rather than testing an empty $HOME.
    mkdir -p "${HOME}/.hermes"

    run zsh "${SETUP_DIR}/hermes-sync.zsh"
    [ "${status}" -eq 0 ]
    [ ! -e "${HOME}/.hermes/plugins/rtk-rewrite" ]
    run cat "${RTK_LOG}"
    [ -z "${output}" ]
}

@test "fails open when rtk is missing (does not stop the rest of the migration)" {
    _install_hermes

    run zsh "${SETUP_DIR}/hermes-sync.zsh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"rtk 未インストール"* ]]
    [ ! -e "${HOME}/.hermes/plugins/rtk-rewrite" ]
}

@test "fails open when rtk init errors" {
    _install_hermes
    _install_rtk_stub

    RTK_EXIT=1 run zsh "${SETUP_DIR}/hermes-sync.zsh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"失敗"* ]]
}

@test "re-running is idempotent (rtk init is invoked again, plugin stays)" {
    _install_hermes
    _install_rtk_stub

    run zsh "${SETUP_DIR}/hermes-sync.zsh"
    [ "${status}" -eq 0 ]
    run zsh "${SETUP_DIR}/hermes-sync.zsh"
    [ "${status}" -eq 0 ]
    [ -d "${HOME}/.hermes/plugins/rtk-rewrite" ]

    # Deliberate: the adapter is a generated artifact tied to the installed rtk
    # version, so it is refreshed on every run rather than skipped once present.
    run grep -c "init --agent hermes" "${RTK_LOG}"
    [ "${output}" -eq 2 ]
}

# --- Sentry MCP (hermes config set mcp_servers.sentry) ---

SENTRY_DECL='{"url":"https://mcp.sentry.dev/mcp","auth":"oauth","enabled":true}'

# Models the slice of the Hermes CLI hermes-sync.zsh depends on:
#   hermes config get --json <mcp_servers.X>  -> JSON value, or exit 1 with empty stdout
#   hermes config set <mcp_servers.X> <JSON>  -> writes only that key
# State is the mcp_servers map kept as JSON in ${HERMES_HOME}/mcp_servers.json, so a
# test can assert that sibling servers survive. Every call's argv and HERMES_HOME are logged.
_install_hermes_stub() {
    cat > "${STUB_BIN}/hermes" <<'EOF2'
#!/bin/bash
echo "HERMES_HOME=${HERMES_HOME} $*" >> "${HERMES_LOG}"
state="${HERMES_HOME}/mcp_servers.json"
[[ -f "${state}" ]] || echo '{}' > "${state}"
if [[ "$1 $2" == "config get" ]]; then
    case "${HERMES_GET_MODE:-}" in
        error) echo "boom token=SECRET-FROM-STDERR" >&2; exit 2 ;;
        other-exit1) echo "Traceback: SECRET-FROM-STDERR" >&2; exit 1 ;;
        empty) exit 0 ;;
        invalid) echo "not-json SECRET-FROM-STDOUT"; exit 0 ;;
    esac
    name="${4#mcp_servers.}"
    jq -e -c --arg n "${name}" '.[$n] // empty' "${state}" && exit 0
    echo "Config key not set: $4" >&2
    exit 1
elif [[ "$1 $2" == "config set" ]]; then
    [[ "${HERMES_SET_EXIT:-0}" -eq 0 ]] || exit "${HERMES_SET_EXIT}"
    name="${3#mcp_servers.}"
    jq --arg n "${name}" --argjson v "$4" '.[$n] = $v' "${state}" > "${state}.tmp" && mv "${state}.tmp" "${state}"
fi
EOF2
    chmod +x "${STUB_BIN}/hermes"
    export HERMES_LOG="${BATS_TEST_TMPDIR}/hermes.log"
    : > "${HERMES_LOG}"
}

@test "sentry: registers the declared server and keeps existing servers" {
    _install_hermes
    _install_hermes_stub
    echo '{"discord_admin":{"command":"x"},"linear":{"url":"https://mcp.linear.app/mcp","auth":"oauth"}}' \
        > "${HOME}/.hermes/mcp_servers.json"

    run zsh "${SETUP_DIR}/hermes-sync.zsh"
    [ "${status}" -eq 0 ]

    run jq -S -c '.sentry' "${HOME}/.hermes/mcp_servers.json"
    [ "${output}" == "$(jq -S -c . <<< "${SENTRY_DECL}")" ]
    run jq -c '.discord_admin, .linear' "${HOME}/.hermes/mcp_servers.json"
    [ "${lines[0]}" == '{"command":"x"}' ]
    [ "${lines[1]}" == '{"url":"https://mcp.linear.app/mcp","auth":"oauth"}' ]

    # Only the sentry key is written, and against ~/.hermes (not an inherited HERMES_HOME).
    run grep "config set" "${HERMES_LOG}"
    [ "${#lines[@]}" -eq 1 ]
    [[ "${output}" == "HERMES_HOME=${HOME}/.hermes config set mcp_servers.sentry "* ]]
}

@test "sentry: re-running is a no-op once the declared value is present" {
    _install_hermes
    _install_hermes_stub

    run zsh "${SETUP_DIR}/hermes-sync.zsh"
    [ "${status}" -eq 0 ]
    run zsh "${SETUP_DIR}/hermes-sync.zsh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"宣言どおり設定済み"* ]]

    run grep -c "config set" "${HERMES_LOG}"
    [ "${output}" -eq 1 ]
}

@test "sentry: key order in the existing value does not count as a conflict" {
    _install_hermes
    _install_hermes_stub
    echo '{"sentry":{"enabled":true,"auth":"oauth","url":"https://mcp.sentry.dev/mcp"}}' \
        > "${HOME}/.hermes/mcp_servers.json"

    run zsh "${SETUP_DIR}/hermes-sync.zsh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"宣言どおり設定済み"* ]]
    run grep -c "config set" "${HERMES_LOG}"
    [ "${output}" -eq 0 ]
}

@test "sentry: does not overwrite a differing existing value, and never logs it" {
    _install_hermes
    _install_hermes_stub
    local existing='{"sentry":{"url":"https://sentry.example.com/mcp?token=SECRET-IN-URL","auth":"oauth","headers":{"Authorization":"Bearer SECRET-IN-HEADER"},"enabled":false}}'
    echo "${existing}" > "${HOME}/.hermes/mcp_servers.json"

    run zsh "${SETUP_DIR}/hermes-sync.zsh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"上書きしません"* ]]
    # Neither the existing value nor the declared JSON is echoed.
    [[ "${output}" != *"SECRET"* ]]
    [[ "${output}" != *"sentry.example.com"* ]]
    [[ "${output}" != *"mcp.sentry.dev"* ]]

    run grep -c "config set" "${HERMES_LOG}"
    [ "${output}" -eq 0 ]
    run jq -S -c . "${HOME}/.hermes/mcp_servers.json"
    [ "${output}" == "$(jq -S -c . <<< "${existing}")" ]
}

@test "sentry: does nothing when Hermes is not installed on this machine" {
    _install_hermes_stub
    mkdir -p "${HOME}/.hermes"

    run zsh "${SETUP_DIR}/hermes-sync.zsh"
    [ "${status}" -eq 0 ]
    run cat "${HERMES_LOG}"
    [ -z "${output}" ]
}

@test "sentry: fails open when the hermes command is missing" {
    _install_hermes

    run zsh "${SETUP_DIR}/hermes-sync.zsh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"hermes コマンドが見つからない"* ]]
}

@test "sentry: fails open when hermes config set errors" {
    _install_hermes
    _install_hermes_stub

    HERMES_SET_EXIT=1 run zsh "${SETUP_DIR}/hermes-sync.zsh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"mcp_servers.sentry に失敗"* ]]
}

@test "sentry: runs independently of the RTK step (rtk missing does not skip it)" {
    _install_hermes
    _install_hermes_stub

    run zsh "${SETUP_DIR}/hermes-sync.zsh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"rtk 未インストール"* ]]
    run jq -e '.sentry' "${HOME}/.hermes/mcp_servers.json"
    [ "${status}" -eq 0 ]
}

# get failures other than the exact "not set" answer must leave the config
# untouched and must not surface Hermes's stdout/stderr in the log.
_assert_get_failure_is_noop() {
    _install_hermes
    _install_hermes_stub
    echo '{"linear":{"url":"https://mcp.linear.app/mcp"}}' > "${HOME}/.hermes/mcp_servers.json"

    HERMES_GET_MODE="$1" run zsh "${SETUP_DIR}/hermes-sync.zsh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Sentry MCP は変更しません"* ]]
    [[ "${output}" != *"SECRET"* ]]
    run grep -c "config set" "${HERMES_LOG}"
    [ "${output}" -eq 0 ]
    run jq -c . "${HOME}/.hermes/mcp_servers.json"
    [ "${output}" == '{"linear":{"url":"https://mcp.linear.app/mcp"}}' ]
}

@test "sentry: get error (non-1 exit) does not write" {
    _assert_get_failure_is_noop error
}

@test "sentry: exit 1 with an unexpected stderr is not treated as 'not set'" {
    _assert_get_failure_is_noop other-exit1
}

@test "sentry: empty successful get does not write" {
    _assert_get_failure_is_noop empty
}

@test "sentry: non-JSON get output does not write" {
    _assert_get_failure_is_noop invalid
}
