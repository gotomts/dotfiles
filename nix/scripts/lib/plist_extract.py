#!/usr/bin/env python3
# nix/scripts/lib/plist_extract.py
#
# defaults export を plistlib で構造化解析し、triage 用チェックリストを stdout に出力。
# 呼び出し: python3 plist_extract.py <domain> [<domain> ...]
#
# 出力形式:
#   - [ ] key = value  <!-- nix化 / 無視 / 検討 -->
#   - persistent-apps / persistent-others はアプリ一覧サマリに変換
#   - bytes / list / dict は 1 行のサマリのみ (triage 単位ではないため checkbox なし)
#
# ノイズ除外ルール:
#   NOISE_PREFIXES  : key がこのプレフィックスで始まる → スキップ
#   NOISE_SUFFIXES  : key がこのサフィックスで終わる → スキップ
#   NOISE_SUBSTRINGS: key にこの文字列が含まれる → スキップ
#   NOISE_EXACT     : key が完全一致 → スキップ

from __future__ import annotations

import subprocess
import sys
import plistlib

# ----------------------------------------------------------------
# ノイズ判定設定
# ----------------------------------------------------------------

# key がこれで始まればノイズ
NOISE_PREFIXES: tuple[str, ...] = (
    "last-",
    "mod-",
    "lastShow",
    "ACDMonthly",
    "AKLast",
    "NSLinguistic",
    "NSSpellChecker",
    "AppleLanguagesSchema",
    "SearchRecents",
    "FXDesktopTouchBar",
    "FXQuickActions",
    "FXToolbar",
    "FXSidebarUpgraded",
    "FXDetached",
    "TagsCloud",
)

# key がこれで終わればノイズ
NOISE_SUFFIXES: tuple[str, ...] = (
    "-stamp",
    "UpgradeLevel",
    "UpgradedTo",
    "UpgradedToTen",
    "LastSelection",
)

# key にこれが含まれればノイズ
NOISE_SUBSTRINGS: tuple[str, ...] = (
    "SerialNumber",
    "TransitionComplete",
    "DataSeparated",
    "HeartbeatDate",
    ".Location",
    "ProgressWindow",
    "ProviderID",
    "MethodLocation",
    "DataAssetsRequest",
    "shouldShowRSVP",
)

# 完全一致でノイズ扱い (機械的状態キャッシュ)
NOISE_EXACT: frozenset[str] = frozenset({
    "loc",
    "region",
    "trash-full",
    "version",
    "LastTrashState",
    "UserPreferences",
    "login",
    "sessionChange",
    "AKLastLocale",
    "AKLastIDMSEnvironment",
    "last-selection-display",
    "HasAttemptedMenuBarWorkflowMigration",
    "RemoteLiveActivitiesEnabled",
    "NSStatusItem Preferred Position BentoBox-0",
    "NSStatusItem Preferred Position WiFi",
    "shouldShowRSVPDataDetectors",
    "AppleAntiAliasingThreshold",
})


def is_noise(key: str) -> bool:
    if key in NOISE_EXACT:
        return True
    for p in NOISE_PREFIXES:
        if key.startswith(p):
            return True
    for s in NOISE_SUFFIXES:
        if key.endswith(s):
            return True
    for sub in NOISE_SUBSTRINGS:
        if sub in key:
            return True
    return False


# ----------------------------------------------------------------
# Dock persistent-apps / persistent-others サマリ
# ----------------------------------------------------------------

def _url_from_file_data(tile_data: dict) -> str:
    """tile-data の file-data から URL を取り出す。"""
    fd = tile_data.get("file-data", {})
    if isinstance(fd, dict):
        return fd.get("_CFURLString", "")
    return ""


def format_persistent_apps(items: list) -> list[str]:
    """persistent-apps の各 tile を 'Label (bundle-id)' 形式のチェックリストに変換。"""
    lines: list[str] = []
    for item in items:
        td = item.get("tile-data", {}) if isinstance(item, dict) else {}
        label = td.get("file-label", "")
        bundle_id = td.get("bundle-identifier", "")
        url = _url_from_file_data(td)

        # 表示ラベルが空の場合は URL から推測
        if not label and url:
            label = url.rstrip("/").rsplit("/", 1)[-1].replace("%20", " ")

        if bundle_id:
            lines.append(
                f"- [ ] {label} ({bundle_id})  <!-- nix化 / 無視 / 検討 -->"
            )
        elif label:
            lines.append(f"- [ ] {label}  <!-- nix化 / 無視 / 検討 -->")
    return lines


def format_persistent_others(items: list) -> list[str]:
    """persistent-others の各 tile をフォルダサマリのチェックリストに変換。"""
    lines: list[str] = []
    for item in items:
        td = item.get("tile-data", {}) if isinstance(item, dict) else {}
        label = td.get("file-label", "")
        url = _url_from_file_data(td)
        arrangement = td.get("arrangement", "?")
        showas = td.get("showas", "?")

        path = url.replace("file://", "").rstrip("/") if url else label
        lines.append(
            f"- [ ] {label} (folder: {path}, arrangement={arrangement}, showas={showas})"
            f"  <!-- nix化 / 無視 / 検討 -->"
        )
    return lines


# ----------------------------------------------------------------
# メイン処理
# ----------------------------------------------------------------

def _val_repr(v: object) -> str:
    """値を triage 表示用の文字列に変換。"""
    if isinstance(v, bool):
        return str(v)
    if isinstance(v, float):
        # 浮動小数は有効桁数を絞って表示
        return f"{v:.4g}"
    return repr(v)


def process_domain(domain: str) -> None:
    """指定ドメインを defaults export → plistlib で解析して stdout に出力。"""
    result = subprocess.run(
        ["defaults", "export", domain, "-"],
        capture_output=True,
    )
    if result.returncode != 0:
        print(f"<!-- {domain}: ドメインが存在しないためスキップ -->")
        return

    try:
        plist = plistlib.loads(result.stdout)
    except Exception as exc:
        print(f"<!-- {domain}: plist 解析エラー — {exc} -->")
        return

    print(f"### {domain}")
    print()

    # persistent-apps / persistent-others は特殊処理
    if domain == "com.apple.dock":
        # スカラー key を先に出力
        for k, v in sorted(plist.items()):
            if not isinstance(v, (str, int, float, bool)):
                continue
            if is_noise(k):
                continue
            print(f"- [ ] {k} = {_val_repr(v)}  <!-- nix化 / 無視 / 検討 -->")

        # persistent-apps
        apps = plist.get("persistent-apps", [])
        if apps:
            print()
            for line in format_persistent_apps(apps):
                print(line)

        # persistent-others
        others = plist.get("persistent-others", [])
        if others:
            print()
            for line in format_persistent_others(others):
                print(line)

        # recent-apps はノイズのためスキップ
    else:
        # 通常ドメイン: スカラーのみチェックリスト化、複合型はスキップ (行数節約)
        has_output = False
        for k, v in sorted(plist.items()):
            if is_noise(k):
                continue
            if isinstance(v, (str, int, float, bool)):
                print(f"- [ ] {k} = {_val_repr(v)}  <!-- nix化 / 無視 / 検討 -->")
                has_output = True
            # bytes / list / dict は triage 不要のためサマリも省略
        if not has_output:
            print("<!-- triage 対象の scalar key がありません -->")

    print()


def main() -> None:
    domains = sys.argv[1:]
    if not domains:
        print("Usage: plist_extract.py <domain> [<domain> ...]", file=sys.stderr)
        sys.exit(1)

    for domain in domains:
        process_domain(domain)


if __name__ == "__main__":
    main()
