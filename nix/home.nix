# home-manager モジュール集約点。
# flake.nix から直接 import される。
# extraSpecialArgs 由来: inputs / username (flake.nix から注入)
# 自動注入: pkgs / lib / config (... で受け取る)
{ inputs, username, ... }:

{
  imports = [
    # CLI ツール群 (S3)
    ./modules/home/packages.nix
    # zsh + oh-my-zsh + initExtra/envExtra (S4)
    ./modules/home/zsh.nix
    # 設定ファイル系 (S5)
    ./modules/home/git.nix
    ./modules/home/starship.nix
    ./modules/home/yazi.nix
    ./modules/home/ssh.nix
    # claude plugin sync activation (S6)
    ./modules/home/claude.nix
    # Codex CLI 用 dotfiles symlink
    ./modules/home/codex.nix
    # 言語ツールチェーン: mise 完全置換 (S7)
    ./modules/home/languages.nix
    # corepack によるグローバル pnpm / yarn 供給 (プロジェクト宣言優先)
    ./modules/home/corepack.nix
    # per-project Nix shell auto-activation
    ./modules/home/direnv.nix
    # grip / cmux 等の home.file 配置 (dir-symlink 再発防止)
    ./modules/home/misc.nix
  ];

  home.username = username;
  home.homeDirectory = "/Users/${username}";
  # home-manager 25.11 (nixpkgs-unstable との組み合わせ) の stateVersion
  home.stateVersion = "25.11";
}
