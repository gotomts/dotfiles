#!/bin/zsh
# setup/defaults.zsh
#
# Tier 2: macOS defaults (Dock/Finder/Trackpad/NSGlobalDomain/MenubarClock 他) と
# IME/入力ソース (com.apple.HIToolbox / com.apple.inputsources) を宣言的に適用する。
# nix-darwin の nix/modules/darwin/defaults.nix・hitoolbox.nix の内容を
# 1:1 で `defaults write`/`defaults import` に翻訳したもの（ロジック変更なし）。
#
# 対象外（本スクリプトでは扱わない）: 「無視」triage された 41 件、
# com.apple.universalaccess / com.apple.screencapture（別途 triage 要）。
# 詳細は docs/superpowers/specs/2026-08-21-restore-script-management-inventory.md 6 節を参照。
#
# role 解決: /etc/dotfiles-role を読む（nix/flake.nix の role 解決ロジックと同じ規約）。
# テスト時は DOTFILES_ROLE_FILE でオーバーライドできる。
#
# 使い方:
#   zsh ${HOME}/.dotfiles/setup/defaults.zsh
#
# 終了コード:
#   0  成功
#   1  role ファイルの値が不正 (default/sub-1 以外)

set -eu

SETUP_DIR="${0:A:h}"
DOTFILES_ROOT="${SETUP_DIR:h}"
source "${SETUP_DIR}/lib/util.zsh"
source "${SETUP_DIR}/lib/fs.zsh"

# ---------------------------------------------------------------------------
# role 解決 (nix/flake.nix と同じ規約: # 始まり/空行を無視、最初の content 行を採用、
# 不在/空なら "default"、default/sub-1 以外は error)
# ---------------------------------------------------------------------------
ROLE_FILE="${DOTFILES_ROLE_FILE:-/etc/dotfiles-role}"

defaults::resolve_role() {
    local raw=""
    if [[ -f "${ROLE_FILE}" ]]; then
        raw="$(<"${ROLE_FILE}")"
    fi

    local line resolved=""
    for line in "${(f)raw}"; do
        local trimmed="${line//[[:space:]]/}"
        [[ -z "${trimmed}" ]] && continue
        [[ "${trimmed[1]}" == "#" ]] && continue
        resolved="${trimmed}"
        break
    done

    [[ -z "${resolved}" ]] && resolved="default"

    if [[ "${resolved}" != "default" && "${resolved}" != "sub-1" ]]; then
        util::error "不明な dotfiles-role です: \"${resolved}\" (${ROLE_FILE})"
        return 1
    fi

    echo "${resolved}"
}

ROLE="$(defaults::resolve_role)"
util::info "=== Tier 2: macOS defaults (role=${ROLE}) ==="

# ---------------------------------------------------------------------------
# バックアップ安全策: domain ごとに初回だけ現状を export する
# ---------------------------------------------------------------------------
BACKUP_DIR="${HOME}/.dotfiles-defaults-backup"
mkdir -p "${BACKUP_DIR}"

defaults::backup_once() {
    local domain="${1}"
    local backup="${BACKUP_DIR}/${domain}.plist"
    if [[ -e "${backup}" ]]; then
        return 0
    fi
    defaults export "${domain}" "${backup}" 2>/dev/null || \
        util::warning "defaults export ${domain} に失敗しました (初回導入等で domain が未使用の可能性、続行します)"
}

# ---------------------------------------------------------------------------
# Dock (基本 5 件 + persistent-apps role 別 + persistent-others)
# ---------------------------------------------------------------------------
defaults::backup_once "com.apple.dock"

defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock magnification -bool true
defaults write com.apple.dock mru-spaces -bool false
defaults write com.apple.dock showAppExposeGestureEnabled -bool true
defaults write com.apple.dock wvous-br-corner -int 14

launchpad_app="/System/Applications/Launchpad.app"
[[ -e "/System/Applications/Apps.app" ]] && launchpad_app="/System/Applications/Apps.app"

default_dock_apps=(
    "${launchpad_app}"
    "/Applications/Linear.app"
    "/Applications/Slack.app"
    "/Applications/Notion.app"
    "/Applications/Google Chrome.app"
    "/Applications/cmux.app"
    "/Applications/Ghostty.app"
    "/Applications/Claude.app"
    "/Applications/Zed.app"
    "/Applications/Figma.app"
    "/Applications/TablePlus.app"
    "/Applications/1Password.app"
    "/Applications/Nani.app"
    "/Applications/OrbStack.app"
    "/System/Applications/System Settings.app"
)

sub1_dock_apps=(
    "${launchpad_app}"
    "/Applications/Slack.app"
    "/Applications/Notion.app"
    "/Applications/Google Chrome.app"
    "/Applications/cmux.app"
    "/Applications/Ghostty.app"
    "/Applications/Claude.app"
    "/Applications/Zed.app"
    "/Applications/Figma.app"
    "/Applications/TablePlus.app"
    "/Applications/1Password.app"
    "/Applications/Nani.app"
    "/Applications/Microsoft Teams.app"
    "/Applications/Microsoft Outlook.app"
    "/Applications/OrbStack.app"
    "/System/Applications/System Settings.app"
)

if [[ "${ROLE}" == "default" ]]; then
    dock_apps=("${default_dock_apps[@]}")
else
    dock_apps=("${sub1_dock_apps[@]}")
fi

# persistent-apps: 一旦空配列にしてから、role 別リストを順番に -array-add する
# (macOS Dock plist の標準構造: tile-data.file-data._CFURLString)
defaults write com.apple.dock persistent-apps -array
for app_path in "${dock_apps[@]}"; do
    defaults write com.apple.dock persistent-apps -array-add \
        "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>${app_path}</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
done

# persistent-others: Downloads フォルダ (role 非依存)
defaults write com.apple.dock persistent-others -array
defaults write com.apple.dock persistent-others -array-add \
    "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>${HOME}/Downloads</string><key>_CFURLStringType</key><integer>0</integer></dict><key>arrangement</key><integer>4</integer><key>displayas</key><integer>1</integer><key>showas</key><integer>1</integer></dict></dict>"

# ---------------------------------------------------------------------------
# Finder (11 件 native 相当 + 6 件 CustomUserPreferences)
# ---------------------------------------------------------------------------
defaults::backup_once "com.apple.finder"

defaults write com.apple.finder FXPreferredViewStyle -string Nlsv
defaults write com.apple.finder FXRemoveOldTrashItems -bool true
defaults write com.apple.finder NewWindowTarget -string PfHm
defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
defaults write com.apple.finder ShowHardDrivesOnDesktop -bool false
defaults write com.apple.finder ShowMountedServersOnDesktop -bool false
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool true
defaults write com.apple.finder ShowStatusBar -bool true
defaults write com.apple.finder _FXSortFoldersFirst -bool true
defaults write com.apple.finder _FXSortFoldersFirstOnDesktop -bool true

defaults write com.apple.finder FK_AppCentricShowSidebar -bool true
defaults write com.apple.finder FXArrangeGroupViewBy -string Name
defaults write com.apple.finder "NSWindowTabbingShoudShowTabBarKey-com.apple.finder.TBrowserWindow" -bool true
defaults write com.apple.finder RecentsArrangeGroupViewBy -string "Date Last Opened"
defaults write com.apple.finder ShowSidebar -bool true
defaults write com.apple.finder SidebarDevicesSectionDisclosedState -bool true

# ---------------------------------------------------------------------------
# Menubar Clock (3 件)
# ---------------------------------------------------------------------------
defaults::backup_once "com.apple.menuextra.clock"

defaults write com.apple.menuextra.clock ShowAMPM -bool true
defaults write com.apple.menuextra.clock ShowDate -int 0
defaults write com.apple.menuextra.clock ShowDayOfWeek -bool true

# ---------------------------------------------------------------------------
# NSGlobalDomain (6 件 native 相当 + 12 件 CustomUserPreferences)
# ---------------------------------------------------------------------------
defaults::backup_once "NSGlobalDomain"

defaults write NSGlobalDomain AppleInterfaceStyle -string Dark
defaults write NSGlobalDomain AppleKeyboardUIMode -int 2
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
defaults write NSGlobalDomain AppleSpacesSwitchOnActivate -bool false
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool true
defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool true

defaults write NSGlobalDomain AppleLocale -string ja_JP
defaults write NSGlobalDomain AppleMiniaturizeOnDoubleClick -bool false
defaults write NSGlobalDomain KB_DoubleQuoteOption -string '“abc”'
defaults write NSGlobalDomain KB_SingleQuoteOption -string '‘abc’'
defaults write NSGlobalDomain NSNavPanelFileLastListModeForOpenModeKey -int 1
defaults write NSGlobalDomain NSNavPanelFileListModeForOpenMode2 -int 1
defaults write NSGlobalDomain NavPanelFileListModeForOpenMode -int 1
defaults write NSGlobalDomain "com.apple.keyboard.fnState" -bool true
defaults write NSGlobalDomain "com.apple.sound.beep.flash" -int 0
defaults write NSGlobalDomain "com.apple.springing.delay" -float 0.5
defaults write NSGlobalDomain "com.apple.springing.enabled" -bool true
defaults write NSGlobalDomain "com.apple.trackpad.forceClick" -bool true

# ---------------------------------------------------------------------------
# Trackpad (21 件 native 相当)
# ---------------------------------------------------------------------------
defaults::backup_once "com.apple.AppleMultitouchTrackpad"

defaults write com.apple.AppleMultitouchTrackpad ActuateDetents -bool true
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
defaults write com.apple.AppleMultitouchTrackpad DragLock -bool false
defaults write com.apple.AppleMultitouchTrackpad Dragging -bool false
defaults write com.apple.AppleMultitouchTrackpad FirstClickThreshold -int 1
defaults write com.apple.AppleMultitouchTrackpad ForceSuppressed -bool false
defaults write com.apple.AppleMultitouchTrackpad SecondClickThreshold -int 1
defaults write com.apple.AppleMultitouchTrackpad TrackpadCornerSecondaryClick -int 0
defaults write com.apple.AppleMultitouchTrackpad TrackpadFourFingerHorizSwipeGesture -int 2
defaults write com.apple.AppleMultitouchTrackpad TrackpadFourFingerPinchGesture -int 2
defaults write com.apple.AppleMultitouchTrackpad TrackpadFourFingerVertSwipeGesture -int 2
defaults write com.apple.AppleMultitouchTrackpad TrackpadMomentumScroll -bool true
defaults write com.apple.AppleMultitouchTrackpad TrackpadPinch -bool true
defaults write com.apple.AppleMultitouchTrackpad TrackpadRightClick -bool true
defaults write com.apple.AppleMultitouchTrackpad TrackpadRotate -bool true
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool false
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerHorizSwipeGesture -int 2
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerTapGesture -int 0
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerVertSwipeGesture -int 0
defaults write com.apple.AppleMultitouchTrackpad TrackpadTwoFingerDoubleTapGesture -bool true
defaults write com.apple.AppleMultitouchTrackpad TrackpadTwoFingerFromRightEdgeSwipeGesture -int 3

# CustomUserPreferences 側の AppleMultitouchTrackpad 5 件 (内蔵のみ、nix-darwin trackpad
# module 非対応分)
defaults write com.apple.AppleMultitouchTrackpad TrackpadFiveFingerPinchGesture -int 2
defaults write com.apple.AppleMultitouchTrackpad TrackpadHandResting -bool true
defaults write com.apple.AppleMultitouchTrackpad TrackpadHorizScroll -int 1
defaults write com.apple.AppleMultitouchTrackpad TrackpadScroll -bool true
defaults write com.apple.AppleMultitouchTrackpad USBMouseStopsTrackpad -int 0

# ---------------------------------------------------------------------------
# Control Center / Menubar (4 件)
# ---------------------------------------------------------------------------
defaults::backup_once "com.apple.controlcenter"

defaults write com.apple.controlcenter "NSStatusItem VisibleCC Battery" -bool true
defaults write com.apple.controlcenter "NSStatusItem VisibleCC BentoBox-0" -bool true
defaults write com.apple.controlcenter "NSStatusItem VisibleCC Clock" -bool true
defaults write com.apple.controlcenter "NSStatusItem VisibleCC WiFi" -bool true

# ---------------------------------------------------------------------------
# IME / 入力ソース (com.apple.HIToolbox / com.apple.inputsources)
# plist は複製せず nix/modules/darwin/ の既存ファイルを単一ソースとして参照する。
# ---------------------------------------------------------------------------
util::info "=== IME / 入力ソース import ==="
# defaults import はドメイン全体を上書きする最も破壊的な操作 (write と違い、
# import 元に無いキーも消える)。他の domain と同じく初回のみバックアップを取ってから実行する。
defaults::backup_once "com.apple.HIToolbox"
defaults import com.apple.HIToolbox "${DOTFILES_ROOT}/nix/modules/darwin/hitoolbox.plist"

defaults::backup_once "com.apple.inputsources"
defaults import com.apple.inputsources "${DOTFILES_ROOT}/nix/modules/darwin/inputsources.plist"

util::info "=== Tier 2: macOS defaults 完了 ==="
