{ inputs }:

{ hostname, system, username }:

inputs.nix-darwin.lib.darwinSystem {
  inherit system;
  specialArgs = { inherit inputs hostname username; };
  modules = [
    ../hosts/${hostname}/darwin.nix
    inputs.home-manager.darwinModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.${username} = import ../hosts/${hostname}/home.nix;
      home-manager.extraSpecialArgs = { inherit inputs hostname username; };
    }
  ];
}
