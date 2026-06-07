{ pkgs, lib, config, role, ... }:

# このモジュールは setup.zsh の claude/ symlink ループ + setup/install/10_claude.zsh の
# symlink セクション（ステップ 2, 3）を home-manager で置換したもの (両スクリプト削除済み)。
#
# mkOutOfStoreSymlink で dotfiles working tree への直接 symlink を張るため、
# skills/agents/hooks/設定ファイルの追加・編集は git pull (or 直接編集) で即反映される
# (darwin-rebuild switch は不要)。トレードオフとして ~/.dotfiles/ が存在しない PC では
# dangling symlink になるが、本リポジトリ前提の運用なので許容する。
let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  # role 別 profile (flake.nix が /etc/dotfiles-role から解決して inject)。
  # default = 自分の開発機。AI 組織開発をベースにするため fleet 層も展開する。
  # sub-1 等 = クライアント作業など。fleet は入れない。
  isDefault = role == "default";
in
{
  # ~/.claude/{settings.json,CLAUDE.md,AGENTS.md} と skills/agents を dotfiles から
  # 配置する。AGENTS.md はグローバル指示のマスターで Claude Code は CLAUDE.md の
  # @AGENTS.md import で取り込む。Codex 等の他 AI ツール向けには
  # nix/modules/home/codex.nix が同じ AGENTS.md を ~/.codex/AGENTS.md に
  # symlink して共有する。
  #
  # 二層レイアウト × role:
  #  - 個人・常用層 (claude/skills = 自作 + 外部 vendor) は全 role で可視。
  #  - AI 組織専用の fleet 層 (claude/fleet/skills = 公式 vendored スキル,
  #    claude/fleet/agents = dev-*/rev-* サブエージェント。DOT-45 で claude/agents
  #    から移動) は **default role のみ** ローカルにも展開する (DOT-45 改訂:
  #    AI 組織開発を default のベースにする)。sub-1 等の別 role には入れない。
  #  - default role の skills は「個人層 + fleet」を 1 つの ~/.claude/skills に
  #    マージする必要があるが、2 つの source dir を 1 symlink で束ねられないため、
  #    home.file の whole-dir symlink ではなく activation で per-entry symlink を
  #    張り直す (下記 claudeFleetSkills)。fleet/agents は個人層 agents が空なので
  #    whole-dir symlink で足りる。
  #  - Claude Code on the web (remote) では role に依らず SessionStart hook
  #    claude/fleet/inject-fleet.sh が CLAUDE_CODE_REMOTE 環境で
  #    ~/.claude/{skills,agents} へ inject する (canonical 方式・本モジュールとは独立)。
  home.file = {
    ".claude/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/settings.json";
    ".claude/CLAUDE.md".source     = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/CLAUDE.md";
    ".claude/AGENTS.md".source     = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/AGENTS.md";
  }
  // lib.optionalAttrs isDefault {
    # default role: fleet agents を whole-dir symlink (個人層 agents は空のため衝突なし)。
    ".claude/agents".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/fleet/agents";
  }
  // lib.optionalAttrs (!isDefault) {
    # 非 default role: 個人層スキルのみ。fleet・agents は展開しない。
    ".claude/skills".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/skills";
  };

  # default role: ~/.claude/skills を「個人層 + fleet 層」のマージとして per-entry
  # symlink で組み立てる。working tree を指す symlink なので個々のファイル編集は即反映
  # (skill の追加・削除のみ次回 switch が必要)。CI (nix build) では activation は走らない
  # ため eval 時に working tree を読まず CI-safe。
  home.activation.claudeFleetSkills = lib.mkIf isDefault (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      _link_claude_skills() {
        set +e
        local target="''${HOME}/.claude/skills"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm -rf "$target"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$target"
        local src entry
        # 個人層 → fleet 層の順。名前衝突時は後勝ち (現状 overlap なし)。
        for src in "${dotfiles}/claude/skills" "${dotfiles}/claude/fleet/skills"; do
          [ -d "$src" ] || continue
          for entry in "$src"/*; do
            [ -e "$entry" ] || continue
            $DRY_RUN_CMD ${pkgs.coreutils}/bin/ln -sfn "$entry" "$target/$(${pkgs.coreutils}/bin/basename "$entry")"
          done
        done
        echo "[claude.nix] default role: ~/.claude/skills = 個人層 + fleet (per-entry symlink)"
      }
      _link_claude_skills
    ''
  );

  # claude plugin の宣言的同期。
  # enabledPlugins キーを settings.json から読んで CLI で install/update を実行する。
  # writeBoundary 後に走らせることで symlink が確立された状態で実行される。
  # 関数化により set +e / return 0 を局所化し、後続 activation への漏出を防ぐ。
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

  # MCP server の user scope を declarative に同期する。
  # ~/.claude.json は Claude Code が動的に書き換える running config (OAuth token・
  # projects 別 state を含む) で symlink 化できないため、dotfiles 側の宣言を
  # activation 時に jq で recursive merge する。
  # claude.ai connector など宣言外のエントリは保持する add-only 設計。
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
