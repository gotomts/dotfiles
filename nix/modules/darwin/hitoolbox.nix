# nix-darwin IME / 入力ソース設定モジュール
# specialArgs 由来: inputs / username (flake.nix から注入)
# 自動注入: pkgs / lib / config (... で受け取る)
#
# macOS Sonoma 以降、入力ソース設定は次の 2 ドメインに分離されている:
#
#   1. com.apple.HIToolbox      — Apple 純正の Keyboard Layout / 補助 IM
#                                   (ABC / CharacterPaletteIM / 50onPaletteIM / PressAndHold)
#   2. com.apple.inputsources    — サードパーティ IME
#                                   (AppleEnabledThirdPartyInputSources = Google 日本語入力 等)
#
# どちらも array of dict 構造のため system.defaults.CustomUserPreferences では
# 表現できない。activationScripts で defaults import を呼ぶ方針 (方針 A) を採用。
#
# 参照 plist (XML 形式、diff 可能):
#   - ./hitoolbox.plist     管理対象 keys:
#       AppleCurrentKeyboardLayoutInputSourceID / AppleEnabledInputSources /
#       AppleSelectedInputSources
#       除外: AppleInputSourceUpdateTime (PC 固有タイムスタンプ),
#             AppleInputSourceHistory (操作履歴)
#   - ./inputsources.plist  管理対象 keys:
#       AppleEnabledThirdPartyInputSources (Google 日本語入力 等)
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
    echo "==> Importing com.apple.HIToolbox (Apple keyboard layouts / 補助 IM)"
    sudo -u ${username} defaults import com.apple.HIToolbox ${./hitoolbox.plist}
    echo "==> Importing com.apple.inputsources (third-party IMEs)"
    sudo -u ${username} defaults import com.apple.inputsources ${./inputsources.plist}
  '';
}
