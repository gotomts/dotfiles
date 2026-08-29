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
elif [[ "$1" == "switch" ]]; then
    # Model cutover's real effect: `darwin-rebuild switch` is what actually
    # installs the desired Homebrew set (including any binary newly added to
    # homebrew.nix, e.g. starship). Only materialize it here, not earlier, so
    # tests can exercise "manifest already says cutover succeeded, but a
    # binary added to the desired set afterward is still missing".
    printf '#!/bin/bash\nexit 0\n' > "$(dirname "$0")/starship"
    chmod +x "$(dirname "$0")/starship"
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

    # migrate.zsh's single-root-invocation de-escalation path shells out to
    # `sudo -u <user> -H zsh <script>` for non-root steps. The sandbox has no
    # real second user to switch to, so this stub just records the call and
    # execs the wrapped command as-is (still exercising migrate.zsh's own
    # invocation contract: which user/flags/script it asked for).
    cat > "${bin_dir}/sudo" <<'EOF'
#!/bin/bash
echo "$*" >> "${SUDO_LOG}"
if [[ "$1" == "-u" ]]; then
    shift 2
    [[ "$1" == "-H" ]] && shift
fi
exec "$@"
EOF
    chmod +x "${bin_dir}/sudo"
}

setup() {
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}"
    unset MIGRATE_STATE_DIR MIGRATE_EUID_OVERRIDE MIGRATE_UNAME_OVERRIDE MIGRATE_SUDO_USER_OVERRIDE MIGRATE_NIX_DIR_OVERRIDE SUDO_USER
    # The sandbox has no real second user for dscl to resolve "testuser"
    # against. Since the sandbox also has no real privilege separation
    # (root and the "original user" are the same process either way), point
    # the delegated-user home lookup back at the same sandboxed $HOME.
    export MIGRATE_HOME_FOR_USER_OVERRIDE="${HOME}"
    export DOTFILES_ROLE_FILE="${BATS_TEST_TMPDIR}/no-such-role-file"
    export SUDO_LOCAL_PATH="${BATS_TEST_TMPDIR}/sudo_local"
    # Model a real machine's starting shape: nix-darwin owns /etc/pam.d/sudo_local
    # and leaves it as a symlink to the macOS static default until setup/pam.zsh
    # customizes it. Starting from a nonexistent target instead would make
    # pam.zsh skip its backup step entirely, so no cutover rerun could ever
    # restore pristine state -- a state this sandbox should not be modelling as
    # the norm.
    export SUDO_LOCAL_STATIC_DEFAULT="${BATS_TEST_TMPDIR}/etc-static-sudo_local"
    : > "${SUDO_LOCAL_STATIC_DEFAULT}"
    ln -s "${SUDO_LOCAL_STATIC_DEFAULT}" "${SUDO_LOCAL_PATH}"

    STUB_BIN="${BATS_TEST_TMPDIR}/stub-bin"
    NODE_BIN_DIR="${BATS_TEST_TMPDIR}/mise-node-bin"
    MISE_LOG="${BATS_TEST_TMPDIR}/mise.log"
    COREPACK_LOG="${BATS_TEST_TMPDIR}/corepack.log"
    DEFAULTS_LOG="${BATS_TEST_TMPDIR}/defaults.log"
    GIT_LOG="${BATS_TEST_TMPDIR}/git.log"
    CLAUDE_LOG="${BATS_TEST_TMPDIR}/claude.log"
    DARWIN_REBUILD_LOG="${BATS_TEST_TMPDIR}/darwin-rebuild.log"
    NIX_LOG="${BATS_TEST_TMPDIR}/nix.log"
    SUDO_LOG="${BATS_TEST_TMPDIR}/sudo.log"
    : > "${MISE_LOG}"; : > "${COREPACK_LOG}"; : > "${DEFAULTS_LOG}"
    : > "${GIT_LOG}"; : > "${CLAUDE_LOG}"; : > "${DARWIN_REBUILD_LOG}"; : > "${NIX_LOG}"; : > "${SUDO_LOG}"
    export NODE_BIN_DIR MISE_LOG COREPACK_LOG DEFAULTS_LOG GIT_LOG CLAUDE_LOG DARWIN_REBUILD_LOG NIX_LOG SUDO_LOG
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
    # languages.zsh calls util::ensure_homebrew_path, which hardcodes the
    # real /opt/homebrew and /usr/local paths unless overridden. Point it at
    # the stub dir so the single-root-invocation test never resolves this
    # machine's real Homebrew mise (if installed) via the delegated step.
    export HOMEBREW_PATH_PREFIX_OVERRIDE="${STUB_BIN}"
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

@test "dry-run: root with a resolvable original user reports every step as WOULD RUN" {
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --dry-run
    [ "${status}" -eq 0 ]
    for step in link languages defaults pam claude-sync codex-sync cutover; do
        [[ "${output}" == *"[WOULD RUN] ${step}:"* ]]
    done
    [[ "${output}" != *"[BLOCKED]"* ]]
}

@test "dry-run: root without a resolvable original user blocks every user-owned step (fail-closed)" {
    # No SUDO_USER, no USER (e.g. a bare root login, not a sudo invocation):
    # migrate.zsh must refuse to guess who the non-root steps belong to. pam
    # needs no user identity (it only writes /etc/pam.d/sudo_local as root),
    # so it alone stays WOULD RUN.
    MIGRATE_EUID_OVERRIDE=0 USER= run zsh "${SETUP_DIR}/migrate.zsh" --dry-run
    [ "${status}" -eq 0 ]
    for step in link languages defaults claude-sync codex-sync cutover; do
        [[ "${output}" == *"[BLOCKED] ${step}:"* ]]
    done
    [[ "${output}" == *"[WOULD RUN] pam:"* ]]
}

@test "apply: as non-root, completes phase 1 (link) and halts before phase 2 (root steps)" {
    MIGRATE_EUID_OVERRIDE=501 run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 1 ]

    # Phase 1 ran for real.
    [ -L "${HOME}/.zshrc" ]

    # Phase 2 (root-only) never attempted.
    run cat "${SUDO_LOCAL_PATH}"
    [[ "${output}" != *"pam_tid.so"* ]]
    [ ! -e "${SUDO_LOCAL_PATH}.before-setup" ]
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

@test "apply: a single root invocation completes the entire migration from a clean state" {
    # One process, root the whole way through: link/languages/defaults/
    # claude-sync/codex-sync must delegate to the original user via the sudo
    # stub; cutover/pam must run directly as root (no delegation).
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"全ステップ success で完了"* ]]
    [[ "${output}" == *"health check: 全ステップの実効果を確認しました"* ]]

    [ -L "${HOME}/.zshrc" ]
    [ -f "${SUDO_LOCAL_PATH}" ]
    [ -f "${HOME}/.claude.json" ]
    [ -f "${HOME}/.codex/config.toml" ]
    run cat "${DARWIN_REBUILD_LOG}"
    [[ "${output}" == *"switch --flake"* ]]
    run cat "${MISE_LOG}"
    [[ "${output}" == *"install"* ]]
    run cat "${DEFAULTS_LOG}"
    [[ "${output}" == *"write"* ]]

    # Delegation contract: non-root steps went through
    # `sudo -u testuser -H env PATH=... zsh <script>`; root-required steps
    # did not.
    run cat "${SUDO_LOG}"
    for step in link languages defaults claude-sync codex-sync; do
        [[ "${output}" == *"-u testuser -H env PATH="*"zsh"*"${step}.zsh"* ]]
    done
    [[ "${output}" != *"cutover.zsh"* ]]
    [[ "${output}" != *"pam.zsh"* ]]

    # Idempotent re-run: everything already success, nothing re-invoked.
    local darwin_calls_before
    darwin_calls_before="$(wc -l < "${DARWIN_REBUILD_LOG}" | tr -d ' ')"
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]
    [ "$(wc -l < "${DARWIN_REBUILD_LOG}" | tr -d ' ')" -eq "${darwin_calls_before}" ]
}

@test "apply: link already done non-root, a single root invocation finishes the rest (idempotent mix)" {
    # Backward-compat path: someone still runs Phase 1 by hand as themselves
    # first; the single root invocation must skip it (manifest already
    # success) and finish Phase 2/3 via delegation.
    MIGRATE_EUID_OVERRIDE=501 run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 1 ]
    [ -L "${HOME}/.zshrc" ]

    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"link: 既に success です"* ]]
    [ -f "${HOME}/.claude.json" ]
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

    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 1 ]

    # Phase 1 (link) completed via delegation before Phase 2 was attempted.
    [ -L "${HOME}/.zshrc" ]

    # cutover failed before switch; pam (later in the same phase) never ran.
    run cat "${DARWIN_REBUILD_LOG}"
    [[ "${output}" != *"switch"* ]]
    run cat "${SUDO_LOCAL_PATH}"
    [[ "${output}" != *"pam_tid.so"* ]]
    [ ! -e "${SUDO_LOCAL_PATH}.before-setup" ]

    run cat "${HOME}/.dotfiles-migrate/manifest.log"
    [[ "${output}" == *$'\t'"cutover"$'\t'"fail"* ]]
}

@test "apply: manifest says cutover succeeded but starship is missing -> re-runs cutover in the same --apply (postcondition repair, 2026-08-22 real-machine incident)" {
    # Reach a fully successful state first (single root invocation).
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]

    # Simulate the real incident: homebrew.nix gained a new required binary
    # (starship) after this cutover already ran and recorded success. Model
    # that by removing the binary the earlier switch happened to install,
    # without touching the manifest (which still legitimately says success).
    rm -f "${STUB_BIN}/starship"
    run cat "${HOME}/.dotfiles-migrate/manifest.log"
    [[ "${output}" == *$'\t'"cutover"$'\t'"success"* ]]
    local pam_success_count_before
    pam_success_count_before="$(grep -c $'\t'pam$'\t'success "${HOME}/.dotfiles-migrate/manifest.log")"

    local darwin_calls_before
    darwin_calls_before="$(wc -l < "${DARWIN_REBUILD_LOG}" | tr -d ' ')"

    # Re-run: cutover's manifest still says success, but the postcondition
    # (starship present) is no longer met -> must not be silently skipped.
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"postcondition 未達成のため再実行"* ]]
    [[ "${output}" == *"missing: starship"* ]]

    # cutover's darwin-rebuild switch really ran again (not skipped).
    [ "$(wc -l < "${DARWIN_REBUILD_LOG}" | tr -d ' ')" -gt "${darwin_calls_before}" ]

    run cat "${HOME}/.dotfiles-migrate/manifest.log"
    [[ "${output}" == *$'\t'"cutover"$'\t'"postcondition-unmet"* ]]

    # Every real cutover re-run invalidates and force-reapplies pam (PAM
    # ownership fix, 2026-08-22): switch requires pam.d/sudo_local pristine,
    # which can wipe pam.zsh's own customization, so pam must never stay
    # silently "success" across a cutover re-run even when starship (not PAM)
    # was the trigger.
    [[ "${output}" == *$'\t'"pam"$'\t'"invalidated"* ]]
    [ "$(grep -c $'\t'pam$'\t'success "${HOME}/.dotfiles-migrate/manifest.log")" -gt "${pam_success_count_before}" ]

    # starship is back (re-installed as a side effect of the re-run), so the
    # final health check passes for real, not just because manifest says so.
    [ -x "${STUB_BIN}/starship" ]
}

@test "apply: cutover rerun safely restores pristine PAM state before switch and force-reapplies pam after (PAM ownership fix, 2026-08-22 real-machine incident)" {
    # First single-invocation run reaches full success, including pam.zsh's
    # real first-time backup (creates ${SUDO_LOCAL_PATH}.before-setup
    # pointing at the static default) and Touch ID write.
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]
    [ -L "${SUDO_LOCAL_PATH}.before-setup" ]
    [[ "$(readlink "${SUDO_LOCAL_PATH}.before-setup")" == "${SUDO_LOCAL_STATIC_DEFAULT}" ]]
    run cat "${SUDO_LOCAL_PATH}"
    [[ "${output}" == *"pam_tid.so"* ]]

    # Simulate the real incident: starship goes missing, forcing cutover to
    # re-run. nix-darwin's activation would abort on the now-customized
    # pam.d/sudo_local unless it's put back to pristine first.
    rm -f "${STUB_BIN}/starship"
    export MIGRATE_PAM_VACATE_SUFFIX_OVERRIDE="rerun1"

    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"へ退避します（既存宛先への直接 mv はしない）"* ]]
    [[ "${output}" == *"pristine 状態に戻します"* ]]

    # The exact vacate->restore sequence, verifiable via the audit trail this
    # leaves behind: the live Touch ID file was moved aside (not replaced
    # in-place) to a fresh, never-before-used path. Since pam then reapplied
    # successfully, that one vacate file is cleaned up again (its content is
    # a duplicate of what pam.zsh just rewrote) -- see the dedicated
    # preservation tests for what happens when cutover or pam fails.
    [ ! -e "${SUDO_LOCAL_PATH}.before-restore.rerun1" ]

    # pam's manifest shows the vacate event, an explicit invalidation, then a
    # fresh start+success, then the cleanup -- not a silent skip.
    run cat "${HOME}/.dotfiles-migrate/manifest.log"
    [[ "${output}" == *$'\t'"pam"$'\t'"vacated"$'\t'*"${SUDO_LOCAL_PATH}.before-restore.rerun1"* ]]
    [[ "${output}" == *$'\t'"pam"$'\t'"invalidated"* ]]
    [[ "${output}" == *$'\t'"pam"$'\t'"vacated-discarded"$'\t'*"${SUDO_LOCAL_PATH}.before-restore.rerun1"* ]]
    [ "$(grep -c $'\t'pam$'\t'success "${HOME}/.dotfiles-migrate/manifest.log")" -eq 2 ]

    # After the whole run, pam's Touch ID content is back (pam.zsh's own
    # idempotent logic recreated a fresh, correct backup rather than tripping
    # its own "backup already exists" fail-closed guard), and it was reached
    # by moving into a now-vacant path, never by replacing the live file
    # in-place.
    [ -L "${SUDO_LOCAL_PATH}.before-setup" ]
    [[ "$(readlink "${SUDO_LOCAL_PATH}.before-setup")" == "${SUDO_LOCAL_STATIC_DEFAULT}" ]]
    run cat "${SUDO_LOCAL_PATH}"
    [[ "${output}" == *"pam_tid.so"* ]]
}

@test "apply: cutover rerun refuses (fail-closed) when the PAM vacate destination already exists" {
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]

    # Pre-create the exact vacate destination this run would compute, as if
    # stray debris from an earlier interrupted attempt were already there.
    export MIGRATE_PAM_VACATE_SUFFIX_OVERRIDE="collision"
    echo "unexpected leftover" > "${SUDO_LOCAL_PATH}.before-restore.collision"

    rm -f "${STUB_BIN}/starship"
    local darwin_calls_before
    darwin_calls_before="$(wc -l < "${DARWIN_REBUILD_LOG}" | tr -d ' ')"

    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"既に存在するため復元しません"* ]]

    # fail-closed before ever touching darwin-rebuild, and the pre-existing
    # (untouched) debris and the still-live Touch ID file are both left
    # exactly as they were -- no data-destroying overwrite was attempted.
    [ "$(wc -l < "${DARWIN_REBUILD_LOG}" | tr -d ' ')" -eq "${darwin_calls_before}" ]
    run cat "${SUDO_LOCAL_PATH}.before-restore.collision"
    [ "${output}" = "unexpected leftover" ]
    run cat "${SUDO_LOCAL_PATH}"
    [[ "${output}" == *"pam_tid.so"* ]]
    run cat "${HOME}/.dotfiles-migrate/manifest.log"
    [[ "${output}" == *$'\t'"cutover"$'\t'"fail"* ]]
}

@test "apply: cutover rerun refuses (fail-closed) when the PAM backup isn't a symlink" {
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]

    # Corrupt the backup: a plain file instead of the expected symlink.
    rm -f "${SUDO_LOCAL_PATH}.before-setup"
    echo "not a symlink" > "${SUDO_LOCAL_PATH}.before-setup"

    rm -f "${STUB_BIN}/starship"
    local darwin_calls_before
    darwin_calls_before="$(wc -l < "${DARWIN_REBUILD_LOG}" | tr -d ' ')"

    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"シンボリックリンクではありません"* ]]
    [[ "${output}" == *"復元しません"* ]]

    # fail-closed before ever touching darwin-rebuild: switch must NOT run
    # against an unverified PAM backup.
    [ "$(wc -l < "${DARWIN_REBUILD_LOG}" | tr -d ' ')" -eq "${darwin_calls_before}" ]
    run cat "${HOME}/.dotfiles-migrate/manifest.log"
    [[ "${output}" == *$'\t'"cutover"$'\t'"fail"* ]]
}

@test "apply: cutover rerun refuses (fail-closed) when the PAM backup points at an unexpected target" {
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]

    # Corrupt the backup: a symlink, but pointing somewhere unexpected.
    rm -f "${SUDO_LOCAL_PATH}.before-setup"
    ln -s "${BATS_TEST_TMPDIR}/something-else" "${SUDO_LOCAL_PATH}.before-setup"

    rm -f "${STUB_BIN}/starship"
    local darwin_calls_before
    darwin_calls_before="$(wc -l < "${DARWIN_REBUILD_LOG}" | tr -d ' ')"

    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"リンク先が想定と異なります"* ]]

    [ "$(wc -l < "${DARWIN_REBUILD_LOG}" | tr -d ' ')" -eq "${darwin_calls_before}" ]
    run cat "${HOME}/.dotfiles-migrate/manifest.log"
    [[ "${output}" == *$'\t'"cutover"$'\t'"fail"* ]]
}

@test "migrate::pam_static_default derives the exact real pristine path with no escaped backslashes (regression, 2026-08-23)" {
    # migrate.zsh has its own top-level CLI dispatch, so it can't be sourced
    # directly for a unit-style call (it would `exit` before returning
    # control here). Extract just this one function's current source and
    # eval it standalone instead -- this still exercises the real deployed
    # implementation, not a re-derivation of the logic in the test.
    #
    # Uses the exact real target this repo uses in production
    # (/etc/pam.d/sudo_local, SUDO_LOCAL_STATIC_DEFAULT left unset) rather
    # than a sandboxed stand-in: every other PAM test in this file sets
    # SUDO_LOCAL_STATIC_DEFAULT explicitly, which bypasses the buggy
    # derivation branch entirely and is why it was never caught until a real
    # cutover rerun hit it. The prior bug
    # (`${target/#\/etc\//\/etc\/static\/}`) is a zsh-specific asymmetry:
    # ${var/pattern/replacement} treats `\/` in the *pattern* as a literal
    # `/`, but does NOT strip the backslash from the *replacement* text, so
    # the result was the literal string `\/etc\/static\/pam.d/sudo_local`
    # (with backslashes) instead of `/etc/static/pam.d/sudo_local`.
    local fn_source
    fn_source="$(sed -n '/^migrate::pam_static_default() {/,/^}/p' "${SETUP_DIR}/migrate.zsh")"
    [ -n "${fn_source}" ]

    unset SUDO_LOCAL_STATIC_DEFAULT
    run zsh -c "${fn_source}"$'\n'"migrate::pam_static_default '/etc/pam.d/sudo_local'"
    [ "${status}" -eq 0 ]
    [ "${output}" = "/etc/static/pam.d/sudo_local" ]
    [[ "${output}" != *'\'* ]]
}

@test "dry-run: cutover shows WOULD RUN (not SKIP) when manifest says success but starship is missing" {
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]

    rm -f "${STUB_BIN}/starship"

    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --dry-run
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"[WOULD RUN] cutover: postcondition 未達成のため再実行 (missing: starship)"* ]]
    [[ "${output}" == *"[SKIP] pam:"* ]]
    [[ "${output}" != *"[SKIP] cutover:"* ]]
}

@test "health check re-verifies real state and does not just trust a success manifest" {
    # Reach full success via a single root invocation first.
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
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

# ---------------------------------------------------------------------------
# desired-input fingerprint（宣言側の変更を cutover の skip 判定に反映する）
# ---------------------------------------------------------------------------

# Blank out the fingerprint detail recorded on cutover's success line, leaving
# the line otherwise intact. This is exactly the shape of a manifest written by
# an older migrate.zsh that had no fingerprint concept at all.
_strip_cutover_fingerprint() {
    local manifest="${HOME}/.dotfiles-migrate/manifest.log"
    awk -F'\t' -v OFS='\t' '$2=="cutover" && $3=="success" {$4=""} {print}' \
        "${manifest}" > "${manifest}.legacy"
    mv "${manifest}.legacy" "${manifest}"
}

_darwin_calls() { wc -l < "${DARWIN_REBUILD_LOG}" | tr -d ' '; }
_manifest_lines() { wc -l < "${HOME}/.dotfiles-migrate/manifest.log" | tr -d ' '; }

# Use a private, writable copy of nix/ so a test can mutate the declaration
# without touching this repository's real checkout.
_use_private_nix_dir() {
    export MIGRATE_NIX_DIR_OVERRIDE="${BATS_TEST_TMPDIR}/nix"
    cp -R "${REPO_ROOT}/nix" "${MIGRATE_NIX_DIR_OVERRIDE}"
}

@test "apply: a legacy cutover success without a recorded fingerprint re-runs cutover exactly once (safe side)" {
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]

    _strip_cutover_fingerprint
    local calls_before manifest_before
    calls_before="$(_darwin_calls)"
    manifest_before="$(_manifest_lines)"

    # dry-run must surface it as a re-run, and stay side-effect free.
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --dry-run
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"[WOULD RUN] cutover:"* ]]
    [[ "${output}" == *"fingerprint"* ]]
    [[ "${output}" != *"[SKIP] cutover:"* ]]
    [ "$(_darwin_calls)" -eq "${calls_before}" ]
    [ "$(_manifest_lines)" -eq "${manifest_before}" ]

    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]
    [ "$(_darwin_calls)" -gt "${calls_before}" ]

    run cat "${HOME}/.dotfiles-migrate/manifest.log"
    [[ "${output}" == *$'\t'"cutover"$'\t'"postcondition-unmet"* ]]

    # Exactly once: the re-run records a fingerprint, so the next apply skips
    # again instead of switching on every invocation forever.
    local calls_after
    calls_after="$(_darwin_calls)"
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]
    [ "$(_darwin_calls)" -eq "${calls_after}" ]
}

@test "dry-run: cutover shows SKIP while the recorded fingerprint still matches the current declaration" {
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]

    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --dry-run
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"[SKIP] cutover:"* ]]
    [[ "${output}" != *"[WOULD RUN] cutover:"* ]]
}

@test "apply: a changed nix declaration re-runs cutover even though every required binary is present" {
    _use_private_nix_dir

    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]
    [ -x "${STUB_BIN}/starship" ]

    # Model "pulled main on another machine": the Homebrew declaration changed,
    # nothing about the local binaries did.
    echo '# a newly declared cask' >> "${MIGRATE_NIX_DIR_OVERRIDE}/modules/darwin/homebrew.nix"

    local calls_before
    calls_before="$(_darwin_calls)"
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"再実行"* ]]
    [ "$(_darwin_calls)" -gt "${calls_before}" ]

    # A newly added file (not just edited content) counts as a changed input too.
    calls_before="$(_darwin_calls)"
    echo '{ }' > "${MIGRATE_NIX_DIR_OVERRIDE}/modules/darwin/extra.nix"
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]
    [ "$(_darwin_calls)" -gt "${calls_before}" ]

    # And a lock bump, which changes nothing else about the tree.
    calls_before="$(_darwin_calls)"
    echo '' >> "${MIGRATE_NIX_DIR_OVERRIDE}/flake.lock"
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]
    [ "$(_darwin_calls)" -gt "${calls_before}" ]
}

@test "apply: the role file appearing or changing re-runs cutover (role selects a different desired set)" {
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]

    # absent -> present
    local calls_before
    calls_before="$(_darwin_calls)"
    echo "sub-1" > "${DOTFILES_ROLE_FILE}"
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]
    [ "$(_darwin_calls)" -gt "${calls_before}" ]

    # content change (sub-1 -> default selects the defaultOnly* sets)
    calls_before="$(_darwin_calls)"
    echo "default" > "${DOTFILES_ROLE_FILE}"
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]
    [ "$(_darwin_calls)" -gt "${calls_before}" ]

    # unchanged -> skip again
    calls_before="$(_darwin_calls)"
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]
    [ "$(_darwin_calls)" -eq "${calls_before}" ]
}

@test "apply: the machine-local homebrew overlay appearing or changing re-runs cutover" {
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]

    local overlay="${HOME}/.config/dotfiles/homebrew.local.nix"
    mkdir -p "$(dirname "${overlay}")"

    # absent -> present
    local calls_before
    calls_before="$(_darwin_calls)"
    echo '{ casks = [ "some-local-app" ]; }' > "${overlay}"
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]
    [ "$(_darwin_calls)" -gt "${calls_before}" ]

    # content change
    calls_before="$(_darwin_calls)"
    echo '{ casks = [ "another-local-app" ]; }' > "${overlay}"
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]
    [ "$(_darwin_calls)" -gt "${calls_before}" ]

    # removal counts as a change as well (zap would take the cask back out)
    calls_before="$(_darwin_calls)"
    rm -f "${overlay}"
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]
    [ "$(_darwin_calls)" -gt "${calls_before}" ]
}

@test "apply: cutover records the fingerprint the switch actually read, not the tree as it looks afterwards" {
    _use_private_nix_dir

    # Model a switch that races with the declaration changing underneath it
    # (e.g. a `git pull` landing while darwin-rebuild is still running). If
    # the fingerprint were taken after the switch, the change this switch
    # never saw would be recorded as already applied and silently lost.
    cat > "${STUB_BIN}/darwin-rebuild" <<'EOF'
#!/bin/bash
echo "$*" >> "${DARWIN_REBUILD_LOG}"
if [[ "$1" == "--list-generations" ]]; then
    echo "42 2026-08-20 10:00:00 (current)"
elif [[ "$1" == "switch" ]]; then
    printf '#!/bin/bash\nexit 0\n' > "$(dirname "$0")/starship"
    chmod +x "$(dirname "$0")/starship"
    echo '# landed mid-switch' >> "${MIGRATE_NIX_DIR_OVERRIDE}/modules/darwin/homebrew.nix"
fi
exit "${DARWIN_REBUILD_EXIT:-0}"
EOF
    chmod +x "${STUB_BIN}/darwin-rebuild"

    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]

    # The very next apply must pick the change up instead of treating it as
    # already switched in.
    local calls_before
    calls_before="$(_darwin_calls)"
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --dry-run
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"[WOULD RUN] cutover:"* ]]

    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]
    [ "$(_darwin_calls)" -gt "${calls_before}" ]
}

@test "apply: a new symlink under nix/ re-runs cutover (link target is fingerprint material, not silently followed)" {
    _use_private_nix_dir

    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]

    local calls_before
    calls_before="$(_darwin_calls)"
    ln -s ../../shared/overlay.nix "${MIGRATE_NIX_DIR_OVERRIDE}/modules/darwin/overlay.nix"
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]
    [ "$(_darwin_calls)" -gt "${calls_before}" ]

    # Repointing an existing symlink is a declaration change too, even though
    # neither the link's path nor any regular file's content moved.
    calls_before="$(_darwin_calls)"
    rm -f "${MIGRATE_NIX_DIR_OVERRIDE}/modules/darwin/overlay.nix"
    ln -s ../../shared/other.nix "${MIGRATE_NIX_DIR_OVERRIDE}/modules/darwin/overlay.nix"
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]
    [ "$(_darwin_calls)" -gt "${calls_before}" ]

    # Unchanged -> back to skipping (a dangling link must not make every
    # single apply switch forever).
    calls_before="$(_darwin_calls)"
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]
    [ "$(_darwin_calls)" -eq "${calls_before}" ]
}

# Reach the state every PAM-cleanup test starts from: a machine already fully
# migrated, with pam.zsh's real backup in place and cutover about to re-run.
_reach_pam_rerun_state() {
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]
    [ -L "${SUDO_LOCAL_PATH}.before-setup" ]

    rm -f "${STUB_BIN}/starship"
}

@test "apply: PAM vacate cleanup removes only the file this run created, leaving older debris alone" {
    _reach_pam_rerun_state

    # Debris from some earlier, unrelated attempt. Cleanup must be scoped to
    # the one path this apply computed, never a glob over every vacate file.
    echo "older debris" > "${SUDO_LOCAL_PATH}.before-restore.20260101T000000Z"

    export MIGRATE_PAM_VACATE_SUFFIX_OVERRIDE="cleanup1"
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]

    [ ! -e "${SUDO_LOCAL_PATH}.before-restore.cleanup1" ]
    run cat "${SUDO_LOCAL_PATH}.before-restore.20260101T000000Z"
    [ "${output}" = "older debris" ]

    # The Touch ID content the vacate file held is not lost: pam.zsh rewrote
    # it, which is the whole reason the duplicate is safe to drop.
    run cat "${SUDO_LOCAL_PATH}"
    [[ "${output}" == *"pam_tid.so"* ]]

    run cat "${HOME}/.dotfiles-migrate/manifest.log"
    [[ "${output}" == *$'\t'"pam"$'\t'"vacated-discarded"* ]]
}

@test "apply: the PAM vacate file is preserved when cutover fails after vacating" {
    _reach_pam_rerun_state

    local touch_id_content_before
    touch_id_content_before="$(cat "${SUDO_LOCAL_PATH}")"
    export MIGRATE_PAM_VACATE_SUFFIX_OVERRIDE="cutoverfail"

    # cutover.zsh's pre-flight `nix build` fails, so the switch never runs --
    # but the vacate already happened, and it holds the only copy of the live
    # Touch ID file at that moment.
    cat > "${STUB_BIN}/nix" <<'EOF'
#!/bin/bash
echo "$*" >> "${NIX_LOG}"
exit 1
EOF
    chmod +x "${STUB_BIN}/nix"

    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 1 ]

    [ -f "${SUDO_LOCAL_PATH}.before-restore.cutoverfail" ]
    run cat "${SUDO_LOCAL_PATH}.before-restore.cutoverfail"
    [ "${output}" = "${touch_id_content_before}" ]

    run cat "${HOME}/.dotfiles-migrate/manifest.log"
    [[ "${output}" == *$'\t'"cutover"$'\t'"fail"* ]]
    [[ "${output}" != *"vacated-discarded"* ]]
}

@test "apply: the PAM vacate file is preserved when pam fails to reapply after the switch" {
    _reach_pam_rerun_state

    local touch_id_content_before
    touch_id_content_before="$(cat "${SUDO_LOCAL_PATH}")"
    export MIGRATE_PAM_VACATE_SUFFIX_OVERRIDE="pamfail"

    # Model activation leaving stray state in /etc: a leftover .before-setup
    # is exactly what pam.zsh refuses to overwrite (its own fail-closed
    # guard), so pam fails after the switch already happened.
    cat > "${STUB_BIN}/darwin-rebuild" <<'EOF'
#!/bin/bash
echo "$*" >> "${DARWIN_REBUILD_LOG}"
if [[ "$1" == "--list-generations" ]]; then
    echo "42 2026-08-20 10:00:00 (current)"
elif [[ "$1" == "switch" ]]; then
    printf '#!/bin/bash\nexit 0\n' > "$(dirname "$0")/starship"
    chmod +x "$(dirname "$0")/starship"
    echo "stray leftover" > "${SUDO_LOCAL_PATH}.before-setup"
fi
exit 0
EOF
    chmod +x "${STUB_BIN}/darwin-rebuild"

    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 1 ]

    # pam never reapplied, so the vacate file is the only remaining copy of
    # the Touch ID content and must survive untouched.
    [ -f "${SUDO_LOCAL_PATH}.before-restore.pamfail" ]
    run cat "${SUDO_LOCAL_PATH}.before-restore.pamfail"
    [ "${output}" = "${touch_id_content_before}" ]

    run cat "${HOME}/.dotfiles-migrate/manifest.log"
    [[ "${output}" == *$'\t'"pam"$'\t'"fail"* ]]
    [[ "${output}" != *"vacated-discarded"* ]]
}

@test "apply: PAM vacate cleanup keeps a vacate file whose content differs from the reapplied target (hand-added rules survive)" {
    _reach_pam_rerun_state

    # A rule added by hand on this machine, on top of what pam.zsh writes.
    # pam.zsh rewrites the file from its own fixed template, so this line only
    # ever exists in the vacate copy after a cutover rerun -- deleting that
    # copy just because it is a regular file would destroy it.
    printf 'auth       sufficient     pam_reattach.so\n' >> "${SUDO_LOCAL_PATH}"
    local target_content_before
    target_content_before="$(cat "${SUDO_LOCAL_PATH}")"

    export MIGRATE_PAM_VACATE_SUFFIX_OVERRIDE="handwritten"
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]

    [ -f "${SUDO_LOCAL_PATH}.before-restore.handwritten" ]
    run cat "${SUDO_LOCAL_PATH}.before-restore.handwritten"
    [ "${output}" = "${target_content_before}" ]
    [[ "${output}" == *"pam_reattach.so"* ]]

    # Kept, not discarded -- and keeping it is not reported as a failure.
    run cat "${HOME}/.dotfiles-migrate/manifest.log"
    [[ "${output}" == *$'\t'"pam"$'\t'"vacated-kept"* ]]
    [[ "${output}" != *"vacated-discarded"* ]]
    [[ "${output}" == *$'\t'"pam"$'\t'"success"* ]]

    # Once the live file matches what pam.zsh writes again, the next rerun's
    # vacate copy is a true duplicate and is cleaned up as usual.
    rm -f "${STUB_BIN}/starship"
    export MIGRATE_PAM_VACATE_SUFFIX_OVERRIDE="duplicate"
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]

    [ ! -e "${SUDO_LOCAL_PATH}.before-restore.duplicate" ]
    [ -f "${SUDO_LOCAL_PATH}.before-restore.handwritten" ]
    run cat "${HOME}/.dotfiles-migrate/manifest.log"
    [[ "${output}" == *$'\t'"pam"$'\t'"vacated-discarded"$'\t'*"${SUDO_LOCAL_PATH}.before-restore.duplicate"* ]]
}

@test "apply: cutover rerun proceeds when neither the PAM target nor its backup exists (true first-time shape)" {
    _reach_pam_rerun_state

    # Nothing to restore and nothing to protect: no sudo_local at all is the
    # genuine pre-pam.zsh shape, and it is already pristine as far as
    # nix-darwin is concerned.
    rm -f "${SUDO_LOCAL_PATH}" "${SUDO_LOCAL_PATH}.before-setup"

    local calls_before
    calls_before="$(_darwin_calls)"
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 0 ]

    [ "$(_darwin_calls)" -gt "${calls_before}" ]
    run cat "${DARWIN_REBUILD_LOG}"
    [[ "${output}" == *"switch --flake"* ]]

    # pam reapplied on top of the empty slate.
    run cat "${SUDO_LOCAL_PATH}"
    [[ "${output}" == *"pam_tid.so"* ]]
}

@test "apply: cutover rerun refuses (fail-closed) when the PAM target is customized but its backup is gone" {
    _reach_pam_rerun_state

    # The backup is the only record of what pristine looked like. Without it,
    # the customized target cannot be restored, and guessing its pristine form
    # would mean overwriting a file whose content nothing else records.
    rm -f "${SUDO_LOCAL_PATH}.before-setup"
    [ -f "${SUDO_LOCAL_PATH}" ]
    [ ! -L "${SUDO_LOCAL_PATH}" ]
    local target_content_before
    target_content_before="$(cat "${SUDO_LOCAL_PATH}")"

    local calls_before
    calls_before="$(_darwin_calls)"
    MIGRATE_EUID_OVERRIDE=0 MIGRATE_SUDO_USER_OVERRIDE=testuser \
        run zsh "${SETUP_DIR}/migrate.zsh" --apply
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"復元しません"* ]]

    # Stopped before cutover ever shelled out, and the live file is byte-identical.
    [ "$(_darwin_calls)" -eq "${calls_before}" ]
    run cat "${SUDO_LOCAL_PATH}"
    [ "${output}" = "${target_content_before}" ]
    [ ! -e "${SUDO_LOCAL_PATH}.before-setup" ]

    run cat "${HOME}/.dotfiles-migrate/manifest.log"
    [[ "${output}" == *$'\t'"cutover"$'\t'"fail"* ]]
    [[ "${output}" != *$'\t'"pam"$'\t'"vacated"* ]]
}
