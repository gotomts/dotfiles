#!/usr/bin/env python3
"""merge-permit CLI: Hermes/orchestrator が現在ターンの明示許可を得たあとに
permit を発行・確認・取り消しするための ID スコープ CLI。

このコマンド自体は誰でも実行できる (物理的な実行権限の分離はできない) が、
運用規約として「permit の作成はユーザーの当該ターンでの明示許可を得た
Hermes/orchestrator の行為としてのみ行う」ことを前提にする。Claude Code が
自分自身の merge を通すために自分で permit を発行することは規約違反であり、
このガードは事故防止 (うっかり/自律的な merge) を対象にしたものであって、
規約を無視する意図的な行為までは技術的に防げない。詳細は
`~/.dotfiles/claude/merge-permit-policy.md` を参照。

zsh wrapper (merge-permit-cli.zsh) から `python3 cli.py "$@"` として呼ばれる。
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from lib import (  # noqa: E402
    DEFAULT_TTL_SECONDS,
    VALID_ACTIONS,
    PermitStore,
    normalize_repo_identity_from_url,
    resolve_current_branch,
    resolve_repo_identity,
)


def _resolve_repo(args) -> str:
    if args.repo_identity:
        # `--repo-path` 経由 (resolve_repo_identity → normalize_repo_identity_from_url)
        # と同じ正規化を通す。素の `.lower()` だけだと `owner/repo` (host 省略) と
        # `github.com/owner/repo` が別文字列になり、コマンド側の repo_hint 抽出結果と
        # 一致しなくなる (レビュー指摘: repo identity の正規化を一貫させる)。
        return normalize_repo_identity_from_url(args.repo_identity)
    repo = resolve_repo_identity(args.repo_path)
    if repo:
        return repo
    return "local:" + str(Path(args.repo_path).resolve())


def _resolve_target(args) -> str:
    if args.action == "graphql-merge":
        return "graphql-mutation"
    if args.action == "gh-stack-merge":
        # stack merge は `gh stack merge <stack-number|pr-number>` または
        # 非同期 REST エンドポイントの pull_number にそのまま対応する。
        # 'current' はインタラクティブピッカー (引数なし呼び出し) 用。
        return "pr:current" if args.target == "current" else f"pr:{args.target}"
    if args.target == "current":
        branch = resolve_current_branch(args.repo_path)
        if not branch:
            print("error: --target current だが現在ブランチを解決できなかった", file=sys.stderr)
            sys.exit(1)
        return f"branch:{branch}"
    if args.action == "gh-pr-merge":
        return f"pr:{args.target}"
    return f"branch:{args.target}"


def cmd_create(args) -> int:
    store = PermitStore()
    repo = _resolve_repo(args)
    target = _resolve_target(args)
    permit = store.create(
        repo=repo,
        action=args.action,
        target=target,
        ttl_seconds=args.ttl,
        created_by=args.actor,
        reason=args.reason or "",
    )
    print(json.dumps(permit.to_json(), indent=2, ensure_ascii=False))
    return 0


def cmd_inspect(args) -> int:
    store = PermitStore()
    permit = store.get(args.id)
    if permit is None:
        print(f"error: permit not found: {args.id}", file=sys.stderr)
        return 1
    print(json.dumps(permit.to_json(), indent=2, ensure_ascii=False))
    return 0


def cmd_list(args) -> int:
    store = PermitStore()
    permits = store.list_all()
    if not args.all:
        permits = [p for p in permits if p.is_valid()]
    permits.sort(key=lambda p: p.created_at, reverse=True)
    if not permits:
        print("(no permits)")
        return 0
    for p in permits:
        state = "consumed" if p.consumed else ("expired" if p.is_expired() else "valid")
        print(f"{p.id}\t{state}\t{p.repo}\t{p.action}\t{p.target}\tcreated_by={p.created_by}")
    return 0


def cmd_revoke(args) -> int:
    store = PermitStore()
    ok = store.revoke(args.id)
    if not ok:
        print(f"error: permit not found / already consumed or expired: {args.id}", file=sys.stderr)
        return 1
    print(f"revoked: {args.id}")
    return 0


def cmd_gc(args) -> int:
    store = PermitStore()
    removed = store.gc(older_than_seconds=args.older_than_days * 24 * 3600)
    print(f"removed {removed} stale permit file(s)")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="merge-permit", description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)

    create = sub.add_parser("create", help="permit を発行する")
    create.add_argument("--action", required=True, choices=VALID_ACTIONS)
    create.add_argument(
        "--target",
        required=True,
        help=(
            "gh-pr-merge: PR番号。git-merge: マージするブランチ名。"
            "gh-stack-merge: `gh stack merge`/非同期 merge API に渡す stack番号 or PR番号 "
            "(実際に実行するコマンドの引数と同じ値を指定すること)。"
            "'current' で gh-pr-merge は現在ブランチ、gh-stack-merge は現在の stack (インタラクティブピッカー相当) を指す。"
        ),
    )
    create.add_argument("--repo-path", default=".", help="git 識別子を解決する repo のパス (既定: cwd)")
    create.add_argument("--repo-identity", default=None, help="git 解決を使わず repo 識別子を直接指定する")
    create.add_argument("--ttl", type=int, default=DEFAULT_TTL_SECONDS, help="有効秒数 (既定 300、上限 900)")
    create.add_argument("--actor", default="unknown", help="発行者 (監査用、例: hermes)")
    create.add_argument("--reason", default=None, help="発行理由の自由記述 (監査用)")
    create.set_defaults(func=cmd_create)

    inspect = sub.add_parser("inspect", help="permit の状態を表示する")
    inspect.add_argument("--id", required=True)
    inspect.set_defaults(func=cmd_inspect)

    lst = sub.add_parser("list", help="permit 一覧を表示する")
    lst.add_argument("--all", action="store_true", help="消費済み/失効済みも含めて表示する")
    lst.set_defaults(func=cmd_list)

    revoke = sub.add_parser("revoke", help="未消費の permit を即時取り消す")
    revoke.add_argument("--id", required=True)
    revoke.set_defaults(func=cmd_revoke)

    gc = sub.add_parser("gc", help="古い消費済み/失効済み permit ファイルを削除する")
    gc.add_argument("--older-than-days", type=int, default=7)
    gc.set_defaults(func=cmd_gc)

    return p


def main(argv: list[str]) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
