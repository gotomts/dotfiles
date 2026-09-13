#!/usr/bin/env bats
# setup/tests/opsa-infra.bats

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/opsa-infra.zsh"

# 実機の Keychain / op を巻き込まないよう、両方を stub に差し替えた PATH で走らせる。
# STUB_TOKEN は stub security が返す値、STUB_OUT は stub op が観測結果を書き出す先。
#
# stub op は token の値そのものを書かず、「期待値と一致したか」の真偽だけを書く。
# 検証物のために秘密値（の代役）をディスクへ落とさないため。
setup() {
    STUB_BIN="${BATS_TEST_TMPDIR}/bin"
    STUB_OUT="${BATS_TEST_TMPDIR}/op-observed"
    ENV_FILE="${BATS_TEST_TMPDIR}/infra.env"
    mkdir -p "${STUB_BIN}"

    cat > "${STUB_BIN}/security" <<'STUB'
#!/bin/sh
[ -n "${STUB_TOKEN}" ] || exit 1
printf '%s\n' "${STUB_TOKEN}"
STUB

    # 実物の `op run` と同じく、`--` の後ろのコマンドを自分の環境ごと exec する。
    # 子（terraform 相当）と孫への環境継承をここで再現する。
    cat > "${STUB_BIN}/op" <<'STUB'
#!/bin/sh
{
  printf 'argv:%s\n' "$*"
  if [ "${OP_SERVICE_ACCOUNT_TOKEN}" = "${STUB_TOKEN}" ]; then
    printf 'token:match\n'
  else
    printf 'token:mismatch\n'
  fi
} > "${STUB_OUT}"
[ -z "${STUB_OP_EXIT}" ] || exit "${STUB_OP_EXIT}"
[ -z "${STUB_OP_EXEC_CHILD}" ] || { shift 3; exec "$@"; }
exit 0
STUB

    chmod +x "${STUB_BIN}/security" "${STUB_BIN}/op"

    export PATH="${STUB_BIN}:${PATH}"
    export STUB_TOKEN="stub-service-account-token"
    export STUB_OUT
    export OPSA_INFRA_ENV_FILE="${ENV_FILE}"

    write_env 'CLOUDFLARE_API_TOKEN=op://Claude Code Infrastructure - Kissa Soft/cf/credential'
}

# write_env <line>...  テンプレートを 0600 で書く（wrapper が権限を検証するため）
write_env() {
    printf '%s\n' "$@" > "${ENV_FILE}"
    chmod 600 "${ENV_FILE}"
}

@test "zsh -n syntax check passes" {
    run zsh -n "${SCRIPT}"
    [ "${status}" -eq 0 ]
}

@test "run injects the Keychain token into the child process only" {
    run zsh "${SCRIPT}" run -- terraform plan
    [ "${status}" -eq 0 ]

    run cat "${STUB_OUT}"
    [[ "${output}" == *"argv:run --env-file ${ENV_FILE} -- terraform plan"* ]]
    [[ "${output}" == *"token:match"* ]]
}

@test "run never prints the token on stdout or stderr" {
    run zsh "${SCRIPT}" run -- terraform plan
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"stub-service-account-token"* ]]
}

@test "the token is not left in the calling shell's environment" {
    run zsh -c "zsh '${SCRIPT}' run -- terraform plan >/dev/null; printenv OP_SERVICE_ACCOUNT_TOKEN; echo rc=\$?"
    [[ "${output}" == *"rc=1"* ]]
    [[ "${output}" != *"stub-service-account-token"* ]]
}

# W1: op が起動したコマンドとその子孫は token を継承し得る。標準経路の残余リスクとして
# 明文化しているので、テストでもその事実を固定する（値は書き出さず有無だけを見る）。
@test "a grandchild of op inherits the service account token (documented residual risk)" {
    local probe="${BATS_TEST_TMPDIR}/probe.sh"
    cat > "${probe}" <<'PROBE'
#!/bin/sh
# 孫プロセスから見た継承の有無だけを記録する。値は書かない。
sh -c 'if [ -n "${OP_SERVICE_ACCOUNT_TOKEN}" ]; then echo inherited=yes; else echo inherited=no; fi' \
  > "${PROBE_OUT}"
PROBE
    chmod +x "${probe}"

    PROBE_OUT="${BATS_TEST_TMPDIR}/probe-out" \
    STUB_OP_EXEC_CHILD=1 \
        run zsh "${SCRIPT}" run -- "${probe}"
    [ "${status}" -eq 0 ]

    run cat "${BATS_TEST_TMPDIR}/probe-out"
    [ "${output}" = "inherited=yes" ]
}

@test "the child's exit code is passed through unchanged" {
    STUB_OP_EXIT=7 run zsh "${SCRIPT}" run -- terraform plan
    [ "${status}" -eq 7 ]
}

@test "run rejects op as the child command" {
    run zsh "${SCRIPT}" run -- op read "op://Claude Code Infrastructure - Kissa Soft/cf/credential"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"op の直接実行"* ]]
    [ ! -f "${STUB_OUT}" ]
}

# R1: macOS の FS は既定で case-insensitive なので、大文字綴りも同じ実行体に解決される。
@test "run rejects op regardless of letter case" {
    for name in OP Op oP; do
        run zsh "${SCRIPT}" run -- "${name}" read "op://Claude Code Infrastructure - Kissa Soft/cf/credential"
        [ "${status}" -eq 1 ]
        [[ "${output}" == *"op の直接実行"* ]]
        [ ! -f "${STUB_OUT}" ]
    done
}

@test "run rejects op given by an absolute path" {
    run zsh "${SCRIPT}" run -- /usr/local/bin/OP read "op://Claude Code Infrastructure - Kissa Soft/cf/credential"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"op の直接実行"* ]]
    [ ! -f "${STUB_OUT}" ]
}

@test "subcommands other than run are rejected" {
    for sub in read item vault signin; do
        run zsh "${SCRIPT}" "${sub}" -- echo hi
        [ "${status}" -eq 1 ]
        [ ! -f "${STUB_OUT}" ]
    done
}

@test "missing -- separator is rejected" {
    run zsh "${SCRIPT}" run terraform plan
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"未知の引数"* ]]
    [ ! -f "${STUB_OUT}" ]
}

@test "empty command after -- is rejected" {
    run zsh "${SCRIPT}" run --
    [ "${status}" -eq 1 ]
    [ ! -f "${STUB_OUT}" ]
}

@test "a missing env-file fails closed" {
    run zsh "${SCRIPT}" run --env-file "${BATS_TEST_TMPDIR}/absent.env" -- terraform plan
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"env-file が無い"* ]]
    [ ! -f "${STUB_OUT}" ]
}

# W4: 参照だけのファイルでも「どの Vault のどの item か」は構成情報なので、
# owner 以外から読める配置のまま実行しない。
@test "a group/world readable env-file fails closed" {
    for mode in 644 640 604 660; do
        chmod "${mode}" "${ENV_FILE}"
        run zsh "${SCRIPT}" run -- terraform plan
        [ "${status}" -eq 1 ]
        [[ "${output}" == *"owner 以外にも読める"* ]]
        [ ! -f "${STUB_OUT}" ]
    done
}

@test "a 0400 env-file is accepted (0600 or tighter)" {
    chmod 400 "${ENV_FILE}"
    run zsh "${SCRIPT}" run -- terraform plan
    [ "${status}" -eq 0 ]
}

@test "an env-file holding a literal value is rejected" {
    write_env 'CLOUDFLARE_API_TOKEN=plaintext-secret'
    run zsh "${SCRIPT}" run -- terraform plan
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"op:// 参照以外"* ]]
    [ ! -f "${STUB_OUT}" ]
}

@test "a reference whose vault name contains spaces is accepted" {
    write_env 'CF=op://Claude Code Infrastructure - Kissa Soft/abc123/credential'
    run zsh "${SCRIPT}" run -- terraform plan
    [ "${status}" -eq 0 ]
}

@test "a double-quoted reference is accepted" {
    write_env 'CF="op://Claude Code Infrastructure - Kissa Soft/abc123/credential"'
    run zsh "${SCRIPT}" run -- terraform plan
    [ "${status}" -eq 0 ]
}

# Nit 2: 引用符なしの形は末尾ゴミを許さない（引用符ありは閉じ引用符が終端になる）。
@test "an unquoted reference with trailing garbage is rejected" {
    write_env 'CF=op://Claude Code Infrastructure - Kissa Soft/abc123/credential よけいな文字列'
    run zsh "${SCRIPT}" run -- terraform plan
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"op:// 参照以外"* ]]
    [ ! -f "${STUB_OUT}" ]
}

@test "a quoted reference with trailing garbage is rejected" {
    write_env 'CF="op://Claude Code Infrastructure - Kissa Soft/abc123/credential" junk'
    run zsh "${SCRIPT}" run -- terraform plan
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"op:// 参照以外"* ]]
    [ ! -f "${STUB_OUT}" ]
}

@test "a reference with an unbalanced quote is rejected" {
    write_env 'CF=op://Claude Code Infrastructure - Kissa Soft/abc123/credential"'
    run zsh "${SCRIPT}" run -- terraform plan
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"op:// 参照以外"* ]]
    [ ! -f "${STUB_OUT}" ]
}

@test "a reference missing the field segment is rejected" {
    write_env 'CF=op://Claude Code Infrastructure - Kissa Soft/abc123'
    run zsh "${SCRIPT}" run -- terraform plan
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"op:// 参照以外"* ]]
    [ ! -f "${STUB_OUT}" ]
}

@test "an env-file with no op:// reference is rejected" {
    write_env '# 参照だけを書く' ''
    run zsh "${SCRIPT}" run -- terraform plan
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"1 行も無い"* ]]
    [ ! -f "${STUB_OUT}" ]
}

@test "comments and blank lines in the env-file are tolerated" {
    write_env '# infra 用の参照だけ' '' 'CF=op://Claude Code Infrastructure - Kissa Soft/cf/credential'
    run zsh "${SCRIPT}" run -- terraform plan
    [ "${status}" -eq 0 ]
}

@test "a missing Keychain entry fails closed without running op" {
    export STUB_TOKEN=""
    run zsh "${SCRIPT}" run -- terraform plan
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"OP_SERVICE_ACCOUNT_TOKEN_INFRA"* ]]
    [ ! -f "${STUB_OUT}" ]
}

@test "--env-file overrides the default and is passed through to op" {
    local other="${BATS_TEST_TMPDIR}/other.env"
    printf 'CF=op://Claude Code Infrastructure - Kissa Soft/cf/credential\n' > "${other}"
    chmod 600 "${other}"
    run zsh "${SCRIPT}" run --env-file "${other}" -- terraform plan
    [ "${status}" -eq 0 ]
    run cat "${STUB_OUT}"
    [[ "${output}" == *"--env-file ${other}"* ]]
}

@test "OPSA_INFRA_ENV_FILE selects the template when --env-file is absent" {
    local other="${BATS_TEST_TMPDIR}/from-env.env"
    printf 'CF=op://Claude Code Infrastructure - Kissa Soft/cf/credential\n' > "${other}"
    chmod 600 "${other}"
    OPSA_INFRA_ENV_FILE="${other}" run zsh "${SCRIPT}" run -- terraform plan
    [ "${status}" -eq 0 ]
    run cat "${STUB_OUT}"
    [[ "${output}" == *"--env-file ${other}"* ]]
}

@test "help exits 0 and documents the single allowed path" {
    run zsh "${SCRIPT}" help
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"opsa-infra run"* ]]
}
