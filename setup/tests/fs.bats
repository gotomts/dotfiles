#!/usr/bin/env bats
# setup/tests/fs.bats

SETUP_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

_zsh_fs() {
    zsh -c "source '${SETUP_DIR}/lib/util.zsh'; source '${SETUP_DIR}/lib/fs.zsh'; ${1}"
}

setup() {
    TMP="${BATS_TEST_TMPDIR}"
    echo "source content" > "${TMP}/source.txt"
}

@test "zsh -n syntax check passes" {
    run zsh -n "${SETUP_DIR}/lib/fs.zsh"
    [ "${status}" -eq 0 ]
}

@test "fs::link_file creates a symlink to target" {
    run _zsh_fs "fs::link_file '${TMP}/source.txt' '${TMP}/home/.target'"
    [ "${status}" -eq 0 ]
    [ -L "${TMP}/home/.target" ]
    [ "$(readlink "${TMP}/home/.target")" = "${TMP}/source.txt" ]
}

@test "fs::link_file is idempotent on second run" {
    _zsh_fs "fs::link_file '${TMP}/source.txt' '${TMP}/home/.target'"
    run _zsh_fs "fs::link_file '${TMP}/source.txt' '${TMP}/home/.target'"
    [ "${status}" -eq 0 ]
    [ -L "${TMP}/home/.target" ]
}

@test "fs::link_file backs up an existing real file instead of clobbering it" {
    mkdir -p "${TMP}/home"
    echo "existing real content" > "${TMP}/home/.target"
    run _zsh_fs "fs::link_file '${TMP}/source.txt' '${TMP}/home/.target'"
    [ "${status}" -eq 0 ]
    [ -L "${TMP}/home/.target" ]
    [ -f "${TMP}/home/.target.before-setup" ]
    [ "$(cat "${TMP}/home/.target.before-setup")" = "existing real content" ]
}

@test "fs::link_file re-links when the existing symlink points elsewhere" {
    mkdir -p "${TMP}/home"
    echo "other content" > "${TMP}/other.txt"
    ln -s "${TMP}/other.txt" "${TMP}/home/.target"
    run _zsh_fs "fs::link_file '${TMP}/source.txt' '${TMP}/home/.target'"
    [ "${status}" -eq 0 ]
    [ "$(readlink "${TMP}/home/.target")" = "${TMP}/source.txt" ]
}

@test "fs::link_file fails clearly when target does not exist" {
    run _zsh_fs "fs::link_file '${TMP}/does-not-exist.txt' '${TMP}/home/.target'"
    [ "${status}" -eq 1 ]
    [ ! -e "${TMP}/home/.target" ]
}

@test "fs::ensure_realfile creates an empty real file when absent" {
    run _zsh_fs "fs::ensure_realfile '${TMP}/home/.gitconfig'"
    [ "${status}" -eq 0 ]
    [ -f "${TMP}/home/.gitconfig" ]
    [ ! -L "${TMP}/home/.gitconfig" ]
}

@test "fs::ensure_realfile does not overwrite an existing real file" {
    mkdir -p "${TMP}/home"
    echo "pc-local value" > "${TMP}/home/.gitconfig"
    run _zsh_fs "fs::ensure_realfile '${TMP}/home/.gitconfig'"
    [ "${status}" -eq 0 ]
    [ "$(cat "${TMP}/home/.gitconfig")" = "pc-local value" ]
}

@test "fs::ensure_realfile converts an existing symlink into a real file" {
    mkdir -p "${TMP}/home"
    ln -s "${TMP}/source.txt" "${TMP}/home/.gitconfig"
    run _zsh_fs "fs::ensure_realfile '${TMP}/home/.gitconfig'"
    [ "${status}" -eq 0 ]
    [ ! -L "${TMP}/home/.gitconfig" ]
    [ -f "${TMP}/home/.gitconfig" ]
}
