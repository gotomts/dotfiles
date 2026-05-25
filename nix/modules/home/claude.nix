{ pkgs, lib, config, ... }:

# このモジュールは setup.zsh の claude/ symlink ループ + setup/install/10_claude.zsh の
# symlink セクション（ステップ 2, 3）を home-manager で置換したもの (両スクリプト削除済み)。
#
# mkOutOfStoreSymlink で dotfiles working tree への直接 symlink を張るため、
# skills/agents/hooks/設定ファイルの追加・編集は git pull (or 直接編集) で即反映される
# (darwin-rebuild switch は不要)。トレードオフとして ~/.dotfiles/ が存在しない PC では
# dangling symlink になるが、本リポジトリ前提の運用なので許容する。
let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
in
{
  # ~/.claude/{agents,skills,hooks,settings.json,CLAUDE.md,AGENTS.md} を
  # dotfiles から symlink する。
  # AGENTS.md はグローバル指示のマスターで Claude Code は CLAUDE.md の
  # @AGENTS.md import で取り込む。Codex 等の他 AI ツール向けには
  # nix/modules/home/codex.nix が同じ AGENTS.md を ~/.codex/AGENTS.md に
  # symlink して共有する。
  home.file = {
    ".claude/agents".source        = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/agents";
    ".claude/skills".source        = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/skills";
    ".claude/hooks".source         = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/hooks";
    ".claude/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/settings.json";
    ".claude/CLAUDE.md".source     = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/CLAUDE.md";
    ".claude/AGENTS.md".source     = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/AGENTS.md";
  };

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
}
