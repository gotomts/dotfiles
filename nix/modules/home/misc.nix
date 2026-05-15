# nix/modules/home/misc.nix
#
# 特定のアプリモジュール (programs.*) に属さない設定ファイルを
# home.file で管理するモジュール。
#
# 対象:
#   - grip (GitHub Readme Instant Preview) の設定
#   - cmux / ghostty のターミナル設定
#
# 旧 setup.zsh が dotfiles への dir-symlink / file-symlink で配置していたものを
# home-manager の file-level symlink に移行する (DOT-27 dir-symlink 再発防止)。
{ ... }:

{
  home.file = {
    # grip 設定 (grip/settings.py)
    # 旧 setup.zsh が ~/.grip -> dotfiles/grip (dir-symlink) を作っていた。
    # home-manager では file-level symlink に変換して管理する。
    ".grip/settings.py".source = ../../../grip/settings.py;

    # cmux (ghostty terminal multiplexer) 設定
    # 旧 setup.zsh の config ループが ~/.config/cmux/config.ghostty -> dotfiles/config/cmux/config.ghostty
    # を file-symlink で作成していた。home-manager に引き継ぐ。
    ".config/cmux/config.ghostty".source = ../../../config/cmux/config.ghostty;
  };
}
