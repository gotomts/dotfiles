#!/usr/bin/env bats
# setup/tests/migrate.bats

SETUP_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
REPO_ROOT="$(cd "${SETUP_DIR}/.." && pwd)"

# Full stub bin covering every external command the 7 underlying Tier scripts
# call, so a real end-to-end `migrate.zsh --apply` run touches nothing real:
# mise/corepack (languages), defaults (defaults), git/claude (claude-sync),
# darwin-rebuild/nix (cutover). codex-sync/pam need no external command
# (SUDO_LOCAL_PATH redirects pam's write target instead of /etc).
_install_full_stubs() {
    local bin_dir="${1}"
    mkdir -p "${bin_dir}"

    cat > "${bin_dir}/mise" <<'EOF'
#!/bin/bash
echo "$*" >> "${MISE_LOG}"
if [[ "$1" == "which" && "$2" == "node" ]]; then
    echo "${NODE_BIN_DIR}/node"
fi
exit 0
EOF
    chmod +x "${bin_dir}/mise"

    mkdir -p "${NODE_BIN_DIR}"
    cat > "${NODE_BIN_DIR}/corepack" <<'EOF'
#!/bin/bash
echo "$*" >> "${COREPACK_LOG}"
exit 0
EOF
    chmod +x "${NODE_BIN_DIR}/corepack"

    cat > "${bin_dir}/defaults" <<'EOF'
#!/bin/bash
echo "$*" >> "${DEFAULTS_LOG}"
if [[ "$1" == "export" ]]; then
    echo "stub plist" > "$3"
fi
exit 0
EOF
    chmod +x "${bin_dir}/defaults"

    cat > "${bin_dir}/git" <<'EOF'
#!/bin/bash
echo "$*" >> "${GIT_LOG}"
if [[ "$1" == "clone" ]]; then
    mkdir -p "$3"
    exit 0
fi
exec /usr/bin/git "$@"
EOF
    chmod +x "${bin_dir}/git"

    cat > "${bin_dir}/claude" <<'EOF'
#!/bin/bash
echo "$*" >> "${CLAUDE_LOG}"
if [[ "$1" == "plugin" && "$2" == "list" ]]; then
    echo '[]'
    exit 0
fi
exit 0
EOF
    chmod +x "${bin_dir}/claude"

    cat > "${bin_dir}/darwin-rebuild" <<'EOF'
#!/bin/bash
echo "$*" >> "${DARWIN_REBUILD_LOG}"
if [[ "$1" == "--list-generations" ]]; then
    echo "42 2026-08-20 10:00:00 (current)"
fi
exit "${DARWIN_REBUILD_EXIT:-0}"
EOF
    chmod +x "${bin_dir}/darwin-rebuild"

    cat > "${bin_dir}/nix" <<'EOF'
#!/bin/bash
echo "$*" >> "${NIX_LOG}"
exit "${NIX_EXIT:-0}"
EOF
    chmod +x "${bin_dir}/nix"
}

setup() {
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}"
    unset MIGRATE_STATE_DIR MIGRATE_EUID_OVERRIDE MIGRATE_UNAME_OVERRIDE
    export DOTFILES_ROLE_FILE="${BATS_TEST_TMPDIR}/no-such-role-file"
    export SUDO_LOCAL_PATH="${BATS_TEST_TMPDIR}/sudo_local"

    STUB_BIN="${BATS_TEST_TMPDIR}/stub-bin"
    NODE_BIN_DIR="${BATS_TEST_TMPDIR}/mise-node-bin"
    MISE_LOG="${BATS_TEST_TMPDIR}/mise.log"
    COREPACK_LOG="${BATS_TEST_TMPDIR}/corepack.log"
    DEFAULTS_LOG="${BATS_TEST_TMPDIR}/defaults.log"
    GIT_LOG="${BATS_TEST_TMPDIR}/git.log"
    CLAUDE_LOG="${BATS_TEST_TMPDIR}/claude.log"
    DARWIN_REBUILD_LOG="${BATS_TEST_TMPDIR}/darwin-rebuild.log"
    NIX_LOG="${BATS_TEST_TMPDIR}/nix.log"
    : > "${MISE_LOG}"; : > "${COREPACK_LOG}"; : > "${DEFAULTS_LOG}"
    : > "${GIT_LOG}"; : > "${CLAUDE_LOG}"; : > "${DARWIN_REBUILD_LOG}"; : > "${NIX_LOG}"
    export NODE_BIN_DIR MISE_LOG COREPACK_LOG DEFAULTS_LOG GIT_LOG CLAUDE_LOG DARWIN_REBUILD_LOG NIX_LOG
    _install_full_stubs "${STUB_BIN}"
    # A minimal, real-machine-shaped PATH (not this dev sandbox's own, often
    # huge, inherited PATH). migrate.zsh chains multiple `zsh <script>`
    # invocations in the same sandboxed $HOME; once link.zsh (Phase 1) plants
    # the real ~/.zshenv symlink, every later child `zsh` process re-sources
    # it. That real ~/.zshenv runs `eval "$(mise activate --shims)"` whenever
    # `mise` resolves on PATH — an interaction no single-script bats file ever
    # exercises, since none of them chain a real Tier 1 symlink into further
    # child `zsh` invocations. This is also why the stub executables below use
    # `#!/bin/bash` instead of `#!/bin/zsh`: a zsh-shebanged stub would itself
    # re-source ~/.zshenv on every invocation, which resolves `mise` back to
    # the stub again, recursing without bound. bash does not source zsh's
    # ~/.zshenv, so the stubs stay leaves instead of becoming part of the
    # loop.
    export PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"
}

@test "zsh -n syntax check passes" {
    run zsh -n "${SETUP_DIR}/migrate.zsh"
    [ "${status}" -eq 0 ]
}

@test "no mode argument prints usage and exits 1 without side effects" {
    run zsh "${SETUP_DIR}/migrate.zsh"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"--dry-run"* ]]
    [[ "${output}" == *"--apply"* ]]
    [ ! -e "${HOME}/.dotfiles-migrate" ]
}

@test "refuses to run on a non-macOS host (preflight fail-closed)" {
    MIGRATE_UNAME_OVERRIDE="Linux" run zsh "${SETUP_DIR}/migrate.zsh" --dry-run
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"macOS"* ]]
}

@test "never invokes rollback.zsh (no-automatic-rollback policy)" {
    run grep -c 'zsh.*rollback\.zsh' "${SETUP_DIR}/migrate.zsh"
    [ "${status}" -eq 1 ]
    [ "${output}" -eq 0 ]
}

@test "dry-run never lists rollback as a step (dynamic guard on PHASE*_STEPS, not just source grep)" {
    # Belt-and-suspenders for the static grep test above: this exercises the
    # actual dispatch data (PHASE1_STEPS/PHASE2_STEPS/PHASE3_STEPS via
    # migrate::preflight's runtime guard), which is what a future edit
    # accidentally adding `rollback` to a phase array would actually touch —
    # the source-grep test alone would not catch that regression.
    run zsh "${SETUP_DIR}/migrate.zsh" --dry-run
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"rollback"* ]]
}

@test "dry-run lists all 7 steps and executes nothing" {
    run zsh "${SETUP_DIR}/migrate.zsh" --dry-run
    [ "${status}" -eq 0 ]

    for step in link languages defaults pam claude-sync codex-sync cutover; do
        [[ "${output}" == *"${step}"* ]]
    done

    # side effects any real step would have caused must NOT exist
    [ ! -e "${HOME}/.zshrc" ]
    [ ! -e "${HOME}/.dotfiles-migrate" ]
    run cat "${DARWIN_REBUILD_LOG}"
    [ -z "${output}" ]
}

@test "dry-run: non-root reports link as WOULD RUN and cutover/pam as BLOCKED" {
    MIGRATE_EUID_OVERRIDE=501 run zsh "${SETUP_DIR}/migrate.zsh" --dry-run
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"[WOULD RUN] link:"* ]]
    [[ "${output}" == *"[BLOCKED] pam:"* ]]
    [[ "${output}" == *"[BLOCKED] cutover:"* ]]
}

@test "apply: as non-root, completes phase 1 (link) and halts before phase 2 (root steps)" {
    MIGRATE_EUID_OVERRIDE=501 run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 1 ]

    # Phase 1 ran for real.
    [ -L "${HOME}/.zshrc" ]

    # Phase 2 (root-only) never attempted.
    [ ! -f "${SUDO_LOCAL_PATH}" ]
    run cat "${DARWIN_REBUILD_LOG}"
    [ -z "${output}" ]

    # Phase 3 (mise/defaults/claude-sync/codex-sync) never reached either,
    # because it depends on Phase 2's cutover having provisioned mise first.
    run cat "${MISE_LOG}"
    [ -z "${output}" ]
    run cat "${DEFAULTS_LOG}"
    [ -z "${output}" ]

    run cat "${HOME}/.dotfiles-migrate/manifest.log"
    [[ "${output}" == *$'\t'"link"$'\t'"success"* ]]
    [[ "${output}" == *$'\t'"pam"$'\t'"blocked"* ]]
    [[ "${output}" == *$'\t'"cutover"$'\t'"blocked"* ]]
}

@test "apply: full 3-invocation recovery choreography reaches success and is idempotent" {
    # 1st invocation (normal user): phase 1 only.
    MIGRATE_EUID_OVERRIDE=501 run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 1 ]
    [ -L "${HOME}/.zshrc" ]
    [ ! -f "${SUDO_LOCAL_PATH}" ]

    # 2nd invocation (root + USER): phase 1 skipped (already success), phase 2 runs,
    # phase 3 blocked again (root steps can't drop privilege mid-process).
    USER=testuser MIGRATE_EUID_OVERRIDE=0 run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 1 ]
    [ -f "${SUDO_LOCAL_PATH}" ]
    run cat "${DARWIN_REBUILD_LOG}"
    [[ "${output}" == *"switch --flake"* ]]
    # languages.zsh itself (mise install/use) has not run yet — only the
    # sandboxed ~/.zshenv's own `mise activate --shims` (a real, expected
    # per-shell-startup side effect, fired every time migrate.zsh or a step
    # script starts a fresh zsh process) has touched the stub so far.
    run cat "${MISE_LOG}"
    [[ "${output}" != *"install"* ]]

    local darwin_calls_before pam_mtime_before
    darwin_calls_before="$(wc -l < "${DARWIN_REBUILD_LOG}" | tr -d ' ')"

    # 3rd invocation (normal user again): phase 1+2 skipped (idempotent), phase 3 runs.
    MIGRATE_EUID_OVERRIDE=501 run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"全ステップ success で完了"* ]]
    [[ "${output}" == *"health check: 全ステップの実効果を確認しました"* ]]

    run cat "${MISE_LOG}"
    [[ "${output}" == *"install"* ]]
    run cat "${DEFAULTS_LOG}"
    [[ "${output}" == *"write"* ]]
    [ -f "${HOME}/.claude.json" ]
    [ -f "${HOME}/.codex/config.toml" ]

    # cutover/pam were NOT re-invoked on the 3rd run.
    [ "$(wc -l < "${DARWIN_REBUILD_LOG}" | tr -d ' ')" -eq "${darwin_calls_before}" ]
}

@test "apply: a real step failure halts immediately (fail-closed, no automatic rollback)" {
    cat > "${STUB_BIN}/darwin-rebuild" <<'EOF'
#!/bin/bash
echo "$*" >> "${DARWIN_REBUILD_LOG}"
exit 0
EOF
    chmod +x "${STUB_BIN}/darwin-rebuild"
    cat > "${STUB_BIN}/nix" <<'EOF'
#!/bin/bash
echo "$*" >> "${NIX_LOG}"
exit 1
EOF
    chmod +x "${STUB_BIN}/nix"

    # Phase 1 (link) must already be done before Phase 2 is even attempted
    # (Phase boundaries are strict), so get there first as a normal user.
    MIGRATE_EUID_OVERRIDE=501 run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 1 ]
    [ -L "${HOME}/.zshrc" ]

    USER=testuser MIGRATE_EUID_OVERRIDE=0 run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 1 ]

    # cutover failed before switch; pam (later in the same phase) never ran.
    run cat "${DARWIN_REBUILD_LOG}"
    [[ "${output}" != *"switch"* ]]
    [ ! -f "${SUDO_LOCAL_PATH}" ]

    run cat "${HOME}/.dotfiles-migrate/manifest.log"
    [[ "${output}" == *$'\t'"cutover"$'\t'"fail"* ]]
}

@test "health check re-verifies real state and does not just trust a success manifest" {
    # Reach full success via the real 3-invocation choreography first.
    MIGRATE_EUID_OVERRIDE=501 run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 1 ]
    USER=testuser MIGRATE_EUID_OVERRIDE=0 run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 1 ]
    MIGRATE_EUID_OVERRIDE=501 run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]

    # Tamper with claude-sync's evidence file without touching the manifest
    # (simulates the file being lost/reverted after the fact, e.g. by an
    # unrelated tool). The manifest still says every step is "success".
    rm -f "${HOME}/.claude.json"

    # Re-running apply should skip every step (manifest says success) yet
    # still fail overall, because health check catches the missing evidence.
    MIGRATE_EUID_OVERRIDE=501 run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"health check 失敗"* ]]
    [[ "${output}" == *"claude-sync:"* ]]
}
