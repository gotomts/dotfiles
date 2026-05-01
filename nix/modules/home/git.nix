{ inputs, pkgs, ... }:

{
  # gitmessage を ~/.gitmessage として固定パスに配置する。
  # inputs.self を commit.template に直接使うと darwin-rebuild のたびに
  # store hash が変わり git config の表示が毎回変化するため、
  # home.file 経由で固定パスに symlink してから参照する。
  home.file.".gitmessage".source = ../../../gitmessage;

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
        template = "~/.gitmessage";
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
