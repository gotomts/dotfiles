#!/bin/zsh
# setup/claude-sync.zsh
#
# Tier 2: Claude Code の running-config 同期。
#   1. gotomts/skills（自作 skill の SSOT）を不在時のみ clone する
#   2. settings.json の enabledPlugins のうち未インストールのものだけ `claude plugin install`
#   3. claude/mcp-servers.json を ~/.claude.json の .mcpServers へ add-only recursive merge
#
# nix/modules/home/claude.nix の home.activation.{cloneSkillsRepo,claudePlugins,
# syncClaudeMcpServers} を移植したもの（ロジック変更なし）。symlink 配置自体（settings.json/
# CLAUDE.md/AGENTS.md/skills/hooks）は Tier 1 の setup/link.zsh が既に担当済み。
#
# 使い方:
#   zsh ${HOME}/.dotfiles/setup/claude-sync.zsh
#
# 終了コード: 常に 0（fail-open。個々のステップの失敗は warning ログのみで継続する。
# SSH 鍵未設定や claude CLI 未インストールの新規 PC で環境構築全体が止まる方が害が大きいため、
# nix 版と同じ設計判断を踏襲する）

SETUP_DIR="${0:A:h}"
DOTFILES_ROOT="${SETUP_DIR:h}"
source "${SETUP_DIR}/lib/util.zsh"

util::info "=== Tier 2: Claude Code sync ==="

# ---------------------------------------------------------------------------
# 1. skills repo clone-if-absent
# ---------------------------------------------------------------------------
claude-sync::clone_skills_repo() {
    local skills_repo="${HOME}/ghq/github.com/gotomts/skills"

    if [[ -e "${skills_repo}" ]]; then
        if ! git -C "${skills_repo}" rev-parse --git-dir &>/dev/null; then
            util::warning "${skills_repo} が git 作業ツリーではない。skill の symlink が dangling のままになる"
        else
            util::skip "${skills_repo} は既に存在します"
        fi
        return 0
    fi

    mkdir -p "${skills_repo:h}"

    GIT_SSH_COMMAND="/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=10" \
        git clone ssh://git@github.com/gotomts/skills.git "${skills_repo}" \
        && util::info "skills repo cloned to ${skills_repo}" \
        || util::warning "skills repo の clone 失敗 (SSH 鍵未設定なら手動 clone が必要)"
}

# ---------------------------------------------------------------------------
# 2. claude plugin 宣言的同期 (未インストール分のみ install)
# ---------------------------------------------------------------------------
claude-sync::sync_plugins() {
    if ! command -v claude &>/dev/null; then
        util::warning "claude CLI 未インストール、plugin 同期をスキップ"
        return 0
    fi

    local settings="${HOME}/.claude/settings.json"
    if [[ ! -f "${settings}" ]]; then
        util::warning "settings.json 不在、plugin 同期をスキップ"
        return 0
    fi

    local installed
    installed="$(claude plugin list --json 2>/dev/null)"
    if [[ $? -ne 0 || -z "${installed}" ]]; then
        util::warning "plugin list の取得に失敗、plugin 同期をスキップ"
        return 0
    fi

    jq -r --argjson installed "${installed}" '
        ($installed | map(.id)) as $have
        | (.enabledPlugins // {} | keys[])
        | select(. as $p | $have | index($p) | not)
    ' "${settings}" 2>/dev/null | while IFS= read -r plugin; do
        claude plugin install "${plugin}" 2>/dev/null \
            && util::info "plugin ${plugin}: installed" \
            || util::warning "plugin ${plugin}: install failed"
    done
}

# ---------------------------------------------------------------------------
# 3. MCP servers (user scope) の declarative 同期
# ---------------------------------------------------------------------------
claude-sync::sync_mcp_servers() {
    local target="${HOME}/.claude.json"
    local decl="${DOTFILES_ROOT}/claude/mcp-servers.json"

    if [[ ! -f "${decl}" ]]; then
        util::warning "mcp-servers.json 不在、MCP 同期をスキップ"
        return 0
    fi

    if [[ ! -f "${target}" ]]; then
        touch "${target}"
        chmod 600 "${target}"
        echo '{}' > "${target}"
    fi

    local tmp
    tmp="$(mktemp)"
    if jq --slurpfile d "${decl}" '
        .mcpServers = ((.mcpServers // {}) * ($d[0].mcpServers // {}))
    ' "${target}" > "${tmp}"; then
        mv "${tmp}" "${target}"
        chmod 600 "${target}"
        util::info "MCP servers synced to ${target}"
    else
        rm -f "${tmp}"
        util::error "MCP sync failed (jq error)"
    fi
}

claude-sync::clone_skills_repo
claude-sync::sync_plugins
claude-sync::sync_mcp_servers

util::info "=== Tier 2: Claude Code sync 完了 ==="
