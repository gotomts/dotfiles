#!/bin/zsh
# 1Password Service Account 経由で Development 用の秘密を注入して実行する wrapper。
#
# インフラ用の `opsa-infra.zsh` とは token・template・Vault scope を分けた別経路である。
# Development 用途とインフラ用途の権限境界を混ぜないため、両者を 1 本の実装に寄せない。
#
# 通常経路は `op run --env-file <template> -- <command>` の 1 本だけ。`op read` /
# `op item` / `op vault` のような値の直接取得・管理系はここを通さない（拒否する）。
#
# 使い方:
#   opsa-development run [--env-file <path>] -- <command> [args...]
#   例: opsa-development run -- jev-dev < payload.json
#
# token は macOS Keychain の generic password（service 名 OP_SERVICE_ACCOUNT_TOKEN_DEVELOPMENT）
# から取り、OP_SERVICE_ACCOUNT_TOKEN として `op run` プロセスの環境にだけ載せる。この shell
# では export せず、表示もファイル書き出しもしない。
#
# ただし **`op run` が起動するコマンドとその子孫は同じ環境を継承し得る**。子プロセスから
# `op` を呼べば Service Account の権限がそのまま使える。これは標準経路の残余リスクとして
# 受け入れ、Development 専用 Vault scope（read_items だけ・期限付き）で影響範囲を限定する。
#
# これは AI に対する絶対境界ではない（同一 macOS user 上では別経路で同じ token に到達できる）。
# wrapper は事故防止のレールであって、境界は上記の Vault scope が作る。
#
# 終了コード:
#   0      help を表示した、または `op run` が 0 で終わった
#   1      使い方・検証エラー（この場合 op は起動していない）。ただし `op run` 自身も 1 を
#          返し得るので、1 だけを見て「検証で落ちた」とは判定できない。区別は stderr の
#          `opsa-development: ` 接頭辞で行う
#   その他 `op run` の終了コードをそのまま返す

emulate -L zsh
setopt no_unset

# Keychain の service 名。保存側（runbook）と同じ値を使う。
# Development 用の Service Account は 1 本だけを宣言する。用途を増やすなら token と
# テンプレートを対で選ぶ入口を足す。今は作らない。
local keychain_service="OP_SERVICE_ACCOUNT_TOKEN_DEVELOPMENT"

# op run に渡す env-file。秘密値ではなく `op://` 参照だけを書いた非追跡ファイルを指す。
local env_file="${OPSA_DEVELOPMENT_ENV_FILE:-${HOME}/.config/opsa-development/development.env}"

opsa::die() {
  print -u2 "opsa-development: ${1}"
  exit 1
}

opsa::usage() {
  print -u2 "使い方: opsa-development run [--env-file <path>] -- <command> [args...]"
  print -u2 "  例:   opsa-development run -- jev-dev < payload.json"
  print -u2 "  値の直接取得・管理系（op read / op item / op vault 等）は通さない。"
}

if (( $# == 0 )); then
  opsa::usage
  exit 1
fi

local subcommand="${1}"
shift

case "${subcommand}" in
  help|-h|--help)
    opsa::usage
    exit 0
    ;;
  run) ;;
  *)
    opsa::usage
    opsa::die "サブコマンド ${subcommand} は受け付けない（run のみ）"
    ;;
esac

# ---- 引数を run の allowlist だけで解釈する -------------------------------
while (( $# > 0 )); do
  case "${1}" in
    --env-file)
      (( $# >= 2 )) || opsa::die "--env-file にパスが無い"
      env_file="${2}"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      opsa::die "未知の引数 ${1}（コマンドは -- の後ろに置く）"
      ;;
  esac
done

(( $# > 0 )) || opsa::die "-- の後ろに実行するコマンドが無い"

# `opsa-development run -- op read ...` のような、wrapper を踏み台にした値の直接取得を塞ぐ。
# shell を挟めば迂回できるので、これは境界ではなく事故防止のレールである。
# macOS の FS は既定で case-insensitive なので、`OP` / `Op` も同じ実行体に解決される。
# 小文字化してから比較する。
local child="${${1:t}:l}"
[[ "${child}" != "op" ]] || opsa::die "op の直接実行は通さない（値の取得・管理は AI 経路の外で行う）"

# ---- env-file の検証（fail-closed）----------------------------------------
[[ -e "${env_file}" ]] || opsa::die "env-file が無い: ${env_file}"
# ディレクトリ・fifo・device を渡された場合に read が詰まる／別物を読むのを避ける。
[[ -f "${env_file}" ]] || opsa::die "env-file が通常ファイルでない: ${env_file}"

# 参照だけを書くファイルとはいえ、「どの Vault のどの item を AI に使わせているか」は
# 構成情報である。owner 以外から読める配置のまま実行しない。
zmodload -F zsh/stat b:zstat 2>/dev/null || opsa::die "zsh/stat を読み込めない"
local -A env_stat
zstat -H env_stat -- "${env_file}" 2>/dev/null \
  || opsa::die "env-file の状態を取得できない: ${env_file}"
# 8#77 と書くのは、zsh が既定 (octalzeroes 無し) では 0077 を十進 77 として解釈し、
# group rw (0660) を取りこぼすため。
(( (env_stat[mode] & 8#77) == 0 )) \
  || opsa::die "env-file が owner 以外にも読める: ${env_file}（chmod 600 が必要）"
(( env_stat[uid] == UID )) \
  || opsa::die "env-file の所有者が現在のユーザーでない: ${env_file}"

local line
local -i refs=0
while IFS= read -r line || [[ -n "${line}" ]]; do
  [[ -z "${line}" || "${line}" == '#'* ]] && continue
  # 復号済みの値がテンプレートに混ざるのを防ぐため、op:// 参照の行だけを許す。
  # vault/item/field の 3 段が必須。Vault 名に空白を含む参照が正当なため、引用符で
  # 囲った形を標準とする（runbook もこの形）。
  #
  # 引用符なしの形も受けるが、その場合は最終セグメントに空白を許さない。許すと
  # `NAME=op://v/i/field よけいな文字列` のような末尾ゴミが参照として通ってしまい、
  # テンプレートに紛れ込んだ別物を検出できなくなる。
  [[ "${line}" =~ '^[A-Za-z_][A-Za-z0-9_]*=("op://[^/]+/[^/]+/[^"]+"|op://[^/]+/[^/]+/[^[:space:]"]+)$' ]] \
    || opsa::die "env-file に op:// 参照以外の行がある: ${env_file}"
  (( refs += 1 ))
done < "${env_file}"

(( refs > 0 )) || opsa::die "env-file に op:// 参照が 1 行も無い: ${env_file}"

command -v op >/dev/null 2>&1 || opsa::die "op コマンドが見つからない"

# ---- Keychain から token を取り、子プロセスにだけ渡す ----------------------
local token
token=$(security find-generic-password -s "${keychain_service}" -w 2>/dev/null) \
  || opsa::die "Keychain に ${keychain_service} が無い（runbook の保存手順を先に実行する）"
[[ -n "${token}" ]] || opsa::die "Keychain の ${keychain_service} が空"

# 前置代入なので token はこの op プロセスの環境にだけ載り、呼び出し元の shell には残らない。
# op が起動する子孫は同じ環境を継承し得る（冒頭の残余リスク）。
OP_SERVICE_ACCOUNT_TOKEN="${token}" op run --env-file "${env_file}" -- "$@"
