#!/usr/bin/env bats
# setup/tests/claude-settings.bats
#
# claude/settings.json は Claude Code のハーネス設定 SSOT。ここで検証するのは
# 「事故防止のレールが宣言から落ちていないこと」であって、境界の強度ではない
# （deny は文字列マッチであり、境界ではない。docs 3 章を参照）。

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
SETTINGS="${REPO_ROOT}/claude/settings.json"

@test "settings.json is valid JSON" {
    run jq -e . "${SETTINGS}"
    [ "${status}" -eq 0 ]
}

@test "secret-handling commands stay on the deny list" {
    for rule in 'Bash(op *)' 'Bash(sops *)' 'Bash(security find-generic-password *)'; do
        run jq -e --arg r "${rule}" '.permissions.deny | index($r)' "${SETTINGS}"
        [ "${status}" -eq 0 ]
    done
}

# opsa-infra は wrapper 名が op / security と別なので、deny の文字列マッチに掛からない。
# Claude Code の deny は Bash ツールに渡すコマンド文字列を見るだけで、スクリプトが内部で
# 起動する子プロセス（この wrapper が呼ぶ security / op）までは辿らない。
@test "no deny rule matches the opsa-infra entry point" {
    # `Bash(op *)` は「op<空白>」で始まるコマンドに掛かる glob なので、末尾の `*` だけを
    # 落として空白を残した接頭辞で判定する（空白まで落とすと opsa-infra が op に誤ヒットする）。
    run jq -e '[.permissions.deny[] | select(startswith("Bash("))]
               | map(sub("^Bash\\("; "") | sub("\\)$"; "") | sub("\\*$"; ""))
               | map(select(. as $p | "opsa-infra run -- terraform plan" | startswith($p)))
               | length == 0' "${SETTINGS}"
    [ "${status}" -eq 0 ]
}

# RTK の Bash hook は追跡済みのこのファイルに直接宣言する（`rtk init -g` を実機で走らせると
# Tier 1 の symlink 越しにリポジトリ側を書き換えてしまう）。ここで守りたいのは 2 点だけ:
# 宣言が落ちていないことと、破壊的コマンドブロックより後ろに居ること。
@test "the RTK Bash hook stays declared, after the destructive-command guard" {
    run jq -e '
        [.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].command]
        | (map(test("destructive-command-guard")) | index(true)) as $guard
        | (map(test("rtk hook claude")) | index(true)) as $rtk
        | $guard != null and $rtk != null and $guard < $rtk
    ' "${SETTINGS}"
    [ "${status}" -eq 0 ]
}

# rtk 不在の PC（新規 Mac の Tier 1 直後、darwin-rebuild switch 前）でも Bash が通らないと
# 環境構築が進まない。hook 自身が素通りする作りであることを宣言側で固定する。
@test "the RTK Bash hook fails open when rtk is not installed" {
    run jq -e '
        [.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].command]
        | map(select(test("rtk hook claude")))
        | all(test("command -v rtk"))
    ' "${SETTINGS}"
    [ "${status}" -eq 0 ]
}

# Context Mode は claude-plugins-official 外なので、marketplace の宣言が無いと
# setup/claude-sync.zsh の `claude plugin install` が解決先を持たない。
@test "context-mode is enabled together with the marketplace it resolves through" {
    run jq -e '.enabledPlugins["context-mode@context-mode"] == true
               and .extraKnownMarketplaces["context-mode"].source.repo == "mksglu/context-mode"' "${SETTINGS}"
    [ "${status}" -eq 0 ]
}

# enabledPlugins の <plugin>@<marketplace> は、その marketplace が宣言されて初めて解決できる。
# context-mode 追加で踏みかけた穴なので、宣言全体に対する不変条件として残す。
@test "every enabled plugin resolves to a declared marketplace" {
    run jq -e '(.extraKnownMarketplaces | keys) as $known
               | .enabledPlugins | keys
               | map(split("@")[1])
               | all(. as $m | $known | index($m) != null)' "${SETTINGS}"
    [ "${status}" -eq 0 ]
}
