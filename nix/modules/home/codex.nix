{ pkgs, lib, config, ... }:

# このモジュールは Codex CLI 用の dotfiles を home-manager で配置する。
#
# project-level AGENTS.md はリポジトリ root に置かれ、Codex CLI が working
# directory の AGENTS.md を自動検出するため symlink せず repo 内に閉じる。
#
# global-level AGENTS.md (グローバル指示) は claude/AGENTS.md をマスターとし、
# ~/.codex/AGENTS.md にも mkOutOfStoreSymlink で working tree を直接指すため、
# 編集は git pull で即反映される (switch 不要)。
# Claude Code 側の配線は nix/modules/home/claude.nix を参照。
#
# config.toml は symlink しない。Codex / ChatGPT desktop アプリが
# ~/.codex/config.toml を running config として動的に書き換える (絶対パス /
# marketplaces / plugins / trust_level / desktop 設定等) ため、mkOutOfStoreSymlink
# で working tree を指すと公開リポにアプリの状態が流れ込む (~/.claude.json と同種の
# 問題)。代わりに codex/config.base.toml を宣言的 seed とし、~/.codex/config.toml が
# 不在のときだけ cp する (seed-if-absent)。既存ファイルはアプリの所有として尊重し
# 一切触らない。
let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
in
{
  home.file = {
    ".codex/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/AGENTS.md";

    # ctx (ctxrs/ctx) の agent-history-search skill を Codex にも供給する。
    # Codex は ~/.codex/skills/ 配下の SKILL.md を skill として読むが、この
    # ディレクトリは Codex アプリ管理の他 skill と同居するため、ディレクトリ全体では
    # なく個別 entry だけを symlink する。skill 本体は claude/skills/ 配下の vendored
    # コピー (Claude Code 版と byte 一致) を単一ソースとして共有する。
    # 更新は ctx 再インストールで claude/skills/ 側を上書き再生成すれば両 agent に反映される。
    ".codex/skills/ctx-agent-history-search".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/skills/ctx-agent-history-search";
  };

  # config.toml の宣言的 seed。~/.codex/config.toml が不在のときだけ
  # codex/config.base.toml を cp する。既存 (アプリ所有の running config) は
  # 触らないため、trust_level 等の動的状態を破壊しない。
  home.activation.syncCodexConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    _run_codex_config_seed() {
      set +e

      local target="''${HOME}/.codex/config.toml"
      local base="${dotfiles}/codex/config.base.toml"

      if [ ! -f "$base" ]; then
        echo "[codex.nix] config.base.toml 不在、config seed をスキップ"
        return 0
      fi

      if [ -e "$target" ]; then
        # 既存はアプリ所有の running config。宣言外の状態を保持するため触らない。
        return 0
      fi

      $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "''${HOME}/.codex"
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/cp "$base" "$target"
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod 600 "$target"
      echo "[codex.nix] config.toml seeded from config.base.toml"
    }

    _run_codex_config_seed
  '';
}
