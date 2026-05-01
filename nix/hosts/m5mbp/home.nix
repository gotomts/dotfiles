{ inputs, hostname, username, ... }:

{
  # S3-S7 で home-manager モジュールを import していく。
  # imports = [ ../../modules/home/packages.nix ];

  home.username = username;
  home.homeDirectory = "/Users/${username}";
  # home-manager 25.11 (nixpkgs-unstable との組み合わせ) の stateVersion
  home.stateVersion = "25.11";
}
