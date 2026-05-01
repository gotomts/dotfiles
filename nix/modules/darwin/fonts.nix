# nix-darwin フォント設定モジュール
# extraSpecialArgs 由来: inputs / hostname / username (mkHost.nix から注入)
# 自動注入: pkgs / lib / config (... で受け取る)
#
# fonts.packages は nixpkgs のフォントパッケージを /Library/Fonts/Nix Fonts/ に配置する。
# 型: list of absolute path (pkgs.<name> の評価結果)
# 現状は SF Mono のみ管理しているが nixpkgs 未収録のため空リスト。
# pkgs を追加する場合は引数を { pkgs, ... }: に変更すること。
{ ... }:

{
  # nixpkgs に収録されているオープンソースフォントをここで管理する。
  #
  # font-sf-mono (Apple 独占フォント) は nixpkgs に未収録のため、
  # Brewfile の `cask 'font-sf-mono'` で引き続き管理する。
  # 親の integration commit で Brewfile (homebrew.nix S9) との整合を確認すること。
  fonts.packages = [
    # SF Mono: nixpkgs 未収録（Apple プロプライエタリライセンス）→ Brewfile 残置
    # 他のフォントが必要になった場合はここに追加する。例:
    # pkgs.nerd-fonts.jetbrains-mono
  ];
}
