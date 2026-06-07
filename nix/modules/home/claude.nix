{ pkgs, lib, config, role, ... }:

# ~/.claude/ の設定・skills・agents を dotfiles から配置する home-manager モジュール。
# mkOutOfStoreSymlink で working tree を直接指すため、追加・編集は git pull で即反映される。
let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  # default role = 自分の開発機 (fleet 層も展開)。sub-1 等 = fleet なし。
  isDefault = role == "default";
in
{
  # 個人層 (claude/skills) は全 role で可視。fleet 層 (claude/fleet/{skills,agents})
  # は default role のみローカル展開。remote では inject-fleet.sh が別途 inject する。
  home.file = {
    ".claude/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/settings.json";
    ".claude/CLAUDE.md".source     = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/CLAUDE.md";
    ".claude/AGENTS.md".source     = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/AGENTS.md";
  }
  // lib.optionalAttrs isDefault {
    ".claude/agents".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/fleet/agents";
  }
  // lib.optionalAttrs (!isDefault) {
    ".claude/skills".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/skills";
  };

  # default role の ~/.claude/skills は個人層 + fleet 層のマージ。2 つの source dir を
  # 1 symlink で束ねられず、eval 時の dir 読み取りは CI を壊すため、activation で
  # per-entry symlink を張り直す (working tree を指すので編集は即反映)。
  home.activation.claudeFleetSkills = lib.mkIf isDefault (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      _link_claude_skills() {
        set +e
        local target="''${HOME}/.claude/skills"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm -rf "$target"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$target"
        local src entry
        for src in "${dotfiles}/claude/skills" "${dotfiles}/claude/fleet/skills"; do
          [ -d "$src" ] || continue
          for entry in "$src"/*; do
            [ -e "$entry" ] || continue
            $DRY_RUN_CMD ${pkgs.coreutils}/bin/ln -sfn "$entry" "$target/$(${pkgs.coreutils}/bin/basename "$entry")"
          done
        done
      }
      _link_claude_skills
    ''
  );

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
