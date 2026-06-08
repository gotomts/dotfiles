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
      # 未設定時 / root のときは throw で明示エラーにして、silent な誤動作を防ぐ。
      #
      # "root" の検出が必要な理由: `sudo darwin-rebuild ...` を素で実行すると
      # sudo の env_reset により USER=root に書き換わり、`users.users.root.home`
      # が `/Users/root` に解決されて nix-darwin の assertion で失敗する。
      # エラーメッセージが原因を全く示唆しないため、ここで早期に明確に止める。
      username =
        let
          u = builtins.getEnv "USER";
        in
        if u == "" then
          throw "USER env var is empty. Run darwin-rebuild with --impure, or set USER explicitly."
        else if u == "root" then
          throw ''
            USER env var is "root". This usually means `sudo darwin-rebuild ...` was run without preserving USER.
            Use: sudo USER=$USER darwin-rebuild <build|switch> --flake .#default --impure
          ''
        else
          u;

      # role は /etc/dotfiles-role から解決する (root 所有、machine-wide 設定)。
      # ファイル不在 / 空 / 全コメントなら "default" にフォールバック (CI もこの経路)。
      # 未知の role は throw で停止 (silent な誤動作を防ぐ)。
      #
      # 仕様:
      #   - "#" で始まる行と空行は無視
      #   - 最初の content 行を role 値として採用
      #   - 認める値: "default" | "sub-1"
      #
      # /etc/dotfiles-role を使う理由:
      #   role は「この物理 Mac の identity」でありマシン単位の宣言。
      #   ユーザー単位の設定ではないため /etc/ 配下が semantically 正しい。
      #   また、sudo darwin-rebuild 実行時に Nix が security 上 HOME を passwd の
      #   root home (/var/root) にフォールバックさせるため、~/ 配下に置くと
      #   HOME-based 解決が壊れる。/etc/ は root 所有なのでこの影響を受けない。
      #
      # 初回セットアップ: `echo sub-1 | sudo tee /etc/dotfiles-role`
      role =
        let
          roleFile = "/etc/dotfiles-role";
          raw =
            if builtins.pathExists roleFile then
              builtins.readFile roleFile
            else
              "";
          rawLines = builtins.filter builtins.isString (builtins.split "\n" raw);
          stripWs = s: builtins.replaceStrings [ " " "\t" "\r" ] [ "" "" "" ] s;
          contentLines = builtins.filter (
            l:
            let
              t = stripWs l;
            in
            t != "" && builtins.substring 0 1 t != "#"
          ) rawLines;
          resolved = if contentLines == [ ] then "default" else stripWs (builtins.head contentLines);
        in
        if resolved == "default" || resolved == "sub-1" then
          resolved
        else
          throw ''
            Unknown .dotfiles-role value: "${resolved}"
            Valid values: default, sub-1
            File: ${roleFile}
          '';
    in
    {
      # output 名は固定値 default。PC の hostname には影響しない (flake 内部のアドレス名)。
      # darwin-rebuild 自動選択 ($HOSTNAME ベース) は活かさず、--flake .#default --impure を明示する運用。
      darwinConfigurations.default = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = { inherit inputs username role; };
        modules = [
          ./darwin.nix
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            # home-manager が以前作った既存 symlink (~/.zshrc, ~/.claude/agents 等) を
            # 重複作成しようとして clobber エラーで弾かないよう、退避拡張子を指定する。
            # 初回 activation で既存ファイルは <file>.before-nix にリネームされる。
            home-manager.backupFileExtension = "before-nix";
            home-manager.users.${username} = import ./home.nix;
            home-manager.extraSpecialArgs = { inherit inputs username role; };
          }
        ];
      };
    };
}
