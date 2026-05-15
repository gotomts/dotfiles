#!/usr/bin/env bats
# nix/scripts/tests/inventory.bats
# bats-core unit tests (syntax, flags, static checks only — e2e is excluded)

# Resolve absolute path to the script under test
SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
INVENTORY_SCRIPT="${SCRIPT_DIR}/inventory.zsh"

# ----------------------------------------------------------------
# --help flag
# ----------------------------------------------------------------

@test "--help exits with status 0" {
    run zsh "${INVENTORY_SCRIPT}" --help
    [ "${status}" -eq 0 ]
}

@test "--help output contains Usage:" {
    run zsh "${INVENTORY_SCRIPT}" --help
    [ "${status}" -eq 0 ]
    echo "${output}" | grep -q "Usage:"
}

@test "--help output lists all collection sections" {
    run zsh "${INVENTORY_SCRIPT}" --help
    [ "${status}" -eq 0 ]
    echo "${output}" | grep -q "defaults"
    echo "${output}" | grep -q "mas"
    echo "${output}" | grep -q "launchctl"
    echo "${output}" | grep -q "sudoers"
    echo "${output}" | grep -q "Brewfile"
    echo "${output}" | grep -q "Fonts"
}

# ----------------------------------------------------------------
# Syntax check
# ----------------------------------------------------------------

@test "zsh -n syntax check passes" {
    run zsh -n "${INVENTORY_SCRIPT}"
    [ "${status}" -eq 0 ]
}

# ----------------------------------------------------------------
# Static content validation
# ----------------------------------------------------------------

@test "DEFAULTS_DOMAINS array contains at least 7 com.apple entries" {
    run grep -c "com.apple" "${INVENTORY_SCRIPT}"
    [ "${status}" -eq 0 ]
    [ "${output}" -ge 7 ]
}

@test "NSGlobalDomain is present in DEFAULTS_DOMAINS" {
    run grep "NSGlobalDomain" "${INVENTORY_SCRIPT}"
    [ "${status}" -eq 0 ]
}

@test "com.apple.dock is present in DEFAULTS_DOMAINS" {
    run grep "com.apple.dock" "${INVENTORY_SCRIPT}"
    [ "${status}" -eq 0 ]
}

# ----------------------------------------------------------------
# Output path template
# ----------------------------------------------------------------

@test "output path uses scutil --get LocalHostName" {
    run grep "scutil --get LocalHostName" "${INVENTORY_SCRIPT}"
    [ "${status}" -eq 0 ]
}

@test "output path uses date +%Y-%m-%d" {
    run grep 'date +%Y-%m-%d' "${INVENTORY_SCRIPT}"
    [ "${status}" -eq 0 ]
}

@test "output directory follows docs/inventory pattern" {
    run grep "docs/inventory" "${INVENTORY_SCRIPT}"
    [ "${status}" -eq 0 ]
}

# ----------------------------------------------------------------
# Error handling (strict mode)
# ----------------------------------------------------------------

@test "ERR_EXIT (set -e equivalent) is enabled" {
    run grep "ERR_EXIT" "${INVENTORY_SCRIPT}"
    [ "${status}" -eq 0 ]
}

@test "NOUNSET (set -u equivalent) is enabled" {
    run grep "NOUNSET" "${INVENTORY_SCRIPT}"
    [ "${status}" -eq 0 ]
}

@test "PIPE_FAIL (set -o pipefail equivalent) is enabled" {
    run grep "PIPE_FAIL" "${INVENTORY_SCRIPT}"
    [ "${status}" -eq 0 ]
}

# ----------------------------------------------------------------
# Triage placeholder
# ----------------------------------------------------------------

@test "nix-ka / mushi / kento placeholder comment is present" {
    run grep "nix化 / 無視 / 検討" "${INVENTORY_SCRIPT}"
    [ "${status}" -eq 0 ]
}

@test "Markdown checklist format (- [ ]) is used" {
    run grep "\- \[ \]" "${INVENTORY_SCRIPT}"
    [ "${status}" -eq 0 ]
}

# ----------------------------------------------------------------
# util.zsh usage
# ----------------------------------------------------------------

@test "util::info is used" {
    run grep "util::info" "${INVENTORY_SCRIPT}"
    [ "${status}" -eq 0 ]
}

@test "util::warning is used" {
    run grep "util::warning" "${INVENTORY_SCRIPT}"
    [ "${status}" -eq 0 ]
}

# ----------------------------------------------------------------
# Section coverage
# ----------------------------------------------------------------

@test "defaults section exists" {
    run grep "## defaults" "${INVENTORY_SCRIPT}"
    [ "${status}" -eq 0 ]
}

@test "mas section exists" {
    run grep "## mas" "${INVENTORY_SCRIPT}"
    [ "${status}" -eq 0 ]
}

@test "launchctl section exists" {
    run grep "## launchctl" "${INVENTORY_SCRIPT}"
    [ "${status}" -eq 0 ]
}

@test "sudoers.d section exists" {
    run grep "## sudoers" "${INVENTORY_SCRIPT}"
    [ "${status}" -eq 0 ]
}

@test "Brewfile diff section exists" {
    run grep "## Brewfile diff" "${INVENTORY_SCRIPT}"
    [ "${status}" -eq 0 ]
}

@test "Fonts section exists" {
    run grep "## Fonts" "${INVENTORY_SCRIPT}"
    [ "${status}" -eq 0 ]
}

# ----------------------------------------------------------------
# --help output regex validation (bats =~ assertion)
# ----------------------------------------------------------------

@test "--help output contains section names (regex)" {
    run zsh "${INVENTORY_SCRIPT}" --help
    [ "${status}" -eq 0 ]
    [[ "${output}" =~ defaults ]]
    [[ "${output}" =~ mas ]]
    [[ "${output}" =~ launchctl ]]
    [[ "${output}" =~ sudoers ]]
    [[ "${output}" =~ Brewfile ]]
    [[ "${output}" =~ Fonts ]]
}

# ----------------------------------------------------------------
# Stub-environment run: verify placeholder appears in generated output
#
# Strategy: place stub executables in a temp bin/ directory and prepend
# it to PATH. This works in zsh child processes without `export -f`.
# ----------------------------------------------------------------

# Create a shared stub bin directory once for the stub tests.
setup_stub_env() {
    STUB_TMPDIR="$(mktemp -d)"
    STUB_BINDIR="${STUB_TMPDIR}/bin"
    mkdir -p "${STUB_BINDIR}"
    STUB_HOMEDIR="${STUB_TMPDIR}/home"
    mkdir -p "${STUB_HOMEDIR}"

    # scutil stub: return a fixed hostname
    printf '#!/bin/sh\necho testhost\n' > "${STUB_BINDIR}/scutil"

    # defaults stub:
    #   - "read" サブコマンド: 旧実装の互換用に key=value を返す
    #   - "export <domain> -": 新実装が plistlib.loads() でパース可能な
    #     最小 XML plist を返す。stubKey が triage checklist として出力される
    cat > "${STUB_BINDIR}/defaults" <<'STUB_DEFAULTS'
#!/bin/sh
if [ "$1" = "read" ]; then
    echo "stubKey = stubValue"
elif [ "$1" = "export" ]; then
    cat <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTD/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>stubKey</key>
    <string>stubValue</string>
</dict>
</plist>
PLIST
fi
STUB_DEFAULTS

    # hostname stub (fallback in case scutil fails)
    printf '#!/bin/sh\necho testhost\n' > "${STUB_BINDIR}/hostname"

    # mas stub: return one app
    printf '#!/bin/sh\necho "999999999  StubApp (1.0)"\n' > "${STUB_BINDIR}/mas"

    # launchctl stub: one com.stub.agent entry
    printf '#!/bin/sh\nprintf "123\t0\tcom.stub.agent\n"\n' > "${STUB_BINDIR}/launchctl"

    # sudo stub: just run remaining args (ls, cat) against real /etc/sudoers.d
    printf '#!/bin/sh\nexec "$@"\n' > "${STUB_BINDIR}/sudo"

    # brew stub: succeed silently (dump creates an empty file)
    printf '#!/bin/sh\ntouch "${BREW_DUMP_FILE:-/dev/null}"; exit 0\n' \
        > "${STUB_BINDIR}/brew"

    # fc-list stub: return one font family
    printf '#!/bin/sh\necho "Stub Font"\n' > "${STUB_BINDIR}/fc-list"

    chmod +x "${STUB_BINDIR}"/*
}

@test "stub run: generated report contains triage placeholder" {
    setup_stub_env

    # OUTPUT_DIR は SCRIPT_DIR-relative なので INVENTORY_OUTPUT_DIR で
    # テスト用の一時 dir に向ける (実 repo の docs/inventory を汚染しないため)
    HOME="${STUB_HOMEDIR}" \
        INVENTORY_OUTPUT_DIR="${STUB_HOMEDIR}/inventory" \
        PATH="${STUB_BINDIR}:/usr/bin:/bin" \
        run zsh "${INVENTORY_SCRIPT}"

    # Locate the generated file
    local outdir="${STUB_HOMEDIR}/inventory"
    local outfile
    if [[ -d "${outdir}" ]]; then
        outfile="${outdir}/$(ls "${outdir}" 2>/dev/null | head -1)"
    fi

    # 新実装は defaults export | plistlib で生成。stub が正しく XML plist を
    # 返せばスクリプトは正常終了し outfile が存在する。outfile 不在は stub
    # セットアップ失敗を意味するためテスト失敗とする (旧 fallback は撤廃)。
    [ "${status}" -eq 0 ]
    [ -n "${outfile}" ] && [ -f "${outfile}" ]
    grep -q 'nix化 / 無視 / 検討' "${outfile}"

    rm -rf "${STUB_TMPDIR}"
}

@test "stub run: generated report contains Markdown checklist items" {
    setup_stub_env

    HOME="${STUB_HOMEDIR}" \
        INVENTORY_OUTPUT_DIR="${STUB_HOMEDIR}/inventory" \
        PATH="${STUB_BINDIR}:/usr/bin:/bin" \
        run zsh "${INVENTORY_SCRIPT}"

    local outdir="${STUB_HOMEDIR}/inventory"
    local outfile
    if [[ -d "${outdir}" ]]; then
        outfile="${outdir}/$(ls "${outdir}" 2>/dev/null | head -1)"
    fi

    [ "${status}" -eq 0 ]
    [ -n "${outfile}" ] && [ -f "${outfile}" ]
    grep -q '^- \[ \]' "${outfile}"

    rm -rf "${STUB_TMPDIR}"
}
