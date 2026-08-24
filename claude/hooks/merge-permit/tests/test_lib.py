"""lib.py (検出ロジック + permit ストア) のユニットテスト。

`uv run --with pytest pytest claude/hooks/merge-permit/tests` で実行できる。
"""

import subprocess
import sys
import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from lib import (  # noqa: E402
    PermitStore,
    detect_merge_actions,
    normalize_repo_identity_from_url,
)


# --------------------------------------------------------------------------
# 検出ロジック
# --------------------------------------------------------------------------


def test_detect_git_merge_basic():
    attempts = detect_merge_actions("git merge feature-branch", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].action == "git-merge"
    assert attempts[0].target == "branch:feature-branch"


def test_detect_git_merge_with_flags_and_extra_whitespace():
    attempts = detect_merge_actions("git   merge   --no-ff   feature-branch", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].target == "branch:feature-branch"


# --- レビュー指摘 (4) PoC: git global option (`-c key=value` 等) がサブコマンド
# 判定を素通りさせてしまう回帰テスト。修正前は `_GIT_MERGE` が単一の正規表現で
# `-C` 以外のグローバルオプションを想定しておらず、`git -c k=v merge x` は
# 「マッチしない」= 検出 0 件 = 無許可で通過、というバイパスがあった。
def test_detect_git_merge_with_dash_c_config_override_poc():
    attempts = detect_merge_actions("git -c user.name=x merge feature-branch", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].action == "git-merge"
    assert attempts[0].target == "branch:feature-branch"


def test_detect_git_merge_with_multiple_dash_c_flags():
    attempts = detect_merge_actions("git -c a.b=1 -c c.d=2 merge feature-branch", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].target == "branch:feature-branch"


def test_detect_git_merge_with_git_dir_and_work_tree_globals():
    attempts = detect_merge_actions(
        "git --git-dir=/x/.git --work-tree=/x merge feature-branch", cwd="."
    )
    assert len(attempts) == 1
    assert attempts[0].target == "branch:feature-branch"


def test_detect_git_merge_with_boolean_global_flags():
    attempts = detect_merge_actions("git --no-pager --literal-pathspecs merge feature-branch", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].target == "branch:feature-branch"


def test_detect_git_merge_dash_c_uppercase_repo_path_still_extracted():
    # -C (大文字) は従来どおり repo 切り替えとして扱われ、-c (小文字、config
    # override) と混同されないこと
    attempts = detect_merge_actions("git -C /some/repo merge feature-branch", cwd=".")
    assert len(attempts) == 1
    # -C は絶対パスなので repo_hint 解決を試みる (git が無い/repo でなければ
    # None になるが、少なくとも -c と違って "config override" 扱いされていない
    # ことは flag_values 経由の挙動で保証されている。ここでは検出自体の成功のみ確認)


# --- 第三者レビュー (2回目) が実機 PoC で確認した検出漏れの回帰テスト ---------
# `_is_command_position` が `;`/`&`/`|`/改行以外の正当なコマンド開始位置
# (subshell `(`・brace group `{`・否定 `!`・シェルキーワード then/do/else/elif
# の直後) を見落としており、これらの直後に置かれた `git merge` が検出 0 件 =
# 無許可で通過するバイパスになっていた。1回目のレビュー指摘 (`-c`/`--git-dir`
# 等のグローバルオプション対応) を弱めずに、コマンド位置の判定だけを広げる。


def test_detect_git_merge_after_if_then_semicolon():
    attempts = detect_merge_actions("if cond; then git merge X; fi", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].action == "git-merge"
    assert attempts[0].target == "branch:X"


def test_detect_git_merge_inside_subshell_parens():
    attempts = detect_merge_actions("(git merge X)", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].target == "branch:X"  # 閉じ括弧が target に glue されない


def test_detect_git_merge_inside_brace_group():
    attempts = detect_merge_actions("{ git merge X; }", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].target == "branch:X"


def test_detect_git_merge_after_negation_bang():
    attempts = detect_merge_actions("! git merge X", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].target == "branch:X"


def test_detect_git_merge_after_do_keyword():
    attempts = detect_merge_actions("for i in 1 2; do git merge X; done", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].target == "branch:X"


def test_detect_git_merge_after_else_keyword():
    attempts = detect_merge_actions("if false; then true; else git merge X; fi", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].target == "branch:X"


def test_detect_git_merge_after_elif_keyword():
    attempts = detect_merge_actions("if false; then true; elif true; then git merge X; fi", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].target == "branch:X"


def test_detect_git_merge_after_while_condition_keyword():
    # then/do/else/elif と構造的に同じ穴 (キーワード直後がコマンド位置) を
    # while/until についても塞いだことの確認
    attempts = detect_merge_actions("while git merge X; do true; done", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].target == "branch:X"


def test_detect_git_merge_as_if_condition():
    # 第三者レビュー (3回目) 指摘の回帰: merge そのものが if の条件式に
    # なっているケース (`if` の直後がコマンド開始位置) を見落としていた。
    attempts = detect_merge_actions("if git merge X; then true; fi", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].action == "git-merge"
    assert attempts[0].target == "branch:X"


def test_detect_git_merge_after_newline_still_works():
    # 改行区切りは修正前から効いていたが、他のキーワード修正と合わせて
    # 回帰していないことを確認する
    attempts = detect_merge_actions("true\ngit merge X", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].target == "branch:X"


def test_detect_git_merge_then_on_own_line_after_if_condition():
    # `then` が独立した行にあるパターン (改行区切りなので then キーワード
    # 判定を経由せずとも検出できるはずだが、念のため確認する)
    attempts = detect_merge_actions("if cond\nthen\n  git merge X\nfi", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].target == "branch:X"


def test_detect_git_merge_nested_subshell_and_negation():
    attempts = detect_merge_actions("(! git merge X)", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].target == "branch:X"


def test_arbitrary_preceding_word_still_detects_git_merge():
    # 第四回レビューの方針転換: 「コマンド開始位置として妥当な文脈を列挙する」
    # 許可リスト方式をやめたため、"git" の直前がどんな単語であっても
    # (`.`/`-` で終わる場合を除き) git-merge として検出する。過去は
    # "softhen" のような非キーワード単語の直後を「検出しない」ことを
    # 期待していたが、今はその逆 (over-detection 優先) が意図した挙動。
    attempts = detect_merge_actions("echo softhen git merge X", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].target == "branch:X"


def test_detect_git_merge_abort_is_excluded():
    attempts = detect_merge_actions("git merge --abort", cwd=".")
    assert attempts == []


def test_detect_git_merge_continue_still_requires_permit():
    attempts = detect_merge_actions("git merge --continue", cwd=".")
    assert len(attempts) == 1


def test_no_false_positive_on_merge_base():
    assert detect_merge_actions("git merge-base main HEAD", cwd=".") == []


def test_no_false_positive_on_merge_tree_and_log_merge_flag():
    assert detect_merge_actions("git merge-tree main HEAD", cwd=".") == []
    assert detect_merge_actions("git log --merge -1", cwd=".") == []


def test_detect_git_merge_inside_compound_command():
    cmd = "echo start && git merge release/1.0 ; echo done"
    attempts = detect_merge_actions(cmd, cwd=".")
    assert len(attempts) == 1
    assert attempts[0].target == "branch:release/1.0"


def test_detect_gh_pr_merge_with_explicit_number():
    attempts = detect_merge_actions("gh pr merge 123 --squash", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].action == "gh-pr-merge"
    assert attempts[0].target == "pr:123"


def test_detect_gh_pr_merge_with_repo_flag():
    attempts = detect_merge_actions("gh pr merge 42 --repo owner/repo --merge", cwd=".")
    assert len(attempts) == 1
    # host 省略の owner/repo は github.com を補って正規化される (レビュー指摘:
    # repo identity の正規化を一貫させる。resolve_repo_identity 側の
    # host/owner/repo 形式と一致させないと permit の repo 完全一致がすり抜ける)
    assert attempts[0].repo_hint == "github.com/owner/repo"
    assert attempts[0].target == "pr:42"


def test_detect_gh_pr_merge_with_short_repo_flag():
    # `-R` (短縮形) も `--repo` と同様に検出できること (レビュー指摘 (2):
    # `-R` を見落とすと別リポジトリの PR を「カレント repo 向け」の permit で
    # merge できてしまう)
    attempts = detect_merge_actions("gh pr merge 42 -R owner/repo", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].repo_hint == "github.com/owner/repo"


def test_detect_gh_pr_merge_with_glued_short_repo_flag():
    attempts = detect_merge_actions("gh pr merge 42 -Rowner/repo", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].repo_hint == "github.com/owner/repo"


def test_detect_gh_pr_merge_with_host_qualified_repo_flag():
    attempts = detect_merge_actions("gh pr merge 42 --repo ghe.example.com/owner/repo", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].repo_hint == "ghe.example.com/owner/repo"


def test_detect_gh_pr_merge_bare_uses_current_branch(monkeypatch):
    import lib

    monkeypatch.setattr(lib, "resolve_current_branch", lambda cwd: "my-branch")
    attempts = detect_merge_actions("gh pr merge --squash", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].target == "branch:my-branch"


def test_detect_curl_rest_merge_endpoint_requires_put():
    get_cmd = 'curl -s https://api.github.com/repos/owner/repo/pulls/7/merge'
    assert detect_merge_actions(get_cmd, cwd=".") == []

    put_cmd = 'curl -X PUT https://api.github.com/repos/owner/repo/pulls/7/merge'
    attempts = detect_merge_actions(put_cmd, cwd=".")
    assert len(attempts) == 1
    assert attempts[0].target == "pr:7"
    assert attempts[0].repo_hint == "github.com/owner/repo"


def test_detect_gh_api_rest_merge_endpoint_with_method_flag():
    cmd = "gh api --method PUT repos/owner/repo/pulls/9/merge"
    attempts = detect_merge_actions(cmd, cwd=".")
    assert len(attempts) == 1
    assert attempts[0].target == "pr:9"


def test_detect_gh_stack_merge_with_number():
    attempts = detect_merge_actions("gh stack merge 128", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].action == "gh-stack-merge"
    assert attempts[0].target == "pr:128"


def test_detect_gh_stack_merge_bare_is_current():
    attempts = detect_merge_actions("gh stack merge", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].target == "pr:current"


def test_gh_stack_merge_has_no_repo_flag_support():
    # `gh stack merge --help` に --repo/-R は存在しない (stack は常にカレント
    # repo/branch 基準)。実在しないオプションのハンドリングは持たせていないため
    # (レビュー指摘: 未サポートの --repo ハンドリングを除去)、repo_hint は常に
    # None になり repo 解決は cwd 経由のみで行われる。
    attempts = detect_merge_actions("gh stack merge 7", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].repo_hint is None
    assert attempts[0].target == "pr:7"


def test_detect_gh_stack_merge_with_yes_and_merge_method_flags():
    attempts = detect_merge_actions("gh stack merge 42 --merge-method rebase --yes", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].target == "pr:42"


def test_detect_gh_stack_merge_bare_with_flags_is_current():
    attempts = detect_merge_actions("gh stack merge --yes --squash", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].target == "pr:current"


def test_detect_rest_merge_async_endpoint_requires_put():
    get_cmd = "curl -s https://api.github.com/repos/owner/repo/pulls/9/merge-async"
    assert detect_merge_actions(get_cmd, cwd=".") == []

    put_cmd = "curl -X PUT https://api.github.com/repos/owner/repo/pulls/9/merge-async"
    attempts = detect_merge_actions(put_cmd, cwd=".")
    assert len(attempts) == 1
    assert attempts[0].action == "gh-stack-merge"
    assert attempts[0].target == "pr:9"
    assert attempts[0].repo_hint == "github.com/owner/repo"


def test_merge_async_endpoint_does_not_also_trigger_legacy_merge_detection():
    # `/merge-async` は素朴な `\bmerge\b` 正規表現だと legacy `/merge` にも
    # マッチしてしまう (word boundary は "-" の前でも成立するため)。
    # 二重に permit が要求されないことを確認する。
    cmd = "curl -X PUT https://api.github.com/repos/owner/repo/pulls/9/merge-async"
    attempts = detect_merge_actions(cmd, cwd=".")
    assert len(attempts) == 1
    assert attempts[0].action == "gh-stack-merge"


def test_legacy_merge_endpoint_still_detected_as_gh_pr_merge():
    cmd = "curl -X PUT https://api.github.com/repos/owner/repo/pulls/9/merge"
    attempts = detect_merge_actions(cmd, cwd=".")
    assert len(attempts) == 1
    assert attempts[0].action == "gh-pr-merge"
    assert attempts[0].target == "pr:9"


def test_detect_graphql_merge_mutation():
    cmd = 'gh api graphql -f query=\'mutation { mergePullRequest(input: {pullRequestId: "abc"}) { clientMutationId } }\''
    attempts = detect_merge_actions(cmd, cwd=".")
    assert len(attempts) == 1
    assert attempts[0].action == "graphql-merge"


def test_no_detection_on_unrelated_command():
    assert detect_merge_actions("git status", cwd=".") == []
    # 第四回レビューの方針転換: 「コマンド開始位置を厳密に判定する」許可
    # リスト方式は 3 回のレビューで 3 回の検出漏れ (回帰) を生んだため廃止し、
    # `.`/`-` で終わる直前文字だけを否定リストで除外する方式に置き換えた。
    # 引用文字列中の「git merge」への言及も区別できなくなったため、これは
    # over-detection (誤って permit を要求する) として意図的に許容する。
    # false positive は false negative (無許可の merge の見逃し) より
    # 安全な失敗方向、という本モジュール全体の設計判断のとおり。
    attempts = detect_merge_actions("echo 'please do not run git merge in prod'", cwd=".")
    assert attempts != []


# --------------------------------------------------------------------------
# リポジトリ識別子の正規化
# --------------------------------------------------------------------------


@pytest.mark.parametrize(
    "url,expected",
    [
        ("https://github.com/gotomts/dotfiles.git", "github.com/gotomts/dotfiles"),
        ("git@github.com:gotomts/dotfiles.git", "github.com/gotomts/dotfiles"),
        ("ssh://git@github.com/gotomts/dotfiles.git", "github.com/gotomts/dotfiles"),
        ("https://github.com/gotomts/dotfiles", "github.com/gotomts/dotfiles"),
    ],
)
def test_normalize_repo_identity_from_url(url, expected):
    assert normalize_repo_identity_from_url(url) == expected


# --------------------------------------------------------------------------
# Permit ストア
# --------------------------------------------------------------------------


@pytest.fixture
def store(tmp_path):
    return PermitStore(base_dir=tmp_path / "merge-permits")


def test_create_and_find_valid(store):
    permit = store.create(repo="github.com/o/r", action="gh-pr-merge", target="pr:1", ttl_seconds=60)
    found = store.find_valid("github.com/o/r", "gh-pr-merge", "pr:1")
    assert found is not None
    assert found.id == permit.id


def test_find_valid_returns_none_for_wrong_repo(store):
    store.create(repo="github.com/o/r", action="gh-pr-merge", target="pr:1", ttl_seconds=60)
    assert store.find_valid("github.com/o/OTHER", "gh-pr-merge", "pr:1") is None


def test_find_valid_returns_none_for_wrong_target(store):
    store.create(repo="github.com/o/r", action="gh-pr-merge", target="pr:1", ttl_seconds=60)
    assert store.find_valid("github.com/o/r", "gh-pr-merge", "pr:999") is None


def test_consume_is_single_use(store):
    permit = store.create(repo="github.com/o/r", action="git-merge", target="branch:x", ttl_seconds=60)
    assert store.consume(permit.id, by_command="git merge x") is True
    # 2回目は失敗する (既に消費済み)
    assert store.consume(permit.id, by_command="git merge x") is False
    assert store.find_valid("github.com/o/r", "git-merge", "branch:x") is None


def test_expired_permit_is_not_valid(store):
    permit = store.create(repo="github.com/o/r", action="git-merge", target="branch:x", ttl_seconds=1)
    assert store.find_valid("github.com/o/r", "git-merge", "branch:x", now=permit.created_at) is not None
    assert store.find_valid("github.com/o/r", "git-merge", "branch:x", now=permit.expires_at + 1) is None


def test_expired_permit_cannot_be_consumed(store):
    permit = store.create(repo="github.com/o/r", action="git-merge", target="branch:x", ttl_seconds=-1000)
    # ttl は最低 1 秒にクランプされるが、作成直後に強制的に expires_at を過去にする
    import json

    path = store._path(permit.id)
    data = json.loads(path.read_text())
    data["expires_at"] = time.time() - 10
    path.write_text(json.dumps(data))
    assert store.consume(permit.id) is False


def test_ttl_is_clamped_to_max(store):
    permit = store.create(repo="github.com/o/r", action="git-merge", target="branch:x", ttl_seconds=999999)
    assert permit.expires_at - permit.created_at <= 900 + 1


def test_revoke_marks_consumed(store):
    permit = store.create(repo="github.com/o/r", action="git-merge", target="branch:x", ttl_seconds=60)
    assert store.revoke(permit.id) is True
    assert store.get(permit.id).consumed is True
    assert store.find_valid("github.com/o/r", "git-merge", "branch:x") is None


def test_gc_removes_only_stale_and_old(store):
    old_consumed = store.create(repo="github.com/o/r", action="git-merge", target="branch:a", ttl_seconds=60)
    store.consume(old_consumed.id)
    # created_at を過去に書き換えて「古い」を再現する
    import json

    path = store._path(old_consumed.id)
    data = json.loads(path.read_text())
    data["created_at"] = time.time() - 100000
    path.write_text(json.dumps(data))

    fresh_valid = store.create(repo="github.com/o/r", action="git-merge", target="branch:b", ttl_seconds=60)

    removed = store.gc(older_than_seconds=3600)
    assert removed == 1
    assert store.get(old_consumed.id) is None
    assert store.get(fresh_valid.id) is not None


def test_concurrent_consume_only_one_wins(store):
    """os.fork で 2 プロセス同時消費を模し、片方だけ成功することを確認する。"""
    import os

    permit = store.create(repo="github.com/o/r", action="git-merge", target="branch:race", ttl_seconds=60)

    results_path = store.base_dir / "race-results.txt"
    results_path.write_text("")

    pid = os.fork()
    if pid == 0:
        # 子プロセス
        ok = store.consume(permit.id, by_command="child")
        with open(results_path, "a") as f:
            f.write(f"child:{ok}\n")
        os._exit(0)
    else:
        ok = store.consume(permit.id, by_command="parent")
        with open(results_path, "a") as f:
            f.write(f"parent:{ok}\n")
        os.waitpid(pid, 0)

    lines = results_path.read_text().splitlines()
    successes = [line for line in lines if line.endswith(":True")]
    assert len(successes) == 1


# ============================================================================
# 第四回レビュー指摘の回帰テスト: 許可リスト方式の廃止と否定リスト方式への
# 置き換え。backtick/command substitution・redirection・環境変数代入・
# wrapper コマンドの直後に置かれた git merge が検出漏れになっていた
# (許可リストにこれらの文脈が列挙されていなかったため)。
# ============================================================================


@pytest.mark.parametrize(
    "command",
    [
        pytest.param("echo `git merge X`", id="backtick-command-substitution"),
        pytest.param("echo $(git merge X)", id="dollar-paren-command-substitution"),
        pytest.param("> /tmp/log git merge X", id="redirect-stdout-spaced"),
        pytest.param(">/tmp/log git merge X", id="redirect-stdout-glued"),
        pytest.param("2>/dev/null git merge X", id="redirect-stderr"),
        pytest.param("< /dev/null git merge X", id="redirect-stdin"),
        pytest.param("git merge X > /tmp/log 2>&1", id="redirect-after-command"),
        pytest.param("FOO=bar git merge X", id="env-assignment-unrelated"),
        pytest.param("FOO=bar BAZ=qux git merge X", id="env-assignment-multiple"),
        pytest.param("true; git merge X", id="separator-semicolon"),
        pytest.param("true && git merge X", id="separator-and"),
        pytest.param("true || git merge X", id="separator-or"),
        pytest.param("time git merge X", id="wrapper-time"),
        pytest.param("exec git merge X", id="wrapper-exec"),
        pytest.param("env git merge X", id="wrapper-env"),
        pytest.param("nice git merge X", id="wrapper-nice"),
        pytest.param("nice -n 10 git merge X", id="wrapper-nice-with-flag-value"),
        pytest.param("nohup git merge X", id="wrapper-nohup"),
        pytest.param("command git merge X", id="wrapper-command"),
        pytest.param("sudo git merge X", id="wrapper-sudo"),
        pytest.param("sudo nice time git merge X", id="wrapper-chained"),
    ],
)
def test_bounded_matrix_git_merge_is_detected(command):
    attempts = detect_merge_actions(command, cwd=".")
    assert len(attempts) >= 1, f"expected git-merge to be detected in: {command!r}"
    assert any(a.action == "git-merge" and a.target == "branch:X" for a in attempts)


@pytest.mark.parametrize(
    "command",
    [
        pytest.param("ls -la", id="benign-unrelated"),
        pytest.param("git status", id="benign-git-status"),
        pytest.param("git merge-base main HEAD", id="benign-merge-base"),
        pytest.param("git log --merge -1", id="benign-log-merge-flag"),
        pytest.param("git merge --abort", id="benign-merge-abort"),
        pytest.param("FOO=bar ls -la", id="benign-env-assignment-unrelated-command"),
        pytest.param("time ls -la", id="benign-wrapper-unrelated-command"),
    ],
)
def test_bounded_matrix_benign_commands_not_detected(command):
    assert detect_merge_actions(command, cwd=".") == []


def test_git_dir_env_override_forces_ambiguous_cwd():
    # GIT_DIR= は -C 相当の repo 切り替え力を持つため、明示的な -C が無い
    # 場合は cwd 由来の repo 解決を信用せず ambiguous にする。
    attempts = detect_merge_actions("GIT_DIR=/other/repo git merge X", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].cwd_ambiguous is True
    assert attempts[0].cwd_override is None


def test_git_work_tree_env_override_forces_ambiguous_cwd():
    attempts = detect_merge_actions("GIT_WORK_TREE=/other/repo git merge X", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].cwd_ambiguous is True


def test_git_dir_env_override_does_not_force_ambiguous_when_explicit_dash_c_present():
    # 明示的な -C (絶対パス、実在する git repo) がある場合は GIT_DIR= より
    # 優先して信用する (git 自身の実際の優先順位も -C/--git-dir がより
    # 具体的な指定として勝つ)。-C の解決先が実在しないと repo_hint が None の
    # ままになり GIT_DIR 側のチェックが働いてしまうため、実在する repo
    # (このチェックアウト自身) を使う。
    repo_root = str(Path(__file__).resolve().parents[4])
    attempts = detect_merge_actions(f"GIT_DIR=/other/repo git -C {repo_root} merge X", cwd=".")
    assert len(attempts) == 1
    if attempts[0].repo_hint is None:
        pytest.skip("このチェックアウトに git origin が設定されていない")
    assert attempts[0].cwd_ambiguous is False


# ============================================================================
# 最終レビュー指摘の回帰テスト: redirect が対象引数より前に来ると
# target 抽出が空になり `branch:HEAD`/`pr:current` (未指定扱い) に化けて
# しまっていた (`_extract_target_token` が redirect トークンで走査を
# 打ち切っていたため)。汎用 permit ("current" 向け) が、実際には明示的な
# 別 target への merge を通してしまう target-binding バイパスだった。
# ============================================================================


@pytest.mark.parametrize(
    "command,expected_target",
    [
        pytest.param("git merge >log branch-name", "branch:branch-name", id="git-redirect-glued-before-target"),
        pytest.param(
            "git merge > log.txt branch-name", "branch:branch-name", id="git-redirect-spaced-before-target"
        ),
        pytest.param(
            "git merge >out.log 2>err.log branch-name",
            "branch:branch-name",
            id="git-multiple-redirects-before-target",
        ),
        pytest.param("gh pr merge >log 42", "pr:42", id="gh-pr-redirect-glued-before-target"),
        pytest.param("gh pr merge > log 42", "pr:42", id="gh-pr-redirect-spaced-before-target"),
        pytest.param("gh stack merge >log 7", "pr:7", id="gh-stack-redirect-glued-before-target"),
        pytest.param("gh stack merge > log 7", "pr:7", id="gh-stack-redirect-spaced-before-target"),
    ],
)
def test_redirect_before_target_does_not_collapse_target_to_current(command, expected_target):
    attempts = detect_merge_actions(command, cwd=".")
    assert len(attempts) == 1, f"expected exactly 1 attempt for {command!r}, got {attempts}"
    assert attempts[0].target == expected_target


def test_redirect_before_target_with_flag_still_resolves_correct_target():
    attempts = detect_merge_actions("git merge --no-ff >log.txt branch-name", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].target == "branch:branch-name"


def test_generic_current_permit_does_not_authorize_redirect_smuggled_explicit_target(tmp_path):
    # target-binding バイパスの核心: "現在ブランチ/現在スタック向け" の
    # 汎用 permit (target="branch:HEAD" 等) は、redirect で偽装された
    # 明示的な別 target への merge を通してはならない。
    from lib import PermitStore

    store = PermitStore(base_dir=tmp_path / "merge-permits")
    store.create(repo="github.com/o/r", action="git-merge", target="branch:HEAD", ttl_seconds=60)
    attempts = detect_merge_actions("git merge >log branch-name", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].target == "branch:branch-name"
    # "branch:HEAD" 用の permit は "branch:branch-name" には一致しない
    assert store.find_valid("github.com/o/r", "git-merge", attempts[0].target) is None


# ============================================================================
# 最終レビュー指摘による設計転換の回帰テスト: 「単純で一意に解釈できる形」
# だけを permit 照合の対象にし、それ以外は unsafe_form=True として常に
# block する。redirect の複合 ampersand 形 (`2>&1`/`&>`/`>&`/`&>>`) は
# 個別に正しく解釈できるかどうかに関わらず、1 文字でも `<`/`>` があれば
# 単純とみなさない。
# ============================================================================


@pytest.mark.parametrize(
    "command",
    [
        pytest.param("git merge branch-name", id="plain-simple"),
        pytest.param("git merge --no-ff branch-name", id="simple-with-flag"),
        pytest.param("git -c user.name=x merge branch-name", id="simple-with-dash-c-global-option"),
        pytest.param("true; git merge branch-name", id="simple-after-semicolon-separator"),
        pytest.param("true && git merge branch-name", id="simple-after-and-separator"),
        pytest.param("true\ngit merge branch-name", id="simple-after-newline-separator"),
        pytest.param("gh pr merge 42 --squash", id="gh-pr-merge-simple"),
        pytest.param("gh stack merge 7 --yes", id="gh-stack-merge-simple"),
    ],
)
def test_simple_forms_are_not_unsafe(command):
    attempts = detect_merge_actions(command, cwd=".")
    assert len(attempts) == 1
    assert attempts[0].unsafe_form is False


@pytest.mark.parametrize(
    "command",
    [
        pytest.param("(git merge branch-name)", id="subshell"),
        pytest.param("{ git merge branch-name; }", id="brace-group"),
        pytest.param("! git merge branch-name", id="negation-bang"),
        pytest.param("if git merge branch-name; then true; fi", id="if-condition"),
        pytest.param("if cond; then git merge branch-name; fi", id="if-then-same-line"),
        pytest.param("echo `git merge branch-name`", id="backtick-command-substitution"),
        pytest.param("echo $(git merge branch-name)", id="dollar-paren-command-substitution"),
        pytest.param("FOO=bar git merge branch-name", id="env-assignment-prefix"),
        pytest.param("GIT_DIR=/other/repo git merge branch-name", id="git-dir-env-override"),
        pytest.param("sudo git merge branch-name", id="wrapper-sudo"),
        pytest.param("time git merge branch-name", id="wrapper-time"),
        pytest.param("env git merge branch-name", id="wrapper-env"),
        pytest.param("nice git merge branch-name", id="wrapper-nice"),
        pytest.param("nice -n 10 git merge branch-name", id="wrapper-nice-with-flag-value"),
        pytest.param("nohup git merge branch-name", id="wrapper-nohup"),
        pytest.param("command git merge branch-name", id="wrapper-command"),
        pytest.param("exec git merge branch-name", id="wrapper-exec"),
        pytest.param("sudo nice time git merge branch-name", id="chained-wrappers"),
        pytest.param("git merge >log branch-name", id="redirect-before-target-glued"),
        pytest.param("git merge > log branch-name", id="redirect-before-target-spaced"),
        pytest.param("git merge branch-name >log", id="redirect-after-target-glued"),
        pytest.param("git merge branch-name > log", id="redirect-after-target-spaced"),
        pytest.param("git merge branch-name 2>&1", id="composite-redirect-stderr-to-stdout"),
        pytest.param("git merge branch-name &> /tmp/log", id="composite-redirect-both-streams"),
        pytest.param("git merge branch-name >& /tmp/log", id="composite-redirect-dup-form"),
        pytest.param("git merge branch-name &>> /tmp/log", id="composite-redirect-append-both"),
        pytest.param("git merge branch-name >> /tmp/log", id="append-redirect"),
        pytest.param("git merge branch-name < /dev/null", id="input-redirect"),
        pytest.param("gh pr merge >log 42", id="gh-pr-redirect-before-target"),
        pytest.param("gh pr merge 42 >log", id="gh-pr-redirect-after-target"),
        pytest.param("gh stack merge >log 7", id="gh-stack-redirect-before-target"),
        pytest.param("gh stack merge 7 >log", id="gh-stack-redirect-after-target"),
    ],
)
def test_complex_forms_are_always_unsafe(command):
    attempts = detect_merge_actions(command, cwd=".")
    assert len(attempts) == 1, f"expected exactly 1 attempt for {command!r}, got {attempts}"
    assert attempts[0].unsafe_form is True, f"expected unsafe_form=True for {command!r}"


def test_unsafe_form_blocks_regardless_of_exact_repo_and_target_match(tmp_path):
    # 核心: unsafe_form の攻撃対象は「repo/target が正しく抽出され permit と
    # 完全一致していても block される」ことなので、わざと一致する permit を
    # 用意したうえで PermitStore.find_valid が呼ばれる前に guard 側が
    # block することを確認する (guard レベルの詳細テストは test_guard.py)。
    from lib import PermitStore

    store = PermitStore(base_dir=tmp_path / "merge-permits")
    store.create(repo="github.com/o/r", action="git-merge", target="branch:branch-name", ttl_seconds=60)
    attempts = detect_merge_actions("git merge branch-name 2>&1", cwd=".")
    assert len(attempts) == 1
    assert attempts[0].target == "branch:branch-name"  # 抽出自体は正しい
    assert attempts[0].unsafe_form is True  # にもかかわらず unsafe_form
    # find_valid が返す permit の有無に関わらず、guard 側は unsafe_form を
    # 最初にチェックして block しなければならない (evaluate() 側の責務)。
    assert store.find_valid("github.com/o/r", "git-merge", attempts[0].target) is not None


# ============================================================================
# 独立レビュー再現 PoC の回帰テスト: redirect-before-subcommand が検出を
# 完全に素通りさせるバイパスと、origin 未設定の -C が session repo へ
# フォールバックしてしまうバイパス。
# ============================================================================


@pytest.mark.parametrize(
    "command",
    [
        pytest.param("git &>log merge branch", id="ampersand-gt-before-subcommand"),
        pytest.param("git >&2 merge branch", id="gt-ampersand-before-subcommand"),
        pytest.param("git 2>&1 merge branch", id="fd-dup-before-subcommand"),
    ],
)
def test_redirect_before_subcommand_cannot_produce_zero_attempts(command):
    # 核心: 修正前はこれらすべてが detect_merge_actions() == [] になり、
    # ガードが merge を無条件に許可していた (`_GIT_STATEMENT_END` が単体の
    # `&` で文を打ち切り、`_find_git_subcommand` がサブコマンドを一切
    # 見つけられなかったため)。
    attempts = detect_merge_actions(command, cwd=".")
    assert attempts != [], f"expected at least 1 attempt for {command!r}, got zero (bypass)"
    assert len(attempts) == 1
    assert attempts[0].action == "git-merge"
    assert attempts[0].target == "branch:branch"
    # redirect を含む形なので unsafe_form も真でなければならない
    assert attempts[0].unsafe_form is True


def test_explicit_dash_c_originless_repo_is_ambiguous_not_session_fallback(tmp_path):
    # 核心: -C が明示されている以上、解決に失敗した場合は「-C の対象が
    # 不明」であって「session の静的 cwd を使ってよい」ではない。
    import subprocess

    originless = tmp_path / "originless-repo"
    originless.mkdir()
    subprocess.run(["git", "init", "-q", "-b", "main", str(originless)], check=True)
    subprocess.run(["git", "-C", str(originless), "config", "user.email", "t@example.com"], check=True)
    subprocess.run(["git", "-C", str(originless), "config", "user.name", "t"], check=True)
    (originless / "f.txt").write_text("hi\n")
    subprocess.run(["git", "-C", str(originless), "add", "-A"], check=True)
    subprocess.run(["git", "-C", str(originless), "commit", "-q", "-m", "init"], check=True)

    # 前提確認: origin が無いこと
    r = subprocess.run(["git", "-C", str(originless), "remote", "get-url", "origin"], capture_output=True)
    assert r.returncode != 0

    session_cwd = str(Path(__file__).resolve().parents[4])  # このチェックアウト自身 (dotfiles)
    cmd = f"git -C {originless} merge branch-name"
    attempts = detect_merge_actions(cmd, cwd=session_cwd)
    assert len(attempts) == 1
    a = attempts[0]
    # repo_hint が session repo にすり替わっていないこと (None のまま)
    assert a.repo_hint is None
    # cwd フォールバックが effective_cwd/session repo に迂回しないよう
    # ambiguous が立っていること
    assert a.cwd_ambiguous is True
    assert a.cwd_override is None
