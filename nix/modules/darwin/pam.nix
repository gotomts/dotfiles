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
  # Touch ID for sudo 有効化 (macOS 14+ の sudo_local PAM)。
  # 旧 enableSudoTouchIdAuth から改名されたオプション。
  security.pam.services.sudo_local.touchIdAuth = true;

  # reattach: tmux/cmux 経由で sudo を実行する場合、Touch ID プロンプトを TTY 経由で
  # 受け取るために pam-reattach パッケージが必要になる。本リポジトリは tmux/cmux 運用を
  # 含むが、Phase A では reattach = false (デフォルト) として、tmux 内 sudo は
  # パスワードフォールバックを許容する判断。
  #
  # tmux 内 Touch ID を求める場合は以下を有効化 (pam-reattach への依存追加):
  #   security.pam.services.sudo_local.reattach = true;
  # security.pam.services.sudo_local.reattach = true;  # 採用時のみコメント解除
}
