#!/bin/zsh
# CWD と git コマンドから handover の保存先解決に必要な値を環境変数形式で出力する。
# 出力例:
#   PROJECT_PATH=/Users/goto/.dotfiles
#   PROJECT_HASH=dotfiles-a1b2c3d4
#   BRANCH=main
#   FINGERPRINT=20260430-153000
#   HANDOVER_DIR=/Users/goto/.claude/handover/dotfiles-a1b2c3d4/main
set -eu

if repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  :
else
  repo_root="${PWD}"
fi

project_basename="$(basename "${repo_root}")"
project_sha="$(printf '%s' "${repo_root}" | shasum -a 1 | cut -c1-8)"
project_hash="${project_basename}-${project_sha}"

if branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"; then
  if [ "${branch}" = "HEAD" ]; then
    branch="detached-$(git rev-parse --short=7 HEAD)"
  fi
else
  branch="nogit"
fi
branch="$(printf '%s' "${branch}" | sed 's|[/:[:space:]]|-|g')"

fingerprint="$(date +%Y%m%d-%H%M%S)"

handover_dir="${HOME}/.claude/handover/${project_hash}/${branch}"

cat <<EOF
PROJECT_PATH=${repo_root}
PROJECT_HASH=${project_hash}
BRANCH=${branch}
FINGERPRINT=${fingerprint}
HANDOVER_DIR=${handover_dir}
EOF
