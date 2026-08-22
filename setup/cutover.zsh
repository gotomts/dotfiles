#!/bin/zsh
# setup/cutover.zsh
#
# Tier 3: home-manager を含む flake から Homebrew/CLI/mise 層のみの flake へ
# 実機を切り替える。Tier 1 (setup/link.zsh) / Tier 2 (setup/*.zsh) 自体はオーケストレーション
# しない（責務を混ぜない。両者は独立して明示実行するものとして既に確立済み）。
#
# 設計根拠: docs/superpowers/specs/2026-08-22-restore-script-management-tier3-cutover-design.md
#
# 呼び出し規約: pam.zsh と同じくスクリプト自身は sudo を内部で呼ばない。
# 実機での実行は以下の形で行う（root 権限と USER 環境変数の両方が必要）:
#   sudo USER=$USER zsh ${HOME}/.dotfiles/setup/cutover.zsh
#
# 終了コード:
#   0  成功
#   1  pre-flight build 失敗（switch は実行されない）

set -eu

SETUP_DIR="${0:A:h}"
DOTFILES_ROOT="${SETUP_DIR:h}"
source "${SETUP_DIR}/lib/util.zsh"

util::info "=== Tier 3: cutover ==="

# ---------------------------------------------------------------------------
# 1. 現行世代を記録する（監査用ログ）。defaults.zsh の backup_once と異なり毎回記録する。
#    世代番号は switch のたびに変わるため「初回のみ」は不適切。
# ---------------------------------------------------------------------------
BACKUP_DIR="${HOME}/.dotfiles-cutover-backup"
mkdir -p "${BACKUP_DIR}"

timestamp="$(date +%Y%m%d%H%M%S)"
generations_log="${BACKUP_DIR}/pre-cutover-generations-${timestamp}.txt"

util::action "現行世代を記録: ${generations_log}"
darwin-rebuild --list-generations > "${generations_log}"

# ---------------------------------------------------------------------------
# 2. pre-flight ビルド確認（副作用なし）
# ---------------------------------------------------------------------------
util::info "=== pre-flight: nix build ==="
# --extra-experimental-features: darwin-rebuild 自体は nix-command/flakes を内蔵で
# 有効化して呼び出す生成物だが、ここは darwin-rebuild を経由しない素の `nix build`
# 直接呼び出しのため、システムの nix.conf が nix-command/flakes をデフォルト有効化
# していない環境（Determinate Nix 前提が崩れている、または未設定の素の Nix）では
# 明示しないと `experimental Nix feature 'nix-command' is disabled` で失敗する。
# CI (.github/workflows/nix-check.yml) はインストール直後の Determinate Nix で
# デフォルト有効なため未指定で足りるが、実機は環境依存のため明示して揃える。
if ! nix build "${DOTFILES_ROOT}/nix#darwinConfigurations.default.system" --no-link --impure \
    --extra-experimental-features "nix-command flakes"; then
    util::error "nix build に失敗しました。switch は実行しません"
    exit 1
fi

# ---------------------------------------------------------------------------
# 3. 実カットオーバー
# ---------------------------------------------------------------------------
util::info "=== darwin-rebuild switch ==="
darwin-rebuild switch --flake "${DOTFILES_ROOT}/nix#default" --impure

util::info "=== Tier 3: cutover 完了 ==="
util::info "問題が発生した場合は setup/rollback.zsh を実行してください"
