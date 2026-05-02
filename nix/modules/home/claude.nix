{ pkgs, lib, ... }:

# このモジュールは setup.zsh の claude/ symlink ループ + setup/install/10_claude.zsh の
# symlink セクション（ステップ 2, 3）を home-manager で置換する。
#
# 注意: 既存 10_claude.zsh はスキルごとに個別 symlink を作るが、本モジュールは
# ~/.claude/skills ディレクトリ全体を Nix store 経由の単一 symlink にする。新スキル追加時は
# `home-manager switch` または `darwin-rebuild switch` で反映する必要がある。
{
  # ~/.claude/{agents,skills,hooks,settings.json,CLAUDE.md,RTK.md} を
  # dotfiles から symlink する。
  # 従来の setup/install/10_claude.zsh の symlink ループを home-manager で置換。
  home.file = {
    ".claude/agents".source        = ../../../claude/agents;
    ".claude/skills".source        = ../../../claude/skills;
    ".claude/hooks".source         = ../../../claude/hooks;
    ".claude/settings.json".source = ../../../claude/settings.json;
    ".claude/CLAUDE.md".source     = ../../../claude/CLAUDE.md;
    ".claude/RTK.md".source        = ../../../claude/RTK.md;
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
