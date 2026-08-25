#!/usr/bin/env bats
# nix/tests/mas-guard.bats
#
# 生成 Brewfile の MAS 導入ガード (nix/modules/darwin/mas-guard.rb) の契約テスト。
# 実 Brewfile と同じく「prelude (homebrew.nix が生成) + mas-guard.rb」を 1 つの
# 文字列として instance_eval し、mas 呼び出しを記録するスタブで検証する。

NIX_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
GUARD_RB="${NIX_DIR}/modules/darwin/mas-guard.rb"

setup() {
    if ! command -v ruby > /dev/null 2>&1; then
        skip "ruby not available"
    fi

    APPS_A="${BATS_TEST_TMPDIR}/Applications"
    APPS_B="${BATS_TEST_TMPDIR}/home/Applications"
    mkdir -p "${APPS_A}" "${APPS_B}"

    # Brewfile DSL の代わりに mas 呼び出しを記録するドライバ。
    # 実装は method_missing 経由で mas を受けるため、キーワード引数で受け取る。
    cat > "${BATS_TEST_TMPDIR}/driver.rb" <<'RUBY'
calls = []
dsl = Object.new
dsl.define_singleton_method(:mas) do |name, **options|
  calls << [name, options[:id]]
end
source = ARGV.map { |path| File.read(path) }.join("\n")
dsl.instance_eval(source, "Brewfile")
calls.each { |name, id| puts "#{name}\t#{id}" }
RUBY
}

# 与えた bundle ID を持つダミー .app を作る (plutil が読める XML plist)。
make_app() {
    local app_path="$1" bundle_id="$2"
    mkdir -p "${app_path}/Contents"
    cat > "${app_path}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>${bundle_id}</string>
</dict>
</plist>
PLIST
}

# homebrew.nix が生成する prelude 相当 (走査対象はサンドボックスに差し替える)。
write_prelude() {
    cat > "${BATS_TEST_TMPDIR}/prelude.rb" <<PRELUDE
mas_apps = $1
mas_app_dirs = ["${APPS_A}", "${APPS_B}"]
PRELUDE
}

run_guard() {
    run ruby "${BATS_TEST_TMPDIR}/driver.rb" "${BATS_TEST_TMPDIR}/prelude.rb" "${GUARD_RB}"
}

@test "ruby syntax check passes" {
    run ruby -c "${GUARD_RB}"
    [ "${status}" -eq 0 ]
}

@test "skips mas when the bundle ID is already present in /Applications" {
    make_app "${APPS_A}/TestFlight.app" "com.apple.TestFlight"
    write_prelude '[["TestFlight",899247664,"com.apple.TestFlight"]]'
    run_guard
    [ "${status}" -eq 0 ]
    [ "${output}" = "" ]
}

@test "skips mas when the bundle ID is present in the user Applications directory" {
    make_app "${APPS_B}/TestFlight.app" "com.apple.TestFlight"
    write_prelude '[["TestFlight",899247664,"com.apple.TestFlight"]]'
    run_guard
    [ "${status}" -eq 0 ]
    [ "${output}" = "" ]
}

@test "skips mas when the app sits one directory below (e.g. Utilities)" {
    make_app "${APPS_A}/Utilities/Transporter.app" "com.apple.TransporterApp"
    write_prelude '[["Transporter",1450874784,"com.apple.TransporterApp"]]'
    run_guard
    [ "${status}" -eq 0 ]
    [ "${output}" = "" ]
}

@test "installs via mas when the bundle ID is absent" {
    make_app "${APPS_A}/Something Else.app" "com.example.other"
    write_prelude '[["TestFlight",899247664,"com.apple.TestFlight"]]'
    run_guard
    [ "${status}" -eq 0 ]
    [ "${output}" = "$(printf 'TestFlight\t899247664')" ]
}

@test "matches on bundle ID, not on the app file name" {
    make_app "${APPS_A}/RunCatNeo.app" "com.kyome.Neo.RunCat"
    write_prelude '[["RunCat Neo",6757801838,"com.kyome.Neo.RunCat"],["Magnet",441258766,"com.crowdcafe.windowmagnet"]]'
    run_guard
    [ "${status}" -eq 0 ]
    [ "${output}" = "$(printf 'Magnet\t441258766')" ]
}

@test "handles names with spaces and quotes without breaking the Brewfile" {
    write_prelude '[["Weird \"App\" Name",1234567890,"com.example.weird"]]'
    run_guard
    [ "${status}" -eq 0 ]
    [ "${output}" = "$(printf 'Weird "App" Name\t1234567890')" ]
}

@test "tolerates a missing Applications directory" {
    rmdir "${APPS_B}"
    write_prelude '[["Magnet",441258766,"com.crowdcafe.windowmagnet"]]'
    run_guard
    [ "${status}" -eq 0 ]
    [ "${output}" = "$(printf 'Magnet\t441258766')" ]
}

@test "ignores a bundle without Info.plist" {
    mkdir -p "${APPS_A}/Broken.app/Contents"
    write_prelude '[["Magnet",441258766,"com.crowdcafe.windowmagnet"]]'
    run_guard
    [ "${status}" -eq 0 ]
    [ "${output}" = "$(printf 'Magnet\t441258766')" ]
}

@test "generated Brewfile carries the declared entries and no unconditional mas line" {
    if ! command -v nix > /dev/null 2>&1; then
        skip "nix not available"
    fi

    run env USER=ciuser nix --extra-experimental-features 'nix-command flakes' \
        eval --impure --raw \
        "${NIX_DIR}#darwinConfigurations.default.config.homebrew.brewfile"
    [ "${status}" -eq 0 ]
    local brewfile="${output}"

    # 両 role 共通の app は role に関係なく載る (default-only は /etc/dotfiles-role 依存)。
    [[ "${brewfile}" == *'["Magnet",441258766,"com.crowdcafe.windowmagnet"]'* ]]
    [[ "${brewfile}" == *'["RunCat Neo",6757801838,"com.kyome.Neo.RunCat"]'* ]]
    # 無条件の mas 行 (行頭 mas ") が出ていないこと。
    run grep -c '^mas "' <<< "${brewfile}"
    [ "${status}" -ne 0 ]
}
