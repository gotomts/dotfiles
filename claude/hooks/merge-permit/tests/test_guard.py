"""guard.py (PreToolUse hook本体) の統合寄りテスト。

evaluate() を直接呼び、実際の hook プロセスが標準入力から受け取るのと
同じ形の event dict / PermitStore を渡して block / allow を検証する。
"""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from guard import evaluate, main  # noqa: E402
from lib import PermitStore, resolve_repo_identity  # noqa: E402

REPO_ROOT = str(Path(__file__).resolve().parents[4])  # .../claude/hooks/merge-permit/tests -> repo root


@pytest.fixture
def store(tmp_path):
    return PermitStore(base_dir=tmp_path / "merge-permits")


@pytest.fixture
def repo_identity():
    identity = resolve_repo_identity(REPO_ROOT)
    if not identity:
        pytest.skip("このチェックアウトに git origin が設定されていない")
    return identity


def test_unrelated_bash_command_is_allowed(store):
    event = {"tool_name": "Bash", "tool_input": {"command": "ls -la"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 0


def test_git_merge_without_permit_is_blocked(store):
    event = {"tool_name": "Bash", "tool_input": {"command": "git merge some-branch"}, "cwd": REPO_ROOT}
    code, msg = evaluate(event, store)
    assert code == 2
    assert "merge-permit" in msg


def test_git_merge_with_valid_permit_is_allowed_and_consumes(store, repo_identity):
    store.create(repo=repo_identity, action="git-merge", target="branch:some-branch", ttl_seconds=60)
    event = {"tool_name": "Bash", "tool_input": {"command": "git merge some-branch"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 0
    # 消費済みなので同じコマンドを再実行するともうブロックされる
    code2, _msg2 = evaluate(event, store)
    assert code2 == 2


def test_git_merge_wrong_target_is_blocked(store, repo_identity):
    store.create(repo=repo_identity, action="git-merge", target="branch:other-branch", ttl_seconds=60)
    event = {"tool_name": "Bash", "tool_input": {"command": "git merge some-branch"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 2


def test_git_merge_wrong_repo_is_blocked(store):
    store.create(repo="github.com/someone/else", action="git-merge", target="branch:some-branch", ttl_seconds=60)
    event = {"tool_name": "Bash", "tool_input": {"command": "git merge some-branch"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 2


def test_expired_permit_is_blocked(store, repo_identity):
    permit = store.create(repo=repo_identity, action="git-merge", target="branch:some-branch", ttl_seconds=60)
    event = {"tool_name": "Bash", "tool_input": {"command": "git merge some-branch"}, "cwd": REPO_ROOT}
    # 有効期限を過去に書き換えて失効を再現する
    import json

    path = store._path(permit.id)
    data = json.loads(path.read_text())
    data["expires_at"] = permit.created_at - 1
    path.write_text(json.dumps(data))
    code, _msg = evaluate(event, store)
    assert code == 2


def test_gh_pr_merge_without_permit_is_blocked(store):
    event = {"tool_name": "Bash", "tool_input": {"command": "gh pr merge 123 --squash"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 2


def test_gh_pr_merge_with_permit_is_allowed(store, repo_identity):
    store.create(repo=repo_identity, action="gh-pr-merge", target="pr:123", ttl_seconds=60)
    event = {"tool_name": "Bash", "tool_input": {"command": "gh pr merge 123 --squash"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 0


def test_mcp_merge_pull_request_without_permit_is_blocked(store):
    event = {
        "tool_name": "mcp__github__merge_pull_request",
        "tool_input": {"owner": "gotomts", "repo": "dotfiles", "pull_number": 52},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_mcp_merge_pull_request_with_permit_is_allowed(store):
    store.create(repo="github.com/gotomts/dotfiles", action="gh-pr-merge", target="pr:52", ttl_seconds=60)
    event = {
        "tool_name": "mcp__github__merge_pull_request",
        "tool_input": {"owner": "gotomts", "repo": "dotfiles", "pull_number": 52},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 0


def test_gh_stack_merge_without_permit_is_blocked(store):
    event = {"tool_name": "Bash", "tool_input": {"command": "gh stack merge 128"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 2


def test_gh_stack_merge_with_permit_is_allowed_single_operation(store, repo_identity):
    # 1 個の permit が「stack 全体を 1 回の操作で merge する」ことに対応する。
    store.create(repo=repo_identity, action="gh-stack-merge", target="pr:128", ttl_seconds=60)
    event = {"tool_name": "Bash", "tool_input": {"command": "gh stack merge 128"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 0
    # 消費済みなので同じ stack を再度 merge しようとするとブロックされる
    code2, _msg2 = evaluate(event, store)
    assert code2 == 2


def test_gh_pr_merge_permit_does_not_authorize_stack_merge(store, repo_identity):
    # gh-pr-merge 用の permit は gh-stack-merge を通さない (action が一致しない)
    store.create(repo=repo_identity, action="gh-pr-merge", target="pr:128", ttl_seconds=60)
    event = {"tool_name": "Bash", "tool_input": {"command": "gh stack merge 128"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 2


def test_rest_merge_async_endpoint_with_permit_is_allowed(store):
    store.create(repo="github.com/owner/repo", action="gh-stack-merge", target="pr:9", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "curl -X PUT https://api.github.com/repos/owner/repo/pulls/9/merge-async"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 0


def test_git_merge_abort_is_always_allowed(store):
    event = {"tool_name": "Bash", "tool_input": {"command": "git merge --abort"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 0


def test_stale_permit_from_other_action_does_not_satisfy_git_merge(store, repo_identity):
    # gh-pr-merge 用の permit は git-merge を通さない (action も一致条件)
    store.create(repo=repo_identity, action="gh-pr-merge", target="branch:some-branch", ttl_seconds=60)
    event = {"tool_name": "Bash", "tool_input": {"command": "git merge some-branch"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 2


def test_main_reads_event_from_stdin_json(tmp_path, monkeypatch):
    monkeypatch.setattr("guard.PermitStore", lambda: PermitStore(base_dir=tmp_path / "merge-permits"))
    stdin_text = (
        '{"tool_name": "Bash", "tool_input": {"command": "git merge x"}, "cwd": "%s"}' % REPO_ROOT
    )
    code = main([], stdin_text, {})
    assert code == 2


# ============================================================================
# 独立レビューで確認された PoC の回帰テスト
# ============================================================================


# --- (1) malformed/missing hook event は fail-closed でブロックする ---------
# 修正前は event を解析できない (tool_name も分からない) 場合、
# `_attempts_from_event` が `[]` を返して「merge ではない」= 許可、という
# fail-open になっていた。settings.json はこのガードを Bash /
# mcp__github__merge_pull_request の matcher にしか配線していないため、
# 呼ばれた時点でどちらかのはずであり、解析できない = merge の可能性を
# 排除できない、として block しなければならない。


def test_poc_empty_event_fails_closed(store):
    code, msg = evaluate({}, store)
    assert code == 2
    assert "解析できなかった" in msg


def test_poc_bash_tool_input_missing_command_key_fails_closed(store):
    # command キー自体が無い (壊れた/想定外の tool_input)。空文字列の command
    # (キーはあるが値が "") とは区別し、キー欠落は block する。
    event = {"tool_name": "Bash", "tool_input": {"description": "no command field"}, "cwd": REPO_ROOT}
    code, msg = evaluate(event, store)
    assert code == 2
    assert "解析できなかった" in msg


def test_bash_with_genuinely_empty_command_is_still_allowed(store):
    # 空文字列の command は「キーはあるが空」であり malformed ではない。
    # fail-closed 化が正常系を壊していないことの確認。
    event = {"tool_name": "Bash", "tool_input": {"command": ""}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 0


def test_poc_mcp_merge_tool_missing_fields_fails_closed(store):
    event = {
        "tool_name": "mcp__github__merge_pull_request",
        "tool_input": {"owner": "gotomts"},  # repo / pull_number が欠けている
        "cwd": REPO_ROOT,
    }
    code, msg = evaluate(event, store)
    assert code == 2
    assert "解析できなかった" in msg


def test_poc_main_with_empty_stdin_and_no_env_fails_closed(tmp_path, monkeypatch):
    monkeypatch.setattr("guard.PermitStore", lambda: PermitStore(base_dir=tmp_path / "merge-permits"))
    code = main([], "", {})
    assert code == 2


# --- (2) `-R`/`--repo` を正しく検出し、明示された repo に permit を束縛する ---
# 修正前は `-R` (短縮形) が検出されず、`--repo owner/repo` (host 省略) も
# 正規化されずに「カレント repo 向けの permit」と別文字列判定になっていた。
# PoC: カレント repo (dotfiles) 向けの正当な permit を持つ攻撃者が、
# `-R` で別リポジトリを明示して同じ permit を転用できるかを検証する。


def test_poc_dash_r_flag_targets_different_repo_and_is_blocked(store, repo_identity):
    # カレント repo (dotfiles) 向けの permit しか無い状態で、-R により
    # 明示的に別リポジトリを指定した gh pr merge は、その別リポジトリ用の
    # permit が無いのでブロックされなければならない。
    store.create(repo=repo_identity, action="gh-pr-merge", target="pr:42", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "gh pr merge 42 -R attacker-owner/other-repo"},
        "cwd": REPO_ROOT,
    }
    code, msg = evaluate(event, store)
    assert code == 2
    assert "github.com/attacker-owner/other-repo" in msg


def test_dash_r_flag_with_matching_permit_is_allowed(store):
    store.create(repo="github.com/owner/repo", action="gh-pr-merge", target="pr:42", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "gh pr merge 42 -R owner/repo"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 0


# --- (3) cd で別リポジトリへ移ってから merge しても static cwd の permit を
#         転用できない -------------------------------------------------------
# 修正前は event の cwd (Bash tool 呼び出し開始時点の静的な値) だけを見ており、
# コマンド文字列内で `cd` した後の実際の実行先ディレクトリを無視していた。
# PoC: カレント repo (dotfiles) 向けの permit を持つ状態で、`cd /tmp &&
# git merge x` のように無関係なディレクトリへ移ってから merge すると、
# 修正前は static cwd (dotfiles) 経由で repo が解決されて許可されてしまっていた。


def test_poc_cd_to_unrelated_dir_before_merge_is_blocked(store, repo_identity):
    store.create(repo=repo_identity, action="git-merge", target="branch:x", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "cd /tmp && git merge x"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    # /tmp は git repo ではないため repo 解決に失敗するか、あるいは static cwd
    # 由来の permit とは異なる repo 識別子になり、いずれにせよブロックされる
    # (修正前は static cwd = dotfiles で解決されて許可されていた)。
    assert code == 2


def test_cd_with_shell_variable_target_is_ambiguous_and_blocked(store, repo_identity):
    store.create(repo=repo_identity, action="git-merge", target="branch:x", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "cd $SOME_OTHER_REPO && git merge x"},
        "cwd": REPO_ROOT,
    }
    code, msg = evaluate(event, store)
    assert code == 2
    assert "cd/pushd" in msg or "作業ディレクトリ" in msg


def test_cd_into_subdirectory_of_same_repo_still_resolves_and_is_allowed(store, repo_identity):
    # cd 追跡は「別リポジトリへの回避」を防ぐためのものであり、同一リポジトリの
    # サブディレクトリへの cd まで一律ブロックするものではないことの確認。
    subdir = str(Path(REPO_ROOT) / "claude")
    if not Path(subdir).is_dir():
        pytest.skip("claude/ サブディレクトリが無いチェックアウト")
    store.create(repo=repo_identity, action="git-merge", target="branch:x", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "cd claude && git merge x"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 0


# --- (4) git global option (`-c key=value` 等) が検出を素通りさせない ---------
# 修正前は `_GIT_MERGE` の正規表現が `-C <path>` 以外のグローバルオプションを
# 想定しておらず、`git -c k=v merge x` はそもそも「検出 0 件」= 無許可で
# 通過するバイパスだった。


def test_poc_git_dash_c_global_option_no_longer_bypasses_guard(store):
    # permit を一切発行しない状態で block されることを確認する
    # (修正前はそもそも検出されず allow されていた)。
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "git -c user.name=x merge some-branch"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_git_dash_c_global_option_with_matching_permit_is_allowed(store, repo_identity):
    store.create(repo=repo_identity, action="git-merge", target="branch:some-branch", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "git -c user.name=x merge some-branch"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 0


# ============================================================================
# 第三者レビュー (2回目) が実機 PoC で確認した検出漏れの回帰テスト
# ============================================================================
# `_is_command_position` が subshell `(` / brace group `{` / 否定 `!` /
# シェルキーワード (then/do/else/elif) の直後をコマンド開始位置と認識せず、
# それらの直後に置かれた `git merge` が検出 0 件 = 無許可で通過していた。
# 1回目のレビュー指摘 (git global option 対応) を弱めていないことは、既存の
# `test_poc_git_dash_c_global_option_no_longer_bypasses_guard` /
# `test_git_dash_c_global_option_with_matching_permit_is_allowed` が
# 引き続き green であることで確認する (このファイル内で一緒に実行される)。


def test_poc_if_then_semicolon_no_longer_bypasses_guard(store):
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "if cond; then git merge some-branch; fi"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_if_then_semicolon_always_blocked_even_with_matching_permit(store, repo_identity):
    # 第六回レビューの設計転換: git の直前コンテキストが「文字列先頭 or
    # ;&|改行のみ」でなければ単純とみなさない。"then" はキーワードであって
    # separator 文字ではないため、"; then git merge ..." の "git" は
    # 直前が "then" という単語であり単純判定を満たさない。有効な permit が
    # あっても常に block される。
    store.create(repo=repo_identity, action="git-merge", target="branch:some-branch", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "if cond; then git merge some-branch; fi"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_poc_subshell_parens_always_blocked_even_without_permit(store):
    event = {"tool_name": "Bash", "tool_input": {"command": "(git merge some-branch)"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 2


def test_subshell_parens_always_blocked_even_with_matching_permit(store, repo_identity):
    # 第六回レビューの設計転換: subshell は「単純な形」ではないため、有効な
    # permit があっても常に block する (複雑な形を許可対象にしないことで、
    # redirect/wrapper/substitution を個別に正しくパースし続ける必要を無くす)。
    store.create(repo=repo_identity, action="git-merge", target="branch:some-branch", ttl_seconds=60)
    event = {"tool_name": "Bash", "tool_input": {"command": "(git merge some-branch)"}, "cwd": REPO_ROOT}
    code, msg = evaluate(event, store)
    assert code == 2
    assert "常に block" in msg


def test_poc_brace_group_always_blocked_even_without_permit(store):
    event = {"tool_name": "Bash", "tool_input": {"command": "{ git merge some-branch; }"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 2


def test_brace_group_always_blocked_even_with_matching_permit(store, repo_identity):
    store.create(repo=repo_identity, action="git-merge", target="branch:some-branch", ttl_seconds=60)
    event = {"tool_name": "Bash", "tool_input": {"command": "{ git merge some-branch; }"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 2


def test_poc_negation_bang_always_blocked_even_without_permit(store):
    event = {"tool_name": "Bash", "tool_input": {"command": "! git merge some-branch"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 2


def test_negation_bang_always_blocked_even_with_matching_permit(store, repo_identity):
    store.create(repo=repo_identity, action="git-merge", target="branch:some-branch", ttl_seconds=60)
    event = {"tool_name": "Bash", "tool_input": {"command": "! git merge some-branch"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 2


def test_poc_do_keyword_always_blocked_even_without_permit(store):
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "for i in 1 2; do git merge some-branch; done"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_do_keyword_always_blocked_even_with_matching_permit(store, repo_identity):
    store.create(repo=repo_identity, action="git-merge", target="branch:some-branch", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "for i in 1 2; do git merge some-branch; done"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_poc_else_keyword_no_longer_bypasses_guard(store):
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "if false; then true; else git merge some-branch; fi"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_else_keyword_always_blocked_even_with_matching_permit(store, repo_identity):
    store.create(repo=repo_identity, action="git-merge", target="branch:some-branch", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "if false; then true; else git merge some-branch; fi"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_poc_elif_keyword_no_longer_bypasses_guard(store):
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "if false; then true; elif true; then git merge some-branch; fi"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_elif_keyword_always_blocked_even_with_matching_permit(store, repo_identity):
    store.create(repo=repo_identity, action="git-merge", target="branch:some-branch", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "if false; then true; elif true; then git merge some-branch; fi"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_poc_newline_separated_still_blocked_without_permit(store):
    # 改行区切りは1回目の修正で既に効いていたが、今回のキーワード対応と
    # 合わせて回帰していないことを guard レベルでも確認する。
    event = {"tool_name": "Bash", "tool_input": {"command": "true\ngit merge some-branch"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 2


def test_newline_separated_with_matching_permit_is_allowed(store, repo_identity):
    store.create(repo=repo_identity, action="git-merge", target="branch:some-branch", ttl_seconds=60)
    event = {"tool_name": "Bash", "tool_input": {"command": "true\ngit merge some-branch"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 0


def test_poc_then_on_own_line_still_blocked_without_permit(store):
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "if cond\nthen\n  git merge some-branch\nfi"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_then_on_own_line_is_simple_form_allowed_with_matching_permit(store, repo_identity):
    # 改行はハード区切りなので、"then" が独立した行にある場合は git 自体の
    # 直前コンテキストが改行のみになり単純形と判定される (同一行の
    # "; then git merge" とは異なる)。この非対称性を明示しておく。
    store.create(repo=repo_identity, action="git-merge", target="branch:some-branch", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "if cond\nthen\n  git merge some-branch\nfi"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 0


# --- 括弧検出の副次修正: `(git merge X)` を検出できるようにした結果、
# cwd の ambiguous 判定 (レビュー(1)指摘 (3) 由来) が「未閉じの `(` があれば
# 常に ambiguous」という粗い判定のままだと、cd を伴わない subshell 単体
# (`(git merge X)`) まで常時ブロックしてしまい、有効な permit があっても
# 通せない回帰になっていた。cd の有無・subshell が merge 呼び出し前に
# 閉じているかで判定するよう修正したことの確認。


def test_cd_inside_still_open_subshell_resolves_correctly(store):
    # subshell がまだ閉じていない状態での cd はそのまま効くべき
    # (ambiguous 誤判定にならない)。/tmp は git repo ではないので
    # "local:<realpath>" 識別子になる。ここでは repo 不一致で block される
    # ことをもって「ambiguous ではなく正常に repo 解決された」ことを示す
    # (ambiguous メッセージ文言が出ないことを確認する)。
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "(cd /tmp && git merge some-branch)"},
        "cwd": REPO_ROOT,
    }
    code, msg = evaluate(event, store)
    assert code == 2
    assert "local:/tmp" in msg or "local:/private/tmp" in msg
    assert "作業ディレクトリが確定できない" not in msg


def test_cd_inside_subshell_that_closes_before_merge_is_ambiguous(store, repo_identity):
    # subshell が merge 呼び出しより前に閉じている場合、内部の cd の効果が
    # 外側へ伝播するかどうかは安全に判定できないため ambiguous として block
    # する (permit があっても block されることを確認する)。
    store.create(repo=repo_identity, action="git-merge", target="branch:some-branch", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "(cd /tmp); git merge some-branch"},
        "cwd": REPO_ROOT,
    }
    code, msg = evaluate(event, store)
    assert code == 2
    assert "作業ディレクトリが確定できない" in msg


# --- 第三者レビュー (3回目) 指摘の回帰: `_COMMAND_START_KEYWORDS` に `if` が
# 欠けており、merge そのものが if の条件式になっているケース
# (`if git merge X; then ...; fi`) が検出 0 件 = 無許可で通過していた。


def test_poc_if_condition_no_longer_bypasses_guard(store):
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "if git merge some-branch; then true; fi"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_if_condition_always_blocked_even_with_matching_permit(store, repo_identity):
    store.create(repo=repo_identity, action="git-merge", target="branch:some-branch", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "if git merge some-branch; then true; fi"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


# ============================================================================
# 第四回レビュー指摘の回帰テスト (guard レベル、実機相当の block/allow PoC)
# ============================================================================
# 許可リスト方式 (_is_command_position) を否定リスト方式
# (_is_plausible_git_invocation) に置き換えたことで、backtick/command
# substitution・redirection・環境変数代入・wrapper コマンドの直後に置かれた
# git merge を正しく検出できるようになった。ただし第六回レビューの設計転換
# (`_is_simple_supported_form`) により、これらはすべて「単純な形」ではない
# ため、検出はするが permit の有無に関わらず常に block する
# (「複雑な形は解析して許可するのではなく一律拒否する」方針)。


def test_poc_backtick_command_substitution_always_blocked_without_permit(store):
    event = {"tool_name": "Bash", "tool_input": {"command": "echo `git merge some-branch`"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 2


def test_backtick_command_substitution_always_blocked_even_with_matching_permit(store, repo_identity):
    store.create(repo=repo_identity, action="git-merge", target="branch:some-branch", ttl_seconds=60)
    event = {"tool_name": "Bash", "tool_input": {"command": "echo `git merge some-branch`"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 2


def test_poc_dollar_paren_command_substitution_always_blocked_without_permit(store):
    event = {"tool_name": "Bash", "tool_input": {"command": "echo $(git merge some-branch)"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 2


def test_dollar_paren_command_substitution_always_blocked_even_with_matching_permit(store, repo_identity):
    store.create(repo=repo_identity, action="git-merge", target="branch:some-branch", ttl_seconds=60)
    event = {"tool_name": "Bash", "tool_input": {"command": "echo $(git merge some-branch)"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 2


def test_poc_leading_redirect_always_blocked_without_permit(store):
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "2>/dev/null git merge some-branch"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_leading_redirect_always_blocked_even_with_matching_permit(store, repo_identity):
    store.create(repo=repo_identity, action="git-merge", target="branch:some-branch", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "2>/dev/null git merge some-branch"},
        "cwd": REPO_ROOT,
    }
    code, msg = evaluate(event, store)
    assert code == 2
    assert "常に block" in msg


def test_poc_trailing_redirect_always_blocked_even_with_matching_permit(store, repo_identity):
    # 第五回レビュー時点では「target が redirect に汚染されず正しく抽出
    # される」ことをもって許可していたが、第六回レビューの設計転換により
    # redirect を含む形は (target 抽出の正確さに関わらず) 単純な形とは
    # みなさず常に block する。複合 ampersand redirect (`2>&1` 等) を
    # 個別に正しく解釈できるかどうかに依存しない、より保守的な設計。
    store.create(repo=repo_identity, action="git-merge", target="branch:some-branch", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "git merge some-branch > /tmp/log 2>&1"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_poc_env_assignment_prefix_always_blocked_without_permit(store):
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "FOO=bar git merge some-branch"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_env_assignment_prefix_always_blocked_even_with_matching_permit(store, repo_identity):
    store.create(repo=repo_identity, action="git-merge", target="branch:some-branch", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "FOO=bar git merge some-branch"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_poc_git_dir_env_override_always_blocked_even_with_permit(store, repo_identity):
    # GIT_DIR= は -C 相当の repo 切り替え力を持つ。env 代入経由の呼び出しは
    # そもそも「単純な形」ではないため、lib.py 側の GIT_DIR 専用 ambiguous
    # 判定に到達する前に unsafe_form で block される。
    store.create(repo=repo_identity, action="git-merge", target="branch:some-branch", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "GIT_DIR=/other/repo git merge some-branch"},
        "cwd": REPO_ROOT,
    }
    code, msg = evaluate(event, store)
    assert code == 2
    assert "常に block" in msg


def test_poc_wrapper_sudo_always_blocked_without_permit(store):
    event = {"tool_name": "Bash", "tool_input": {"command": "sudo git merge some-branch"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 2


def test_wrapper_sudo_always_blocked_even_with_matching_permit(store, repo_identity):
    store.create(repo=repo_identity, action="git-merge", target="branch:some-branch", ttl_seconds=60)
    event = {"tool_name": "Bash", "tool_input": {"command": "sudo git merge some-branch"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 2


def test_poc_wrapper_time_no_longer_bypasses_guard(store):
    event = {"tool_name": "Bash", "tool_input": {"command": "time git merge some-branch"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 2


def test_poc_wrapper_env_no_longer_bypasses_guard(store):
    event = {"tool_name": "Bash", "tool_input": {"command": "env git merge some-branch"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 2


def test_poc_wrapper_nice_with_flag_value_no_longer_bypasses_guard(store):
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "nice -n 10 git merge some-branch"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_wrapper_nice_with_flag_value_always_blocked_even_with_matching_permit(store, repo_identity):
    store.create(repo=repo_identity, action="git-merge", target="branch:some-branch", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "nice -n 10 git merge some-branch"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_poc_wrapper_nohup_no_longer_bypasses_guard(store):
    event = {"tool_name": "Bash", "tool_input": {"command": "nohup git merge some-branch"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 2


def test_poc_wrapper_command_no_longer_bypasses_guard(store):
    event = {"tool_name": "Bash", "tool_input": {"command": "command git merge some-branch"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 2


def test_poc_wrapper_exec_no_longer_bypasses_guard(store):
    event = {"tool_name": "Bash", "tool_input": {"command": "exec git merge some-branch"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 2


def test_poc_chained_wrappers_no_longer_bypass_guard(store):
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "sudo nice time git merge some-branch"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_chained_wrappers_always_blocked_even_with_matching_permit(store, repo_identity):
    store.create(repo=repo_identity, action="git-merge", target="branch:some-branch", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "sudo nice time git merge some-branch"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_poc_separator_semicolon_still_blocked_without_permit(store):
    event = {"tool_name": "Bash", "tool_input": {"command": "true; git merge some-branch"}, "cwd": REPO_ROOT}
    code, _msg = evaluate(event, store)
    assert code == 2


def test_benign_commands_still_allowed_at_guard_level(store):
    for cmd in ("ls -la", "git status", "git merge-base main HEAD", "FOO=bar ls -la", "time ls -la"):
        event = {"tool_name": "Bash", "tool_input": {"command": cmd}, "cwd": REPO_ROOT}
        code, _msg = evaluate(event, store)
        assert code == 0, f"expected {cmd!r} to be allowed, got block"


# ============================================================================
# 最終レビュー指摘の回帰テスト (guard レベル): redirect が対象引数より前に
# 来ると target 抽出が空になり `branch:HEAD`/`pr:current` に化けていた
# ("現在ブランチ/現在スタック向け" の汎用 permit が、実際には明示的な別
# target への merge を通してしまう target-binding バイパス)。
# ============================================================================


def test_exploit_git_merge_redirect_before_target_blocked_without_matching_permit(store):
    # 明示 target 用の permit が無い状態では block される
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "git merge >log branch-name"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_exploit_git_merge_redirect_before_target_not_authorized_by_generic_current_permit(store, repo_identity):
    # PoC の核心: "現在ブランチ" 向けの汎用 permit (target 省略 = HEAD) は、
    # redirect で偽装された明示的な別 branch への merge を通してはならない。
    store.create(repo=repo_identity, action="git-merge", target="branch:HEAD", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "git merge >log branch-name"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_git_merge_redirect_before_target_always_blocked_even_with_exact_matching_permit(store, repo_identity):
    # 第六回レビューの設計転換: redirect を含む形は、target 抽出の結果が
    # permit と厳密に一致していても「単純な形」ではないため常に block する。
    # これにより複合 ampersand redirect (`2>&1`/`&>`/`>&` 等) を個別に
    # 正しく解釈できるかどうかに依存しなくなる。
    store.create(repo=repo_identity, action="git-merge", target="branch:branch-name", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "git merge >log branch-name"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_git_merge_redirect_after_target_always_blocked_even_with_exact_matching_permit(store, repo_identity):
    # target-after variant: redirect が対象の後ろに来ても同様に常に block する
    store.create(repo=repo_identity, action="git-merge", target="branch:branch-name", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "git merge branch-name >log"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_exploit_gh_pr_merge_redirect_before_target_blocked_without_matching_permit(store):
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "gh pr merge >log 42"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_exploit_gh_pr_merge_redirect_before_target_not_authorized_by_generic_current_permit(store, repo_identity):
    # "現在ブランチの PR" 向けの汎用 permit は PR #42 への merge を
    # 権限委譲してはならない。
    store.create(repo=repo_identity, action="gh-pr-merge", target="branch:HEAD", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "gh pr merge >log 42"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_gh_pr_merge_redirect_before_target_always_blocked_even_with_exact_matching_permit(store, repo_identity):
    store.create(repo=repo_identity, action="gh-pr-merge", target="pr:42", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "gh pr merge >log 42"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_gh_pr_merge_redirect_after_target_always_blocked_even_with_exact_matching_permit(store, repo_identity):
    store.create(repo=repo_identity, action="gh-pr-merge", target="pr:42", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "gh pr merge 42 >log"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_exploit_gh_stack_merge_redirect_before_target_blocked_without_matching_permit(store):
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "gh stack merge >log 7"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_exploit_gh_stack_merge_redirect_before_target_not_authorized_by_generic_current_permit(
    store, repo_identity
):
    # "現在の stack" 向けの汎用 permit (target 省略 = pr:current) は
    # stack #7 への merge を権限委譲してはならない。
    store.create(repo=repo_identity, action="gh-stack-merge", target="pr:current", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "gh stack merge >log 7"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_gh_stack_merge_redirect_before_target_always_blocked_even_with_exact_matching_permit(store, repo_identity):
    store.create(repo=repo_identity, action="gh-stack-merge", target="pr:7", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "gh stack merge >log 7"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


def test_gh_stack_merge_redirect_after_target_always_blocked_even_with_exact_matching_permit(store, repo_identity):
    store.create(repo=repo_identity, action="gh-stack-merge", target="pr:7", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": "gh stack merge 7 >log"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2


# ============================================================================
# 「最終レビュー限定の狭いレビュー」指摘: 複合 ampersand redirect
# (`2>&1` / `&>` / `>&`) を含む形も、単純形とはみなさず常に block すること。
# `_is_simple_supported_form` は `<`/`>` の存在有無だけで判定するため、
# これらの複合演算子を個別に区別する必要が無いことをデモする。
# ============================================================================


@pytest.mark.parametrize(
    "redirect_form",
    [
        pytest.param("2>&1", id="stderr-to-stdout"),
        pytest.param("&>", id="stdout-and-stderr-both"),
        pytest.param(">&", id="dup-form"),
        pytest.param("&>>", id="append-stdout-and-stderr"),
        pytest.param(">>", id="append-stdout"),
    ],
)
def test_composite_ampersand_redirect_always_blocked_without_permit(store, redirect_form):
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": f"git merge some-branch {redirect_form} /tmp/log"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2, f"expected {redirect_form!r} form to be blocked"


@pytest.mark.parametrize(
    "redirect_form",
    [
        pytest.param("2>&1", id="stderr-to-stdout"),
        pytest.param("&>", id="stdout-and-stderr-both"),
        pytest.param(">&", id="dup-form"),
        pytest.param("&>>", id="append-stdout-and-stderr"),
        pytest.param(">>", id="append-stdout"),
    ],
)
def test_composite_ampersand_redirect_always_blocked_even_with_matching_permit(store, repo_identity, redirect_form):
    # PoC の核心: 複合演算子を「正しく解釈できたかどうか」に関わらず、
    # redirect が 1 つでもあれば permit の有無を問わず block される。
    store.create(repo=repo_identity, action="git-merge", target="branch:some-branch", ttl_seconds=60)
    event = {
        "tool_name": "Bash",
        "tool_input": {"command": f"git merge some-branch {redirect_form} /tmp/log"},
        "cwd": REPO_ROOT,
    }
    code, _msg = evaluate(event, store)
    assert code == 2, f"expected {redirect_form!r} form to still be blocked even with a matching permit"


# ============================================================================
# 独立レビュー再現 PoC の回帰テスト (guard レベル)
# ============================================================================


@pytest.mark.parametrize(
    "command",
    [
        pytest.param("git &>log merge branch-name", id="ampersand-gt-before-subcommand"),
        pytest.param("git >&2 merge branch-name", id="gt-ampersand-before-subcommand"),
        pytest.param("git 2>&1 merge branch-name", id="fd-dup-before-subcommand"),
    ],
)
def test_poc_redirect_before_subcommand_blocked_with_empty_permit_store(store, command):
    # store は空 (create を一切呼んでいない)。修正前はこれらが検出 0 件で
    # 無条件に許可されていた (evaluate() が attempts=[] を見て code=0 を
    # 返していた)。permit が 1 件も無い状態で block されることを確認する。
    event = {"tool_name": "Bash", "tool_input": {"command": command}, "cwd": REPO_ROOT}
    code, msg = evaluate(event, store)
    assert code == 2, f"expected {command!r} to be blocked by an empty permit store, got allow (bypass)"
    assert "merge-permit" in msg


def test_explicit_dash_c_originless_repo_cannot_be_authorized_by_session_repo_permit(store, repo_identity, tmp_path):
    # 核心: セッション repo (このチェックアウト自身) 向けの正当な permit が
    # 存在していても、-C が指す origin 未設定の別 repo への merge を
    # 権限委譲してはならない。
    import subprocess

    originless = tmp_path / "originless-repo"
    originless.mkdir()
    subprocess.run(["git", "init", "-q", "-b", "main", str(originless)], check=True)
    subprocess.run(["git", "-C", str(originless), "config", "user.email", "t@example.com"], check=True)
    subprocess.run(["git", "-C", str(originless), "config", "user.name", "t"], check=True)
    (originless / "f.txt").write_text("hi\n")
    subprocess.run(["git", "-C", str(originless), "add", "-A"], check=True)
    subprocess.run(["git", "-C", str(originless), "commit", "-q", "-m", "init"], check=True)

    # セッション repo (dotfiles) 向けの permit を発行する。攻撃者が -C で
    # 別 repo を明示しても、この permit を悪用できてはならない。
    store.create(repo=repo_identity, action="git-merge", target="branch:branch-name", ttl_seconds=60)

    event = {
        "tool_name": "Bash",
        "tool_input": {"command": f"git -C {originless} merge branch-name"},
        "cwd": REPO_ROOT,
    }
    code, msg = evaluate(event, store)
    assert code == 2, "session repo permit must not authorize merge in an unrelated -C target (bypass)"
    assert "作業ディレクトリが確定できない" in msg
