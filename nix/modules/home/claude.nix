{ pkgs, lib, config, ... }:

# ~/.claude/ の設定・skills を dotfiles から配置する home-manager モジュール。
# mkOutOfStoreSymlink で working tree を直接指すため、追加・編集は git pull で即反映される。
#
# skills は 1 ディレクトリの symlink なので、複数リポジトリの skill を同居させるには
# ディレクトリの中で分岐させるしかない。自作 skill は gotomts/skills を SSOT とし、
# claude/skills/<name> を同リポへの相対 symlink にすることで、~/.claude/skills を
# 単一 symlink のまま保っている (絶対パスにするとユーザー名が公開リポに載る)。
# 外部由来 (vendor) の skill は従来どおり dotfiles 内の実体。
let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  skillsRepo = "${config.home.homeDirectory}/ghq/github.com/gotomts/skills";
in
{
  home.file = {
    ".claude/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/settings.json";
    ".claude/CLAUDE.md".source     = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/CLAUDE.md";
    ".claude/AGENTS.md".source     = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/AGENTS.md";
    ".claude/skills".source        = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/skills";
    ".claude/hooks".source         = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/hooks";
  };

  # 自作 skill は gotomts/skills が SSOT で、claude/skills/ 配下には相対 symlink だけを
  # 置いている。clone が無いと symlink が dangling になるので、不在のときだけ clone する。
  # 既存の clone はユーザー所有の作業ツリーとして扱い、pull もチェックアウト変更もしない。
  home.activation.cloneSkillsRepo = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    _run_skills_repo_clone() {
      # 他の activation と同じく fail-open。clone に失敗しても switch は通す。
      # SSH 鍵が未設定の新規 PC で環境構築そのものが止まる方が害が大きい。
      set +e

      if [ -e "${skillsRepo}" ]; then
        # 実在するが git 作業ツリーでない場合、clone をスキップすると symlink が
        # dangling のまま残る。中身を消す判断はできないので警告だけ出す。
        if ! ${pkgs.git}/bin/git -C "${skillsRepo}" rev-parse --git-dir &>/dev/null; then
          echo "[claude.nix] ${skillsRepo} が git 作業ツリーではない。skill の symlink が dangling のままになる"
        fi
        return 0
      fi

      $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "${skillsRepo}")"

      # BatchMode/ConnectTimeout が無いと、host-key 確認や passphrase 入力の
      # プロンプトで activation が無期限に止まる。
      # activation の PATH に /usr/bin が無いため ssh は絶対パスで呼ぶ。nixpkgs の
      # openssh ではなく macOS 同梱を使うのは、keychain 経由の鍵を引くため。
      GIT_SSH_COMMAND="/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=10" \
        $DRY_RUN_CMD ${pkgs.git}/bin/git clone ssh://git@github.com/gotomts/skills.git "${skillsRepo}"

      if [ $? -eq 0 ]; then
        echo "[claude.nix] skills repo cloned to ${skillsRepo}"
      else
        echo "[claude.nix] skills repo の clone 失敗 (SSH 鍵未設定なら手動 clone が必要)"
      fi
    }

    _run_skills_repo_clone
  '';

  # claude plugin の宣言的同期。settings.json の enabledPlugins を CLI で install/update。
  home.activation.claudePlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    _run_claude_plugin_sync() {
      set +e  # 個々のプラグイン失敗で関数内処理を止めない

      # activation の PATH に /opt/homebrew/bin が無いため、command -v では
      # cask で入っている claude を見つけられない。
      local CLAUDE="/opt/homebrew/bin/claude"
      if [ ! -x "$CLAUDE" ]; then
        echo "[claude.nix] claude CLI 未インストール、plugin 同期をスキップ"
        return 0
      fi

      local SETTINGS="''${HOME}/.claude/settings.json"
      if [ ! -f "$SETTINGS" ]; then
        echo "[claude.nix] settings.json 不在、plugin 同期をスキップ"
        return 0
      fi

      $DRY_RUN_CMD "$CLAUDE" plugin marketplace update 2>/dev/null || true

      ${pkgs.jq}/bin/jq -r '.enabledPlugins // {} | keys[]' "$SETTINGS" 2>/dev/null | while IFS= read -r plugin; do
        if "$CLAUDE" plugin list --json 2>/dev/null | ${pkgs.jq}/bin/jq -e --arg p "$plugin" '.[] | select(.id == $p)' &>/dev/null; then
          $DRY_RUN_CMD "$CLAUDE" plugin update "$plugin" 2>/dev/null || \
            echo "[claude.nix] plugin $plugin: update failed"
        else
          $DRY_RUN_CMD "$CLAUDE" plugin install "$plugin" 2>/dev/null && \
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

  # i-have-adhd プラグインの常時適用マーカー。存在すればプラグインが毎回自動発動する。
  # touch は冪等なので switch のたびに実行しても副作用なし。
  home.activation.enableIHaveAdhdAlways = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.coreutils}/bin/touch "''${HOME}/.claude/.i-have-adhd-always"
  '';
}
