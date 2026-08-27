#!/usr/bin/env python3
"""PreToolUse hook: Bash の破壊的コマンドをブロックする。

stdin の PreToolUse JSON から `.tool_input.command` を取り、shell の字句として
トークン化してからコマンド語の位置に立つ実行ファイル名とその引数だけを見る。
正規表現の部分一致だと commit message・grep パターン・echo・ドキュメント表示に
現れた危険語まで誤検出するため、引用符で囲まれた文字列は 1 トークンに畳んで
コマンドとしては解釈しない。ただし単一引用符の外にある `$(...)` と `` `...` ``
は shell が実際に実行するので、中身を独立した断片として取り出して再帰的に見る。

`git push --force-with-lease` は上流の巻き戻しを検出して中断するため通す。
オプション境界を見ずに `--force` を部分一致させると、これも巻き添えで落ちる。

exit code は 0 (通過) か 2 (ブロック) のみ。それ以外の非ゼロは Claude Code が
non-blocking error として扱い hook が素通りするため、例外は全て 0 に倒す。
"""

import json
import os
import re
import shlex
import sys

# shlex の punctuation_chars が 1 トークンに束ねる制御・リダイレクト文字。
CONTROL_CHARS = set("();<>|&")

# `if git push --force; then` のように、直後の語がそのままコマンドになる shell 予約語。
SHELL_KEYWORDS = {
    "!", "{", "}", "case", "coproc", "do", "done", "elif", "else", "esac", "fi",
    "for", "function", "if", "in", "select", "then", "time", "until", "while",
}

# 本体コマンドを引数として受け取る前置コマンド。オプションや `timeout 30` の
# duration など語数が可変なので、これ以降は本体が現れるまで読み飛ばす。
WRAPPERS = {
    "builtin", "command", "doas", "env", "exec", "ionice", "nice", "nohup",
    "setsid", "stdbuf", "sudo", "timeout", "watch", "xargs",
}

# 読み飛ばしを打ち切る対象コマンド (basename で判定)。
TARGETS = {"git", "rm", "dd"}

ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")

# 値を 1 つ取る git のグローバルオプション (サブコマンド探索でスキップする)。
GIT_GLOBAL_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}

# rm -rf の削除先として危険とみなす接頭辞。"/" が絶対パス全般を覆う。
RM_DANGEROUS_PREFIXES = ("/", "~", "$HOME", "${HOME}")

BLOCK_DEVICE_PREFIX = "/dev/sd"

# 置換の入れ子は現実的な深さで打ち切る。
MAX_DEPTH = 8


def read_balanced(source, start, opener, closer):
    """`start` から対応する閉じ括弧までを返す。閉じていなければ末尾まで。"""
    depth = 1
    i = start
    while i < len(source):
        ch = source[i]
        if ch == "\\":
            i += 2
            continue
        if ch == opener:
            depth += 1
        elif ch == closer:
            depth -= 1
            if depth == 0:
                return source[start:i], i + 1
        i += 1
    return source[start:], len(source)


def substitutions(source):
    """single quote の外にある `$(...)` / `` `...` `` の中身を返す。"""
    found = []
    quote = None
    i = 0
    while i < len(source):
        ch = source[i]
        if quote == "'":
            if ch == "'":
                quote = None
            i += 1
            continue
        if ch == "\\":
            i += 2
            continue
        if quote == '"':
            if ch == '"':
                quote = None
                i += 1
                continue
        elif ch in "'\"":
            quote = ch
            i += 1
            continue
        if ch == "$" and source[i + 1 : i + 2] == "(":
            body, i = read_balanced(source, i + 2, "(", ")")
            found.append(body)
            continue
        if ch == "`":
            end = source.find("`", i + 1)
            if end == -1:
                found.append(source[i + 1 :])
                break
            found.append(source[i + 1 : end])
            i = end + 1
            continue
        i += 1
    return found


def logical_lines(source):
    """引用符の外にある改行でコマンド行を切る (行継続はつなげたまま)。"""
    lines = []
    buf = []
    quote = None
    i = 0
    while i < len(source):
        ch = source[i]
        if ch == "\\" and quote != "'":
            buf.append(source[i : i + 2])
            i += 2
            continue
        if quote:
            if ch == quote:
                quote = None
            buf.append(ch)
            i += 1
            continue
        if ch in "'\"":
            quote = ch
            buf.append(ch)
            i += 1
            continue
        if ch == "\n":
            lines.append("".join(buf))
            buf = []
            i += 1
            continue
        buf.append(ch)
        i += 1
    lines.append("".join(buf))
    return lines


def tokenize(line):
    lexer = shlex.shlex(line, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    # `#` は shell では語頭でしかコメントにならない。shlex の既定に任せると
    # `curl 'http://x/#y'` のような語中の `#` 以降を落としてしまう。
    lexer.commenters = ""
    return list(lexer)


def segments(tokens):
    """制御演算子でコマンド単位に切り、リダイレクト先は別に集める。"""
    segs = []
    cur = []
    redirect_targets = []
    i = 0
    while i < len(tokens):
        tok = tokens[i]
        if tok and all(c in CONTROL_CHARS for c in tok):
            if "<" in tok or ">" in tok:
                if i + 1 < len(tokens):
                    redirect_targets.append(tokens[i + 1])
                    i += 2
                    continue
            elif cur:
                segs.append(cur)
                cur = []
            i += 1
            continue
        cur.append(tok)
        i += 1
    if cur:
        segs.append(cur)
    return segs, redirect_targets


def split_args(args):
    """`--` を境に flag と operand へ分ける。"""
    flags = []
    operands = []
    end_of_options = False
    for arg in args:
        if end_of_options:
            operands.append(arg)
            continue
        if arg == "--":
            end_of_options = True
            continue
        if arg.startswith("-") and arg != "-":
            flags.append(arg)
        else:
            operands.append(arg)
    return flags, operands


def short_letters(flag):
    """`-fd` のような短縮束ねのフラグ文字を返す。長オプションは空。"""
    if not flag.startswith("-") or flag.startswith("--") or len(flag) < 2:
        return ""
    body = flag[1:]
    return body if body.isalpha() else ""


def git_subcommand(args):
    i = 0
    while i < len(args):
        arg = args[i]
        if arg in GIT_GLOBAL_WITH_VALUE:
            i += 2
            continue
        if arg.startswith("-"):
            i += 1
            continue
        return arg, args[i + 1 :]
    return None, []


def check_git(args):
    sub, rest = git_subcommand(args)
    flags, operands = split_args(rest)
    if sub == "push":
        for flag in flags:
            # --force-with-lease / --force-if-includes は上流を確認して中断する
            # ため通す。オプション境界で一致させるので前方一致では引っかからない。
            if flag == "--force" or "f" in short_letters(flag):
                return "git push の強制上書き。--force-with-lease を使ってください"
        return None
    if sub == "reset":
        if "--hard" in flags:
            return "git reset --hard は作業ツリーを破棄します"
        return None
    if sub == "clean":
        for flag in flags:
            if flag == "--force" or "f" in short_letters(flag):
                return "git clean の強制削除。-n で対象を確認してください"
        return None
    return None


def check_rm(args):
    flags, operands = split_args(args)
    recursive = any(flag in ("--recursive", "-r", "-R") or set("rR") & set(short_letters(flag)) for flag in flags)
    force = any(flag == "--force" or "f" in short_letters(flag) for flag in flags)
    if not (recursive and force):
        return None
    for target in operands:
        if target.startswith(RM_DANGEROUS_PREFIXES):
            return "rm -rf による絶対パス/ホーム配下の再帰削除 (%s)" % target
    return None


def is_target(name):
    return name in TARGETS or name == "mkfs" or name.startswith("mkfs.")


def command_words(seg):
    """代入・shell 予約語・前置コマンドを剥がして、本体コマンド以降を返す。

    前置コマンドを剥がした後は語数が可変 (`sudo -u deploy git ...` /
    `timeout -k 5 30 git ...`) なので、対象コマンドが現れるまで読み飛ばす。
    前置コマンドが無い場合は先頭語だけを見る (`echo git push --force` のような
    引用符なしの説明文まで拾わないため)。
    """
    words = list(seg)
    after_wrapper = False
    while words:
        name = os.path.basename(words[0])
        if ASSIGNMENT.match(words[0]) or name in SHELL_KEYWORDS:
            words.pop(0)
            continue
        if name in WRAPPERS:
            words.pop(0)
            after_wrapper = True
            continue
        if after_wrapper and not is_target(name):
            words.pop(0)
            continue
        break
    return words


def check_segment(seg):
    words = command_words(seg)
    if not words:
        return None
    name = os.path.basename(words[0])
    args = words[1:]
    if name == "git":
        return check_git(args)
    if name == "rm":
        return check_rm(args)
    if name == "dd":
        if any(arg.startswith("if=") for arg in args):
            return "dd による raw コピー"
        return None
    if name == "mkfs" or name.startswith("mkfs."):
        return "mkfs によるファイルシステム作成"
    return None


def inspect(source, depth=0):
    if depth > MAX_DEPTH:
        return None
    for line in logical_lines(source):
        if not line.strip():
            continue
        try:
            tokens = tokenize(line)
        except ValueError:
            # 引用符が閉じていない行は字句解析できない。誤検出を避けて通す。
            continue
        segs, redirect_targets = segments(tokens)
        for target in redirect_targets:
            if target.startswith(BLOCK_DEVICE_PREFIX):
                return "ブロックデバイスへの書き込み (%s)" % target
        for seg in segs:
            reason = check_segment(seg)
            if reason:
                return reason
    for body in substitutions(source):
        reason = inspect(body, depth + 1)
        if reason:
            return reason
    return None


def main():
    raw = sys.stdin.read()
    if not raw.strip():
        return 0
    payload = json.loads(raw)
    if not isinstance(payload, dict):
        return 0
    tool_name = payload.get("tool_name")
    if tool_name is not None and tool_name != "Bash":
        return 0
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return 0
    command = tool_input.get("command")
    if not isinstance(command, str) or not command.strip():
        return 0
    reason = inspect(command)
    if reason:
        print("BLOCK: %s" % reason, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)
