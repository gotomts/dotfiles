#!/usr/bin/env bats
# setup/tests/git-config.bats

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"

@test "config/git/config is valid git config syntax" {
    run git config --file "${REPO_ROOT}/config/git/config" --list
    [ "${status}" -eq 0 ]
}

@test "config/git/config sets user.email" {
    run git config --file "${REPO_ROOT}/config/git/config" user.email
    [ "${status}" -eq 0 ]
    [ "${output}" = "mh.goto.web@gmail.com" ]
}

@test "config/git/config sets commit.template to ~/.gitmessage" {
    run git config --file "${REPO_ROOT}/config/git/config" commit.template
    [ "${status}" -eq 0 ]
    [ "${output}" = "~/.gitmessage" ]
}

@test "config/git/ignore contains .serena/" {
    run grep -c '^\.serena/$' "${REPO_ROOT}/config/git/ignore"
    [ "${status}" -eq 0 ]
}
