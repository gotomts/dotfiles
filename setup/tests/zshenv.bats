#!/usr/bin/env bats
# setup/tests/zshenv.bats

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"

@test "zsh -n syntax check passes for zshenv" {
    run zsh -n "${REPO_ROOT}/zshenv"
    [ "${status}" -eq 0 ]
}

@test "zshenv exports COREPACK_HOME" {
    run grep -c 'COREPACK_HOME' "${REPO_ROOT}/zshenv"
    [ "${status}" -eq 0 ]
}

@test "zshenv guards mise shims activation" {
    run grep -c 'mise activate --shims' "${REPO_ROOT}/zshenv"
    [ "${status}" -eq 0 ]
}

@test "zshenv appends \${HOME}/.local/bin to PATH exactly once" {
    # Homebrew 管理外の CLI (setup/notion.zsh が入れる ntn 等) の解決を、たまたま
    # PATH に載っている偶然に依存させない。append なのは、prepend にすると
    # Homebrew/mise が供給する同名コマンドを横取りして既存の解決順を変えるため。
    run grep -cF 'export PATH="${PATH}:${HOME}/.local/bin"' "${REPO_ROOT}/zshenv"
    [ "${status}" -eq 0 ]
    [ "${output}" -eq 1 ]
    # prepend 形が混ざっていないこと
    run grep -cF 'export PATH="${HOME}/.local/bin:${PATH}"' "${REPO_ROOT}/zshenv"
    [ "${status}" -eq 1 ]
}
