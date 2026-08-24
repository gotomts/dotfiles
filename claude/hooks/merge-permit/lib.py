"""merge-permit の共有ロジック。

guard.py (PreToolUse hook 本体) と cli.py (Hermes 向け permit 発行 CLI) の
両方から import される。検出ロジックと permit ストアを 1 箇所に集約し、
テスト (tests/test_lib.py) から直接ユニットテストできるようにするための分離。

設計:
- merge アクションの検出は正規表現ベース。シェルの完全なパースはしない
  (subshell / パイプ / 変数展開まで正しく解析するにはシェル実装そのものが
  要る)。コマンド文字列全体を対象に検索するため、`&&` / `;` / `|` / 改行の
  前後、subshell/brace group/backtick/command substitution の中、
  redirection・環境変数代入・wrapper コマンド (time/exec/env/nice/nohup/
  command/sudo) の直後にあっても検出できる。
- git-merge の検出は「コマンド開始位置として妥当なものを列挙する」許可
  リスト方式を取らない (3 回のレビューで 3 回の回帰を生んだモグラ叩きの
  反省)。代わりに `_is_plausible_git_invocation` が「`.git`/`--git-dir` の
  ようなパス/フラグ名の一部に `\bgit\b` が偶然マッチしただけ」と確信できる
  ケースだけを否定リストで除外し、それ以外は無条件に `_find_git_subcommand`
  へ渡す (そちらが `tokens[0] == "git"` の完全一致でさらに絞り込む)。
  判定に迷うものは常に「検出する」側に倒す。
- 他の検出 (gh pr merge 等) は元々コマンド開始位置を要求しない単純な正規表現
  であり、この種の見落としは無い。ただし無関係な文字列 (コメントや echo の
  引数) に偶然マッチする false positive はあり得る。false positive (誤って
  permit を要求する) は false negative (無許可の merge を見逃す) より
  安全な失敗方向なので、本モジュール全体でこの方向の誤検出を積極的に許容
  する。
- merge 呼び出しの手前に `cd`/`pushd` があれば実効 cwd を追跡し
  (`_compute_effective_cwd`)、静的に解決できない cd (変数展開・コマンド
  置換・pipe/subshell 越境等) は ambiguous として fail-closed する。
- permit は `~/.claude/merge-permits/<id>.json` に平文 JSON で保存する。
  秘密情報は持たない (リポジトリ識別子・対象・有効期限のみ)。
"""

from __future__ import annotations

import fcntl
import json
import os
import re
import subprocess
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

DEFAULT_PERMITS_DIR = Path.home() / ".claude" / "merge-permits"
DEFAULT_TTL_SECONDS = 300  # 5分。「素早く失効する」という要件に対する既定値
MAX_TTL_SECONDS = 900  # 15分。CLI 側で明示指定してもこれ以上は延長させない

VALID_ACTIONS = ("gh-pr-merge", "git-merge", "graphql-merge", "gh-stack-merge")


# --------------------------------------------------------------------------
# リポジトリ識別子の正規化
# --------------------------------------------------------------------------


def normalize_repo_identity_from_url(url: str) -> str:
    """git remote URL、または `owner/repo` / `host/owner/repo` 形式の文字列を
    `host/owner/repo` へ正規化する。

    https://github.com/owner/repo.git / git@github.com:owner/repo.git /
    ssh://git@github.com/owner/repo.git のいずれも同じ識別子になるようにする
    (worktree ごとにパスは変わるが origin は同じであるため)。

    `gh` の `--repo`/`-R` フラグや merge-permit-cli の `--repo-identity` に
    渡される値は host を省略した `owner/repo` のこともある。gh CLI 自身の既定
    (host 未指定なら github.com) に合わせ、正規化後にスラッシュが 1 個だけ
    (= owner/repo のみ) なら `github.com/` を補う。これにより
    `git remote get-url origin` 経由の識別子と `--repo owner/repo` 経由の
    識別子が同じ文字列に揃い、permit の repo 完全一致判定がすり抜けない。
    """
    u = url.strip().strip('"').strip("'")
    u = re.sub(r"^[a-zA-Z][a-zA-Z0-9+.-]*://", "", u)  # scheme:// を落とす
    u = re.sub(r"^[^@/]+@", "", u)  # user@ を落とす (ssh 形式)
    u = u.replace(":", "/", 1) if re.match(r"^[^/]+:[^/]", u) else u  # host:owner/repo -> host/owner/repo
    u = u.rstrip("/")
    if u.endswith(".git"):
        u = u[: -len(".git")]
    u = u.lower()
    if u.count("/") == 1:
        u = "github.com/" + u
    return u


def resolve_repo_identity(cwd: str) -> Optional[str]:
    """cwd から git origin を引いて識別子を返す。取得できなければ None。"""
    try:
        out = subprocess.run(
            ["git", "-C", cwd, "remote", "get-url", "origin"],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0 or not out.stdout.strip():
        return None
    return normalize_repo_identity_from_url(out.stdout)


def resolve_current_branch(cwd: str) -> Optional[str]:
    try:
        out = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0:
        return None
    branch = out.stdout.strip()
    return branch or None


# --------------------------------------------------------------------------
# merge アクションの検出
# --------------------------------------------------------------------------


@dataclass
class MergeAttempt:
    action: str  # "gh-pr-merge" | "git-merge" | "graphql-merge"
    target: str  # "pr:123" | "branch:foo" | "graphql-mutation" | "pr:current"
    repo_hint: Optional[str] = None  # コマンド中で -C / --repo 等が明示された場合の repo identity
    snippet: str = ""  # ブロックメッセージ用の抜粋
    # merge 呼び出し位置より前に `cd`/`pushd` があった場合の実効 cwd。
    # repo_hint が無い攻撃 (cwd から git remote を引いて repo を決める経路) は
    # これを使う。ambiguous=True の場合は None のままで、呼び出し側は
    # fail-closed (block) しなければならない (`cd $VAR && git merge x` のように
    # 静的に解決できない cd を挟んで static cwd の permit を使い回すのを防ぐ)。
    cwd_override: Optional[str] = None
    cwd_ambiguous: bool = False
    # 第六回レビュー指摘による設計転換: redirect (特に `2>&1`/`&>`/`>&` 等の
    # 複合 ampersand 形) を個別に正しくパースし続けるのは構造的に脆い。
    # 「単純で一意に解釈できる形」だけを permit 照合の対象にし、それ以外
    # (redirect が 1 文字でもある / wrapper コマンド経由 / 環境変数代入経由 /
    # subshell・brace group・command substitution・シェルキーワードの直後)
    # は repo_hint や target が明示されていても常に block する
    # (`_is_simple_supported_form` で判定)。True の場合、guard 側は permit の
    # 有無を一切確認せず block しなければならない。
    unsafe_form: bool = False


# `--repo owner/repo` / `-R owner/repo` の抽出 (gh 系コマンド共通)。gh(1) の
# global flag は `-R, --repo [HOST/]OWNER/REPO`。短縮形 `-R` を見落とすと、
# `gh pr merge 123 -R other/repo` が「カレント repo 向け」と誤認され、
# カレント repo 用の permit で実際には別 repo の PR を merge できてしまう
# (レビュー指摘 (2))。`-R` は空白区切り (`-R owner/repo`) と glued 形式
# (`-Rowner/repo`) の両方を pflag が受け付けるため `\s*` で両対応する。
_GH_REPO_FLAG = re.compile(r"(?:^|\s)(?:--repo[= ]|-R\s*)(\S+)")

_GIT_MERGE_ABORT = re.compile(r"--abort\b")

# git のサブコマンド境界。`;`/改行/`)`/`}`/backtick/`&&`/`||` のような
# 疑いようのない区切りでのみ止める。単体の `&`/`|` を区切りに含めない理由:
# `git &>log merge branch` / `git >&2 merge branch` / `git 2>&1 merge branch`
# のように、複合 redirect 演算子の先頭が `&` そのもの、あるいは `&` を含む
# 演算子が "git" と実際のサブコマンドの間に来ると、単体の `&`/`|` を境界に
# していた旧実装では文がそこで打ち切られ ("git" だけ、あるいは redirect
# トークン自体がサブコマンドと誤認される形) `_find_git_subcommand` が
# サブコマンドを一切見つけられず検出そのものが素通りしていた
# (独立レビュー再現 PoC で確認された回帰)。`_is_simple_supported_form` 用の
# `_SIMPLICITY_SCAN_TERMINATOR` と同じ終端集合に統一する。
_GIT_STATEMENT_END = re.compile(r";|\n|\)|\}|`|&&|\|\|")

# redirection 演算子で始まるトークン (`>`, `>>`, `<`, `2>&1`, `&>`, `>&` 等)。
# `_find_git_subcommand` が git のグローバルオプションを読み飛ばして実際の
# サブコマンドを探す際、redirect トークンをサブコマンドやフラグと誤認しない
# ようにするため (上記 `_GIT_STATEMENT_END` の変更に伴い、redirect トークンが
# `stmt` 内に残るようになったため必要)。`_extract_target_token` (対象引数の
# 抽出) でも同じ理由で使う。
_REDIRECT_TOKEN_PREFIX = re.compile(r"^&?\d*(?:>>|>&|<<<|<<|<>|<|>)")

# 第四回レビュー指摘: 「コマンド開始位置として妥当な文字/キーワードを
# 列挙する」許可リスト方式 (旧 `_is_command_position`) は、subshell・
# brace group・否定・if/then/do/else/elif/while/until に加え、
# backtick/command substitution・redirection・環境変数代入・wrapper
# コマンド (time/exec/env/nice/nohup/command/sudo) の直後という
# キリのない組み合わせを都度追加するモグラ叩きになっていた
# (3 回のレビューで 3 回の回帰)。
#
# 方針転換: 許可リストをやめ、「`\bgit\b` にマッチした位置のうち、
# 明らかに git 呼び出しではないと確信できるものだけ」を除外する
# 否定リスト方式に置き換える。除外対象は次の 2 パターンのみ:
#   - 直前の文字が `.` (例: `--git-dir=/x/.git` の末尾の `.git`)
#   - 直前の文字が `-` (例: `--git-dir` の中の `git`)
# これ以外の位置 (先頭・空白・`;`/`&`/`|`/改行・`(`/`{`/`!`・キーワード直後・
# backtick/`$(` の中・redirection や環境変数代入や wrapper コマンドの後) は
# すべて「git 呼び出しの可能性がある」として `_find_git_subcommand` に
# 渡す。`_find_git_subcommand` 自体が `tokens[0] == "git"` の完全一致を
# 要求するため、`--git-dir=...` のような複合トークンはここでも自然に
# 弾かれる。redirection/環境変数代入/wrapper コマンドは個別に読み飛ばす
# ロジックを持たせず、単に「その手前に何があっても git 呼び出しの可能性を
# 排除しない」という設計で対応する (= 見逃すより誤検出を優先する)。
_GIT_FALSE_MATCH_PRECEDING_CHARS = frozenset(".-")


def _is_plausible_git_invocation(command: str, pos: int) -> bool:
    """`pos` の `\\bgit\\b` が `.git`/`--git-dir` のような path/flag 名の
    一部ではなく、git 呼び出しの可能性がある位置かどうかを判定する。

    許可リストではなく否定リストであることに注意: ここで True を返した
    位置がすべて実際に git を呼び出しているとは限らない
    (`_find_git_subcommand` の `tokens[0] == "git"` チェックでさらに絞り込む)。
    判定に迷う/静的に確信が持てないケースは常に True 側 (= 検出を続行する)
    に倒す。false positive (誤って merge-permit を要求する) は
    false negative (無許可の merge を見逃す) より安全な失敗方向である。
    """
    if pos == 0:
        return True
    return command[pos - 1] not in _GIT_FALSE_MATCH_PRECEDING_CHARS


# GIT_DIR/GIT_WORK_TREE 環境変数は `-C`/`--git-dir` と同様に操作対象
# リポジトリそのものを切り替えられる。`GIT_DIR=/other/repo git merge x`
# のように merge 呼び出し手前で代入されていると、明示的な `-C` が無い限り
# cwd 由来の repo 解決が実際の操作対象と一致する保証が無いため、
# ambiguous 扱いにして fail-closed する。
_GIT_ENV_OVERRIDE_TOKEN = re.compile(r"\b(?:GIT_DIR|GIT_WORK_TREE)=")


def _has_git_env_override_before(command: str, match_start: int) -> bool:
    """`match_start` の直近の文区切り (`;`/`&`/`|`/改行) から `match_start`
    までの範囲に `GIT_DIR=`/`GIT_WORK_TREE=` があるかどうかを判定する。"""
    sep_positions = [command.rfind(c, 0, match_start) for c in ";&|\n"]
    start = max([p for p in sep_positions if p != -1], default=-1) + 1
    return bool(_GIT_ENV_OVERRIDE_TOKEN.search(command, start, match_start))


# --------------------------------------------------------------------------
# 「単純で一意に解釈できる形」かどうかの判定 (第六回レビューによる設計転換)
# --------------------------------------------------------------------------
#
# それまでの設計は「redirect/wrapper/command substitution/環境変数代入の
# 直後でも git 呼び出しを正しく検出し、repo/target を正確に抽出したうえで
# permit と照合する」というものだった。だが `2>&1` / `&>` / `>&` のような
# 複合 ampersand redirect まで含めて「対象コマンドの引数はどこからどこまでか」
# を素朴なトークン分割で恒久的に正しく判定し続けるのは構造的に脆く、都度
# バリエーションが見つかるモグラ叩きになっていた (第五回レビューの
# redirect-before-target バイパスがその一例)。
#
# 方針転換: 「正確に抽出できる」ことを目指すのをやめ、「単純で疑いようのない
# 形かどうか」だけを判定する。単純でなければ repo/target の抽出結果が
# どうであれ (たとえ明示的な -C や PR 番号があっても) permit の有無を
# 一切見ずに常に block する。これにより複合 redirect の正確なパースが
# 不要になる (1 文字でも `<`/`>` があれば単純とみなさないため、
# `2>&1`/`&>`/`>&`/`&>>` 等を個別に区別する必要が無い)。
_SIMPLE_LEADING_CONTEXT_CHARS = frozenset(";&|\n")


def _is_simple_leading_context(command: str, pos: int) -> bool:
    """`pos` の直前 (空白を読み飛ばした最初の非空白文字) が「文字列先頭」か
    `;`/`&`/`|`/改行 のみであることを確認する。subshell `(`・brace group `{`・
    backtick・環境変数代入・wrapper コマンド・シェルキーワード (if/then/do/
    else/elif/while/until) の直後はすべて False になる。"""
    i = pos - 1
    while i >= 0 and command[i] in " \t":
        i -= 1
    if i < 0:
        return True
    return command[i] in _SIMPLE_LEADING_CONTEXT_CHARS


# `_is_simple_supported_form` 専用の走査終端。target 抽出用の
# `_GIT_STATEMENT_END`/`[^;&|\n]*` (gh 系の rest) は `&`/`|` 単体でも打ち切る
# ため、`&>`/`&>>` のような複合 redirect だと `&` の時点で切れてしまい、
# 後続の `>` を見落とす (実機テストで発覚)。この判定専用の走査は `&`/`|`
# 単体では止めず、`;`/改行/`)`/`}`/backtick/`&&`/`||` のような疑いようのない
# 区切りでのみ止める。単体の `&`/`|` を境界にしないぶん走査範囲が広がり、
# 無関係な後続コマンドの `<`/`>` を拾って過剰に block する可能性はあるが、
# 「複雑な形は一律拒否する」という設計方針上、安全な方向の誤検出として許容する。
_SIMPLICITY_SCAN_TERMINATOR = re.compile(r";|\n|\)|\}|`|&&|\|\|")


def _is_simple_supported_form(command: str, invocation_start: int) -> bool:
    """merge-permit が repo/target の抽出結果を信頼してよい「単純な」形
    かどうかを判定する。False の場合、呼び出し側は permit の有無に関わらず
    常に block しなければならない。

    条件 (すべて満たす場合のみ True):
    - `invocation_start` の直前の実行コンテキストが「文字列先頭」または
      `;`/`&`/`|`/改行 のみ (`_is_simple_leading_context`)
    - `invocation_start` から `_SIMPLICITY_SCAN_TERMINATOR` までの範囲に
      redirection を示唆する文字 (`<` または `>`) が一切含まれない。
      演算子の複合形 (`2>&1`/`&>`/`>&`/`&>>` 等) を個別に判別する必要を
      無くすため、1 文字でも `<`/`>` があれば単純とはみなさない
    """
    if not _is_simple_leading_context(command, invocation_start):
        return False
    m = _SIMPLICITY_SCAN_TERMINATOR.search(command, invocation_start)
    scan_end = m.start() if m else len(command)
    scan_text = command[invocation_start:scan_end]
    if "<" in scan_text or ">" in scan_text:
        return False
    return True


# git のグローバルオプションのうち、次のトークンを値として消費するもの
# (git(1) OPTIONS のうち代表的なもの。網羅目的ではなく、値を取るせいで
# 素朴な「最初の非ダッシュトークン = サブコマンド」判定を誤らせるものだけを
# 列挙する。例: `git -c foo=bar merge x` を `-c` 自体をサブコマンドと
# 誤認したり、`merge` を素通りさせたりしないようにする (レビュー指摘 (4))。
_GIT_GLOBAL_VALUE_FLAGS = frozenset(
    {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--super-prefix", "--config-env", "--exec-path"}
)


def _find_git_subcommand(command: str, git_token_start: int) -> Optional[tuple[str, str, dict, str]]:
    """`git` トークンの出現位置からグローバルオプションを読み飛ばし、実際の
    サブコマンドを特定する。真偽値グローバルオプション (`--no-pager` 等) は
    網羅列挙せず「ダッシュ始まりなら 1 トークン読み飛ばす」で汎用的に扱う一方、
    値を取るオプション (`_GIT_GLOBAL_VALUE_FLAGS`) だけは次のトークンも値として
    読み飛ばす。こうしないと `-c foo=bar` のような形で `merge` の直前に挟まる
    オプションがあると検出そのものが素通りしてしまう。

    `git` とサブコマンドの間に redirection (`2>&1` / `&>` / `>&` 等の複合
    ampersand 形を含む) が挟まる場合も、redirect トークン (演算子のみの
    分離形ならその対象トークンも含む) を読み飛ばしてからサブコマンド探索を
    続ける。読み飛ばさないと redirect トークン自体をサブコマンドやフラグと
    誤認し、検出が素通りする (独立レビュー再現 PoC で確認された回帰)。

    戻り値: (subcommand, rest_of_statement, flag_values, full_statement_text)
    または、サブコマンドが見つからない場合 None。
    """
    stmt_end_m = _GIT_STATEMENT_END.search(command, git_token_start)
    stmt_end = stmt_end_m.start() if stmt_end_m else len(command)
    stmt = command[git_token_start:stmt_end]

    tokens = stmt.split()
    if not tokens or tokens[0] != "git":
        return None

    flag_values: dict = {}
    i = 1
    n = len(tokens)
    while i < n:
        tok = tokens[i]
        m = _REDIRECT_TOKEN_PREFIX.match(tok)
        if m:
            i += 1
            if m.end() == len(tok) and i < n:
                # 演算子だけの分離形トークン (`>` 単体等)。次のトークンが
                # リダイレクト対象 (ファイル名/fd) なのでそれも読み飛ばす。
                i += 1
            continue
        if not tok.startswith("-"):
            rest = " ".join(tokens[i + 1 :])
            return tok, rest, flag_values, stmt
        if tok in _GIT_GLOBAL_VALUE_FLAGS:
            if i + 1 < n:
                flag_values[tok] = tokens[i + 1]
            i += 2
            continue
        if "=" in tok:
            name = tok.split("=", 1)[0]
            if name in _GIT_GLOBAL_VALUE_FLAGS:
                flag_values[name] = tok.split("=", 1)[1]
            i += 1
            continue
        i += 1  # その他のダッシュ始まりの真偽値グローバルオプション
    return None  # フラグだけで終わっており、サブコマンドが見つからなかった


# `cd` / `pushd` を辿って merge 呼び出し時点の実効 cwd を計算するための部品。
# hook イベントの `cwd` は Bash tool 呼び出し開始時点の静的な値であり、
# コマンド文字列内で `cd` した後の実際の実行ディレクトリを反映しない。
# `cd /other-repo && git merge x` のように別リポジトリへ `cd` してから
# merge すると、static cwd 基準で発行された permit を別リポジトリへの
# merge に転用できてしまう (レビュー指摘 (3))。
_SAFE_CD_TARGET = re.compile(r"^[A-Za-z0-9_./-]+$")
# `(` / `{` の直後 (subshell / brace group の先頭) の cd も検出する。
# 第三者レビュー (2回目) 指摘の `(git merge X)` 系の回帰修正に伴い、
# `(cd /tmp && git merge X)` のようなケースで cd 自体を見落とさないため。
_CD_STATEMENT = re.compile(r"(?:^|;|&&|\n|\(|\{)\s*(?:cd|pushd)\s+(?:--\s+)?(\S+)")


def _compute_effective_cwd(command: str, match_start: int, static_cwd: str) -> tuple[Optional[str], bool]:
    """`match_start` (merge 呼び出しの開始位置) より前を辿り、実効 cwd を
    計算する。戻り値は `(実効 cwd, ambiguous)`。

    `ambiguous=True` は静的解析で安全に確定できないことを意味し、呼び出し側は
    repo_hint が無い限り fail-closed (block) しなければならない。ambiguous に
    なるケース: `cd` の後に `|` がある (pipe をまたいだ cwd 継承はシェル依存)、
    最初の cd より後に `)` がある (その cd を含む subshell が merge 呼び出し
    より前に閉じ、cd の効果が外側へ伝播しない可能性がある。ネストの深さまでは
    追わない簡易判定だが安全側に倒す)、`cd` の対象が `$VAR` / `` ` `` / `*` /
    `~` / クォートなど静的に解決できない形。

    `cd` が 1 つも無ければ、subshell (`()`) や brace group (`{}`) に囲まれて
    いても実行ディレクトリは static cwd のまま変わらない (それらは cwd を
    継承するだけで、内部で cd しない限り変化させない) ため、括弧の対応が
    崩れていても ambiguous にはしない。これにより `(git merge X)` のように
    cd を伴わない subshell 単体は fail-closed の対象にならない
    (第三者レビュー (2回目) が指摘した回帰の修正)。
    """
    text_before = command[:match_start]
    cds = list(_CD_STATEMENT.finditer(text_before))
    if not cds:
        return static_cwd, False
    if "|" in text_before:
        return None, True
    first_cd_start = cds[0].start()
    if ")" in text_before[first_cd_start:]:
        # 最初の cd より後に subshell の閉じ括弧がある = その cd を含んでいた
        # subshell が merge 呼び出しより前に閉じた可能性がある
        # (`(cd /tmp); git merge x` では cd の効果は subshell の外に
        # 伝播しない)。安全に確定できないため block する。
        return None, True
    effective = static_cwd
    for m in cds:
        target = m.group(1)
        if not _SAFE_CD_TARGET.match(target):
            return None, True
        effective = os.path.normpath(os.path.join(effective, target))
    return effective, False


# gh pr merge。`gh` と `pr merge` の間に `--repo owner/repo` / `-R owner/repo`
# 等のグローバルフラグが挟まるケースを許容する。
_GH_PR_MERGE = re.compile(r"\bgh\b(?:\s+\S+)*?\s+pr\s+merge\b(?P<rest>[^;&|\n]*)")

# GitHub REST の PR merge エンドポイント (同期, 単体 PR 専用):
# PUT /repos/{owner}/{repo}/pulls/{n}/merge
# stack 対応の非同期エンドポイント (.../merge-async) は別パターンで扱うため、
# `-async` が続く場合はここでマッチさせない (`\bmerge\b` は `-` の前でも
# word boundary が立つため、素朴な正規表現だと両方にマッチしてしまう)。
_REST_MERGE_URL = re.compile(
    r"repos/(?P<owner>[\w.-]+)/(?P<repo>[\w.-]+)/pulls/(?P<number>\d+)/merge\b(?!-async)"
)
_HTTP_METHOD_PUT = re.compile(r"(?:-X|--request|--method)[= ]\"?PUT\"?", re.IGNORECASE)

# GitHub 純正 stacked pull requests の stack merge 操作。
#
# 2026-07-30 の public preview 発表時点の一次情報 (docs.github.com,
# github.blog/changelog, github.com/github/gh-stack) で確認した事実:
# - stack の merge は「選択した PR とその下の未マージ PR すべてが 1 回の
#   操作でまとめて base branch に着地する」atomic 操作。個々の PR を順に
#   merge するものではない (docs: "land on the base branch together as a
#   single operation")
# - legacy の同期 merge エンドポイント/mutation では stack を merge できず、
#   非同期 merge API (`PUT .../pulls/{n}/merge-async`) が必須
# - GraphQL は stack について read-only (`stack` mutation は存在しない)
# - 公式 CLI 拡張は `gh-stack` (`gh extension install github/gh-stack`,
#   github org 直下)。core の `gh pr merge` に stack 対応の記載は無い。
#   実際のマージ subcommand は `gh stack merge [<stack-number> | <pr-number>]`。
#   `gh stack merge --help` で確認した flag は `--merge` / `--merge-method` /
#   `--rebase` / `--squash` / `-y,--yes` のみで `--repo`/`-R` は存在しない
#   (stack は常にカレント repo/branch 基準)。実在しないオプションのハンドリング
#   は持たせない (レビュー指摘: 未サポートの --repo ハンドリングを除去)。
#
# public preview であり仕様は変更され得る。詳細と出典は
# `~/.dotfiles/claude/merge-permit-policy.md` を参照。
_GH_STACK_MERGE = re.compile(r"\bgh\b(?:\s+\S+)*?\s+stack\s+merge\b(?P<rest>[^;&|\n]*)")
_REST_MERGE_ASYNC_URL = re.compile(
    r"repos/(?P<owner>[\w.-]+)/(?P<repo>[\w.-]+)/pulls/(?P<number>\d+)/merge-async\b"
)

# GraphQL 経由の mergePullRequest mutation (curl / gh api graphql 共通)。
# stack には使えない (GraphQL は stack read-only) が、単体 PR の merge には
# 使えるため引き続き検出対象にする。
_GRAPHQL_MERGE_MUTATION = re.compile(r"mergePullRequest\b")


# `--flag value` の 2 トークン形式で値を取るフラグ。`--flag=value` の 1 トークン
# 形式は素朴に `-` 始まりとして弾かれるのでここでは扱わなくてよい。
_GIT_MERGE_VALUE_FLAGS = frozenset({"-s", "--strategy", "-X", "--strategy-option", "-m", "--message"})
_GH_PR_MERGE_VALUE_FLAGS = frozenset({"--repo", "-R", "--body", "-b", "--subject", "-t"})
# gh stack merge に --repo/-R は存在しない (実機の --help で確認済み) ので
# --merge-method のみを値フラグとして扱う
_GH_STACK_MERGE_VALUE_FLAGS = frozenset({"--merge-method"})


def _extract_target_token(rest: str, value_flags: frozenset = frozenset()) -> str:
    """フラグを除いた非フラグトークンを対象として拾う (octopus merge は複数拾って
    `,` 結合)。`value_flags` に含まれるフラグは次のトークンも値として読み飛ばす
    (例: `--merge-method rebase` の `rebase` を誤って対象トークンにしない)。

    redirection はシェル上どこにでも書ける (`git merge >log.txt X` も
    `git merge X >log.txt` も同じ意味) ため、redirection トークンに出会っても
    走査を打ち切らず、演算子 (+ 分離形なら続くリダイレクト対象トークンも) だけ
    読み飛ばして後続の引数を探し続ける。第五回レビュー指摘の回帰: 以前は
    redirection に出会った時点で走査を打ち切っていたため、
    `git merge >log branch` のように対象より前に redirection が来ると
    対象トークンが 1 つも見つからず `branch:HEAD` (未指定扱い) に化けて
    しまい、汎用 permit で明示的な別 target への merge を通せてしまっていた。
    """
    tokens = []
    toks = rest.split()
    i = 0
    n = len(toks)
    while i < n:
        tok = toks[i]
        m = _REDIRECT_TOKEN_PREFIX.match(tok)
        if m:
            i += 1
            if m.end() == len(tok) and i < n:
                # 演算子だけの分離形トークン (`>` 単体等)。次のトークンが
                # リダイレクト対象 (ファイル名/fd) なのでそれも読み飛ばす。
                # glued 形式 (`>log.txt`) は既に 1 トークンで完結している
                # ので追加の読み飛ばしは不要。
                i += 1
            continue
        if tok.startswith("-"):
            i += 1
            if tok in value_flags and i < n:
                i += 1
            continue
        tokens.append(tok)
        i += 1
    return ",".join(tokens) if tokens else ""


def detect_merge_actions(command: str, cwd: str) -> list[MergeAttempt]:
    """コマンド文字列から merge アクションを検出する。0 件なら安全に通す。

    `cwd` は hook イベントの静的な cwd (Bash tool 呼び出し開始時点の値)。
    各 merge 候補について、その手前に `cd`/`pushd` が無いか調べ (`cwd_override`/
    `cwd_ambiguous`)、明示的な repo_hint (`-C`/`--repo`/`-R`/URL 由来) が無い
    場合の cwd フォールバック解決を安全にする。

    git-merge / gh-pr-merge / gh-stack-merge の各候補は、さらに
    `_is_simple_supported_form` で「単純で一意に解釈できる形」かどうかを
    判定し `MergeAttempt.unsafe_form` に反映する。redirect を 1 文字でも
    含む・wrapper コマンド経由・環境変数代入経由・subshell/brace group/
    command substitution/シェルキーワードの直後、のいずれかに該当すれば
    unsafe_form=True になり、呼び出し側 (guard.py) は repo/target の抽出
    結果や permit の有無に関わらず常に block しなければならない
    (最終レビューによる設計転換: 複合 ampersand redirect (`2>&1`/`&>`/`>&`
    等) を含め、すべての形を正確にパースし続けるのは構造的に脆いため)。
    """
    attempts: list[MergeAttempt] = []

    # --- git merge ---------------------------------------------------------
    # `_is_plausible_git_invocation` は否定リスト (`.git`/`--git-dir` 相当を
    # 除外するだけ) であり、それ以外の位置は無条件に候補として扱う。
    # `_find_git_subcommand` でグローバルオプションを読み飛ばしてサブコマンドを
    # 特定する (`git -c k=v merge x` のような global option を挟まれても
    # 素通りさせない)。
    for gm in re.finditer(r"\bgit\b", command):
        if not _is_plausible_git_invocation(command, gm.start()):
            continue  # `.git` / `--git-dir` の中の "git" 等、明らかな誤検出のみ除外
        found = _find_git_subcommand(command, gm.start())
        if found is None:
            continue
        subcommand, rest, flag_values, stmt = found
        if subcommand != "merge":
            continue
        if _GIT_MERGE_ABORT.search(rest):
            continue  # abort は新規 merge を発生させないので対象外

        effective_cwd, ambiguous = _compute_effective_cwd(command, gm.start(), cwd)

        repo_hint = None
        c_path = flag_values.get("-C")
        if c_path:
            if os.path.isabs(c_path):
                # 絶対パスなら手前の cd の有無に関係なく解決できる
                repo_hint = resolve_repo_identity(c_path)
            elif not ambiguous:
                repo_hint = resolve_repo_identity(os.path.normpath(os.path.join(effective_cwd, c_path)))
            # else: 相対 -C かつ手前の cd が曖昧 → repo_hint は None のまま。
            # cwd_ambiguous=True により guard 側が fail-closed する。
            if repo_hint is None:
                # -C が明示されたにもかかわらず解決できなかった (origin 未設定
                # の git repo・git repo ですらない・相対パスが曖昧、等)。
                # ここで ambiguous にせず放置すると、guard 側が repo_hint 無し
                # と誤認して session の静的 cwd (実行元 worktree) 由来の repo
                # へフォールバックしてしまい、-C が実際に指す対象とは無関係な
                # repo 向けの permit で merge を許可してしまう
                # (独立レビュー再現 PoC で確認された回帰)。明示された -C は
                # 常にその対象を指すべきで、無関係な cwd への転用は許さない。
                ambiguous = True

        if repo_hint is None and _has_git_env_override_before(command, gm.start()):
            # `-C` 等の明示的な repo_hint が無く、かつ GIT_DIR=/GIT_WORK_TREE=
            # が手前で代入されている場合、cwd 由来の repo 解決が実際の操作
            # 対象と一致する保証が無いため ambiguous 扱いにする。
            ambiguous = True

        target_token = _extract_target_token(rest, _GIT_MERGE_VALUE_FLAGS)
        target = f"branch:{target_token}" if target_token else "branch:HEAD"
        attempts.append(
            MergeAttempt(
                action="git-merge",
                target=target,
                repo_hint=repo_hint,
                snippet=stmt.strip(),
                cwd_override=effective_cwd if not ambiguous else None,
                cwd_ambiguous=ambiguous,
                unsafe_form=not _is_simple_supported_form(command, gm.start()),
            )
        )

    # --- gh pr merge ---------------------------------------------------------
    for m in _GH_PR_MERGE.finditer(command):
        rest = m.group("rest") or ""
        whole = m.group(0)
        effective_cwd, ambiguous = _compute_effective_cwd(command, m.start(), cwd)

        repo_hint = None
        rf = _GH_REPO_FLAG.search(whole)
        if rf:
            # --repo/-R は owner/repo (または host/owner/repo) を直接指すので
            # cwd の cd 追跡とは無関係に解決できる
            repo_hint = normalize_repo_identity_from_url(rf.group(1))
        rest_wo_flags = _GH_REPO_FLAG.sub("", rest)
        target_token = _extract_target_token(rest_wo_flags, _GH_PR_MERGE_VALUE_FLAGS)
        if target_token:
            target = f"pr:{target_token}"
        elif not ambiguous:
            # 引数なし = 実行時点のカレントブランチに紐づく PR
            branch = resolve_current_branch(effective_cwd)
            target = f"branch:{branch}" if branch else "branch:HEAD"
        else:
            target = "branch:<ambiguous-cwd>"  # guard 側が cwd_ambiguous で block する
        attempts.append(
            MergeAttempt(
                action="gh-pr-merge",
                target=target,
                repo_hint=repo_hint,
                snippet=whole.strip(),
                cwd_override=effective_cwd if not ambiguous else None,
                cwd_ambiguous=ambiguous,
                unsafe_form=not _is_simple_supported_form(command, m.start()),
            )
        )

    # --- REST API 経由の merge (curl / gh api) --------------------------------
    for m in _REST_MERGE_URL.finditer(command):
        # PUT method の指定が同じコマンド文字列のどこかにあることを要求する
        # (エンドポイント文字列だけでは GET での状態確認と区別できないため)。
        if not _HTTP_METHOD_PUT.search(command):
            continue
        owner, repo, number = m.group("owner"), m.group("repo"), m.group("number")
        attempts.append(
            MergeAttempt(
                action="gh-pr-merge",
                target=f"pr:{number}",
                repo_hint=normalize_repo_identity_from_url(f"{owner}/{repo}"),
                snippet=m.group(0),
            )
        )

    # --- gh stack merge (GitHub 純正 stacked PR の stack merge、CLI) ----------
    # `gh stack merge` に `--repo`/`-R` は存在しない (`gh stack merge --help`
    # で確認済み) ので repo は常に実効 cwd から解決する。
    for m in _GH_STACK_MERGE.finditer(command):
        rest = m.group("rest") or ""
        whole = m.group(0)
        effective_cwd, ambiguous = _compute_effective_cwd(command, m.start(), cwd)
        target_token = _extract_target_token(rest, _GH_STACK_MERGE_VALUE_FLAGS)
        # stack-number/PR-number いずれも `pr:<token>` として扱う (guard 側は
        # 区別できないため、permit 発行時に運用者が実際に渡す引数と同じ値を
        # --target に指定してもらう前提)。引数なし = インタラクティブピッカーで
        # 選ばれる「現在の stack」を指す。
        target = f"pr:{target_token}" if target_token else "pr:current"
        attempts.append(
            MergeAttempt(
                action="gh-stack-merge",
                target=target,
                repo_hint=None,
                snippet=whole.strip(),
                cwd_override=effective_cwd if not ambiguous else None,
                cwd_ambiguous=ambiguous,
                unsafe_form=not _is_simple_supported_form(command, m.start()),
            )
        )

    # --- REST 非同期 merge エンドポイント (stack merge に必須) -----------------
    for m in _REST_MERGE_ASYNC_URL.finditer(command):
        if not _HTTP_METHOD_PUT.search(command):
            continue
        owner, repo, number = m.group("owner"), m.group("repo"), m.group("number")
        attempts.append(
            MergeAttempt(
                action="gh-stack-merge",
                target=f"pr:{number}",
                repo_hint=normalize_repo_identity_from_url(f"{owner}/{repo}"),
                snippet=m.group(0),
            )
        )

    # --- GraphQL 経由の mergePullRequest mutation -------------------------
    for m in _GRAPHQL_MERGE_MUTATION.finditer(command):
        # node ID からは owner/repo/number を静的に復元できないため、
        # repo 識別は呼び出し元 (cwd) の origin に委ねる粗い binding になる。
        # 既知の制約として operator flow ドキュメントに明記する。
        attempts.append(
            MergeAttempt(action="graphql-merge", target="graphql-mutation", repo_hint=None, snippet=m.group(0))
        )

    return attempts


# --------------------------------------------------------------------------
# Permit ストア
# --------------------------------------------------------------------------


@dataclass
class Permit:
    id: str
    repo: str
    action: str
    target: str
    created_at: float
    expires_at: float
    created_by: str = "unknown"
    reason: str = ""
    consumed: bool = False
    consumed_at: Optional[float] = None
    consumed_by_command: Optional[str] = None

    def to_json(self) -> dict:
        return {
            "id": self.id,
            "repo": self.repo,
            "action": self.action,
            "target": self.target,
            "created_at": self.created_at,
            "expires_at": self.expires_at,
            "created_by": self.created_by,
            "reason": self.reason,
            "consumed": self.consumed,
            "consumed_at": self.consumed_at,
            "consumed_by_command": self.consumed_by_command,
        }

    @staticmethod
    def from_json(d: dict) -> "Permit":
        return Permit(
            id=d["id"],
            repo=d["repo"],
            action=d["action"],
            target=d["target"],
            created_at=d["created_at"],
            expires_at=d["expires_at"],
            created_by=d.get("created_by", "unknown"),
            reason=d.get("reason", ""),
            consumed=d.get("consumed", False),
            consumed_at=d.get("consumed_at"),
            consumed_by_command=d.get("consumed_by_command"),
        )

    def is_expired(self, now: Optional[float] = None) -> bool:
        return (now if now is not None else time.time()) >= self.expires_at

    def is_valid(self, now: Optional[float] = None) -> bool:
        return not self.consumed and not self.is_expired(now)


class PermitStore:
    """`~/.claude/merge-permits/` (既定) 配下の permit ファイルを扱う。

    repo に閉じない: 複数リポジトリの permit を同じディレクトリに置き、
    repo フィールドで絞り込む (permit そのものは秘密情報を含まないため
    リポジトリごとに分離する必要はない)。
    """

    def __init__(self, base_dir: Path = DEFAULT_PERMITS_DIR):
        self.base_dir = Path(base_dir)

    def _ensure_dir(self) -> None:
        self.base_dir.mkdir(parents=True, exist_ok=True, mode=0o700)

    def _path(self, permit_id: str) -> Path:
        return self.base_dir / f"{permit_id}.json"

    def create(
        self,
        repo: str,
        action: str,
        target: str,
        ttl_seconds: int = DEFAULT_TTL_SECONDS,
        created_by: str = "unknown",
        reason: str = "",
    ) -> Permit:
        if action not in VALID_ACTIONS:
            raise ValueError(f"unknown action: {action}")
        ttl = max(1, min(ttl_seconds, MAX_TTL_SECONDS))
        self._ensure_dir()
        now = time.time()
        permit = Permit(
            id="mp_" + uuid.uuid4().hex[:12],
            repo=repo,
            action=action,
            target=target,
            created_at=now,
            expires_at=now + ttl,
            created_by=created_by,
            reason=reason,
        )
        path = self._path(permit.id)
        tmp = path.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(permit.to_json(), indent=2, ensure_ascii=False) + "\n")
        tmp.chmod(0o600)
        tmp.rename(path)  # 同一ファイルシステム内の rename はアトミック
        return permit

    def get(self, permit_id: str) -> Optional[Permit]:
        path = self._path(permit_id)
        if not path.exists():
            return None
        try:
            return Permit.from_json(json.loads(path.read_text()))
        except (json.JSONDecodeError, KeyError):
            return None

    def list_all(self) -> list[Permit]:
        if not self.base_dir.exists():
            return []
        permits = []
        for p in sorted(self.base_dir.glob("mp_*.json")):
            try:
                permits.append(Permit.from_json(json.loads(p.read_text())))
            except (json.JSONDecodeError, KeyError):
                continue
        return permits

    def find_valid(self, repo: str, action: str, target: str, now: Optional[float] = None) -> Optional[Permit]:
        candidates = [
            p
            for p in self.list_all()
            if p.repo == repo and p.action == action and p.target == target and p.is_valid(now)
        ]
        if not candidates:
            return None
        # 最も早く失効するものから使う (長寿命の permit を温存しない)
        candidates.sort(key=lambda p: p.expires_at)
        return candidates[0]

    def consume(self, permit_id: str, by_command: str = "") -> bool:
        """permit を消費する。ファイルロックで同時実行時の二重消費を防ぐ。

        戻り値: 消費に成功したら True。既に消費済み/失効/不存在なら False。
        """
        path = self._path(permit_id)
        if not path.exists():
            return False
        with open(path, "r+") as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            try:
                data = json.loads(f.read())
                permit = Permit.from_json(data)
                if not permit.is_valid():
                    return False
                permit.consumed = True
                permit.consumed_at = time.time()
                permit.consumed_by_command = by_command[:500]
                f.seek(0)
                f.truncate()
                f.write(json.dumps(permit.to_json(), indent=2, ensure_ascii=False) + "\n")
                f.flush()
                return True
            finally:
                fcntl.flock(f, fcntl.LOCK_UN)

    def revoke(self, permit_id: str) -> bool:
        """未消費の permit を即失効させる (運用者による取り消し)。"""
        return self.consume(permit_id, by_command="<revoked>")

    def gc(self, older_than_seconds: int = 7 * 24 * 3600) -> int:
        """消費済み/失効済みで一定時間経過した permit ファイルを削除する。"""
        if not self.base_dir.exists():
            return 0
        now = time.time()
        removed = 0
        for permit in self.list_all():
            stale = permit.consumed or permit.is_expired(now)
            if stale and (now - permit.created_at) > older_than_seconds:
                path = self._path(permit.id)
                path.unlink(missing_ok=True)
                removed += 1
        return removed
