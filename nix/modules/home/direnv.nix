# home-manager モジュール: direnv + nix-direnv
#
# per-project の Nix shell (flake.nix / shell.nix) を `cd` で自動有効化するために
# direnv + nix-direnv を導入する。
#
# 設計判断との整合性 (DOT-35):
# - グローバル言語ランタイムは languages.nix で一元管理 (mise 排除方針 = S7 維持)
# - nix-direnv は per-project Nix shell の ergonomic な activate が目的で、
#   言語管理ロジックは Nix のまま。mise/asdf 再導入とは別軸
#
# 直接の動機: SCN-12 (Flutter iOS の pod install が Ruby 3.4 + CFPropertyList 3.0.8
# の kconv 削除で失敗) を per-project flake.nix + `.envrc (use flake)` で解決するため
#
# programs.direnv.enable = true で:
#   - direnv パッケージを install
#   - zsh hook (eval "$(direnv hook zsh)") を home-manager 管理の zsh に自動配線
#
# programs.direnv.nix-direnv.enable = true で:
#   - nix-direnv plugin を install
#   - ~/.config/direnv/direnvrc に use_flake / use_nix を提供
#
# home.nix への配線:
#   imports = [ ./modules/home/direnv.nix ];
{ ... }:

{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    # 新規タブ起動時の `direnv: loading ...` / `direnv: export +AR +AS ...` の
    # 長大なログを抑止する。silent = true は DIRENV_LOG_FORMAT を空に設定する
    # 薄いラッパで、devbox 側の `✓ devshell:` 表示には影響しない (そちらは
    # 各プロジェクト .envrc を `... >/dev/null` で包む方針)。
    silent = true;
  };
}
