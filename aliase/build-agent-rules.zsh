#!/bin/zsh
# AI エージェントのグローバル指示を claude/rules/ のフラグメントから結合生成する。
#
# 生成物:
#   claude/AGENTS.md      = core + worker            (Claude Code / Codex CLI が読む)
#   claude/hermes/SOUL.md = hermes-identity + core + orchestrator (Hermes が読む)
#
# 結合が必要な理由: Codex CLI も Hermes も `@AGENTS.md` 形式の import を展開せず、
# 与えられたファイルの中身をそのまま system prompt へ入れる。共通ルール (core) を
# 1 箇所に保ったまま両者へ届けるには、フラット化した成果物を用意するしかない。
#
# 生成物を working tree にコミットするのは、~/.claude/AGENTS.md 等が
# mkOutOfStoreSymlink で working tree を直接指しており、編集が switch なしで
# 即反映される性質を壊さないため (nix store 経由で生成すると switch 必須になる)。
# 生成漏れは .github/workflows/agent-rules-check.yml の --check で検出する。
#
# 使い方:
#   agent-rules-build            生成物を書き出す
#   agent-rules-build --check    生成物が最新か検証する (差分があれば exit 1)

emulate -L zsh
setopt no_unset pipe_fail

local repo_root="${0:A:h:h}"
local rules_dir="${repo_root}/claude/rules"

local check_only=0
case "${1:-}" in
  --check) check_only=1 ;;
  "") ;;
  *)
    print -u2 "build-agent-rules: 不明な引数: ${1}"
    print -u2 "使い方: build-agent-rules.zsh [--check]"
    exit 2
    ;;
esac

# 末尾の空行を落として 1 改行で終える。フラグメントの末尾改行の有無で
# 生成物が揺れると --check が偽陽性を出すため、ここで正規化する。
_emit_fragment() {
  awk '
    { lines[NR] = $0 }
    END {
      last = NR
      while (last > 0 && lines[last] == "") last--
      for (i = 1; i <= last; i++) print lines[i]
    }
  ' "$1"
}

# _build <出力先の repo 相対パス> <フラグメントの repo 相対パス>...
_build() {
  local out_rel="$1"; shift
  local -a frag_rels=("$@")

  local -a frag_paths=()
  # zsh の `path` は PATH に連動する特殊配列なので、ローカル変数名に使わない
  local rel frag_path
  for rel in "${frag_rels[@]}"; do
    frag_path="${repo_root}/${rel}"
    if [[ ! -f "${frag_path}" ]]; then
      print -u2 "build-agent-rules: フラグメントが見つからない: ${rel}"
      return 1
    fi
    frag_paths+=("${frag_path}")
  done

  local tmp="${TMPDIR:-/tmp}/build-agent-rules.$$.${out_rel:t}"
  {
    print -r -- "<!-- 生成物: aliase/build-agent-rules.zsh が claude/rules/ から生成する。このファイルを直接編集しない -->"
    print -r -- "<!-- SSOT: ${(j: + :)frag_rels} -->"
    local i
    for i in {1..${#frag_paths}}; do
      print -r -- ""
      _emit_fragment "${frag_paths[i]}"
    done
  } > "${tmp}" || { rm -f "${tmp}"; return 1 }

  local out_path="${repo_root}/${out_rel}"

  if (( check_only )); then
    local baseline="${out_path}"
    [[ -f "${baseline}" ]] || baseline=/dev/null
    if ! diff -q "${baseline}" "${tmp}" >/dev/null; then
      print -u2 "build-agent-rules: ${out_rel} が SSOT と一致しない"
      diff -u "${baseline}" "${tmp}" >&2 || true
      rm -f "${tmp}"
      return 1
    fi
    rm -f "${tmp}"
    return 0
  fi

  if ! mkdir -p "${out_path:h}" || ! mv "${tmp}" "${out_path}"; then
    print -u2 "build-agent-rules: ${out_rel} の書き出しに失敗した"
    rm -f "${tmp}"
    return 1
  fi
  print -r -- "build-agent-rules: generated ${out_rel}"
}

local status_code=0

_build "claude/AGENTS.md" \
  "claude/rules/core.md" \
  "claude/rules/worker.md" || status_code=1

_build "claude/hermes/SOUL.md" \
  "claude/rules/hermes-identity.md" \
  "claude/rules/core.md" \
  "claude/rules/orchestrator.md" || status_code=1

if (( check_only )) && (( status_code != 0 )); then
  print -u2 "build-agent-rules: claude/rules/ を編集したら agent-rules-build を実行して生成物を更新すること"
fi

exit ${status_code}
