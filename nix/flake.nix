{
  description = "gotomts macOS dotfiles via nix-darwin + home-manager";

  inputs = {
    # Phase A は unstable を使用 (home-manager との整合性優先)。
    # stable に切り替える場合は nixpkgs-YY.MM 形式に変更し、
    # home.stateVersion も対応バージョンに更新すること。
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # rtk-src: rtk (Rust Token Killer) のソース。
    # nix/modules/overlays/rtk.nix が rustPlatform.buildRustPackage でビルドする。
    # flake = false で nix flake input としてはソースのみ取得（rtk 自身は flake ではない）。
    rtk-src = {
      url = "github:rtk-ai/rtk";
      flake = false;
    };
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
