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
