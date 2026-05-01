# nix/modules/home/zsh.nix
#
# home-manager programs.zsh モジュール。
# 現環境 (zshrc / zshenv / aliases) を宣言的に再現する。
#
# 自動注入: pkgs / lib / config 等は ... で受け取る（本モジュールでは現在未使用）
{ ... }:

{
  programs.zsh = {
    enable = true;

    # -----------------------------------------------------------------------
    # oh-my-zsh
    # -----------------------------------------------------------------------
    oh-my-zsh = {
      enable = true;
      # 現 zshrc plugins から移植。
      # zsh-autosuggestions は programs.zsh.autosuggestion.enable で管理するため除外。
      plugins = [
        "git"
        "kubectl"
        "terraform"
        "gcloud"
      ];
      # 現 zshrc では ZSH_THEME="" (starship が代替)。
      # oh-my-zsh.theme を空にすると "robbyrussell" にフォールバックするため、
      # theme 設定は行わず starship は initExtra で有効化する。
      # （starship モジュールは別 sub-issue で追加予定）
    };

    # zsh-autosuggestions を home-manager 組み込み機能で有効化
    autosuggestion.enable = true;

    # -----------------------------------------------------------------------
    # shellAliases — aliases ファイルから移植
    # -----------------------------------------------------------------------
    shellAliases = {
      # general
      history  = "history 1";
      reload   = "exec $SHELL -l";
      datetime = "date '+%Y%m%d%T' | tr -d ':'";

      # git
      gp    = "git push origin HEAD";
      gch   = "git branch --all | tr -d '* ' | grep -v -e '->' | fzf | sed -e 's+remotes/[^/]*/++g' | xargs git checkout";
      gchb  = "git checkout -b $1";
      grsh  = "git reset --soft HEAD^";
      gbclear = "git branch --merged|egrep -v '\\*|develop|main|master'|xargs git branch -d; git fetch -p";

      # fzf
      repo  = "ghq list -p | fzf";
      repoc = "cd \"$(repo)\"";

      # gcloud
      gcal   = "gcloud auth login";
      gcadl  = "gcloud auth application-default login";
      gcpa   = "gcloud config configurations activate $(gcloud config configurations list | fzf | awk \"{print \\$1}\")";
      gcps   = "gcloud config set project $(gcloud projects list | fzf | awk \"{print \\$1}\")";
      gcgc   = "bash $HOME/.aliase/get-gke-credentials.sh";

      # vscode
      codeo = "code $(repo)";

      # docker
      dcu = "docker compose up -d $@";
      dcn = "docker compose down $@";
    };

    # -----------------------------------------------------------------------
    # initExtra — zshrc の独自設定
    # -----------------------------------------------------------------------
    # oh-my-zsh の source・shellAliases・envExtra は home-manager が自動挿入するため除外。
    # programs.zsh に対応属性がないものをここに移植。
    initExtra = ''
      # mise (interactive hook) — shims は envExtra で有効化済み
      if type mise &>/dev/null; then
        eval "$(mise activate zsh)"
      fi

      # gcloud path — gcloud-cli (新名) と google-cloud-sdk (旧名) 両対応
      for _gcloud_inc in \
          '/opt/homebrew/Caskroom/gcloud-cli/latest/google-cloud-sdk/path.zsh.inc' \
          '/opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc'; do
          if [[ -f "''${_gcloud_inc}" ]]; then source "''${_gcloud_inc}"; break; fi
      done
      unset _gcloud_inc

      # worktrunk shell integration
      if command -v wt >/dev/null 2>&1; then eval "$(command wt config shell init zsh)"; fi

      # fzf — カスタム履歴ウィジェット (functions/fzf-history を使用)
      autoload fzf-history
      zle -N fzf-history
      bindkey '^r' fzf-history

      # stern completion
      if [ ''${commands[stern]} ]; then
        source <(stern --completion=zsh)
      fi

      # bison
      export PATH="/opt/homebrew/opt/bison/bin:$PATH"

      # pipx local bin
      export PATH="$PATH:$HOME/.local/bin"

      # dart-cli completion
      [[ -f "$HOME/.dart-cli-completion/zsh-config.zsh" ]] && . "$HOME/.dart-cli-completion/zsh-config.zsh" || true

      # TODO(S5): programs.starship モジュール追加後にこの行を削除すること。
      # starship を有効化したまま残すと二重初期化が発生する。
      eval "$(starship init zsh)"

      # firebase / pub-cache
      export PATH="$PATH:$HOME/.pub-cache/bin"

      # kubectl グローバルエイリアス (shellAliases は -g 非対応のため initExtra に配置)
      alias -g KP='$(kubectl get pods | fzf | awk "{print \$1}")'
      alias -g KD='$(kubectl get deploy | fzf | awk "{print \$1}")'
      alias -g KS='$(kubectl get svc | fzf | awk "{print \$1}")'
      alias -g KI='$(kubectl get ing | fzf | awk "{print \$1}")'
      alias -g KJ='$(kubectl get job | fzf | awk "{print \$1}")'
      alias -g KA='$(kubectl get all | awk "! /NAME/" | fzf | awk "{print \$1}")'
      # kubectle 系は KP/KA グローバルエイリアスを参照するため、展開順を保証するため直後に定義
      alias kubectle='kubectl exec -it KP $@'
      alias kubectll='kubectl stern $(kubectl get deploy | fzf | awk "{print \$1}")'
      alias kubectlo='kubectl get KA -o yaml'
    '';

    # -----------------------------------------------------------------------
    # envExtra — zshenv の内容を移植
    # -----------------------------------------------------------------------
    # FPATH への .functions 追加は home-manager が管理する ~/.zshenv に挿入される。
    # ただし home-manager 自身が FPATH を管理するケースと競合しないよう、
    # .functions を fpath に加える記述をここに置く。
    envExtra = ''
      # general settings — .functions を fpath に追加
      export FPATH=''${HOME}/.functions:''${FPATH}

      # pipx
      export PIPX_HOME="''${HOME}/.local/pipx"
      export PIPX_BIN_DIR="''${HOME}/.local/bin"

      # fzf
      export FZF_DEFAULT_COMMAND='rg --files --hidden --glob "!.git"'
      export FZF_DEFAULT_OPTS='--height 40% --reverse --border'

      # gcloud
      export USE_GKE_GCLOUD_AUTH_PLUGIN=True

      # golang
      export GOPATH=''${HOME}/go
      export PATH=''${GOPATH}/bin:''${PATH}

      # mise (shims — non-interactive シェル向け)
      if type mise &>/dev/null; then
        eval "$(mise activate --shims)"
      fi

      # custom local override
      if [[ -f ''${HOME}/.zshenv.local ]]; then
        source ''${HOME}/.zshenv.local
      fi
    '';
  };

  # -----------------------------------------------------------------------
  # home.file — 関数・スクリプトの symlink 配置
  # -----------------------------------------------------------------------
  home.file = {
    # fzf カスタム履歴ウィジェット (initExtra の `autoload fzf-history` が参照)
    ".functions/fzf-history".source = ../../../functions/fzf-history;
    # GKE 認証情報取得スクリプト (shellAliases.gcgc が参照)
    ".aliase/get-gke-credentials.sh".source = ../../../aliase/get-gke-credentials.sh;
  };
}
