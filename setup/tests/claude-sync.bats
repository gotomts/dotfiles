#!/usr/bin/env bats
# setup/tests/claude-sync.bats

SETUP_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
REPO_ROOT="$(cd "${SETUP_DIR}/.." && pwd)"

_install_git_clone_stub() {
    local bin_dir="${1}"
    mkdir -p "${bin_dir}"
    cat > "${bin_dir}/git" <<EOF
#!/bin/zsh
echo "\$*" >> "${GIT_LOG}"
if [[ "\$1" == "clone" ]]; then
    mkdir -p "\$3"
    exit 0
fi
exec /usr/bin/git "\$@"
EOF
    chmod +x "${bin_dir}/git"
}

_install_claude_stub() {
    local bin_dir="${1}"
    local installed_json="${2}"
    mkdir -p "${bin_dir}"
    cat > "${bin_dir}/claude" <<EOF
#!/bin/zsh
echo "\$*" >> "${CLAUDE_LOG}"
if [[ "\$1" == "plugin" && "\$2" == "list" ]]; then
    cat <<'JSON'
${installed_json}
JSON
    exit 0
fi
if [[ "\$1" == "plugin" && "\$2" == "install" ]]; then
    exit 0
fi
exit 0
EOF
    chmod +x "${bin_dir}/claude"
}

setup() {
    STUB_BIN="${BATS_TEST_TMPDIR}/stub-bin"
    GIT_LOG="${BATS_TEST_TMPDIR}/git.log"
    CLAUDE_LOG="${BATS_TEST_TMPDIR}/claude.log"
    : > "${GIT_LOG}"
    : > "${CLAUDE_LOG}"
    export GIT_LOG CLAUDE_LOG
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}/.claude"
}

@test "zsh -n syntax check passes" {
    run zsh -n "${SETUP_DIR}/claude-sync.zsh"
    [ "${status}" -eq 0 ]
}

@test "skips skills repo clone when it already exists as a git worktree" {
    local skills_dir="${HOME}/ghq/github.com/gotomts/skills"
    mkdir -p "${skills_dir}"
    (cd "${skills_dir}" && /usr/bin/git init -q)
    _install_git_clone_stub "${STUB_BIN}"
    _install_claude_stub "${STUB_BIN}" '[]'

    PATH="${STUB_BIN}:${PATH}" run zsh "${SETUP_DIR}/claude-sync.zsh"
    [ "${status}" -eq 0 ]

    run grep -c '^clone ' "${GIT_LOG}"
    [ "${status}" -eq 1 ]
}

@test "clones skills repo when absent" {
    _install_git_clone_stub "${STUB_BIN}"
    _install_claude_stub "${STUB_BIN}" '[]'

    PATH="${STUB_BIN}:${PATH}" run zsh "${SETUP_DIR}/claude-sync.zsh"
    [ "${status}" -eq 0 ]

    run cat "${GIT_LOG}"
    [[ "${output}" == *"clone ssh://git@github.com/gotomts/skills.git ${HOME}/ghq/github.com/gotomts/skills"* ]]
}

@test "MCP merge creates ~/.claude.json and preserves unrelated existing keys" {
    _install_git_clone_stub "${STUB_BIN}"
    _install_claude_stub "${STUB_BIN}" '[]'
    mkdir -p "${HOME}/ghq/github.com/gotomts/skills"
    (cd "${HOME}/ghq/github.com/gotomts/skills" && /usr/bin/git init -q)

    cat > "${HOME}/.claude.json" <<'JSON'
{
  "oauthAccount": { "id": "keep-me" },
  "mcpServers": { "custom-local": { "type": "stdio", "command": "custom" } }
}
JSON

    PATH="${STUB_BIN}:${PATH}" run zsh "${SETUP_DIR}/claude-sync.zsh"
    [ "${status}" -eq 0 ]

    run jq -r '.oauthAccount.id' "${HOME}/.claude.json"
    [ "${output}" = "keep-me" ]

    run jq -r '.mcpServers["custom-local"].command' "${HOME}/.claude.json"
    [ "${output}" = "custom" ]

    run jq -r '.mcpServers.linear.url' "${HOME}/.claude.json"
    [ "${output}" = "https://mcp.linear.app/mcp" ]
}

@test "plugin sync installs only the plugins missing from claude plugin list" {
    _install_git_clone_stub "${STUB_BIN}"
    mkdir -p "${HOME}/ghq/github.com/gotomts/skills"
    (cd "${HOME}/ghq/github.com/gotomts/skills" && /usr/bin/git init -q)

    cat > "${HOME}/.claude/settings.json" <<'JSON'
{
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true,
    "context7@claude-plugins-official": true
  }
}
JSON

    _install_claude_stub "${STUB_BIN}" '[{"id": "superpowers@claude-plugins-official"}]'

    PATH="${STUB_BIN}:${PATH}" run zsh "${SETUP_DIR}/claude-sync.zsh"
    [ "${status}" -eq 0 ]

    run grep -c '^plugin install context7@claude-plugins-official$' "${CLAUDE_LOG}"
    [ "${status}" -eq 0 ]
    run grep -c '^plugin install superpowers@claude-plugins-official$' "${CLAUDE_LOG}"
    [ "${status}" -eq 1 ]
}

@test "plugin sync is skipped (exit 0) when settings.json is absent" {
    _install_git_clone_stub "${STUB_BIN}"
    _install_claude_stub "${STUB_BIN}" '[]'
    mkdir -p "${HOME}/ghq/github.com/gotomts/skills"
    (cd "${HOME}/ghq/github.com/gotomts/skills" && /usr/bin/git init -q)
    rm -f "${HOME}/.claude/settings.json"

    PATH="${STUB_BIN}:${PATH}" run zsh "${SETUP_DIR}/claude-sync.zsh"
    [ "${status}" -eq 0 ]

    run grep -c '^plugin install' "${CLAUDE_LOG}"
    [ "${status}" -eq 1 ]
}
