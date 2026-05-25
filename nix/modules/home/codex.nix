{ config, ... }:

# このモジュールは Codex CLI 用の dotfiles を home-manager で symlink する (DOT-38)。
#
# project-level AGENTS.md はリポジトリ root に置かれ、Codex CLI が working
# directory の AGENTS.md を自動検出するため symlink せず repo 内に閉じる。
#
# global-level AGENTS.md (グローバル指示) は claude/AGENTS.md をマスターとし、
# ~/.codex/AGENTS.md にも symlink して Claude Code / Codex で共有する。
# Claude Code 側の配線は nix/modules/home/claude.nix を参照。
#
# mkOutOfStoreSymlink で dotfiles working tree への直接 symlink を張るため、
# config.toml / AGENTS.md の編集は git pull で即反映される (switch 不要)。
let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
in
{
  home.file = {
    ".codex/config.toml".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/.codex/config.toml";
    ".codex/AGENTS.md".source   = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/AGENTS.md";
  };
}
