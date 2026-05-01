{ inputs, pkgs, ... }:

{
  programs.yazi = {
    enable = true;
    # 既存の yazi.toml / keymap.toml を builtins.fromTOML で読み込む。
    # keymap の prepend_keymap エントリは TOML 配列としてそのまま注入される。
    # TODO(Phase B): config/yazi/keymap.toml の grip-preview 呼び出しに含まれる
    # `$HOME/.dotfiles/config/yazi/grip-preview.sh` を pkgs パッケージ化または
    # Nix store path 参照に置換する。Phase A では Brewfile + 既存 dotfiles パスのまま運用。
    settings = builtins.fromTOML (builtins.readFile ../../../config/yazi/yazi.toml);
    keymap = builtins.fromTOML (builtins.readFile ../../../config/yazi/keymap.toml);
  };
}
