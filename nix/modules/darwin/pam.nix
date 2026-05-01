# nix-darwin PAM 設定モジュール
# extraSpecialArgs 由来: inputs / hostname / username (mkHost.nix から注入)
# 自動注入: pkgs / lib / config (... で受け取る)
#
# security.pam.services.sudo_local.touchIdAuth は nix-darwin 固有のオプション。
# macOS 14 (Sonoma) 以降は /etc/pam.d/sudo_local が OS アップデートで上書きされないため
# この設定が有効。旧来の security.pam.enableSudoTouchIdAuth から改名された。
# 参照: https://github.com/nix-darwin/nix-darwin/blob/master/modules/security/pam.nix
{ ... }:

{
  # Touch ID (および Apple Watch) による sudo 認証を有効化。
  # 型: boolean, デフォルト: false
  #
  # 注: tmux / screen 等のマルチプレクサ内で Touch ID を使う場合は
  #     security.pam.services.sudo_local.reattach = true も併せて設定が必要になる場合がある。
  security.pam.services.sudo_local.touchIdAuth = true;
}
