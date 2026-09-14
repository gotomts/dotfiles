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
