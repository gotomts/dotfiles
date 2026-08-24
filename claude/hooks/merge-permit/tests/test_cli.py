"""merge-permit-cli.zsh を実プロセスとして起動する end-to-end テスト。

HOME を tmp_path に差し替えて実行することで、実際の ~/.claude/merge-permits/
を汚さずに CLI の create/inspect/list/revoke/gc を検証する。
"""

import json
import os
import subprocess
from pathlib import Path

CLI = str(Path(__file__).resolve().parent.parent / "merge-permit-cli.zsh")
REPO_ROOT = str(Path(__file__).resolve().parents[4])


def run_cli(args, home: Path):
    env = dict(os.environ)
    env["HOME"] = str(home)
    return subprocess.run(
        ["zsh", CLI, *args],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        env=env,
        timeout=15,
    )


def test_create_then_list_then_inspect(tmp_path):
    created = run_cli(
        ["create", "--action", "git-merge", "--target", "some-branch", "--repo-path", REPO_ROOT, "--actor", "test"],
        home=tmp_path,
    )
    assert created.returncode == 0, created.stderr
    permit = json.loads(created.stdout)
    assert permit["action"] == "git-merge"
    assert permit["target"] == "branch:some-branch"
    assert permit["consumed"] is False

    listed = run_cli(["list"], home=tmp_path)
    assert listed.returncode == 0
    assert permit["id"] in listed.stdout

    inspected = run_cli(["inspect", "--id", permit["id"]], home=tmp_path)
    assert inspected.returncode == 0
    assert json.loads(inspected.stdout)["id"] == permit["id"]


def test_revoke_prevents_future_use(tmp_path):
    created = run_cli(
        ["create", "--action", "git-merge", "--target", "x", "--repo-path", REPO_ROOT],
        home=tmp_path,
    )
    permit = json.loads(created.stdout)

    revoked = run_cli(["revoke", "--id", permit["id"]], home=tmp_path)
    assert revoked.returncode == 0

    inspected = run_cli(["inspect", "--id", permit["id"]], home=tmp_path)
    assert json.loads(inspected.stdout)["consumed"] is True

    # list (デフォルト) は有効な permit のみ表示するので、取り消し済みは出ない
    listed = run_cli(["list"], home=tmp_path)
    assert permit["id"] not in listed.stdout


def test_inspect_unknown_id_fails(tmp_path):
    result = run_cli(["inspect", "--id", "mp_doesnotexist"], home=tmp_path)
    assert result.returncode == 1


def test_gc_reports_zero_when_nothing_stale(tmp_path):
    run_cli(["create", "--action", "git-merge", "--target", "x", "--repo-path", REPO_ROOT], home=tmp_path)
    result = run_cli(["gc"], home=tmp_path)
    assert result.returncode == 0
    assert "removed 0" in result.stdout


def test_create_gh_stack_merge_permit(tmp_path):
    result = run_cli(
        ["create", "--action", "gh-stack-merge", "--target", "128", "--repo-path", REPO_ROOT, "--actor", "hermes"],
        home=tmp_path,
    )
    assert result.returncode == 0, result.stderr
    permit = json.loads(result.stdout)
    assert permit["action"] == "gh-stack-merge"
    assert permit["target"] == "pr:128"


def test_create_gh_stack_merge_permit_current(tmp_path):
    result = run_cli(
        ["create", "--action", "gh-stack-merge", "--target", "current", "--repo-path", REPO_ROOT],
        home=tmp_path,
    )
    assert result.returncode == 0, result.stderr
    permit = json.loads(result.stdout)
    # gh-stack-merge の 'current' はブランチ解決をせず、そのまま pr:current になる
    assert permit["target"] == "pr:current"


def test_create_target_current_resolves_branch(tmp_path):
    result = run_cli(
        ["create", "--action", "gh-pr-merge", "--target", "current", "--repo-path", REPO_ROOT],
        home=tmp_path,
    )
    assert result.returncode == 0, result.stderr
    permit = json.loads(result.stdout)
    assert permit["target"].startswith("branch:")
