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
  # nix-darwin はこの内容を /etc/sudoers.d/10-nix-darwin-extra-config として書き出す。
  #
  # TODO(Phase A 完了時): setup/install/10_claude.zsh の sudoers ブロック (行 7-15) を
  # 削除すること。並存期間中は二重エントリ (/etc/sudoers.d/pmset と
  # /etc/sudoers.d/10-nix-darwin-extra-config の両方) になるが、sudo 動作上は無害。
  # 削除を忘れると Phase B 後も古いエントリが残り、sudoers 監査時の誤解を招く。
  #
  # 注意: security.sudo.extraConfig は types.lines (複数モジュール連結)。
  # 他モジュールから extraConfig を追加する場合は事前に visudo -c で構文検証すること。
  # 適用前検証: echo "..." | visudo -c -f -
  security.sudo.extraConfig = ''
    ${username} ALL=(ALL) NOPASSWD: /usr/bin/pmset
  '';

  # 検証ポイント (実機 darwin-rebuild switch 後):
  # - /etc/sudoers.d/10-nix-darwin-extra-config の所有者が root:wheel か
  # - パーミッションが 0440 か
  # - sudo がエラーなく動作するか (sudo: ... is owned by uid X エラーが出ないこと)
  # 問題が出た場合は environment.etc."sudoers.d/...".{mode,user,group} を明示指定する。
}
