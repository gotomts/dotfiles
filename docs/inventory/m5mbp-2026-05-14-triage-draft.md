# Triage Draft — m5mbp — 2026-05-14

> 自動生成: `defaults export <domain> | plistlib` + Claude 推奨マーク pre-fill
> 元データ: `docs/inventory/m5mbp-2026-05-14.md` (5,364 行) → スカラー key のみ抽出 (114 件)

各項目を確認し、推奨マークが不適切な場合は書き換えてください。
マーク完了後、Claude が `nix/modules/darwin/defaults.nix` への翻訳を行います。

## サマリ

| ドメイン | nix化 | 無視 | 検討 | 計 |
|---|---:|---:|---:|---:|
| com.apple.dock (Dock) | 5 | 4 | 0 | 9 |
| com.apple.finder (Finder) | 15 | 16 | 7 | 38 |
| com.apple.menuextra.clock (Menubar Clock) | 3 | 0 | 0 | 3 |
| com.apple.controlcenter (Control Center / Menubar) | 4 | 2 | 3 | 9 |
| NSGlobalDomain (Global (Keyboard / Locale / etc.)) | 15 | 7 | 5 | 27 |
| com.apple.HIToolbox (Input Sources (IME)) | 0 | 0 | 0 | 0 |
| com.apple.AppleMultitouchTrackpad (Trackpad) | 26 | 1 | 1 | 28 |
| **合計** | **68** | **30** | **16** | **114** |

## 凡例

- `[nix化]` 推奨: 別 PC でも同じ設定を再現したい
- `[無視]` 推奨: マシン固有 or OS 自動管理で宣言しても意味ない
- `[検討]` 推奨: 自動判定不可。ユーザーが判断して `[nix化]` か `[無視]` に書き換える

各行の `<!-- ... -->` 部分は **(意味) — (現在値 / 値の解釈)** の形式。

---

## com.apple.dock
> Dock

- [nix化] `autohide` = True
  - **意味**: Dock 自動非表示
  - **値**: True=隠す（マウスホバーで表示） / False=常時表示
- [無視] `loc` = 'ja_JP:JP'
  - **意味**: Dock 内部ロケール文字列
  - **値**: AppleLocale から派生キャッシュ。明示宣言不要
- [nix化] `magnification` = True
  - **意味**: Dock アイコン拡大表示
  - **値**: True=ホバーで拡大 / False=固定
- [nix化] `mru-spaces` = False
  - **意味**: Space 自動並び替え
  - **値**: True=最近使用した Space を左に / False=固定順
- [無視] `region` = 'JP'
  - **意味**: リージョン (JP/US 等)
  - **値**: ロケール派生キャッシュ
- [nix化] `showAppExposeGestureEnabled` = True
  - **意味**: App Exposé ジェスチャ (下スワイプ)
  - **値**: True=有効 / False=無効
- [無視] `trash-full` = False
  - **意味**: ゴミ箱に項目あり状態
  - **値**: Finder/Dock 状態キャッシュ
- [無視] `version` = 1
  - **意味**: Dock 設定スキーマバージョン
  - **値**: OS 内部管理
- [nix化] `wvous-br-corner` = 14
  - **意味**: ホットコーナー（右下）の動作
  - **値**: 14=クイックメモ。他: 2=Mission Control, 4=Desktop, 5=Screensaver, 11=Launchpad, 13=Lock

## com.apple.finder
> Finder

- [無視] `DownloadsFolderListViewSettingsVersion` = 1
  - **意味**: ダウンロード一覧表示設定スキーマver
  - **値**: OS 内部
- [nix化] `FK_AppCentricShowSidebar` = True
  - **意味**: アプリ別 Open/Save ダイアログのサイドバー
  - **値**: True=表示 / False=非表示
- [無視] `FK_SidebarWidth2` = 171.0
  - **意味**: Open/Save サイドバー幅 (pt)
  - **値**: 171.0pt。ディスプレイ解像度依存
- [nix化] `FXArrangeGroupViewBy` = 'Name'
  - **意味**: グループ表示の並び替え基準
  - **値**: 'Name'=名前順
- [無視] `FXDesktopTouchBarUpgradedToTenTwelveOne` = 1
  - **意味**: 10.12.1 移行マーカー
  - **値**: OS 内部
- [無視] `FXDetachedDesktopProviderID` = 'com.apple.CloudDocs.iCloudDriveFileProvider/036A52E3-6178-420B-B9F2-EE0D2BD449B0'
  - **意味**: iCloud Desktop プロバイダ ID
  - **値**: Apple ID 固有 UUID
- [無視] `FXDetachedDocumentsProviderID` = 'com.apple.CloudDocs.iCloudDriveFileProvider/036A52E3-6178-420B-B9F2-EE0D2BD449B0'
  - **意味**: iCloud Documents プロバイダ ID
  - **値**: Apple ID 固有 UUID
- [無視] `FXICloudDriveDesktop` = True
  - **意味**: iCloud に Desktop 同期
  - **値**: True=同期。PC 毎に分けたい場合は無視
- [無視] `FXICloudDriveDocuments` = True
  - **意味**: iCloud に Documents 同期
  - **値**: True=同期。PC 毎に分けたい場合は無視
- [無視] `FXICloudDriveEnabled` = True
  - **意味**: iCloud Drive 有効
  - **値**: True=有効
- [無視] `FXICloudLoggedIn` = True
  - **意味**: iCloud ログイン状態
  - **値**: OS 自動管理
- [無視] `FXPreferencesWindow.Location` = '{{2588, 723}, {377, 424}}'
  - **意味**: Finder 環境設定ウィンドウ位置 (pt)
  - **値**: 画面サイズ依存
- [nix化] `FXPreferredViewStyle` = 'Nlsv'
  - **意味**: 新規ウィンドウのデフォルト表示
  - **値**: 'Nlsv'=リスト / 'icnv'=アイコン / 'clmv'=カラム / 'glyv'=ギャラリー
- [無視] `FXQuickActionsConfigUpgradeLevel` = 3
  - **意味**: Quick Actions 移行マーカー
  - **値**: OS 内部
- [nix化] `FXRemoveOldTrashItems` = True
  - **意味**: 30 日後にゴミ箱を自動削除
  - **値**: True=有効 / False=保持
- [無視] `FXSidebarUpgradedToSixteen` = True
  - **意味**: macOS 16 サイドバー移行マーカー
  - **値**: OS 内部
- [無視] `FXToolbarUpgradedToTenEight` = 1
  - **意味**: 10.8 ツールバー移行マーカー
  - **値**: OS 内部
- [無視] `FXToolbarUpgradedToTenNine` = 2
  - **意味**: 10.9 ツールバー移行マーカー
  - **値**: OS 内部
- [無視] `FXToolbarUpgradedToTenSeven` = 1
  - **意味**: 10.7 ツールバー移行マーカー
  - **値**: OS 内部
- [無視] `LastTrashState` = False
  - **意味**: 前回のゴミ箱状態
  - **値**: 状態キャッシュ
- [nix化] `NSWindowTabbingShoudShowTabBarKey-com.apple.finder.TBrowserWindow` = True
  - **意味**: Finder のタブバー表示
  - **値**: True=常に表示
- [nix化] `NewWindowTarget` = 'PfHm'
  - **意味**: 新規 Finder ウィンドウの初期フォルダ
  - **値**: 'PfHm'=Home / 'PfDe'=Desktop / 'PfDo'=Documents / 'PfCm'=Computer / 'PfLo'=Recents / 'PfCu'=Custom
- [無視] `PreferencesWindow.LastSelection` = 'GNRL'
  - **意味**: Finder 環境設定の最後のタブ
  - **値**: UI 状態キャッシュ
- [nix化] `RecentsArrangeGroupViewBy` = 'Date Last Opened'
  - **意味**: 「最近使った項目」グループ基準
  - **値**: 'Date Last Opened'=最近開いた順
- [無視] `SearchRecentsSavedViewStyleVersion` = '%00%00%00%01'
  - **意味**: 検索結果表示スキーマver
  - **値**: OS 内部バイナリ
- [nix化] `ShowExternalHardDrivesOnDesktop` = False
  - **意味**: 外付け HDD をデスクトップ表示
  - **値**: True=表示 / False=非表示
- [nix化] `ShowHardDrivesOnDesktop` = False
  - **意味**: 内蔵 HDD をデスクトップ表示
  - **値**: True=表示 / False=非表示
- [nix化] `ShowMountedServersOnDesktop` = False
  - **意味**: マウント済サーバをデスクトップ表示
  - **値**: True=表示 / False=非表示
- [nix化] `ShowPathbar` = True
  - **意味**: Finder パスバー表示
  - **値**: True=表示（下部にパス）/ False=非表示
- [nix化] `ShowRemovableMediaOnDesktop` = True
  - **意味**: USB/CD 等をデスクトップ表示
  - **値**: True=表示 / False=非表示
- [nix化] `ShowSidebar` = True
  - **意味**: Finder サイドバー表示
  - **値**: True=表示 / False=非表示
- [nix化] `ShowStatusBar` = True
  - **意味**: Finder ステータスバー表示
  - **値**: True=表示（下部に項目数/空き容量）/ False=非表示
- [nix化] `SidebarDevicesSectionDisclosedState` = True
  - **意味**: サイドバー「デバイス」展開状態
  - **値**: True=展開
- [無視] `SidebarWidth2` = 161.0
  - **意味**: Finder サイドバー幅 (pt)
  - **値**: 161.0pt。ディスプレイ依存
- [無視] `TagsCloudSerialNumber` = 1
  - **意味**: iCloud タグ同期シリアル
  - **値**: OS 内部
- [無視] `_FXInputMethodLocation` = '{{0, 1374}, {3360, 44}}'
  - **意味**: IME ウィンドウ位置 (pt)
  - **値**: 画面サイズ依存
- [nix化] `_FXSortFoldersFirst` = True
  - **意味**: Finder でフォルダを先頭ソート
  - **値**: True=フォルダ先 / False=混在
- [nix化] `_FXSortFoldersFirstOnDesktop` = True
  - **意味**: デスクトップでもフォルダ先頭ソート
  - **値**: True=フォルダ先 / False=混在

## com.apple.menuextra.clock
> Menubar Clock

- [nix化] `ShowAMPM` = False
  - **意味**: メニューバー時計の AM/PM 表示
  - **値**: True=12 時間制 / False=24 時間制
- [nix化] `ShowDate` = 2
  - **意味**: メニューバー時計の日付表示
  - **値**: 0=非表示 / 1=日付のみ / 2=時刻と日付の両方
- [nix化] `ShowDayOfWeek` = True
  - **意味**: メニューバー時計の曜日表示
  - **値**: True=曜日表示 / False=非表示

## com.apple.controlcenter
> Control Center / Menubar

- [無視] `HasAttemptedMenuBarWorkflowMigration` = True
  - **意味**: メニューバー移行試行マーカー
  - **値**: OS 内部
- [無視] `LastHeartbeatDateString.daily` = '2026-05-13T11:12:17Z'
  - **意味**: Daily Heartbeat 最終実行日時
  - **値**: OS 内部キャッシュ
- [無視] `NSStatusItem Preferred Position BentoBox-0` = 252.0
  - **意味**: BentoBox 位置 (px from right)
  - **値**: 252.0px。メニューバー幅依存
- [無視] `NSStatusItem Preferred Position WiFi` = 214.0
  - **意味**: WiFi 位置 (px from right)
  - **値**: 214.0px。メニューバー幅依存
- [nix化] `NSStatusItem VisibleCC Battery` = True
  - **意味**: メニューバーの Battery 表示
  - **値**: True=表示 / False=非表示
- [nix化] `NSStatusItem VisibleCC BentoBox-0` = True
  - **意味**: メニューバーの BentoBox 表示
  - **値**: True=表示（Control Center 拡張）
- [nix化] `NSStatusItem VisibleCC Clock` = True
  - **意味**: メニューバーの Clock 表示
  - **値**: True=表示
- [nix化] `NSStatusItem VisibleCC WiFi` = True
  - **意味**: メニューバーの WiFi 表示
  - **値**: True=表示 / False=非表示
- [無視] `RemoteLiveActivitiesEnabled` = True
  - **意味**: iPhone Live Activities 連携
  - **値**: True=有効

## NSGlobalDomain
> Global (Keyboard / Locale / etc.)

- [無視] `ACDMonthlyAnalyticsLastPosted` = 800256923.193733
  - **意味**: アナリティクス送信最終時刻
  - **値**: OS 内部キャッシュ
- [無視] `AKLastIDMSEnvironment` = 0
  - **意味**: Apple ID IDMS 環境
  - **値**: OS 自動管理
- [無視] `AKLastLocale` = 'ja_JP'
  - **意味**: Apple Account 最終ロケール
  - **値**: OS キャッシュ
- [無視] `AppleAntiAliasingThreshold` = 4
  - **意味**: アンチエイリアス閾値 (pt)
  - **値**: 4pt 未満はアンチエイリアスしない。Retina では効果薄
- [nix化] `AppleInterfaceStyle` = 'Dark'
  - **意味**: 外観モード
  - **値**: 'Dark'=ダーク / unset=ライト / 'Auto'=自動
- [nix化] `AppleKeyboardUIMode` = 2
  - **意味**: キーボードフルアクセス
  - **値**: 0=テキストのみ / 2=すべてのコントロール
- [無視] `AppleLanguagesSchemaVersion` = 5400
  - **意味**: 言語設定スキーマver
  - **値**: OS 内部
- [nix化] `AppleLocale` = 'ja_JP'
  - **意味**: ロケール
  - **値**: 'ja_JP'=日本語/日本
- [nix化] `AppleMiniaturizeOnDoubleClick` = False
  - **意味**: タイトルバーダブルクリックで最小化
  - **値**: True=最小化 / False=何もしない（macOS デフォルトでは zoom）
- [nix化] `AppleShowAllExtensions` = True
  - **意味**: Finder 拡張子を常に表示
  - **値**: True=常に表示 / False=隠す
- [nix化] `AppleSpacesSwitchOnActivate` = False
  - **意味**: アプリ起動時に既存ウィンドウのある Space へ
  - **値**: True=切替 / False=現在の Space に新規表示
- [nix化] `KB_DoubleQuoteOption` = '“abc”'
  - **意味**: スマートクォート（ダブル）
  - **値**: '"abc"'=英文用カーリー / 'abc'=ストレート
- [nix化] `KB_SingleQuoteOption` = '‘abc’'
  - **意味**: スマートクォート（シングル）
  - **値**: 'abc' のカーリー版
- [nix化] `NSAutomaticCapitalizationEnabled` = True
  - **意味**: 英文の自動大文字化
  - **値**: True=有効 / False=無効（コード書きには False 推奨）
- [nix化] `NSAutomaticPeriodSubstitutionEnabled` = True
  - **意味**: スペース 2 連打でピリオド挿入
  - **値**: True=有効 / False=無効
- [無視] `NSLinguisticDataAssetsRequestLastInterval` = 86400.0
  - **意味**: 言語データ取得間隔キャッシュ
  - **値**: OS 内部
- [nix化] `NSNavPanelFileLastListModeForOpenModeKey` = 1
  - **意味**: Open ダイアログの直近表示モード
  - **値**: 1=リスト表示記憶
- [nix化] `NSNavPanelFileListModeForOpenMode2` = 1
  - **意味**: Open ダイアログの新形式表示モード
  - **値**: 1=リスト
- [無視] `NSSpellCheckerContainerTransitionComplete` = True
  - **意味**: スペルチェッカー移行マーカー
  - **値**: OS 内部
- [無視] `NSSpellCheckerDictionaryContainerTransitionComplete` = True
  - **意味**: 辞書移行マーカー
  - **値**: OS 内部
- [nix化] `NavPanelFileListModeForOpenMode` = 1
  - **意味**: Open ダイアログ表示モード (legacy)
  - **値**: 1=リスト
- [nix化] `com.apple.keyboard.fnState` = True
  - **意味**: Fn キーで F1〜F12 ファンクション扱い
  - **値**: True=Fn 押下時のみメディアキー / False=Fn なしでメディアキー
- [nix化] `com.apple.sound.beep.flash` = 0
  - **意味**: ビープ時の画面フラッシュ
  - **値**: 0=フラッシュしない / 1=フラッシュ
- [nix化] `com.apple.springing.delay` = 0.5
  - **意味**: Spring-loaded フォルダの遅延 (秒)
  - **値**: 0.5s でフォルダドラッグオーバー時に自動展開
- [nix化] `com.apple.springing.enabled` = True
  - **意味**: Spring-loaded フォルダ有効化
  - **値**: True=有効 / False=無効
- [nix化] `com.apple.trackpad.forceClick` = True
  - **意味**: Force Click & 触覚フィードバック
  - **値**: True=有効（強めクリック検出）/ False=無効
- [無視] `shouldShowRSVPDataDetectors` = False
  - **意味**: RSVP/データ検出器表示
  - **値**: False=非表示

## com.apple.HIToolbox
> Input Sources (IME)

（scalar key 抽出 0 件。`AppleEnabledInputSources` 等の dict array は `system.activationScripts` で別実装する。）

## com.apple.AppleMultitouchTrackpad
> Trackpad

- [nix化] `ActuateDetents` = 1
  - **意味**: Force Touch クリック触覚 (detent)
  - **値**: 1=有効
- [nix化] `Clicking` = True
  - **意味**: タップでクリック (Tap to Click)
  - **値**: True=タップ=クリック / False=物理押下のみ
- [nix化] `DragLock` = 0
  - **意味**: ドラッグロック
  - **値**: 0=無効 / 1=有効（タップ後一定時間ドラッグ継続）
- [nix化] `Dragging` = 0
  - **意味**: ダブルタップでドラッグ開始
  - **値**: 0=無効 / 1=有効
- [nix化] `FirstClickThreshold` = 1
  - **意味**: 通常クリック圧
  - **値**: 0=軽い / 1=中 / 2=強い
- [nix化] `ForceSuppressed` = False
  - **意味**: Force Click 抑制
  - **値**: False=Force Click 有効 / True=抑制
- [nix化] `SecondClickThreshold` = 1
  - **意味**: Force Click 検出圧
  - **値**: 0=軽い / 1=中 / 2=強い
- [nix化] `TrackpadCornerSecondaryClick` = 0
  - **意味**: 右下/左下コーナーで副ボタンクリック
  - **値**: 0=コーナークリック無効 / 2=右下副ボタン
- [nix化] `TrackpadFiveFingerPinchGesture` = 2
  - **意味**: 5 本指つまみ → Launchpad
  - **値**: 0=無効 / 2=Launchpad 表示
- [nix化] `TrackpadFourFingerHorizSwipeGesture` = 2
  - **意味**: 4 本指水平スワイプ → フルスクリーンアプリ切替
  - **値**: 0=無効 / 2=切替
- [nix化] `TrackpadFourFingerPinchGesture` = 2
  - **意味**: 4 本指広げ → デスクトップ表示
  - **値**: 0=無効 / 2=デスクトップ
- [nix化] `TrackpadFourFingerVertSwipeGesture` = 2
  - **意味**: 4 本指垂直スワイプ → Mission Control / App Exposé
  - **値**: 0=無効 / 2=有効
- [nix化] `TrackpadHandResting` = True
  - **意味**: 手のひら検出
  - **値**: True=手のひらを無視 / False=入力扱い
- [nix化] `TrackpadHorizScroll` = 1
  - **意味**: 水平スクロール
  - **値**: 1=有効
- [nix化] `TrackpadMomentumScroll` = True
  - **意味**: 慣性スクロール
  - **値**: True=有効 / False=即停止
- [nix化] `TrackpadPinch` = 1
  - **意味**: ピンチでズーム
  - **値**: 1=有効
- [nix化] `TrackpadRightClick` = True
  - **意味**: 副ボタンクリック
  - **値**: True=2 本指タップで副ボタン / False=無効
- [nix化] `TrackpadRotate` = 1
  - **意味**: 2 本指回転
  - **値**: 1=有効
- [nix化] `TrackpadScroll` = True
  - **意味**: 2 本指スクロール
  - **値**: True=有効
- [nix化] `TrackpadThreeFingerDrag` = False
  - **意味**: 3 本指ドラッグ
  - **値**: False=無効（macOS ではアクセシビリティ機能経由）
- [nix化] `TrackpadThreeFingerHorizSwipeGesture` = 2
  - **意味**: 3 本指水平スワイプ → Space 切替
  - **値**: 0=無効 / 1=ページ切替 / 2=Space
- [nix化] `TrackpadThreeFingerTapGesture` = 0
  - **意味**: 3 本指タップ → 辞書/データ検出
  - **値**: 0=無効 / 2=辞書/データ検出
- [nix化] `TrackpadThreeFingerVertSwipeGesture` = 0
  - **意味**: 3 本指垂直スワイプ → Mission Control
  - **値**: 0=無効 / 2=有効
- [nix化] `TrackpadTwoFingerDoubleTapGesture` = 1
  - **意味**: 2 本指ダブルタップ → スマートズーム
  - **値**: 0=無効 / 1=有効
- [nix化] `TrackpadTwoFingerFromRightEdgeSwipeGesture` = 3
  - **意味**: 右端から 2 本指スワイプ → 通知センター
  - **値**: 0=無効 / 3=通知センター
- [nix化] `USBMouseStopsTrackpad` = 0
  - **意味**: USB マウス接続時にトラックパッド無効
  - **値**: 0=両方有効 / 1=トラックパッド停止
- [無視] `UserPreferences` = True
  - **意味**: ユーザー設定の存在フラグ
  - **値**: True=ユーザー上書きあり / 通常 True 固定
- [無視] `version` = 12
  - **意味**: トラックパッド設定スキーマver
  - **値**: OS 内部
