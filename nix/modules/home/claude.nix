{ pkgs, lib, config, ... }:

# ~/.claude/ の設定・skills を dotfiles から配置する home-manager モジュール。
# mkOutOfStoreSymlink で working tree を直接指すため、追加・編集は git pull で即反映される。
let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
in
{
  home.file = {
    ".claude/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/settings.json";
    ".claude/CLAUDE.md".source     = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/CLAUDE.md";
    ".claude/AGENTS.md".source     = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/AGENTS.md";
    ".claude/skills".source        = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/skills";
  };

  # claude plugin の宣言的同期。settings.json の enabledPlugins を CLI で install/update。
  home.activation.claudePlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    _run_claude_plugin_sync() {
      set +e  # 個々のプラグイン失敗で関数内処理を止めない

      if ! command -v claude &>/dev/null; then
        echo "[claude.nix] claude CLI 未インストール、plugin 同期をスキップ"
        return 0
      fi

      local SETTINGS="''${HOME}/.claude/settings.json"
      if [ ! -f "$SETTINGS" ]; then
        echo "[claude.nix] settings.json 不在、plugin 同期をスキップ"
        return 0
      fi

      $DRY_RUN_CMD claude plugin marketplace update 2>/dev/null || true

      ${pkgs.jq}/bin/jq -r '.enabledPlugins // {} | keys[]' "$SETTINGS" 2>/dev/null | while IFS= read -r plugin; do
        if claude plugin list --json 2>/dev/null | ${pkgs.jq}/bin/jq -e --arg p "$plugin" '.[] | select(.id == $p)' &>/dev/null; then
          $DRY_RUN_CMD claude plugin update "$plugin" 2>/dev/null || \
            echo "[claude.nix] plugin $plugin: update failed"
        else
          $DRY_RUN_CMD claude plugin install "$plugin" 2>/dev/null && \
            echo "[claude.nix] plugin $plugin: installed" || \
            echo "[claude.nix] plugin $plugin: install failed"
        fi
      done
    }

    _run_claude_plugin_sync
  '';

  # MCP server (user scope) の declarative 同期。~/.claude.json は Claude Code が動的に
  # 書き換える running config (OAuth token 等) で symlink 化できないため、jq で
  # recursive merge する (add-only、宣言外エントリは保持)。
  home.activation.syncClaudeMcpServers = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    _run_claude_mcp_sync() {
      set +e

      local target="''${HOME}/.claude.json"
      local decl="${dotfiles}/claude/mcp-servers.json"

      if [ ! -f "$decl" ]; then
        echo "[claude.nix] mcp-servers.json 不在、MCP 同期をスキップ"
        return 0
      fi

      if [ ! -f "$target" ]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/touch "$target"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod 600 "$target"
        $DRY_RUN_CMD ${pkgs.bash}/bin/sh -c "echo '{}' > '$target'"
      fi

      local tmp
      tmp=$(${pkgs.coreutils}/bin/mktemp)
      if ${pkgs.jq}/bin/jq --slurpfile d "$decl" '
        .mcpServers = ((.mcpServers // {}) * ($d[0].mcpServers // {}))
      ' "$target" > "$tmp"; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/mv "$tmp" "$target"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod 600 "$target"
        echo "[claude.nix] MCP servers synced to $target"
      else
        ${pkgs.coreutils}/bin/rm -f "$tmp"
        echo "[claude.nix] MCP sync failed (jq error)"
      fi
    }

    _run_claude_mcp_sync
  '';
}
