{ inputs, pkgs, ... }:

{
  programs.git = {
    enable = true;

    userName = "gotomts";
    userEmail = "mh.goto.web@gmail.com";

    extraConfig = {
      core = {
        # excludesFile は programs.git.ignores で管理するため不要
        ignorecase = false;
      };

      ghq = {
        # toGitINI がリスト値を同一キーの複数行として展開するため、
        # gitconfig の "[ghq] root = ~/.dotfiles / root = ~/ghq" が再現される。
        root = [
          "~/.dotfiles"
          "~/ghq"
        ];
      };

      "filter \"lfs\"" = {
        clean = "git-lfs clean -- %f";
        smudge = "git-lfs smudge -- %f";
        process = "git-lfs filter-process";
        required = true;
      };

      rerere = {
        enabled = true;
      };

      pull = {
        autostash = true;
      };

      rebase = {
        autoStash = true;
      };

      commit = {
        # inputs.self は flake のリポジトリルートを指す。
        # Nix store パスを文字列として展開するために toString を使用する。
        template = "${toString inputs.self}/gitmessage";
      };

      alias = {
        graph = "log --graph --date-order -C -M --pretty=format:\"<%h> %ad [%an] %Cgreen%d%Creset %s\" --all --date=short";
      };
    };

    ignores = [
      ".DS_Store"
    ];
  };
}
