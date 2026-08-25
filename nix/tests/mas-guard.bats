#!/usr/bin/env bats
# nix/tests/mas-guard.bats
#
# 生成 Brewfile の MAS install スキップ判定 (nix/modules/darwin/mas-guard.rb) の契約テスト。
# 実 Brewfile と同じ並び (nix-darwin が出す mas 行 → homebrew.nix が出す prelude →
# mas-guard.rb) を 1 つの文字列として instance_eval し、DSL に渡った mas エントリと
# 組み上がった HOMEBREW_BUNDLE_MAS_SKIP を検証する。

NIX_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
GUARD_RB="${NIX_DIR}/modules/darwin/mas-guard.rb"

setup() {
    if ! command -v ruby > /dev/null 2>&1; then
        skip "ruby not available"
    fi

    APPS_A="${BATS_TEST_TMPDIR}/Applications"
    APPS_B="${BATS_TEST_TMPDIR}/home/Applications"
    mkdir -p "${APPS_A}" "${APPS_B}"

    # Brewfile DSL の代わりに mas エントリを記録するドライバ。
    # 実装は method_missing 経由で mas を受けるため、キーワード引数で受け取る。
    cat > "${BATS_TEST_TMPDIR}/driver.rb" <<'RUBY'
calls = []
dsl = Object.new
dsl.define_singleton_method(:mas) do |name, **options|
  calls << [name, options[:id]]
end
source = ARGV.map { |path| File.read(path) }.join("\n")
dsl.instance_eval(source, "Brewfile")
calls.each { |name, id| puts "mas\t#{name}\t#{id}" }
puts "skip\t#{ENV.fetch("HOMEBREW_BUNDLE_MAS_SKIP", "")}"
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

# 実 Brewfile 相当を組み立てる。引数は mas_apps の Ruby リテラル。
# 前半は nix-darwin の masApps が出す mas 行、後半は homebrew.nix が出す prelude。
write_brewfile() {
    local literal="$1"
    ruby -e 'eval(ARGV[0]).each { |name, id, _| puts format("mas %p, id: %d", name, id) }' \
        "${literal}" > "${BATS_TEST_TMPDIR}/brewfile.rb"
    cat >> "${BATS_TEST_TMPDIR}/brewfile.rb" <<PRELUDE
mas_apps = ${literal}
mas_app_dirs = ["${APPS_A}", "${APPS_B}"]
PRELUDE
}

run_guard() {
    run ruby "${BATS_TEST_TMPDIR}/driver.rb" "${BATS_TEST_TMPDIR}/brewfile.rb" "${GUARD_RB}"
}

# DSL に渡った mas エントリ (name / id)。
assert_mas_entry() {
    printf '%s\n' "${output}" | grep -qxF "$(printf 'mas\t%s\t%s' "$1" "$2")"
}

# 組み上がった HOMEBREW_BUNDLE_MAS_SKIP の全文 (空なら空文字)。
assert_skip_list() {
    local actual
    actual="$(printf '%s\n' "${output}" | grep '^skip' | cut -f2-)"
    [ "${actual}" = "$1" ]
}

@test "ruby syntax check passes" {
    run ruby -c "${GUARD_RB}"
    [ "${status}" -eq 0 ]
}

@test "keeps every declared mas entry in the DSL even when already installed" {
    make_app "${APPS_A}/TestFlight.app" "com.apple.TestFlight"
    write_brewfile '[["TestFlight",899247664,"com.apple.TestFlight"],["Magnet",441258766,"com.crowdcafe.windowmagnet"]]'
    run_guard
    [ "${status}" -eq 0 ]
    assert_mas_entry "TestFlight" 899247664
    assert_mas_entry "Magnet" 441258766
}

@test "skips only the App Store ID whose bundle ID was detected" {
    make_app "${APPS_A}/TestFlight.app" "com.apple.TestFlight"
    write_brewfile '[["TestFlight",899247664,"com.apple.TestFlight"],["Magnet",441258766,"com.crowdcafe.windowmagnet"]]'
    run_guard
    [ "${status}" -eq 0 ]
    # 検出したのは TestFlight だけ。未導入の Magnet の ID は skip に載らない。
    assert_skip_list "899247664"
}

@test "leaves the skip list empty when no bundle ID is present" {
    make_app "${APPS_A}/Something Else.app" "com.example.other"
    write_brewfile '[["TestFlight",899247664,"com.apple.TestFlight"]]'
    run_guard
    [ "${status}" -eq 0 ]
    assert_mas_entry "TestFlight" 899247664
    assert_skip_list ""
}

@test "detects an app in the user Applications directory" {
    make_app "${APPS_B}/TestFlight.app" "com.apple.TestFlight"
    write_brewfile '[["TestFlight",899247664,"com.apple.TestFlight"]]'
    run_guard
    [ "${status}" -eq 0 ]
    assert_skip_list "899247664"
}

@test "detects an app one directory below (e.g. Utilities)" {
    make_app "${APPS_A}/Utilities/Transporter.app" "com.apple.TransporterApp"
    write_brewfile '[["Transporter",1450874784,"com.apple.TransporterApp"]]'
    run_guard
    [ "${status}" -eq 0 ]
    assert_skip_list "1450874784"
}

@test "matches on bundle ID, not on the app file name" {
    make_app "${APPS_A}/RunCatNeo.app" "com.kyome.Neo.RunCat"
    write_brewfile '[["RunCat Neo",6757801838,"com.kyome.Neo.RunCat"],["Magnet",441258766,"com.crowdcafe.windowmagnet"]]'
    run_guard
    [ "${status}" -eq 0 ]
    assert_mas_entry "RunCat Neo" 6757801838
    assert_mas_entry "Magnet" 441258766
    # ファイル名は RunCatNeo.app だが bundle ID で一致する。Magnet は不在。
    assert_skip_list "6757801838"
}

@test "handles names with spaces and quotes without breaking the Brewfile" {
    make_app "${APPS_A}/Weird.app" "com.example.weird"
    write_brewfile '[["Weird \"App\" Name",1234567890,"com.example.weird"]]'
    run_guard
    [ "${status}" -eq 0 ]
    assert_mas_entry 'Weird "App" Name' 1234567890
    assert_skip_list "1234567890"
}

@test "keeps an already exported skip list" {
    make_app "${APPS_A}/TestFlight.app" "com.apple.TestFlight"
    write_brewfile '[["TestFlight",899247664,"com.apple.TestFlight"]]'
    HOMEBREW_BUNDLE_MAS_SKIP="123456789" run_guard
    [ "${status}" -eq 0 ]
    assert_skip_list "123456789 899247664"
}

@test "tolerates a missing Applications directory" {
    rmdir "${APPS_B}"
    write_brewfile '[["Magnet",441258766,"com.crowdcafe.windowmagnet"]]'
    run_guard
    [ "${status}" -eq 0 ]
    assert_mas_entry "Magnet" 441258766
    assert_skip_list ""
}

@test "ignores a bundle without Info.plist" {
    mkdir -p "${APPS_A}/Broken.app/Contents"
    write_brewfile '[["Magnet",441258766,"com.crowdcafe.windowmagnet"]]'
    run_guard
    [ "${status}" -eq 0 ]
    assert_mas_entry "Magnet" 441258766
    assert_skip_list ""
}

@test "generated Brewfile keeps a mas line for every declared app" {
    if ! command -v nix > /dev/null 2>&1; then
        skip "nix not available"
    fi

    run env USER=ciuser nix --extra-experimental-features 'nix-command flakes' \
        eval --impure --raw \
        "${NIX_DIR}#darwinConfigurations.default.config.homebrew.brewfile"
    [ "${status}" -eq 0 ]
    local brewfile="${output}"

    # 両 role 共通の app は role に関係なく載る (default-only は /etc/dotfiles-role 依存)。
    [[ "${brewfile}" == *'mas "Magnet", id: 441258766'* ]]
    [[ "${brewfile}" == *'mas "RunCat Neo", id: 6757801838'* ]]
    [[ "${brewfile}" == *'["Magnet",441258766,"com.crowdcafe.windowmagnet"]'* ]]
    [[ "${brewfile}" == *'["RunCat Neo",6757801838,"com.kyome.Neo.RunCat"]'* ]]
    [[ "${brewfile}" == *'HOMEBREW_BUNDLE_MAS_SKIP'* ]]

    # 宣言数と mas 行の本数が一致すること (行が落ちると cleanup の uninstall 候補になる)。
    local mas_lines declared
    mas_lines="$(grep -c '^mas "' <<< "${brewfile}")"
    declared="$(grep -m1 '^mas_apps = ' <<< "${brewfile}" | sed 's/^mas_apps = //' \
        | ruby -e 'puts eval(STDIN.read).length')"
    [ "${mas_lines}" -eq "${declared}" ]
}

@test "toRubyLiteral emits a Ruby literal that neither interpolates nor evaluates" {
    if ! command -v nix > /dev/null 2>&1; then
        skip "nix not available"
    fi

    cat > "${BATS_TEST_TMPDIR}/expr.nix" <<NIXEXPR
import ${NIX_DIR}/lib/to-ruby-literal.nix [
  "plain"
  "with space"
  ''He said "hi"''
  "#{1 + 1}"
  "#{Kernel.exit 99}"
  "back\\\\slash"
  "日本語 アプリ"
  [ "nested" 12345 ]
]
NIXEXPR

    run nix --extra-experimental-features 'nix-command flakes' eval --raw \
        --file "${BATS_TEST_TMPDIR}/expr.nix"
    [ "${status}" -eq 0 ]
    printf '%s' "${output}" > "${BATS_TEST_TMPDIR}/literal.rb"

    # "#" は必ず escape されている (escape 漏れは式展開になる)。
    [[ "${output}" == *'\#{1 + 1}'* ]]
    [[ "${output}" != *'"#{'* ]]

    cat > "${BATS_TEST_TMPDIR}/verify.rb" <<'RUBY'
# 式展開が起きていれば Kernel.exit 99 が走り、この eval は戻ってこない。
values = eval(File.read(ARGV[0]))
expected = [
  "plain",
  "with space",
  'He said "hi"',
  '#{1 + 1}',
  '#{Kernel.exit 99}',
  'back\slash',
  "日本語 アプリ",
  ["nested", 12345]
]
if values != expected
  warn "mismatch: #{values.inspect}"
  exit 1
end
RUBY

    run ruby "${BATS_TEST_TMPDIR}/verify.rb" "${BATS_TEST_TMPDIR}/literal.rb"
    [ "${status}" -eq 0 ]
}
