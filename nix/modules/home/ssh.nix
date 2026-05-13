{ inputs, pkgs, ... }:

{
  # SSH 鍵管理はスコープ外（Phase A 終了後に programs.ssh への移行を別検討）。
  # config ファイルのみを symlink で配置する。
  home.file.".ssh/config".source = ../../../ssh/config;
}
