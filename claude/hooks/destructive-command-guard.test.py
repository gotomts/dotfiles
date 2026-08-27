#!/usr/bin/env python3
"""destructive-command-guard.py の回帰テスト。

`python3 claude/hooks/destructive-command-guard.test.py` で実行する。
hook 本体はファイル名にハイフンを含み import できないため importlib で読む。
"""

import importlib.util
import json
import os
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
GUARD = os.path.join(HERE, "destructive-command-guard.py")

# リポジトリ内に __pycache__ を作らせない。
sys.dont_write_bytecode = True

_spec = importlib.util.spec_from_file_location("destructive_command_guard", GUARD)
guard = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(guard)


def run_hook(stdin_text):
    """hook を実プロセスとして起動し (exit code, stderr) を返す。"""
    proc = subprocess.run(
        [sys.executable, GUARD],
        input=stdin_text,
        capture_output=True,
        text=True,
    )
    return proc.returncode, proc.stderr


def payload(command, tool_name="Bash"):
    return json.dumps({"tool_name": tool_name, "tool_input": {"command": command}})


BLOCKED = [
    "git push --force origin HEAD",
    "git push -f origin HEAD",
    "git push origin HEAD --force",
    "git push --force",
    "git push -fu origin HEAD",
    "git -C /repo push --force origin main",
    "git push --force-with-lease --force origin HEAD",
    "git reset --hard HEAD~1",
    "git reset --hard",
    "git clean -fd",
    "git clean -f",
    "git clean -fdx",
    "rm -rf /usr/local",
    "rm -rf ~/Documents",
    "rm -rf $HOME/work",
    "sudo rm -rf /",
    'rm -rf "/etc/x"',
    "dd if=/dev/zero of=/tmp/img",
    "mkfs.ext4 /dev/sdb1",
    "echo boom > /dev/sda",
    "git status && git push --force origin HEAD",
    "npm test; git push -f origin HEAD",
    "echo $(git push --force origin HEAD)",
    'echo "$(git reset --hard)"',
    "echo `git push --force origin HEAD`",
    "git status\ngit push --force origin HEAD",
    "FOO=bar git push --force origin HEAD",
    "/usr/bin/git push --force origin HEAD",
    # shell の制御構文キーワードの直後。
    "if git push --force origin HEAD; then echo ok; fi",
    "if ! git push -f origin HEAD; then echo ng; fi",
    "if true; then git push --force origin HEAD; fi",
    "if false; then echo skip; else git reset --hard HEAD~1; fi",
    "if false; then echo a; elif true; then git clean -fd; fi",
    "while ! git push -f origin HEAD; do sleep 1; done",
    "until git push --force origin HEAD; do sleep 1; done",
    "for i in 1 2 3; do git push --force origin HEAD; done",
    "{ git push --force origin HEAD; }",
    "time git push --force origin HEAD",
    # 本体コマンドを引数に取る前置コマンドの後ろ。
    "timeout 30 git push --force origin HEAD",
    "timeout -k 5 30 git push -f origin HEAD",
    "timeout --preserve-status -k 5 30 git reset --hard HEAD~1",
    "sudo -u deploy git push --force origin HEAD",
    "env FOO=bar git push --force origin HEAD",
    "nice -n 10 git clean -fd",
    "xargs -0 git push --force origin HEAD",
    # heredoc の開始行に同居する実コマンド。
    "cat <<'EOF' > note.md; rm -rf /usr/local\nsafe\nEOF\n",
    # heredoc の終端より後ろは通常のコマンド行に戻る。
    "cat <<'EOF' > note.md\nsafe\nEOF\ngit push --force origin HEAD\n",
    "cat <<'EOF'\nsafe\nEOF\nsudo rm -rf /\n",
    "cat <<-'EOF'\n\tsafe\n\tEOF\n\tgit clean -fd\n",
    # heredoc より前で既に実行されている。
    "git reset --hard HEAD~1 && cat <<'EOF' > note.md\nsafe\nEOF\n",
    # 区切り語を quote していない heredoc の本文では置換が展開・実行される。
    "cat <<EOF > note.md\n$(git push --force origin HEAD)\nEOF\n",
    "cat <<EOF > note.md\n`git reset --hard HEAD~1`\nEOF\n",
    # 本文の引用符は展開を止めない。
    "cat <<EOF > note.md\n'$(git clean -fd)'\nEOF\n",
    # 算術式の左シフトは heredoc ではないので、後続行を本文として飲み込まない。
    "x=$((1 << 3))\ngit push --force origin HEAD\n",
    "(( i << 2 ))\ngit reset --hard HEAD~1\n",
    # 制御構文の直後も算術評価コマンドの位置。
    "if (( i << 2 )); then echo ok; fi\ngit push --force origin HEAD\n",
    "while (( n << 1 )); do break; done\ngit reset --hard HEAD~1\n",
    "until (( n << 1 )); do break; done\ngit clean -fd\n",
    "! (( n << 1 ))\nrm -rf /usr/local\n",
    "for ((i = 0; i < 3; i++)); do echo $i; done\nrm -rf /usr/local\n",
    # herestring も heredoc ではない。
    "grep force <<< 'git push --force origin HEAD'\ngit push --force origin HEAD\n",
    "cat <<<\"$note\"\ngit reset --hard HEAD~1\n",
    # コメント中の `<<` も heredoc ではない。
    "# 例: cat <<EOF ... EOF\ngit push --force origin HEAD\n",
    "echo hi # cat <<EOF\ngit reset --hard HEAD~1\n",
    # 区切り語で閉じない heredoc は誤認の疑いがあるため、本文を捨てずに読み直す。
    "cat <<'EOF'\ngit push --force origin HEAD\n",
    "cat <<EOF\nrm -rf /usr/local\n",
]

ALLOWED = [
    # force-with-lease はオプション境界で区別する。
    "git push --force-with-lease origin HEAD",
    "git push --force-with-lease=refs/heads/main:abc123 origin HEAD",
    "git push --force-if-includes --force-with-lease origin HEAD",
    "git push origin HEAD",
    "git push -u origin HEAD",
    "git status",
    "git clean -n",
    "git clean --dry-run",
    "git reset --soft HEAD~1",
    "git reset HEAD~1",
    "rm -rf ./build",
    "rm -rf node_modules",
    "rm -f /etc/hosts.bak",
    "dd of=/tmp/x bs=1",
    "ls /dev/sda",
    # 制御構文・前置コマンドの後ろでも lease 付きは通す。
    "if git push --force-with-lease origin HEAD; then echo ok; fi",
    "until git push --force-with-lease origin HEAD; do sleep 1; done",
    "timeout 30 git push --force-with-lease origin HEAD",
    "sudo -u deploy git push --force-with-lease origin HEAD",
    "for i in 1 2 3; do git push --force-with-lease origin HEAD; done",
    "if true; then git status; fi",
    "while read -r line; do echo \"$line\"; done",
]

# レビューで挙がった説明文の偽陽性。危険語は引用符の中や別コマンドの引数にある。
DESCRIPTIVE_TEXT = [
    'git commit -m "fix(hook): git push --force を禁止する"',
    "git commit -m 'chore: rm -rf / の誤検出を直す'",
    'git commit -m "revert: git reset --hard をやめた"',
    'grep -rn "rm -rf /" docs/',
    "grep -rnE 'git push .*--force' claude/",
    'echo "git reset --hard is destructive"',
    "echo 'git clean -fd wipes untracked files'",
    "cat docs/dangerous-commands.md",
    "printf '%s\\n' 'mkfs.ext4 /dev/sdb1'",
    # 枝名やパスの末尾に危険語が含まれるだけのケース。
    "git push origin feature/no-force",
    "git push origin hotfix-force",
    "git push origin refs/heads/force-with-lease",
    "git checkout -b fix/allow-pre-pr-force-with-lease",
    "rm -rf ./tmp/force",
    "git log --oneline --grep='git push --force'",
    # 制御構文の中にあっても、引用符で囲まれた説明文はコマンドではない。
    'if true; then echo "git push --force is banned"; fi',
    "for f in docs/*; do grep -n 'rm -rf /' \"$f\"; done",
    'if [ -n "$CI" ]; then git commit -m "docs: git reset --hard の注意書き"; fi',
    'while true; do echo "git clean -fd wipes untracked files"; break; done',
]

# heredoc の本文は shell がコマンドへ渡すデータで、実行されない。
HEREDOC_BODY_TEXT = [
    # quote した区切り語。本文は展開すらされない。
    "cat > docs/note.md <<'EOF'\n"
    "禁止: git push --force を使わない\n"
    "rm -rf / も実行しない\n"
    "EOF\n",
    'cat > docs/note.md <<"EOF"\ngit reset --hard は作業ツリーを破棄する\nEOF\n',
    "cat <<'EOF'\n$(git push --force origin HEAD)\nEOF\n",
    # quote していない区切り語でも、置換でない本文は素通しする。
    "cat > note.md <<EOF\ngit clean -fd wipes untracked files\nEOF\n",
    # 本文中の閉じない引用符で行の切り出しが壊れないこと。
    "cat <<'EOF'\ndon't run git clean -fd\nEOF\ngit status\n",
    # `<<-` は終端行の先頭タブを剥がして一致させる。
    "cat <<-'EOF'\n\tgit push --force origin HEAD\n\tEOF\n",
    # 1 行に複数の heredoc。宣言順に本文が続く。
    "cat <<'A' <<'B'\nrm -rf /\nA\ngit push --force origin HEAD\nB\n",
    # herestring は本文を持たない別物 (引用符付きのデータのまま)。
    "grep force <<< 'git push --force origin HEAD'",
    "grep force <<<'git push --force origin HEAD'\ngit status\n",
    # 区切り語で閉じない heredoc は本文を読み直すが、危険操作が無ければ通る。
    "cat <<'EOF'\nhello world\n",
    # 実運用の形: スクリプトを heredoc で流し込む。
    "python3 - <<'PY'\nprint('git push --force origin HEAD')\nPY\n",
    "ssh host bash -s <<'EOF'\nrm -rf /var/tmp/cache\nEOF\n",
]

# 語頭の `#` から行末まではコメントで、shell は読まない。
COMMENT_TEXT = [
    "echo ok # git push --force origin HEAD",
    "# rm -rf / と書いてあるだけの行\ngit status\n",
    "git status  # git reset --hard は使わない\n",
    # コメントは制御演算子より優先される (`;` の後ろまでコメント)。
    "echo ok # 補足; rm -rf /usr/local\n",
    # 語中の `#` はコメントではない (URL のフラグメント)。
    "curl -sS 'https://example.com/docs#git-push-force'",
    "curl -sS https://example.com/docs#git-push-force",
]

DEGENERATE = [
    ("", "stdin が空"),
    ("{}", "tool_input なし"),
    ('{"tool_input": {}}', "command なし"),
    ('{"tool_input": {"command": null}}', "command が null"),
    ('{"tool_input": {"command": "   "}}', "command が空白のみ"),
    ("not-json", "JSON として壊れている"),
    ("[1, 2, 3]", "オブジェクトでない"),
    (payload("rm -rf /", tool_name="Read"), "Bash 以外のツール"),
    ('{"tool_name": "Edit", "tool_input": {"file_path": "/etc/passwd"}}', "command を持たないツール"),
]


class InspectTest(unittest.TestCase):
    def test_blocked(self):
        for command in BLOCKED:
            with self.subTest(command=command):
                self.assertIsNotNone(guard.inspect(command), "block されるべき: %r" % command)

    def test_allowed(self):
        for command in ALLOWED:
            with self.subTest(command=command):
                self.assertIsNone(guard.inspect(command), "通すべき: %r" % command)

    def test_descriptive_text_is_not_a_command(self):
        for command in DESCRIPTIVE_TEXT:
            with self.subTest(command=command):
                self.assertIsNone(guard.inspect(command), "説明文なので通すべき: %r" % command)

    def test_heredoc_body_is_not_a_command(self):
        for command in HEREDOC_BODY_TEXT:
            with self.subTest(command=command):
                self.assertIsNone(guard.inspect(command), "heredoc 本文なので通すべき: %r" % command)

    def test_comment_is_not_a_command(self):
        for command in COMMENT_TEXT:
            with self.subTest(command=command):
                self.assertIsNone(guard.inspect(command), "コメントなので通すべき: %r" % command)

    def test_unbalanced_quote_does_not_crash(self):
        self.assertIsNone(guard.inspect('echo "unterminated'))


class HookProcessTest(unittest.TestCase):
    """settings.json から起動される実プロセスとしての契約。"""

    def test_blocked_exits_2_with_reason(self):
        for command in BLOCKED:
            with self.subTest(command=command):
                code, stderr = run_hook(payload(command))
                self.assertEqual(code, 2, "block されるべき: %r" % command)
                self.assertIn("BLOCK:", stderr)

    def test_allowed_exits_0(self):
        for command in ALLOWED + DESCRIPTIVE_TEXT + HEREDOC_BODY_TEXT + COMMENT_TEXT:
            with self.subTest(command=command):
                code, stderr = run_hook(payload(command))
                self.assertEqual(code, 0, "通すべき: %r (%s)" % (command, stderr))

    def test_degenerate_input_exits_0(self):
        for stdin_text, label in DEGENERATE:
            with self.subTest(case=label):
                code, stderr = run_hook(stdin_text)
                self.assertEqual(code, 0, "%s は通すべき (%s)" % (label, stderr))

    def test_exit_code_is_only_0_or_2(self):
        for stdin_text, _ in DEGENERATE:
            code, _stderr = run_hook(stdin_text)
            self.assertIn(code, (0, 2))


if __name__ == "__main__":
    unittest.main(verbosity=2)
