# nix-darwin フォント設定モジュール
# specialArgs 由来: inputs / username (flake.nix から注入)
# 自動注入: pkgs / lib / config (... で受け取る)
#
# fonts.packages は nixpkgs のフォントパッケージを /Library/Fonts/Nix Fonts/ に配置する。
# 型: list of absolute path (pkgs.<name> の評価結果)
{ pkgs, ... }:

{
  # nixpkgs に収録されているオープンソースフォントをここで管理する。
  #
  # font-sf-mono (Apple 独占フォント) は nixpkgs に未収録のため、
  # Brewfile の `cask 'font-sf-mono'` で引き続き管理する。
  # 親の integration commit で Brewfile (homebrew.nix S9) との整合を確認すること。
  fonts.packages = [
    # SF Mono: nixpkgs 未収録（Apple プロプライエタリライセンス）→ Brewfile 残置

    # ghostty 同梱の JetBrains Mono は和文グリフを持たず、macOS の
    # プロポーショナル系フォントへフォールバックして字幅と太さが揃わない。
    # UDEV Gothic は半角:全角=1:2 が厳密なため、和文を混ぜても端末の桁が崩れない。
    # Nerd Font 記号は ghostty がビルトインでフォールバックするので素の版で足りる。
    pkgs.udev-gothic

    # ghostty 同梱の JetBrains Mono は内部埋め込みでフォント検索に出てこず、
    # 名前で指定できない。欧文を JetBrains Mono に固定したまま和文だけ別ファミリー
    # へフォールバックさせるには、検索可能な実体が必要になる。
    pkgs.jetbrains-mono
  ];
}
