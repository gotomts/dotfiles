#!/bin/zsh
# setup/rollback.zsh
#
# Tier 3: setup/cutover.zsh 実行後に問題が見つかった場合、直前世代（home-manager を
# 含む生成物）へ戻す。home-manager 再活性化時に backupFileExtension = "before-nix" が
# 既存の .before-nix と衝突して失敗する既知リスクがあるため、実行前に .before-nix
# ファイルの残骸を検出し、見つかった場合は fail-closed で停止する
# （fs::ensure_realfile と同じ no-data-loss 方針。自動退避はしない）。
#
# 設計根拠: docs/superpowers/specs/2026-08-22-restore-script-management-tier3-cutover-design.md
#
# 呼び出し規約: pam.zsh/cutover.zsh と同じくスクリプト自身は sudo を内部で呼ばない。
# 実機での実行は以下の形で行う:
#   sudo zsh ${HOME}/.dotfiles/setup/rollback.zsh
#
# 終了コード:
#   0  成功
#   1  .before-nix の残骸を検出したため停止（darwin-rebuild は一切呼ばれない）

set -eu

SETUP_DIR="${0:A:h}"
source "${SETUP_DIR}/lib/util.zsh"

util::info "=== Tier 3: rollback ==="

# ---------------------------------------------------------------------------
# 1. .before-nix 残骸の検出（fail-closed）
#    (N) glob qualifier: マッチしない場合に空配列を返す（nullglob をこのパターンだけに適用）。
#    (D) glob qualifier: ドットディレクトリ (.config/.claude 等) の中も再帰的に見る
#    （zsh の既定では ** はドットで始まるパス要素を辿らないため、D なしだと
#    $HOME 配下の主要な管理対象 (.config/.claude/.codex 等) を素通りしてしまう）
# ---------------------------------------------------------------------------
stale_backups=("${HOME}"/**/*.before-nix(DN))

if (( ${#stale_backups[@]} > 0 )); then
    util::error "以下の .before-nix バックアップが既に存在するため rollback を中止します:"
    for backup_file in "${stale_backups[@]}"; do
        util::error "  ${backup_file}"
    done
    util::error "home-manager 再活性化時にこれらと衝突する可能性があります。"
    util::error "手動で確認・退避してから再実行してください（darwin-rebuild は実行していません）"
    exit 1
fi

# ---------------------------------------------------------------------------
# 2. rollback 実行
# ---------------------------------------------------------------------------
util::info "=== darwin-rebuild switch --rollback ==="
darwin-rebuild switch --rollback

util::info "=== Tier 3: rollback 完了 ==="
