#!/bin/zsh
# scripts/jev-ultrafast.zsh
#
# Claude Code と Hermes が共有する Jev Ultrafast の CLI（Tier 1 の setup/link.zsh が
# ${HOME}/.local/bin/jev-ultrafast へ symlink する。${HOME}/.local/bin は zshenv が PATH に
# 載せる）。本体は setup/jev-ultrafast.zsh が uv tool として入れた upstream の library で、
# ここはそれを専用ブラウザに繋いで呼ぶだけの薄い入口。
#
# upstream の `jev` 実行ファイルはデモ用の inspector（ローカル Web UI）なので agent からは
# 使わず、upstream の examples/run.py と同じ呼び方（Agent(url, goals)）をこの CLI が持つ。
#
# 専用ブラウザの境界:
#   - Chrome は setup/lib/jev-ultrafast.zsh が宣言する専用 profile（--user-data-dir）と
#     専用 port でだけ起動する。remote debugging を有効にするのはこの profile だけ
#   - port を listen しているプロセスのコマンドラインがこの profile を持っていなければ
#     接続しない（普段の Chrome などが同じ port に居ても拾わない）
#   - browser-harness には BU_CDP_URL でこの endpoint だけを渡す。BU_CDP_URL があると
#     browser-harness は普段の Chrome の profile 探索・起動・chrome://inspect を一切しない。
#     優先度が上の BU_CDP_WS・クラウド用の BU_BROWSER_ID は引き継がない
#   - BH_HOME を専用ディレクトリへ向け、既定の ~/.config/browser-harness（.env を読む
#     場所でもある）を使わせない。daemon 名（BU_NAME）も分け、他の daemon を再利用しない
#
# 秘密: TYPESAFE_API_KEY / TEXT_MODEL_API_KEY は環境変数として受け取るだけで、表示・保存・
# 引数化しない（有無だけを扱う）。注入は opsa-development 経由（docs/jev-development-control-plane.md
# の「秘密の注入」）。browser-harness の daemon は run の後も残る長寿命プロセスなので、
# key を落とした環境で先に起こしてから agent を走らせる。
#
# 使い方と終了コードは `jev-ultrafast --help`。使う条件・通常のブラウザ tool へ戻る条件・
# 安全境界は claude/jev-ultrafast.md（Claude Code と Hermes が同じファイルを読む）。

set -eu

DOTFILES_ROOT="${0:A:h:h}"
source "${DOTFILES_ROOT}/setup/lib/jev-ultrafast.zsh"

PYTHON_BIN="$(jev_ultrafast::python "${HOME}")"
PROFILE_DIR="$(jev_ultrafast::profile_dir "${HOME}")"
HARNESS_HOME="$(jev_ultrafast::harness_home "${HOME}")"
CDP_URL="$(jev_ultrafast::cdp_url)"
POLICY="${DOTFILES_ROOT}/claude/jev-ultrafast.md"
# 専用 Chrome が endpoint を開くまで待つ秒数
START_TIMEOUT="${JEV_ULTRAFAST_START_TIMEOUT:-20}"

# 文字入力用の small LLM の既定値。upstream の .env.example と同じ（upstream のコード側の
# 既定は別 provider を指しているため、key を意図しない endpoint へ送らないようここで揃える）。
# 環境変数で渡されていればそちらを使う。
DEFAULT_TEXT_MODEL_BASE_URL="https://openrouter.ai/api/v1"
DEFAULT_TEXT_MODEL="inception/mercury-2.5"
DEFAULT_TEXT_MODEL_REASONING="none"

# upstream の examples/run.py 相当。結果は agent が独立に検証できるよう最終 URL と可視テキストを返す。
JEV_RUNNER='
import argparse
import json
import sys

from jev_ultrafast import Agent

parser = argparse.ArgumentParser(prog="jev-ultrafast run")
parser.add_argument("--url", required=True)
parser.add_argument("--goal", action="append", required=True, help="Repeat for an ordered list of goals.")
args = parser.parse_args()

with Agent(args.url, args.goal) as agent:
    state = agent.snapshot()
    for state in agent.run():
        print("%5d ms  %d actions  %s" % (state["elapsed_ms"], len(state["history"]), state["status"]), file=sys.stderr, flush=True)
page = state["page"]
json.dump({"status": state["status"], "url": page.get("url"), "actions": len(state["history"]),
           "elapsed_ms": state["elapsed_ms"], "text": page.get("text")}, sys.stdout, ensure_ascii=False)
print()
sys.exit(0 if state["status"] == "done" else 3)
'

JEV_DAEMON='
from browser_harness.admin import ensure_daemon

ensure_daemon()
'

jev::err() {
    print -r -- "jev-ultrafast: ${1}" >&2
}

jev::usage() {
    cat <<EOF
使い方: jev-ultrafast <command> [args...]

  run --url <URL> --goal <goal> [--goal <goal>...]
            専用ブラウザで Jev Ultrafast の agent を 1 回走らせる。経過は stderr、結果
            （status / url / actions / elapsed_ms / text）は stdout に JSON 1 行で出す。
            終了コードは status が done なら 0、blocked なら 3、それ以外の失敗は非 0。
            done は成功の証拠ではない（結果の url / text で独立に確かめる）。
            TYPESAFE_API_KEY と TEXT_MODEL_API_KEY を環境変数で要求する（有料 API を呼ぶ）。
  browser   専用ブラウザを起動（起動済みなら再利用）して CDP endpoint を表示する
  doctor    revision・パス・専用ブラウザ・API key の有無（値は出さない）を確認する

専用ブラウザ: ${CDP_URL}（profile: ${PROFILE_DIR}）
使う条件・通常のブラウザ tool へ戻る条件・安全境界: ${POLICY}
EOF
}

# jev::browser_state  0: 専用 profile の Chrome が port を listen している / 1: 誰も listen
#   していない / 2: 専用 profile ではないプロセスが port を持っている
jev::browser_state() {
    local pids pid cmd
    pids="$(lsof -nP -iTCP:"${JEV_ULTRAFAST_CDP_PORT}" -sTCP:LISTEN -t 2>/dev/null)" || return 1
    [[ -n "${pids}" ]] || return 1
    for pid in ${(f)pids}; do
        cmd="$(ps -o command= -p "${pid}" 2>/dev/null)" || return 2
        # 前後に空白を足して完全一致させる（profile-other のような接頭辞一致を所有とみなさない）
        [[ " ${cmd} " == *" --user-data-dir=${PROFILE_DIR} "* ]] || return 2
    done
    return 0
}

jev::ensure_browser() {
    local state=0 i
    jev::browser_state || state=$?
    case "${state}" in
        0) return 0 ;;
        2)
            jev::err "port ${JEV_ULTRAFAST_CDP_PORT} を専用 profile 以外のプロセスが使っています。接続しません"
            return 1
            ;;
    esac

    mkdir -p "${PROFILE_DIR}"
    chmod 700 "${PROFILE_DIR}"
    open -na "${JEV_ULTRAFAST_CHROME_APP}" --args \
        "--user-data-dir=${PROFILE_DIR}" \
        "--remote-debugging-port=${JEV_ULTRAFAST_CDP_PORT}" \
        --no-first-run --no-default-browser-check about:blank

    for (( i = 0; i < START_TIMEOUT * 4; i++ )); do
        state=0
        jev::browser_state || state=$?
        if (( state == 2 )); then
            jev::err "port ${JEV_ULTRAFAST_CDP_PORT} を専用 profile 以外のプロセスが使っています。接続しません"
            return 1
        fi
        if (( state == 0 )) && curl -fsS --max-time 1 "${CDP_URL}/json/version" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.25
    done
    jev::err "専用ブラウザが ${CDP_URL} で応答しません（${START_TIMEOUT} 秒）。専用 profile の Chrome が remote debugging 無しで開いているなら閉じてから再実行してください"
    return 1
}

jev::require_installed() {
    [[ -x "${PYTHON_BIN}" ]] && return 0
    jev::err "未導入です。zsh ${DOTFILES_ROOT}/setup/jev-ultrafast.zsh を実行してください"
    return 1
}

jev::export_harness_env() {
    unset BU_CDP_WS BU_BROWSER_ID BH_CONFIG_DIR BH_RUNTIME_DIR BH_TMP_DIR BH_AGENT_WORKSPACE BROWSER_HARNESS_HOME
    mkdir -p "${HARNESS_HOME}"
    chmod 700 "${HARNESS_HOME}"
    export BU_CDP_URL="${CDP_URL}"
    export BU_NAME="${JEV_ULTRAFAST_DAEMON_NAME}"
    export BH_HOME="${HARNESS_HOME}"
    # telemetry と PyPI への更新確認を止める（版は宣言側で固定している）
    export BH_TELEMETRY=0
    export BH_UPDATE_CHECK=0
}

# jev::python_without_keys <args>...  API key を落とした環境で venv の python を走らせる
jev::python_without_keys() {
    env -u TYPESAFE_API_KEY -u TEXT_MODEL_API_KEY "${PYTHON_BIN}" -I "$@"
}

jev::run() {
    local name
    for name in TYPESAFE_API_KEY TEXT_MODEL_API_KEY; do
        if [[ -z "${(P)name:-}" ]]; then
            jev::err "${name} が環境にありません（opsa-development run -- jev-ultrafast run ... で注入してください）"
            return 1
        fi
    done
    jev::require_installed || return 1
    jev::ensure_browser || return 1
    jev::export_harness_env

    if ! jev::python_without_keys -c "${JEV_DAEMON}"; then
        jev::err "browser-harness の daemon を ${CDP_URL} へ接続できませんでした"
        return 1
    fi

    export TEXT_MODEL_BASE_URL="${TEXT_MODEL_BASE_URL:-${DEFAULT_TEXT_MODEL_BASE_URL}}"
    export TEXT_MODEL="${TEXT_MODEL:-${DEFAULT_TEXT_MODEL}}"
    export TEXT_MODEL_REASONING="${TEXT_MODEL_REASONING:-${DEFAULT_TEXT_MODEL_REASONING}}"
    # -I: cwd や PYTHON* 環境変数から module を拾わない
    exec "${PYTHON_BIN}" -I -c "${JEV_RUNNER}" "$@"
}

jev::doctor() {
    local result=0 installed state=0 name
    installed="$(jev_ultrafast::installed_rev "${HOME}")"
    print -r -- "upstream: ${JEV_ULTRAFAST_REPO_URL}"
    print -r -- "revision (宣言): ${JEV_ULTRAFAST_REV}"
    print -r -- "revision (導入): ${installed:-未導入}"
    [[ "${installed}" == "${JEV_ULTRAFAST_REV}" ]] || result=1
    print -r -- "python: ${PYTHON_BIN}"
    print -r -- "profile: ${PROFILE_DIR}"
    print -r -- "browser-harness home: ${HARNESS_HOME}"

    jev::browser_state || state=$?
    case "${state}" in
        0) print -r -- "専用ブラウザ: 起動中 (${CDP_URL})" ;;
        1) print -r -- "専用ブラウザ: 停止中 (${CDP_URL}。run / browser で起動する)" ;;
        *) print -r -- "専用ブラウザ: port 競合 (${CDP_URL} を専用 profile 以外が使用中)"; result=1 ;;
    esac

    for name in TYPESAFE_API_KEY TEXT_MODEL_API_KEY; do
        if [[ -n "${(P)name:-}" ]]; then
            print -r -- "${name}: set"
        else
            print -r -- "${name}: unset"
        fi
    done

    if [[ -x "${PYTHON_BIN}" ]]; then
        jev::export_harness_env
        if jev::python_without_keys -c "import jev_ultrafast"; then
            print -r -- "import jev_ultrafast: ok"
        else
            print -r -- "import jev_ultrafast: 失敗"
            result=1
        fi
    else
        print -r -- "import jev_ultrafast: 未導入"
        result=1
    fi
    return "${result}"
}

case "${1:-}" in
    run)
        shift
        jev::run "$@"
        ;;
    browser)
        jev::ensure_browser || exit 1
        print -r -- "${CDP_URL}"
        ;;
    doctor)
        jev::doctor
        ;;
    -h|--help|help)
        jev::usage
        ;;
    *)
        jev::usage >&2
        exit 2
        ;;
esac
