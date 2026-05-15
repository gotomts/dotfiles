# nix-darwin IME / 入力ソース設定モジュール (DOT-25)
# specialArgs 由来: inputs / username (flake.nix から注入)
# 自動注入: pkgs / lib / config (... で受け取る)
#
# com.apple.HIToolbox の AppleEnabledInputSources は array of dict 構造であり、
# system.defaults.CustomUserPreferences では表現できない。
# そのため activationScripts で defaults import を呼ぶ方針 (方針 A) を採用。
#
# 参照 plist: ./hitoolbox.plist (XML 形式、diff 可能)
# - AppleInputSourceUpdateTime (PC 固有タイムスタンプ) は除外済み
# - AppleInputSourceHistory (操作履歴) は除外済み
# - 管理対象: AppleCurrentKeyboardLayoutInputSourceID / AppleEnabledInputSources /
#             AppleSelectedInputSources
#
# 冪等性: defaults import はドメイン全体を上書き書き込みするため、
#         複数回 darwin-rebuild switch を実行しても結果は変わらない。
#
# 適用タイミング: activation は root で実行されるため、user-scoped defaults への書き込みは
#                 sudo -u <username> defaults import で実行する。
#                 (postUserActivation は nix-darwin 最新版で削除済み)
{ username, ... }:

{
  system.activationScripts.postActivation.text = ''
    echo "==> Importing com.apple.HIToolbox (IME / Input Sources)"
    sudo -u ${username} defaults import com.apple.HIToolbox ${./hitoolbox.plist}
  '';
}
