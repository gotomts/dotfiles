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
      # username は実行環境の $USER から動的に解決する。
      # darwin-rebuild は --impure を必要とする (alias で吸収しないので明示的に付ける)。
      # 未設定時は throw で明示エラーにして、silent な誤動作を防ぐ。
      username =
        let
          u = builtins.getEnv "USER";
        in
        if u != "" then
          u
        else
          throw "USER env var is empty. Run darwin-rebuild with --impure, or set USER explicitly.";
    in
    {
      # output 名は固定値 default。PC の hostname には影響しない (flake 内部のアドレス名)。
      # darwin-rebuild 自動選択 ($HOSTNAME ベース) は活かさず、--flake .#default --impure を明示する運用。
      darwinConfigurations.default = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = { inherit inputs username; };
        modules = [
          ./darwin.nix
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            # setup.zsh が以前作った既存 symlink (~/.zshrc, ~/.claude/agents 等) を
            # home-manager が clobber エラーで弾かないよう、退避拡張子を指定する。
            # 初回 activation で既存ファイルは <file>.before-nix にリネームされる。
            home-manager.backupFileExtension = "before-nix";
            home-manager.users.${username} = import ./home.nix;
            home-manager.extraSpecialArgs = { inherit inputs username; };
          }
        ];
      };
    };
}
