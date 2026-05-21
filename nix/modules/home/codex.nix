{ ... }:

# このモジュールは Codex CLI 用の dotfiles を home-manager で symlink する (DOT-38)。
#
# AGENTS.md はリポジトリ root に置かれ、Codex CLI が working directory の
# AGENTS.md を自動検出するため symlink せず repo 内に閉じる。
# global instruction を別途配りたくなったら ~/AGENTS.md の symlink を後付けする。
{
  # ~/.codex/config.toml を dotfiles から symlink する。
  home.file = {
    ".codex/config.toml".source = ../../../.codex/config.toml;
  };
}
