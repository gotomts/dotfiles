#!/usr/bin/env bash
# Claude Code on the web 用: dotfiles の自作スキルを personal スコープ
# (~/.claude/skills/) に注入する。各クラウド環境の Setup script から実行する。
#
# 背景:
#   ローカル (CLI/デスクトップ) では home-manager が claude/skills/ を
#   ~/.claude/skills/ に symlink するため全リポジトリで自動的に効くが、
#   Claude Code on the web は毎回まっさらな ephemeral コンテナで fresh clone
#   起動するため ~/.claude/ は一切引き継がれない。
#
# 方針:
#   正本は gotomts/dotfiles の claude/skills/ 一か所のまま。各リポジトリには
#   何も置かない。Setup script (root 実行・コンテナ起動時) で skills サブツリー
#   だけを sparse-checkout し ~/.claude/skills/ にコピーする。
#   ~/.claude/skills/ は作業リポジトリの外なので fresh clone の影響を受けず、
#   personal スコープとして全リポジトリ・全セッションで自動的に有効になる。
#
# 使い方 (クラウド環境の Setup script フィールドに 1 行貼る):
#   curl -fsSL https://raw.githubusercontent.com/gotomts/dotfiles/main/claude/web-skills-setup.sh | bash
#
# bash 前提 (Ubuntu 24.04 / root)。リポジトリの zsh スクリプト規約 (#!/bin/zsh)
# とは別系統で、クラウド側で動かす都合上 bash を使う。
set -euo pipefail

DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/gotomts/dotfiles}"
DOTFILES_REF="${DOTFILES_REF:-main}"
SKILLS_SUBPATH="claude/skills"
DEST="${HOME}/.claude/skills"
TMP="$(mktemp -d)"

cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

# skills サブツリーだけを blobless + sparse で取得 (リポジトリ全体は落とさない)
git clone --depth 1 --filter=blob:none --sparse --branch "${DOTFILES_REF}" \
  "${DOTFILES_REPO}" "${TMP}/dotfiles"
git -C "${TMP}/dotfiles" sparse-checkout set "${SKILLS_SUBPATH}"

mkdir -p "${DEST}"
cp -R "${TMP}/dotfiles/${SKILLS_SUBPATH}/." "${DEST}/"

count="$(find "${DEST}" -name SKILL.md | wc -l | tr -d ' ')"
echo "[web-skills-setup] injected ${count} skills into ${DEST}"
