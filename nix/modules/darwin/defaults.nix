# nix-darwin macOS defaults モジュール (S10 / KISSA-30)
# specialArgs 由来: inputs / username / role (flake.nix から注入)
# 自動注入: pkgs / lib / config (... で受け取る)
#
# 元データ:
#   - docs/inventory/m5mbp-2026-05-14.md         (棚卸スナップショット 5,364 行 / 自動生成)
#   - docs/inventory/m5mbp-2026-05-14-triage-draft.md (triage 結果 / 73 件 nix化 / 41 件 無視)
#
# 戦略:
#   - nix-darwin の native module (dock / finder / menuExtraClock / NSGlobalDomain / trackpad)
#     で型付きサポートがある key は system.defaults.<module>.<attr> を使う (型検証あり)
#   - それ以外 (27 件) は system.defaults.CustomUserPreferences."<domain>".<attr> で書く
#
# 棚卸 triage マルチホスト注意:
#   このマシン (m5mbp) を source of truth として triage した値。別 PC では再 triage が必要。
#   特に AppleLocale / KB_*QuoteOption は日本語入力環境前提。
{ username, role, ... }:

let
  # ----------------------------------------------------------------
  # Dock persistent-apps: role 別に独立宣言する
  # ----------------------------------------------------------------
  # homebrew.nix と異なり persistent-apps は「リスト順 = Dock 左→右の表示順」
  # そのものなので core ++ optional パターンでは System Settings が中間に
  # 挟まる等の表示崩れが起きる。各 role の Dock 並びは独立に宣言する。
  #
  # Apps.app は macOS 26+ の Launchpad 後継。macOS 15.x には存在しないため
  # Launchpad.app にフォールバックする。builtins.pathExists は --impure 評価時に判定。
  # OS アップデート後に Apps.app が出現したら次回 darwin-rebuild switch で自動切替。
  launchpadApp =
    if builtins.pathExists /System/Applications/Apps.app
    then "/System/Applications/Apps.app"
    else "/System/Applications/Launchpad.app";

  # default role (15 件): Linear が default 専用 (sub-1 PC では Dock に出さない方針)。
  defaultDockApps = [
    launchpadApp
    "/Applications/Linear.app"
    "/Applications/Slack.app"
    "/Applications/Notion.app"
    "/Applications/Google Chrome.app"
    "/Applications/cmux.app"
    "/Applications/Claude.app"
    "/Applications/Zed.app"
    "/Applications/Figma.app"
    "/Applications/TablePlus.app"
    "/Applications/1Password.app"
    "/Applications/Postman.app"
    "/Applications/Nani.app"
    "/Applications/OrbStack.app"
    "/System/Applications/System Settings.app"
  ];

  # sub-1 role (16 件): Microsoft Teams / Outlook が sub-1 専用 (MDM 配布)。
  # それ以外の sub-1 専用アプリは公開リポジトリには宣言しない方針 (homebrew.nix の
  # cleanup = "none" 設計と整合) のため Dock にも含めない。
  sub1DockApps = [
    launchpadApp
    "/Applications/Slack.app"
    "/Applications/Notion.app"
    "/Applications/Google Chrome.app"
    "/Applications/cmux.app"
    "/Applications/Claude.app"
    "/Applications/Zed.app"
    "/Applications/Figma.app"
    "/Applications/TablePlus.app"
    "/Applications/1Password.app"
    "/Applications/Postman.app"
    "/Applications/Nani.app"
    "/Applications/Microsoft Teams.app"
    "/Applications/Microsoft Outlook.app"
    "/Applications/OrbStack.app"
    "/System/Applications/System Settings.app"
  ];
in
{
  system.defaults = {
    # =================================================================
    # Dock (基本設定 5 件 + persistent-apps role 別 + persistent-others 1 / 全 native)
    # =================================================================
    dock = {
      autohide = true;                            # Dock 自動非表示
      magnification = true;                       # ホバーで拡大
      mru-spaces = false;                         # Space 自動並び替え無効（固定順）
      showAppExposeGestureEnabled = true;         # App Exposé ジェスチャ (下スワイプ)
      wvous-br-corner = 14;                       # ホットコーナー右下 = Quick Note
                                                  # (2=Mission Control / 4=Desktop / 5=Screensaver
                                                  #  / 11=Launchpad / 13=Lock / 14=Quick Note)

      # ---- Dock 左側 (アプリ) role 別 ----
      # nix-darwin の coercedTo により文字列リストは自動的に { app = "..."; } タグ付きに変換される。
      # アプリが当該 PC に存在しないと Dock アイコンが "?" になる。
      # 別 PC で展開するアプリは homebrew.nix の casks で導入されることが前提。
      persistent-apps =
        if role == "default" then defaultDockApps
        else if role == "sub-1" then sub1DockApps
        else throw "defaults.nix: unknown role \"${role}\"";

      # ---- Dock 右側 (フォルダ / ファイル) 1 件 ----
      # ユーザーホームをハードコードしないため username パラメータを使う。
      persistent-others = [
        {
          folder = {
            path = "/Users/${username}/Downloads";
            arrangement = "date-added";   # 追加日順 (新しい順)
            displayas = "stack";          # スタック表示
            showas = "fan";               # クリック時はファン展開
          };
        }
      ];
    };

    # =================================================================
    # Finder (11 件 native / 残 6 件は CustomUserPreferences 側)
    # =================================================================
    finder = {
      FXPreferredViewStyle = "Nlsv";              # デフォルトはリスト表示
                                                  # (icnv=Icon / Nlsv=List / clmv=Column / glyv=Gallery)
      FXRemoveOldTrashItems = true;               # 30 日後にゴミ箱自動削除
      NewWindowTarget = "Home";                   # 新規ウィンドウ初期フォルダ
                                                  # apply で "PfHm" に変換される
      ShowExternalHardDrivesOnDesktop = true;
      ShowHardDrivesOnDesktop = false;
      ShowMountedServersOnDesktop = false;
      ShowPathbar = true;                         # パスバー表示
      ShowRemovableMediaOnDesktop = true;
      ShowStatusBar = true;                       # ステータスバー表示
      _FXSortFoldersFirst = true;                 # フォルダ先頭ソート
      _FXSortFoldersFirstOnDesktop = true;        # デスクトップでもフォルダ先頭
    };

    # =================================================================
    # Menubar Clock (3 件 / 全 native)
    # =================================================================
    menuExtraClock = {
      ShowAMPM = true;                            # AM/PM 表示
      ShowDate = 0;                               # 0=When space allows / 1=Always / 2=Never
      ShowDayOfWeek = true;                       # 曜日表示
    };

    # =================================================================
    # NSGlobalDomain (6 件 native / 残 12 件は CustomUserPreferences 側)
    # =================================================================
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";               # ダークモード
      AppleKeyboardUIMode = 2;                    # 0=テキストのみ / 2=すべてのコントロール
      AppleShowAllExtensions = true;              # 拡張子常に表示
      AppleSpacesSwitchOnActivate = false;        # アプリ起動時に既存 Space へ自動切替しない
      NSAutomaticCapitalizationEnabled = true;    # 英文の自動大文字化
      NSAutomaticPeriodSubstitutionEnabled = true;# スペース 2 連打でピリオド挿入
    };

    # =================================================================
    # Trackpad (21 件 native / 残 5 件は CustomUserPreferences 側)
    # nix-darwin trackpad モジュールは内蔵 (com.apple.AppleMultitouchTrackpad) と
    # Bluetooth (com.apple.driver.AppleBluetoothMultitouch.trackpad) の双方に書き込む。
    # =================================================================
    trackpad = {
      ActuateDetents = true;                              # Force Touch 触覚フィードバック
      Clicking = true;                                    # タップでクリック
      DragLock = false;                                   # ドラッグロック無効
      Dragging = false;                                   # ダブルタップドラッグ無効
      FirstClickThreshold = 1;                            # 通常クリック圧 (中)
      ForceSuppressed = false;                            # Force Click 有効
      SecondClickThreshold = 1;                           # Force Click 検出圧 (中)
      TrackpadCornerSecondaryClick = 0;                   # コーナークリック無効
      TrackpadFourFingerHorizSwipeGesture = 2;            # 4 本指水平 = フルスクリーンアプリ切替
      TrackpadFourFingerPinchGesture = 2;                 # 4 本指ピンチ = Desktop/Launchpad
      TrackpadFourFingerVertSwipeGesture = 2;             # 4 本指垂直 = Mission Control
      TrackpadMomentumScroll = true;                      # 慣性スクロール
      TrackpadPinch = true;                               # ピンチでズーム
      TrackpadRightClick = true;                          # 2 本指タップ = 副ボタン
      TrackpadRotate = true;                              # 2 本指回転
      TrackpadThreeFingerDrag = false;                    # 3 本指ドラッグ無効
      TrackpadThreeFingerHorizSwipeGesture = 2;           # 3 本指水平 = Space 切替
      TrackpadThreeFingerTapGesture = 0;                  # 3 本指タップ無効
      TrackpadThreeFingerVertSwipeGesture = 0;            # 3 本指垂直無効
      TrackpadTwoFingerDoubleTapGesture = true;           # スマートズーム
      TrackpadTwoFingerFromRightEdgeSwipeGesture = 3;     # 右端 2 本指スワイプ = 通知センター
    };

    # =================================================================
    # CustomUserPreferences (native module で型サポートのない 27 件)
    # 構造化 array of dict (AppleEnabledInputSources 等) は別途 activationScript 案件。
    # =================================================================
    CustomUserPreferences = {
      # ---- NSGlobalDomain (12 件) ----
      "NSGlobalDomain" = {
        AppleLocale = "ja_JP";
        AppleMiniaturizeOnDoubleClick = false;
        # スマートクォート設定。値はリテラル "“abc”" 形式で macOS が runtime に解釈する。
        # “=U+201C("), ”=U+201D("), ‘=U+2018('), ’=U+2019(').
        KB_DoubleQuoteOption = "\\u201cabc\\u201d";
        KB_SingleQuoteOption = "\\u2018abc\\u2019";
        NSNavPanelFileLastListModeForOpenModeKey = 1;       # Open ダイアログのモード記憶
        NSNavPanelFileListModeForOpenMode2 = 1;             # 新形式 Open ダイアログ
        NavPanelFileListModeForOpenMode = 1;                # legacy Open ダイアログ
        "com.apple.keyboard.fnState" = true;                # Fn+F1..F12 でメディアキー扱い反転
        "com.apple.sound.beep.flash" = 0;                   # ビープ時に画面フラッシュしない
        "com.apple.springing.delay" = 0.5;                  # Spring-loaded フォルダ遅延 (秒)
        "com.apple.springing.enabled" = true;
        "com.apple.trackpad.forceClick" = true;             # Force Click 強めクリック検出
      };

      # ---- Finder (6 件) ----
      "com.apple.finder" = {
        FK_AppCentricShowSidebar = true;                    # アプリ別 Open/Save ダイアログのサイドバー
        FXArrangeGroupViewBy = "Name";                      # グループ表示の並び替え基準
        "NSWindowTabbingShoudShowTabBarKey-com.apple.finder.TBrowserWindow" = true;
        RecentsArrangeGroupViewBy = "Date Last Opened";     # 「最近の項目」並び替え
        ShowSidebar = true;
        SidebarDevicesSectionDisclosedState = true;         # サイドバー「デバイス」展開
      };

      # ---- Control Center / Menubar (4 件) ----
      # メニューバーに表示する Control Center アイコン群。
      # key 名にスペース・ハイフンを含むため Nix で quoted attr 必須。
      "com.apple.controlcenter" = {
        "NSStatusItem VisibleCC Battery" = true;
        "NSStatusItem VisibleCC BentoBox-0" = true;
        "NSStatusItem VisibleCC Clock" = true;
        "NSStatusItem VisibleCC WiFi" = true;
      };

      # ---- AppleMultitouchTrackpad (5 件 / nix-darwin trackpad モジュール非対応分) ----
      # 内蔵トラックパッドにのみ書き込み (native trackpad モジュールは bluetooth にも書くが、
      # これらは内蔵のみで十分)。
      "com.apple.AppleMultitouchTrackpad" = {
        TrackpadFiveFingerPinchGesture = 2;                 # 5 本指つまみ = Launchpad
        TrackpadHandResting = true;                         # 手のひら無視
        TrackpadHorizScroll = 1;                            # 水平スクロール
        TrackpadScroll = true;                              # 2 本指スクロール
        USBMouseStopsTrackpad = 0;                          # USB マウス接続時もトラックパッド有効
      };
    };
  };

  # =====================================================================
  # 翻訳しなかった項目の記録 (CLAUDE.md §棚卸ワークフロー の要請)
  # =====================================================================
  # 「無視」マーク 41 件: 機械的 metadata / 移行マーカー / 状態キャッシュ / ロケール派生
  #   → 詳細は docs/inventory/m5mbp-2026-05-14-triage-draft.md
  #
  # com.apple.HIToolbox (Input Sources / IME): scalar key 0 件
  #   AppleEnabledInputSources / AppleSelectedInputSources は array of dict 構造で
  #   CustomUserPreferences の plist 値変換が不安定。今は IME は手動セットアップに任せ、
  #   activationScript で defaults write -array-add を呼ぶ実装は後続 issue で対応する。
  #
  # com.apple.universalaccess / com.apple.screencapture: 今回 triage スコープ外。
  #   別 PC で必要が生じたら inventory を取り直して再 triage する。
  #
  # =====================================================================
  # 検証ポイント (実機 darwin-rebuild switch 後)
  # =====================================================================
  # - defaults read com.apple.dock autohide                       → 1
  # - defaults read com.apple.finder FXPreferredViewStyle         → Nlsv
  # - defaults read -g AppleInterfaceStyle                        → Dark
  # - defaults read com.apple.AppleMultitouchTrackpad Clicking    → 1
  # - defaults read com.apple.controlcenter "NSStatusItem VisibleCC WiFi" → 1
  # - 視覚: Dock 自動非表示 / Finder リスト表示 / メニューバーに WiFi/Clock/Battery 表示
  #
  # 適用直後は影響を受ける UI (Finder / Dock / SystemUIServer) の再起動が必要な場合あり:
  #   killall Dock Finder SystemUIServer ControlCenter
}
