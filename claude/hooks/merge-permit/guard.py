#!/usr/bin/env python3
"""merge-permit の PreToolUse hook 本体。

settings.json から `PreToolUse` (matcher: "Bash" および
"mcp__github__merge_pull_request") で呼ばれる。Claude Code は hook イベントの
JSON を stdin へ渡す契約 (tool_name / tool_input / cwd を含む) なので、それを
読んで merge アクションを検出し、有効な permit が無ければ block (exit 2) する。

exit code は AGENTS.md の規約どおり 0 (通過) か 2 (ブロック) のみを使う。
それ以外の非ゼロは Claude Code に non-blocking error として素通りされるため、
検出/解析に失敗した経路でも意図的に 2 を返す (fail-closed)。
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))

from lib import (  # noqa: E402
    MergeAttempt,
    Permit,
    PermitStore,
    detect_merge_actions,
    normalize_repo_identity_from_url,
    resolve_repo_identity,
)

BLOCK_MESSAGE_HEADER = "BLOCK: merge には有効な merge-permit が必要"


def _read_event(stdin_text: str, env: dict) -> dict:
    """stdin の hook イベント JSON を読む。空なら $CLAUDE_TOOL_INPUT 等の
    環境変数へフォールバックする (バージョン差異に対する保険)。"""
    text = (stdin_text or "").strip()
    if text:
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            pass

    # フォールバック: 既存の destructive-command hook と同じ環境変数を試す
    raw_input = env.get("CLAUDE_TOOL_INPUT", "")
    tool_name = env.get("CLAUDE_TOOL_NAME", "")
    if raw_input:
        try:
            tool_input = json.loads(raw_input)
        except json.JSONDecodeError:
            tool_input = {"command": raw_input}
        # cwd は $PWD のみを使う。このガード自身のプロセス cwd
        # (`os.getcwd()`) は tool 呼び出しの実行ディレクトリと無関係な値の
        # ことがあるため、フォールバックとして使わない (evaluate() 側で
        # $PWD も無ければ sentinel パスへ倒す)。
        return {"tool_name": tool_name, "tool_input": tool_input, "cwd": env.get("PWD")}

    return {}


class _Malformed(Exception):
    """event/tool_input を解析できなかったことを示す内部シグナル。

    このガードは PreToolUse の "Bash" と "mcp__github__merge_pull_request"
    matcher にしか配線されていない (settings.json)。つまり本スクリプトが
    呼ばれた時点で、実際の tool 呼び出しはこの 2 種類のどちらかのはずである。
    にもかかわらず event JSON が壊れている/tool_name や必須フィールドが
    欠けているために「Bash か mcp merge tool かすら判別できない」場合、
    "merge ではない" と解釈して通す (fail-open) のではなく、
    "merge かもしれないので止める" (fail-closed) を選ぶ (レビュー指摘 (1))。
    """


def _attempts_from_event(event: dict, cwd: str) -> list[MergeAttempt]:
    tool_name = event.get("tool_name")
    if not tool_name:
        # event 自体が空/壊れている (stdin 空・不正 JSON・env フォールバックも
        # 失敗)。tool_name を特定できない = fail-closed。
        raise _Malformed("tool_name を特定できない (event が空または不正)")

    if tool_name == "Bash":
        tool_input = event.get("tool_input")
        if not isinstance(tool_input, dict) or "command" not in tool_input:
            # tool_input が無い/dict でない/command キーが無い = 壊れている。
            # 空文字列の command (キーはあるが値が "") は正当な「何もしない
            # コマンド」として許容し、fail-closed の対象にはしない。
            raise _Malformed("Bash tool_input.command が欠けている")
        command = tool_input.get("command") or ""
        if not isinstance(command, str):
            raise _Malformed("Bash tool_input.command が文字列でない")
        if not command:
            return []
        return detect_merge_actions(command, cwd)

    if tool_name == "mcp__github__merge_pull_request":
        tool_input = event.get("tool_input")
        if not isinstance(tool_input, dict):
            raise _Malformed("mcp__github__merge_pull_request の tool_input が dict でない")
        owner = tool_input.get("owner")
        repo = tool_input.get("repo")
        pull_number = tool_input.get("pull_number")
        if not owner or not repo or pull_number is None:
            # 必須フィールドが欠けている = 想定外の呼び出し。fail-closed。
            raise _Malformed("mcp__github__merge_pull_request の owner/repo/pull_number が欠けている")
        return [
            MergeAttempt(
                action="gh-pr-merge",
                target=f"pr:{pull_number}",
                repo_hint=normalize_repo_identity_from_url(f"{owner}/{repo}"),
                snippet=f"mcp__github__merge_pull_request({owner}/{repo}#{pull_number})",
            )
        ]

    # matcher 上ここに来ることは通常無いが、来た場合は対象外の tool として
    # 素通りする (Bash でも mcp merge tool でもないと明確に判明しているため)。
    return []


def _resolve_repo_for_attempt(attempt: MergeAttempt, static_cwd: str) -> tuple[Optional[str], bool]:
    """(repo_identity または None, ambiguous_block_required) を返す。

    2 個目の要素が True の場合、repo を特定できても/できなくても
    fail-closed でブロックしなければならない (cwd が `cd` で曖昧になった
    ケース。レビュー指摘 (3))。
    """
    if attempt.repo_hint:
        return attempt.repo_hint, False
    if attempt.cwd_ambiguous:
        return None, True
    cwd = attempt.cwd_override or static_cwd
    repo = resolve_repo_identity(cwd)
    if repo:
        return repo, False
    # origin が無いローカル専用リポジトリ。realpath をフォールバック識別子にする。
    try:
        return "local:" + str(Path(cwd).resolve()), False
    except OSError:
        return None, False


def evaluate(event: dict, permit_store: PermitStore, env: Optional[dict] = None) -> tuple[int, str]:
    """(exit_code, message) を返す。message は exit_code==2 のときだけ意味を持つ。"""
    env = env or {}
    # `os.getcwd()` (このガード自身のプロセス cwd) は tool 呼び出しの実行
    # ディレクトリと無関係な値でありうるため、cwd フォールバックとしては
    # 使わない (レビュー指摘 (1)(3): 分からないものは guess せず fail-closed)。
    # event/env から cwd を得られない場合は、git 解決が確実に失敗する
    # sentinel パスを使う。repo_hint が明示されている attempt には影響せず、
    # cwd に依存する attempt は既存の「repo を解決できない」経路で block される。
    cwd = event.get("cwd") or env.get("PWD") or "/nonexistent-merge-permit-guard-unresolved-cwd"

    try:
        attempts = _attempts_from_event(event, cwd)
    except _Malformed as exc:
        return 2, (
            f"{BLOCK_MESSAGE_HEADER}\n"
            f"理由: hook イベントを解析できなかった ({exc})。\n"
            "本 hook は Bash / mcp__github__merge_pull_request にしか配線されていないため、"
            "解析できない呼び出しは merge の可能性を排除できず fail-closed でブロックする。"
        )
    if not attempts:
        return 0, ""

    command_text = ""
    tool_input = event.get("tool_input") or {}
    if event.get("tool_name") == "Bash":
        command_text = tool_input.get("command", "") or ""
    else:
        command_text = json.dumps(tool_input, ensure_ascii=False)

    # フェーズ1: 全 attempt に有効な permit があるか確認する (未消費のまま)。
    resolved: list[tuple[MergeAttempt, str, Permit]] = []
    for attempt in attempts:
        if attempt.unsafe_form:
            # 「単純で一意に解釈できる形」ではない (redirect が 1 文字でも
            # ある / wrapper コマンド経由 / 環境変数代入経由 / subshell・
            # brace group・command substitution・シェルキーワードの直後)。
            # repo/target がどう見えていても信用せず、permit の有無を一切
            # 確認せず block する (第六回レビュー指摘による設計転換)。
            return 2, (
                f"{BLOCK_MESSAGE_HEADER}\n"
                f"対象: {attempt.snippet}\n"
                "理由: redirect / wrapper コマンド / 環境変数代入 / command substitution / subshell 等を"
                "含む複雑な形のコマンドは、repo/target を安全に一意抽出できないため permit の有無に関わらず"
                "常に block する。単純な形 (git merge <branch> のような、redirect/wrapper/代入/"
                "command substitution を含まない直接呼び出し) に書き直してから再試行すること。"
            )
        repo, ambiguous_block = _resolve_repo_for_attempt(attempt, cwd)
        if ambiguous_block:
            return 2, (
                f"{BLOCK_MESSAGE_HEADER}\n"
                f"対象: {attempt.snippet}\n"
                "理由: merge 呼び出し手前の cd/pushd の対象が静的に解決できない、または pipe/subshell を"
                "またいでおり実行時の作業ディレクトリが確定できない。cwd を静的に確定できないコマンドは"
                "fail-closed でブロックする (permit の repo 束縛を cd で回避させないため)。"
            )
        if not repo:
            return 2, (
                f"{BLOCK_MESSAGE_HEADER}\n"
                f"対象: {attempt.snippet}\n"
                "理由: リポジトリ識別子を解決できなかった (origin 未設定・パス不明)。\n"
                "merge-permit-cli で permit を発行してから再試行すること。"
            )
        permit = permit_store.find_valid(repo, attempt.action, attempt.target)
        if permit is None:
            return 2, (
                f"{BLOCK_MESSAGE_HEADER}\n"
                f"対象: {attempt.snippet}\n"
                f"repo={repo} action={attempt.action} target={attempt.target}\n"
                "理由: 有効な permit が無い (未発行 / 失効 / 消費済み / repo または target 不一致)。\n"
                "profile 既定値・過去の承認・スタック既定・推論された意図は許可の代わりにならない。\n"
                "この場での明示許可を得たうえで、Hermes/orchestrator が merge-permit-cli で permit を"
                "発行してから再試行すること。運用は ~/.dotfiles/claude/merge-permit-policy.md を参照。"
            )
        resolved.append((attempt, repo, permit))

    # フェーズ2: 全件そろって初めて消費する (一部だけ消費して残りをブロックし、
    # permit を無駄にしないため)。
    for attempt, repo, permit in resolved:
        ok = permit_store.consume(permit.id, by_command=command_text)
        if not ok:
            # 直前の確認から消費までの間に他プロセスが使い切った (レース)。fail-closed。
            return 2, (
                f"{BLOCK_MESSAGE_HEADER}\n"
                f"対象: {attempt.snippet}\n"
                "理由: permit の消費に失敗した (直前に他プロセスが消費した可能性)。再発行して再試行すること。"
            )

    return 0, ""


def main(argv: list[str], stdin_text: str, env: dict) -> int:
    event = _read_event(stdin_text, env)
    permit_store = PermitStore()
    exit_code, message = evaluate(event, permit_store, env)
    if exit_code != 0:
        print(message, file=sys.stderr)
    return exit_code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:], sys.stdin.read(), dict(os.environ)))
