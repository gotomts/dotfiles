{
  description = "gotomts macOS dotfiles via nix-darwin + home-manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # rtk-src は S8 で本格採用するため、雛形では未追加。
    # S8 で以下を追加予定:
    #   rtk-src.url = "github:gotomts/rtk";
    #   rtk-src.flake = false;
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-darwin,
      home-manager,
      ...
    }@inputs:
    let
      mkHost = import ./lib/mkHost.nix { inherit inputs; };
    in
    {
      darwinConfigurations.m5mbp = mkHost {
        hostname = "m5mbp";
        system = "aarch64-darwin";
        username = "goto";
      };
    };
}
