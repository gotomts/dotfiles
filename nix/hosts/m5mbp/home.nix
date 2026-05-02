# ホスト m5mbp の home-manager モジュール集約点。
# mkHost.nix から直接 import される（default.nix 中間層は不使用）。
# extraSpecialArgs 由来: inputs / hostname / username (mkHost.nix から注入)
# 自動注入: pkgs / lib / config (... で受け取る)
{ inputs, hostname, username, ... }:

{
  imports = [
    # CLI ツール群 (S3 / KISSA-23)
    ../../modules/home/packages.nix
    # zsh + oh-my-zsh + initExtra/envExtra (S4 / KISSA-24)
    ../../modules/home/zsh.nix
    # 設定ファイル系 (S5 / KISSA-25)
    ../../modules/home/git.nix
    ../../modules/home/starship.nix
    ../../modules/home/yazi.nix
    ../../modules/home/ssh.nix
    # claude plugin sync activation (S6 / KISSA-26)
    ../../modules/home/claude.nix
    # 言語ツールチェーン: mise 完全置換 (S7 / KISSA-27)
    ../../modules/home/languages.nix
  ];

  home.username = username;
  home.homeDirectory = "/Users/${username}";
  # home-manager 25.11 (nixpkgs-unstable との組み合わせ) の stateVersion
  home.stateVersion = "25.11";
}
