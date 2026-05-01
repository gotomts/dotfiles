{ inputs, pkgs, ... }:

{
  programs.yazi = {
    enable = true;
    # 既存の yazi.toml / keymap.toml を builtins.fromTOML で読み込む。
    # keymap の prepend_keymap エントリは TOML 配列としてそのまま注入される。
    settings = builtins.fromTOML (builtins.readFile ../../../config/yazi/yazi.toml);
    keymap = builtins.fromTOML (builtins.readFile ../../../config/yazi/keymap.toml);
  };
}
