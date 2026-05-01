# nix-darwin sudo 設定モジュール
# extraSpecialArgs 由来: inputs / hostname / username (mkHost.nix から注入)
# 自動注入: pkgs / lib / config (... で受け取る)
#
# 注意: nix-darwin の security.sudo は extraConfig (raw sudoers テキスト) のみを持つ。
#       NixOS の security.sudo.extraRules (構造化 attr) は nix-darwin 非対応。
#       https://github.com/nix-darwin/nix-darwin/blob/master/modules/security/sudo.nix
{ username, ... }:

{
  # 現 setup/install/10_claude.zsh が /etc/sudoers.d/pmset に追加していたエントリを宣言化:
  #   <username> ALL=(ALL) NOPASSWD: /usr/bin/pmset
  # sleep-guard スキル (claude/skills/sleep-guard) で pmset をパスワードなし実行するために必要。
  #
  # nix-darwin はこの内容を /etc/sudoers.d/10-nix-darwin-extra-config に書き出す。
  # macOS の /etc/sudoers は #includedir /private/etc/sudoers.d を含むため有効になる。
  security.sudo.extraConfig = ''
    ${username} ALL=(ALL) NOPASSWD: /usr/bin/pmset
  '';
}
