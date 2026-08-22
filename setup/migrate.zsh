#!/bin/zsh
# setup/migrate.zsh
#
# 単一エントリポイント: これ以外のスクリプトを実機で直接叩かない。実機での real-machine
# migration/recovery はこのスクリプトからのみ行う（setup/README.md 参照）。
#
# 個々の Tier 1/2/3 スクリプト（link.zsh/languages.zsh/.../cutover.zsh）は、このスクリプトが
# 呼び出す内部実装として残る。直接実行は非推奨（メンテナンス作業時のみ）。
#
# 過去の部分適用インシデントの分析・依存順序の根拠:
# docs/superpowers/specs/2026-08-22-migrate-orchestrator-recovery-plan.md
#
# モード（どちらか一方を明示指定する。未指定は使い方を表示して終了コード1）:
#   --dry-run  現在の状態と実行計画を表示するだけ（副作用なし、manifest も書かない）
#   --apply    計画を実際に実行する（manifest に記録しながら進める）
#
# 依存順序（Phase 1 -> 2 -> 3。Phase 境界は厳格、Phase 内は blocked を skip して続行）:
#   Phase 1: link                       (symlink 配置。特権不要)
#   Phase 2: cutover, pam               (root 必須。cutover が先に darwin-rebuild switch で
#                                         Homebrew 経由の mise 等を導入する。languages.zsh 自身が
#                                         「mise が無ければ darwin-switch を先に」と要求している
#                                         ため、Phase 3 より前に置く。pam は cutover と同じく
#                                         root 必須なので同じ Phase にまとめ、sudo プロンプトを
#                                         1 回にまとめる)
#   Phase 3: languages, defaults, claude-sync, codex-sync  (非 root。mise は Phase 2 で導入済み)
#
# 安全設計:
#   - fail-closed: 実失敗（ステップの実コマンドが非ゼロ終了）が起きたら即座に全体を
#     停止する。以降のステップは一切実行しない
#   - no-automatic-rollback: setup/rollback.zsh は一切呼ばない。ロールバックは常に
#     人間が明示的に判断・実行する別作業（setup/rollback.zsh を直接参照すること）
#   - 権限ガード: cutover/pam は root 必須、それ以外は「root では実行しない」
#     （sudo 経由で $HOME に root 所有物が書き込まれる事故を防ぐ）。満たさない
#     ステップは blocked として記録し、同じ Phase 内の残りステップだけ試行を続け、
#     Phase 境界は厳格に守る（次の Phase には進まない）
#   - 冪等検知: manifest に success の記録があるステップは再実行せず skip する。
#     これにより「部分適用済みの実機」を安全に検出・再開できる
#   - 部分適用は健全な状態として扱わない: 全ステップが success になるまで
#     --apply は終了コード 1 を返し続ける。「動いているように見える」ことは
#     完了の根拠にしない（health check で実ファイル/実状態を確認する）
#   - health check: 全ステップ success 後、各ステップの実際の効果（symlink の実在・
#     生成物ファイルの実在等）を改めてファイルシステムから確認する。manifest の
#     success 記録だけを信用しない（「switch が成功したように見えて実は途中で
#     abort していた」系の既知インシデントへの対策）
#
# 終了コード:
#   0  (--dry-run) 計画表示に成功 / (--apply) 全ステップが success かつ health check 通過
#   1  preflight 失敗、モード未指定、計画未完了（blocked/fail が残っている）、
#      または health check 失敗

set -eu

SETUP_DIR="${0:A:h}"
source "${SETUP_DIR}/lib/util.zsh"

MIGRATE_STATE_DIR="${MIGRATE_STATE_DIR:-${HOME}/.dotfiles-migrate}"
MANIFEST="${MIGRATE_STATE_DIR}/manifest.log"

# ---------------------------------------------------------------------------
# ステップ定義（配列内の並び = 実行順序。Phase 番号が依存順序を表す）
# ---------------------------------------------------------------------------
PHASE1_STEPS=(link)
PHASE2_STEPS=(cutover pam)
PHASE3_STEPS=(languages defaults claude-sync codex-sync)

migrate::script_for() {
    echo "${SETUP_DIR}/${1}.zsh"
}

# migrate::requires_root <step>  root 必須なステップなら 0、そうでなければ 1
migrate::requires_root() {
    case "${1}" in
        cutover|pam) return 0 ;;
        *)           return 1 ;;
    esac
}

# migrate::euid  実効 EUID を返す。テストでは MIGRATE_EUID_OVERRIDE で差し替える
# （実プロセスの EUID は変更できないため。実機実行時は素の $EUID を使う）
migrate::euid() {
    echo "${MIGRATE_EUID_OVERRIDE:-${EUID}}"
}

# migrate::privilege_ok <step>  現在の実行コンテキストでそのステップを試みてよいか
migrate::privilege_ok() {
    local step="${1}"
    local euid_val
    euid_val="$(migrate::euid)"

    if migrate::requires_root "${step}"; then
        (( euid_val == 0 )) || return 1
        if [[ "${step}" == "cutover" ]]; then
            [[ -n "${USER:-}" && "${USER}" != "root" ]] || return 1
        fi
    else
        (( euid_val != 0 )) || return 1
    fi
    return 0
}

migrate::privilege_hint() {
    local step="${1}"
    case "${step}" in
        cutover)
            echo "root + USER env が必要です: sudo USER=\${USER} zsh ${SETUP_DIR}/migrate.zsh --apply"
            ;;
        pam)
            echo "root が必要です: sudo zsh ${SETUP_DIR}/migrate.zsh --apply"
            ;;
        *)
            echo "root では実行できません（sudo なしで再実行してください）"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# manifest（persistent transaction log）
# ---------------------------------------------------------------------------

# migrate::log_event <step> <status> [<detail>]
#   apply モードでのみ呼ばれる。呼ばれるまで ${MIGRATE_STATE_DIR} は作成しない
#   （dry-run が真に副作用ゼロであることを保証するため）。
migrate::log_event() {
    local step="${1}" status_val="${2}" detail="${3:-}"
    [[ -d "${MIGRATE_STATE_DIR}" ]] || mkdir -p "${MIGRATE_STATE_DIR}"
    printf '%s\t%s\t%s\t%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${step}" "${status_val}" "${detail}" \
        >> "${MANIFEST}"
}

# migrate::latest_status <step>
#   manifest 中でそのステップの最新の「終端状態」(success/fail/blocked) を返す。
#   記録が無ければ空文字列を返す（"start" は途中経過なので無視する）。
migrate::latest_status() {
    local step="${1}"
    [[ -f "${MANIFEST}" ]] || { echo ""; return 0; }
    awk -F'\t' -v s="${step}" \
        '$2==s && ($3=="success"||$3=="fail"||$3=="blocked") {line=$3} END{print line}' \
        "${MANIFEST}"
}

# ---------------------------------------------------------------------------
# 1 ステップの実行（apply モード）
#   戻り値: 0=success(または既に success で skip) / 1=実失敗 / 2=blocked
# ---------------------------------------------------------------------------
migrate::run_step() {
    local step="${1}"
    local latest
    latest="$(migrate::latest_status "${step}")"

    if [[ "${latest}" == "success" ]]; then
        util::skip "${step}: 既に success です（前回実行の manifest より）"
        return 0
    fi

    if ! migrate::privilege_ok "${step}"; then
        local hint
        hint="$(migrate::privilege_hint "${step}")"
        util::warning "${step}: blocked - ${hint}"
        migrate::log_event "${step}" "blocked" "${hint}"
        return 2
    fi

    util::action "${step}: 実行開始 ($(migrate::script_for "${step}"))"
    migrate::log_event "${step}" "start"
    if zsh "$(migrate::script_for "${step}")"; then
        util::info "${step}: success"
        migrate::log_event "${step}" "success"
        return 0
    else
        util::error "${step}: 失敗しました"
        migrate::log_event "${step}" "fail"
        return 1
    fi
}

# migrate::steps_for <phase1|phase2|phase3>  対応するステップ配列を echo で返す
migrate::steps_for() {
    case "${1}" in
        phase1) echo "${PHASE1_STEPS[@]}" ;;
        phase2) echo "${PHASE2_STEPS[@]}" ;;
        phase3) echo "${PHASE3_STEPS[@]}" ;;
    esac
}

# migrate::run_phase <phase名>
#   Phase 内の全ステップを順に試みる（blocked は skip して次のステップへ進む。
#   実失敗のみ即座に return 1 で全体を止める）。全ステップ試行後、Phase 内が
#   全て success でなければ return 2（blocked のまま = Phase 境界で停止）。
migrate::run_phase() {
    local phase_name="${1}"
    local -a steps
    steps=(${(z)$(migrate::steps_for "${phase_name}")})

    local step rc
    for step in "${steps[@]}"; do
        if migrate::run_step "${step}"; then
            rc=0
        else
            rc=$?
        fi
        if (( rc == 1 )); then
            return 1
        fi
    done

    for step in "${steps[@]}"; do
        if [[ "$(migrate::latest_status "${step}")" != "success" ]]; then
            return 2
        fi
    done
    return 0
}

# ---------------------------------------------------------------------------
# health check（apply が全ステップ success を報告した後の独立検証）
#   manifest の自己申告を信用せず、実ファイル/実状態を確認する。
#   1 件でも欠けていれば apply 全体を失敗として扱う。
# ---------------------------------------------------------------------------
migrate::health_check() {
    local -a failures=()

    [[ -L "${HOME}/.zshrc" ]] || failures+=("link: ${HOME}/.zshrc が symlink ではありません")

    local pam_target="${SUDO_LOCAL_PATH:-/etc/pam.d/sudo_local}"
    [[ -f "${pam_target}" ]] || failures+=("pam: ${pam_target} が存在しません")

    local backup_glob=("${HOME}"/.dotfiles-cutover-backup/pre-cutover-generations-*.txt(N))
    (( ${#backup_glob[@]} >= 1 )) || failures+=("cutover: ${HOME}/.dotfiles-cutover-backup/ に世代バックアップがありません")

    command -v mise &>/dev/null || failures+=("languages: mise が PATH 上に見つかりません")

    [[ -d "${HOME}/.dotfiles-defaults-backup" ]] || failures+=("defaults: ${HOME}/.dotfiles-defaults-backup/ がありません（初回スナップショット未取得）")

    [[ -f "${HOME}/.claude.json" ]] || failures+=("claude-sync: ${HOME}/.claude.json がありません")

    [[ -f "${HOME}/.codex/config.toml" ]] || failures+=("codex-sync: ${HOME}/.codex/config.toml がありません")

    if (( ${#failures[@]} > 0 )); then
        util::error "=== health check 失敗: manifest 上は success でも実状態が伴っていません ==="
        local f
        for f in "${failures[@]}"; do
            util::error "  - ${f}"
        done
        return 1
    fi

    util::info "health check: 全ステップの実効果を確認しました"
    return 0
}

migrate::apply() {
    util::info "=== migrate: apply ==="
    local phase_name rc
    for phase_name in phase1 phase2 phase3; do
        if migrate::run_phase "${phase_name}"; then
            rc=0
        else
            rc=$?
        fi
        if (( rc == 1 )); then
            util::error "=== migrate: 実失敗のため停止しました（部分適用は健全な状態ではありません。自動ロールバックは行いません。setup/rollback.zsh は手動判断でのみ実行してください） ==="
            return 1
        elif (( rc == 2 )); then
            util::error "=== migrate: ${phase_name} が未完了のため停止しました（部分適用は健全な状態ではありません。blocked ステップを解消してから再実行してください） ==="
            return 1
        fi
    done

    if ! migrate::health_check; then
        return 1
    fi

    util::info "=== migrate: 全ステップ success で完了しました ==="
    return 0
}

# ---------------------------------------------------------------------------
# dry-run（副作用なし）
# ---------------------------------------------------------------------------
migrate::dry_run() {
    util::info "=== migrate: dry-run（計画表示のみ、副作用なし） ==="
    local phase_name step latest
    for phase_name in phase1 phase2 phase3; do
        local -a steps
        steps=(${(z)$(migrate::steps_for "${phase_name}")})
        echo "--- ${phase_name} ---"
        for step in "${steps[@]}"; do
            latest="$(migrate::latest_status "${step}")"
            if [[ "${latest}" == "success" ]]; then
                echo "  [SKIP] ${step}: 既に success です"
            elif ! migrate::privilege_ok "${step}"; then
                echo "  [BLOCKED] ${step}: $(migrate::privilege_hint "${step}")"
            else
                echo "  [WOULD RUN] ${step}: $(migrate::script_for "${step}")"
            fi
        done
    done
    echo "---"
    echo "部分適用は健全な状態として扱いません。全ステップが success になるまで"
    echo "--apply を再実行してください（fail-closed。自動ロールバックはしません）。"
}

# ---------------------------------------------------------------------------
# preflight（dry-run/apply 共通）
# ---------------------------------------------------------------------------
migrate::preflight() {
    local os
    os="${MIGRATE_UNAME_OVERRIDE:-$(uname -s)}"
    if [[ "${os}" != "Darwin" ]]; then
        util::error "この orchestrator は macOS 専用です (uname -s = ${os})"
        return 1
    fi

    local step script
    for step in "${PHASE1_STEPS[@]}" "${PHASE2_STEPS[@]}" "${PHASE3_STEPS[@]}"; do
        # 防御的二重チェック: no-automatic-rollback ポリシーは「rollback.zsh を
        # コードのどこからも呼ばない」ことで成り立っている。将来の変更が誤って
        # rollback を PHASE*_STEPS に追加してしまう事故を、grep によるソース
        # テキスト検査（setup/tests/migrate.bats）だけでなく実行時にも検出する。
        if [[ "${step}" == "rollback" ]]; then
            util::error "rollback は PHASE*_STEPS に含めてはいけません（no-automatic-rollback ポリシー違反）"
            return 1
        fi

        script="$(migrate::script_for "${step}")"
        if [[ ! -f "${script}" ]]; then
            util::error "想定するスクリプトが見つかりません: ${script}（チェックアウトが壊れている可能性があります）"
            return 1
        fi
    done
    return 0
}

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
migrate::usage() {
    cat <<EOF
使い方: zsh ${SETUP_DIR}/migrate.zsh (--dry-run|--apply)

  --dry-run   現在の状態と実行計画を表示する（副作用なし、manifest も書かない）
  --apply     計画を実際に実行する（Phase 1 -> Phase 2 -> Phase 3 の順、manifest に記録）

Phase 1: link (非 root)
Phase 2: cutover, pam (root 必須。sudo で実行すること)
Phase 3: languages, defaults, claude-sync, codex-sync (非 root)

個別スクリプト（link.zsh 等）は内部実装です。実機での実行はこのスクリプトからのみ
行ってください。詳細は setup/README.md を参照。
EOF
}

MODE="${1:-}"

case "${MODE}" in
    --dry-run)
        migrate::preflight || exit 1
        migrate::dry_run
        exit 0
        ;;
    --apply)
        migrate::preflight || exit 1
        if migrate::apply; then
            exit 0
        else
            exit 1
        fi
        ;;
    *)
        migrate::usage
        exit 1
        ;;
esac
