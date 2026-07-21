{ inputs, pkgs, lib, ... }:

{
  # gitmessage を ~/.gitmessage として固定パスに配置する。
  # inputs.self を commit.template に直接使うと darwin-rebuild のたびに
  # store hash が変わり git config の表示が毎回変化するため、
  # home.file 経由で固定パスに symlink してから参照する。
  home.file.".gitmessage".source = ../../../gitmessage;

  programs.git = {
    enable = true;

    settings = {
      user = {
        name = "gotomts";
        email = "mh.goto.web@gmail.com";
      };

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
      # Claude Code per-project local approvals (per-machine, do not share)
      # 旧 gitignore_global から移植。home.file でも ~/.gitignore_global を配置するが、
      # programs.git.ignores が正規の管理場所であるためここに宣言する。
      ".claude/settings.local.json"
      # Serena がプロジェクト activate 時に作る tool 状態 (project.yml / memories)。
      # serena を使う全リポで出るため global で無視する。
      ".serena/"
    ];
  };

  # ~/.gitignore_global を home.file として配置する。
  # programs.git.ignores が ~/.config/git/ignore に書き出すため、
  # ~/.gitignore_global は git が参照しないが、旧環境との互換性のため残置する。
  # 旧 setup.zsh が dotfiles への dir-symlink を作っていたため、migration 後も
  # file-level symlink として nix store 経由で管理する。
  home.file.".gitignore_global".source = ../../../gitignore_global;

  # ~/.gitconfig を nix 非管理の「実体ファイル」として用意する。
  # git 設定本体の SSOT は programs.git (~/.config/git/config) 側であり、
  # ~/.gitconfig は設定を持たせず PC 固有値の隔離先としてのみ使う。
  #
  # なぜ home.file ではなく home.activation か:
  #   home.file で置くと nix store への read-only symlink になり、
  #   `git config --global` で書き込むツール (coderabbit CLI の machineId 等) が
  #   書き込めない。git は ~/.gitconfig が存在すれば最優先で書き込み先に選ぶため、
  #   ここを read-only にすると read-only な ~/.config/git/config へ書こうとして失敗する。
  #   そこで書き込み可能な空の実体ファイルを置き、PC 固有値の落書き帳として隔離する。
  #
  # 旧構成では ~/.gitconfig が dotfiles/gitconfig への手動 symlink だったため、
  # その残骸が残っていれば撤去してから空実体を作る。machineId は PC 固有値であり
  # 失われても各マシンの coderabbit が再生成するだけで、共有すべきものではない。
  home.activation.gitconfigLocalRealfile =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      gitconfig="$HOME/.gitconfig"
      if [ -L "$gitconfig" ]; then
        case "$(readlink "$gitconfig")" in
          */.dotfiles/gitconfig)
            $DRY_RUN_CMD rm $VERBOSE_ARG "$gitconfig"
            ;;
        esac
      fi
      if [ ! -e "$gitconfig" ]; then
        $DRY_RUN_CMD touch $VERBOSE_ARG "$gitconfig"
      fi
    '';
}
