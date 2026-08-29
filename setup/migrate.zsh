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
# 実行形態: 単一の root 起動 (`sudo zsh migrate.zsh --apply`) で全 Phase が完結する。
#   sudo が自動設定する SUDO_USER から元ユーザーを特定し、非 root ステップ (Phase 1/3) は
#   `sudo -u <元ユーザー> -H` で元ユーザーへ委譲実行する（$HOME が root 化する事故を防ぐ）。
#   root 必須ステップ (Phase 2) はそのまま root で実行するが、USER 環境変数だけ元ユーザーに
#   補正して渡す（cutover.zsh の `nix build --impure` がユーザー名解決に USER を使うため）。
#   元ユーザーを特定できない場合（SUDO_USER 未設定など）は fail-closed で blocked にする。
#   非 root のまま `zsh migrate.zsh --apply` を直接叩く従来の起動（root 必須ステップは
#   blocked のまま進まない）も引き続き使える。
#
# 依存順序（Phase 1 -> 2 -> 3。Phase 境界は厳格、Phase 内は blocked を skip して続行）:
#   Phase 1: link                       (symlink 配置。root 起動時は元ユーザーへ委譲)
#   Phase 2: cutover, pam               (root 必須。cutover が先に darwin-rebuild switch で
#                                         Homebrew 経由の mise 等を導入する。languages.zsh 自身が
#                                         「mise が無ければ darwin-switch を先に」と要求している
#                                         ため、Phase 3 より前に置く。pam は cutover と同じく
#                                         root 必須なので同じ Phase にまとめ、sudo プロンプトを
#                                         1 回にまとめる)
#   Phase 3: languages, defaults, claude-sync, codex-sync, herdr-sync  (root 起動時は元ユーザーへ
#                                         委譲。
#                                         mise は Phase 2 で導入済み)
#
# 安全設計:
#   - fail-closed: 実失敗（ステップの実コマンドが非ゼロ終了）が起きたら即座に全体を
#     停止する。以降のステップは一切実行しない
#   - no-automatic-rollback: setup/rollback.zsh は一切呼ばない。ロールバックは常に
#     人間が明示的に判断・実行する別作業（setup/rollback.zsh を直接参照すること）
#   - 権限ガード: cutover/pam は root 必須かつ元ユーザーを特定できること。それ以外の
#     ステップは、非 root ならそのまま実行、root 起動なら元ユーザーが特定できる場合のみ
#     `sudo -u <元ユーザー> -H` で委譲実行する（$HOME に root 所有物が書き込まれる事故を
#     防ぐ）。元ユーザーが特定できないステップは blocked として記録し、同じ Phase 内の
#     残りステップだけ試行を続け、Phase 境界は厳格に守る（次の Phase には進まない）
#   - 冪等検知: manifest に success の記録があるステップは再実行せず skip する。
#     これにより「部分適用済みの実機」を安全に検出・再開できる。ただし cutover は
#     manifest の success だけでは skip 可としない。次の 2 つを都度再検証し、どちらかが
#     崩れていれば manifest に `postcondition-unmet` を記録したうえで同じ --apply 内で
#     cutover を再実行する（migrate::skippable / migrate::cutover_rerun_reason）:
#       1. postcondition（mise/starship 等、desired Homebrew set の必須バイナリが実在
#          すること）。desired set が switch 後に変わった場合（例: starship を後から
#          追加）、古い success はもう postcondition を保証しない（実機インシデント、
#          2026-08-22）
#       2. 直近 success 時に記録した desired-input fingerprint（nix/ 配下の構成と
#          flake.lock、/etc/dotfiles-role、~/.config/dotfiles/homebrew.local.nix）が
#          現在値と一致すること。1 だけでは「main を pull して宣言にアプリが増えた」
#          ケースを検出できない（必須バイナリは前回の switch のまま残っているので
#          skip され、増えたアプリが適用されない）。fingerprint の記録が無い旧 manifest
#          は安全側に 1 度だけ再実行する
#   - PAM/cutover の所有権結合: nix-darwin の activation は pam.d/sudo_local を
#     「macOS 純正デフォルトへの symlink であること」以外一切許容しない（許容ハッシュが
#     常に空）。setup/pam.zsh が Touch ID 内容へ書き換え済みの状態で switch すると
#     activation ごと abort する。そのため cutover 実行の直前に pam.zsh の
#     `.before-setup` バックアップから pristine 状態へ一時復元し（想定外の形なら
#     fail-closed で switch 自体を止める）、switch 成功後は pam の manifest success を
#     `invalidated` にして同じ Phase 内で必ず再実行させる（migrate::skippable が
#     success 以外を再実行対象として扱う既存ロジックにそのまま乗る）。cutover が
#     再実行されるたびに同じ手順を踏む（実機インシデント、2026-08-22）。復元自体は
#     既存の宛先へ直接 mv せず、nix-darwin 自身の /etc 置換手順と同じ「新規パスへ退避
#     してから空いたパスへ置く」形を取る（既存宛先への直接 mv は macOS 側が
#     "Operation not permitted" を返した実機インシデントあり、2026-08-23）。退避した
#     ファイルは、switch 後の pam 再適用が success し、かつ内容が再適用後の pam.d/sudo_local
#     と byte-for-byte 一致するときだけ削除する（複製にすぎないと確認できた場合のみ）。
#     cutover か pam が失敗した場合、および手書き追加ルール等で内容が一致しない場合は
#     その内容の唯一の控えなので残す（migrate::pam_discard_vacated）
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
source "${SETUP_DIR}/lib/herdr.zsh"

# ---------------------------------------------------------------------------
# ステップ定義（配列内の並び = 実行順序。Phase 番号が依存順序を表す）
# ---------------------------------------------------------------------------
PHASE1_STEPS=(link)
PHASE2_STEPS=(cutover pam)
PHASE3_STEPS=(languages defaults claude-sync codex-sync herdr-sync)

# この --apply の中で cutover 直前に退避した Touch ID ファイルのパス（
# migrate::pam_restore_pristine_if_safe が設定し、migrate::pam_discard_vacated が使う）。
MIGRATE_PAM_VACATED_PATH=""

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

# migrate::original_user  root 起動時に「元ユーザー」として扱う値を返す。
#   優先順位: テスト用 override > sudo が自動設定する SUDO_USER > $USER（非 root 実行時や
#   旧来の `sudo USER=$USER zsh migrate.zsh` 起動との後方互換用）。
#   特定できなければ空文字列を返す（呼び出し側で fail-closed に扱うこと）。
migrate::original_user() {
    echo "${MIGRATE_SUDO_USER_OVERRIDE:-${SUDO_USER:-${USER:-}}}"
}

# migrate::original_user_ok  元ユーザーを一意に特定できているか（非空かつ root でない）
migrate::original_user_ok() {
    local orig_user
    orig_user="$(migrate::original_user)"
    [[ -n "${orig_user}" && "${orig_user}" != "root" ]]
}

# migrate::home_for_user <user>  Directory Service から <user> の実ホームディレクトリを
#   解決する（$HOME 環境変数には依存しない。root プロセス自身の $HOME は sudo の
#   env_reset で /var/root 化していることがあるため、名前引きで確実に取得する）。
#   テストでは MIGRATE_HOME_FOR_USER_OVERRIDE で差し替える（dscl が無いサンドボックス用）。
migrate::home_for_user() {
    local user="${1}"
    if [[ -n "${MIGRATE_HOME_FOR_USER_OVERRIDE:-}" ]]; then
        echo "${MIGRATE_HOME_FOR_USER_OVERRIDE}"
        return 0
    fi
    dscl . -read "/Users/${user}" NFSHomeDirectory 2>/dev/null | awk '{print $NF}'
}

# migrate::effective_home  manifest/health check が参照すべき「元ユーザーのホーム」を返す。
#   root 起動かつ元ユーザーを特定できるときはそのユーザーの実ホームを解決して返す
#   （委譲実行された各ステップスクリプトが実際に書き込んだ先と一致させるため）。
#   それ以外（非 root 実行、または元ユーザー未特定）は素の $HOME をそのまま使う。
#   解決に失敗した場合は空文字列を返す（呼び出し側で fail-closed に扱うこと。$HOME への
#   だまし込みフォールバックはしない。root 自身の $HOME と元ユーザーの $HOME を取り違えて
#   manifest/health check が誤った場所を見に行く事故を防ぐため）。
migrate::effective_home() {
    local euid_val orig_user resolved
    euid_val="$(migrate::euid)"
    if (( euid_val == 0 )) && migrate::original_user_ok; then
        orig_user="$(migrate::original_user)"
        resolved="$(migrate::home_for_user "${orig_user}")"
        echo "${resolved}"
        return 0
    fi
    echo "${HOME}"
}

# migrate::privilege_ok <step>  現在の実行コンテキストでそのステップを試みてよいか
migrate::privilege_ok() {
    local step="${1}"
    local euid_val
    euid_val="$(migrate::euid)"

    if migrate::requires_root "${step}"; then
        (( euid_val == 0 )) || return 1
        if [[ "${step}" == "cutover" ]]; then
            migrate::original_user_ok || return 1
        fi
    else
        # 非 root ステップ: 非 root 実行ならそのまま許可。root 起動（単一 sudo 起動）の
        # 場合は、委譲先の元ユーザーを一意に特定できるときだけ許可する
        # （特定できないまま root で直接実行すると $HOME に root 所有物が紛れ込む）。
        if (( euid_val == 0 )); then
            migrate::original_user_ok || return 1
        fi
    fi
    return 0
}

migrate::privilege_hint() {
    local step="${1}"
    case "${step}" in
        cutover)
            echo "root 権限と、元ユーザーの特定（sudo 経由なら SUDO_USER が自動設定される）の両方が必要です: sudo zsh ${SETUP_DIR}/migrate.zsh --apply"
            ;;
        pam)
            echo "root が必要です: sudo zsh ${SETUP_DIR}/migrate.zsh --apply"
            ;;
        *)
            if (( $(migrate::euid) == 0 )); then
                echo "root 起動では元ユーザーを特定できないため委譲実行できません（SUDO_USER 未設定など）"
            else
                echo "root では実行できません（sudo なしで再実行してください）"
            fi
            ;;
    esac
}

# ---------------------------------------------------------------------------
# manifest（persistent transaction log）
# ---------------------------------------------------------------------------

# migrate::bootstrap_state_dir  MIGRATE_STATE_DIR/MANIFEST を確定する（グローバル変数への
#   代入なので関数定義がすべて揃った後、CLI ディスパッチの直前で呼ぶこと）。root 起動時は
#   元ユーザーの実ホームを基準にする（root 自身の $HOME を使うと、委譲実行された各ステップが
#   実際に書き込んだ先と manifest の置き場所がズレる）。解決できなければ fail-closed で
#   呼び出し側に非 0 を返す（$HOME へのフォールバックはしない）。
migrate::bootstrap_state_dir() {
    local home_dir
    home_dir="$(migrate::effective_home)"
    if [[ -z "${home_dir}" ]]; then
        util::error "元ユーザー($(migrate::original_user))の実ホームディレクトリを解決できませんでした（dscl 失敗）。中断します"
        return 1
    fi
    MIGRATE_STATE_DIR="${MIGRATE_STATE_DIR:-${home_dir}/.dotfiles-migrate}"
    MANIFEST="${MIGRATE_STATE_DIR}/manifest.log"
    return 0
}

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
#   manifest 中でそのステップの最新の「終端状態」(success/fail/blocked/invalidated) を
#   返す。記録が無ければ空文字列を返す（"start"/"postcondition-unmet" は途中経過の
#   イベントなので無視する）。invalidated は「過去に success したが、他ステップの
#   再実行により前提が崩れたので skip 対象から外す」ことを明示する終端状態
#   （migrate::skippable 参照。cutover 再実行後の pam 等）。
migrate::latest_status() {
    local step="${1}"
    [[ -f "${MANIFEST}" ]] || { echo ""; return 0; }
    awk -F'\t' -v s="${step}" \
        '$2==s && ($3=="success"||$3=="fail"||$3=="blocked"||$3=="invalidated") {line=$3} END{print line}' \
        "${MANIFEST}"
}

# migrate::command_available <name>  <name> が実行可能か（PATH 直接 + Homebrew prefix
#   フォールバックの両方で確認）。root（migrate.zsh 自身）の PATH は nix-darwin 生成の
#   /etc/zshenv の無条件上書きで Homebrew prefix を含まないことがあるため
#   （setup/lib/util.zsh の util::ensure_homebrew_path 参照）、同じ prefix を足した PATH
#   でも試す。テストでは HOMEBREW_PATH_PREFIX_OVERRIDE で差し替える。
migrate::command_available() {
    local name="${1}"
    local homebrew_paths="${HOMEBREW_PATH_PREFIX_OVERRIDE:-/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin}"
    command -v "${name}" &>/dev/null && return 0
    PATH="${homebrew_paths}:${PATH}" command -v "${name}" &>/dev/null
}

# migrate::nix_dir  fingerprint の対象にする nix 宣言ディレクトリ。テストでは
#   MIGRATE_NIX_DIR_OVERRIDE で差し替える（このリポジトリ自身の nix/ を書き換えずに
#   「宣言が変わった」状況を再現するため）。
migrate::nix_dir() {
    echo "${MIGRATE_NIX_DIR_OVERRIDE:-${SETUP_DIR:h}/nix}"
}

# migrate::fingerprint_entry <label> <path>
#   fingerprint 材料の 1 行を出力する。ファイルの内容だけでなく「不在」も明示的に
#   区別する（不在 -> 在、在 -> 不在のどちらも desired set を変えるため）。
#   変数名に `path` を使わないこと: zsh の `path` は PATH に結び付いた特殊配列で、
#   `local path=...` はこの関数の中だけ PATH を壊し、shasum すら解決できなくなる。
migrate::fingerprint_entry() {
    local label="${1}" entry_path="${2}"
    if [[ -f "${entry_path}" ]]; then
        printf '%s\tpresent\t%s\n' "${label}" "$(shasum -a 256 "${entry_path}" | awk '{print $1}')"
    else
        printf '%s\tabsent\n' "${label}"
    fi
}

# migrate::cutover_fingerprint  「次の switch の desired set を決める入力」の要約を返す。
#   材料:
#     - nix/ 配下の全ファイル（相対パス + 内容ハッシュ）。flake.lock・homebrew.nix・
#       role 分岐・plist/rb などの実データを一括で覆う。ファイルの追加・削除も
#       相対パスの一覧ごとハッシュするため検出できる
#     - nix/ 配下の symlink（相対パス + readlink 値）。リンク先を辿って内容を読むと、
#       リンクの張り替え自体（同じ内容の別ファイルへ向け直す等）を取りこぼすうえ、
#       dangling link で毎回 fingerprint が揺れる。リンクそのものを材料にする
#     - /etc/dotfiles-role の内容/不在（flake.nix が role を読んで desired set を切り替える）
#     - ~/.config/dotfiles/homebrew.local.nix の内容/不在（homebrew.nix が絶対パスで
#       import する、リポジトリ外の PC ローカル overlay）
#   nix/ 配下は「switch の結果に効かないファイル」（README 等）も含めて丸ごと覆う。
#   実際に効く入力だけを allowlist すると、宣言側の構造が変わったときに allowlist だけが
#   古くなり「変更を検知できない」死角が生まれる。余分な再実行（switch は冪等）より
#   検知漏れの方が高くつくため、安全側に倒している。
#   パスは nix ディレクトリからの相対で組むので、チェックアウト位置（~/.dotfiles か
#   worktree か）が変わっても fingerprint は変わらない。
migrate::cutover_fingerprint() {
    local nix_dir role_file home_dir
    nix_dir="$(migrate::nix_dir)"
    role_file="${DOTFILES_ROLE_FILE:-/etc/dotfiles-role}"
    home_dir="$(migrate::effective_home)"

    {
        if [[ -d "${nix_dir}" ]]; then
            # `result`/`result-*` は nix build の成果物 symlink（nix/.gitignore 済み）で
            # 宣言ではないため除外する。
            ( cd "${nix_dir}" && \
              find . \( -name 'result' -o -name 'result-*' \) -prune -o -type f -print \
              | LC_ALL=C sort \
              | while IFS= read -r f; do
                    printf 'nix\t%s\t%s\n' "${f}" "$(shasum -a 256 "${f}" | awk '{print $1}')"
                done )
            ( cd "${nix_dir}" && \
              find . \( -name 'result' -o -name 'result-*' \) -prune -o -type l -print \
              | LC_ALL=C sort \
              | while IFS= read -r l; do
                    printf 'nix-link\t%s\t%s\n' "${l}" "$(readlink "${l}")"
                done )
        else
            printf 'nix\tabsent\n'
        fi
        migrate::fingerprint_entry "role" "${role_file}"
        migrate::fingerprint_entry "homebrew-local" "${home_dir}/.config/dotfiles/homebrew.local.nix"
    } | shasum -a 256 | awk '{print $1}'
}

# migrate::recorded_cutover_fingerprint
#   manifest 上の cutover の最新の終端イベントに記録された fingerprint を返す。
#   fingerprint の概念が無かった頃の manifest（legacy）では detail が空なので、
#   空文字列を返す = 「記録なし」として呼び出し側が安全側に倒す。
migrate::recorded_cutover_fingerprint() {
    [[ -f "${MANIFEST}" ]] || { echo ""; return 0; }
    awk -F'\t' \
        '$2=="cutover" && ($3=="success"||$3=="fail"||$3=="blocked"||$3=="invalidated") {line=$4}
         END{ if (line ~ /^fingerprint=/) { sub(/^fingerprint=/, "", line); print line } }' \
        "${MANIFEST}"
}

# migrate::cutover_missing_bins  cutover の postcondition として必須の Homebrew バイナリの
#   うち、現在見つからないものを空白区切りで返す（空文字列なら全部揃っている）。mise は
#   languages.zsh が、starship は ~/.zshrc の prompt 初期化が直接依存する。homebrew.nix の
#   desired set 全体（約80 formula）を毎回検証するのは過剰なので、後続ステップ/シェル体験の
#   成否に直結する最小集合に絞る。
migrate::cutover_missing_bins() {
    local -a required_bins=(mise starship)
    local -a missing=()
    local bin
    for bin in "${required_bins[@]}"; do
        migrate::command_available "${bin}" || missing+=("${bin}")
    done
    echo "${missing[@]}"
}

# migrate::cutover_rerun_reason
#   manifest 上 cutover が success のときに、それでも再実行すべき理由を 1 行で返す
#   （空文字列なら skip 可）。cutover の postcondition は 2 つある:
#     1. 必須 Homebrew バイナリが実在すること（switch の効果が残っているか）
#     2. 直近 success 時に記録した desired-input fingerprint が現在値と一致すること
#        （宣言側が変わっていないか）
#   1 だけでは「main を pull して homebrew.nix にアプリが増えた」ケースを検出できない。
#   必須バイナリは前回の switch で入ったまま残っているので、宣言が変わっても skip され、
#   新しいアプリが永遠に適用されない。2 はその死角を塞ぐ。
#   fingerprint の記録が無い legacy manifest は「一致しない」扱いにして安全側に 1 度だけ
#   再実行する（その再実行で fingerprint が記録され、以降は通常どおり skip に戻る）。
migrate::cutover_rerun_reason() {
    local missing recorded current
    missing="$(migrate::cutover_missing_bins)"
    if [[ -n "${missing}" ]]; then
        echo "missing: ${missing}"
        return 0
    fi

    recorded="$(migrate::recorded_cutover_fingerprint)"
    if [[ -z "${recorded}" ]]; then
        echo "fingerprint: 前回 success に宣言入力の記録がありません（旧 manifest のため安全側に 1 度だけ再実行します）"
        return 0
    fi

    current="$(migrate::cutover_fingerprint)"
    if [[ "${recorded}" != "${current}" ]]; then
        echo "fingerprint: 宣言入力が変わりました（記録: ${recorded[1,12]} / 現在: ${current[1,12]}）"
        return 0
    fi

    echo ""
}

# migrate::skippable <step>  そのステップを「manifest 上 success だから skip してよい」と
#   判定してよいか。cutover は manifest の自己申告だけでなく、postcondition
#   （migrate::cutover_rerun_reason 参照: 必須 Homebrew バイナリの実在 + desired-input
#   fingerprint の一致）も満たしているときのみ skip 可とする。
#   health check（apply 完了後の独立検証）と同じ「manifest の自己申告を信用しない」方針を
#   skip 判定そのものにも適用する（実機インシデント、2026-08-22）。
migrate::skippable() {
    local step="${1}"
    [[ "$(migrate::latest_status "${step}")" == "success" ]] || return 1
    if [[ "${step}" == "cutover" ]]; then
        [[ -z "$(migrate::cutover_rerun_reason)" ]] || return 1
    fi
    return 0
}

# migrate::pam_static_default <target>  <target> の「macOS 純正デフォルト」パスを返す。
#   nix-darwin 自身の activation スクリプトが使う規約 (etcStaticFile=/etc/static/$subPath)
#   と同じ導出規則: 先頭の /etc/ を /etc/static/ に置き換える。テストでは
#   SUDO_LOCAL_STATIC_DEFAULT で差し替える（サンドボックスは /etc 配下に書けないため）。
#
#   注意: `${target/#\/etc\//\/etc\/static\/}` 形式は使わないこと。zsh の
#   ${var/pattern/replacement} はパターン側の `\/` は「リテラルな /」と解釈するが、
#   置換文字列側の `\/` はバックスラッシュを剥がさずそのまま出力に残す非対称な挙動を
#   持つため、結果が `\/etc\/static\/...`（バックスラッシュ付き）になり、実際の
#   symlink 先（バックスラッシュ無し）と一致しなくなる（実機インシデントで確認済み、
#   2026-08-23）。prefix 除去 + 文字列連結という、スラッシュのエスケープが一切不要な
#   形で組み立てる。
migrate::pam_static_default() {
    local target="${1}"
    if [[ -n "${SUDO_LOCAL_STATIC_DEFAULT:-}" ]]; then
        echo "${SUDO_LOCAL_STATIC_DEFAULT}"
        return 0
    fi
    if [[ "${target}" == /etc/* ]]; then
        echo "/etc/static/${target#/etc/}"
    else
        echo "${target}"
    fi
}

# migrate::pam_restore_pristine_if_safe <target>
#   cutover（darwin-rebuild switch）実行の直前に呼ぶ。nix-darwin の activation は
#   pam.d/sudo_local を「macOS 純正デフォルトへの symlink であること」以外の内容を
#   一切許容しない（許容ハッシュ一覧が空、実機インシデントで確認済み）。setup/pam.zsh が
#   既に Touch ID 内容へ書き換え済みの状態で switch すると "Unexpected files in /etc,
#   aborting activation" で活性化ごと失敗する。
#
#   pam.zsh 自身が作った <target>.before-setup（元の pristine symlink の退避）が
#   「本当に想定どおりの形」だと検証できたときだけ、それを <target> へ戻す
#   （setup/pam.zsh の mv の逆操作）。これにより switch の瞬間だけ pristine 状態に戻り、
#   switch 成功後は migrate::run_step が pam を強制再実行して Touch ID 内容を復元する。
#
#   <target> へ直接 `mv <backup> <target>` すると（既存の宛先への置換 mv）、実機で
#   macOS 側が "Operation not permitted" を返した（実機インシデント、2026-08-23）。
#   nix-darwin 自身の /etc 置換手順（activate スクリプトの etc リンク処理）も
#   pam.zsh 自身の書き込みも、既存の宛先へ直接 mv したことは一度も無く、必ず
#   「新規/未使用のパスへ退避してから、空になったパスへ新しく置く」形を取っている。
#   それに合わせ、<target> に何か存在する場合はまず一意な新規パス
#   （<target>.before-restore.<timestamp>）へ退避し、それが完了してから
#   <backup> を <target> へ移す（こちらも「空になったパスへ mv」であり置換ではない）。
#
#   <target> が既に pristine（想定どおりの symlink）な場合、および <target> と
#   バックアップの両方が存在しない（真の初回、pam.zsh がまだ一度も走っていない）場合は
#   何もせず 0 を返す。<target> が存在して pristine でないのにバックアップが無い場合は、
#   pristine が何だったかの記録が無いまま上書きすることになるため fail-closed で 1 を返す。
#   バックアップが存在するのに symlink でない、リンク先が想定と異なる、または
#   退避先パスが既に存在する（想定外の残骸の可能性）場合も fail-closed で 1 を返し、
#   呼び出し側は switch を実行してはならない（不明な状態を盲信して復元しない）。
#   退避先の時刻部分はテストでは MIGRATE_PAM_VACATE_SUFFIX_OVERRIDE で固定できる
#   （秒境界をまたぐ flaky なテストを避けるため）。
migrate::pam_restore_pristine_if_safe() {
    local target="${1}"
    local backup="${target}.before-setup"
    local expected_static
    expected_static="$(migrate::pam_static_default "${target}")"

    # 既に pristine なら何もしない（nix-darwin 自身の etc リンク処理と同じ
    # 「一致していれば触らない」ショートカット）。
    if [[ -L "${target}" && "$(readlink "${target}")" == "${expected_static}" ]]; then
        return 0
    fi

    if [[ ! -e "${backup}" && ! -L "${backup}" ]]; then
        # バックアップが無いケースは 2 つあり、扱いが正反対になる。
        #   <target> も無い: 真の初回（pam.zsh がまだ一度も走っていない）。restore する
        #     ものも守るものも無く、nix-darwin から見ても既に pristine なので通す。
        #   <target> はある: pam.zsh か人が書いた非 pristine な内容が居座っているのに、
        #     pristine が何だったかの記録が無い。ここで内容を推測して上書きすると、
        #     その内容を記録している唯一のファイルを壊す。switch 前に停止する。
        if [[ ! -e "${target}" && ! -L "${target}" ]]; then
            return 0
        fi
        util::error "pam: ${target} は pristine ではないのに ${backup} がありません（pristine の記録が無いため内容を推測して復元しません）"
        return 1
    fi

    if [[ ! -L "${backup}" ]]; then
        util::error "pam: ${backup} がシンボリックリンクではありません（想定外のバックアップ形式のため復元しません）"
        return 1
    fi

    local backup_link_target
    backup_link_target="$(readlink "${backup}")"
    if [[ "${backup_link_target}" != "${expected_static}" ]]; then
        util::error "pam: ${backup} のリンク先が想定と異なります（実際: ${backup_link_target} / 期待: ${expected_static}）。復元しません"
        return 1
    fi

    if [[ -e "${target}" || -L "${target}" ]]; then
        local vacate_name
        vacate_name="${target}.before-restore.${MIGRATE_PAM_VACATE_SUFFIX_OVERRIDE:-$(date -u +%Y%m%dT%H%M%SZ)}"
        if [[ -e "${vacate_name}" || -L "${vacate_name}" ]]; then
            util::error "pam: 退避先 ${vacate_name} が既に存在するため復元しません（想定外の残骸の可能性）"
            return 1
        fi
        util::action "pam: cutover 実行前に ${target} を ${vacate_name} へ退避します（既存宛先への直接 mv はしない）"
        /bin/mv "${target}" "${vacate_name}"
        MIGRATE_PAM_VACATED_PATH="${vacate_name}"
        migrate::log_event "pam" "vacated" "${target} moved to ${vacate_name} pending switch"
    fi

    util::action "pam: ${backup} を ${target} へ移動し pristine 状態に戻します"
    /bin/mv "${backup}" "${target}"
}

# migrate::pam_discard_vacated
#   同じ --apply の中で cutover 直前に退避した Touch ID ファイル（
#   migrate::pam_restore_pristine_if_safe が作った <target>.before-restore.<timestamp>）を
#   後始末する。呼ぶのは「switch 後の pam 再適用が success した直後」だけ。その時点で
#   pam.zsh が Touch ID 内容を書き直しているので、退避ファイルはその複製にすぎない。
#
#   宣言側の変更で cutover が日常的に走るようになったため、掃除しないと switch のたびに
#   <target>.before-restore.<timestamp> が /etc/pam.d に増え続ける。一方で cutover か pam の
#   どちらかが失敗した場合、この退避ファイルは Touch ID 内容の唯一の控えなので絶対に
#   消さない（失敗時はこの関数に到達しない）。
#
#   削除対象はこの実行が自分で作った 1 パスだけを追跡して指す。glob で
#   <target>.before-restore.* をまとめて消すことはしない（別の実行が残した、まだ復旧に
#   使うかもしれない退避ファイルを巻き込むため）。
#
#   さらに「通常ファイルであること」だけでは削除の根拠にしない: 退避ファイルの内容が
#   再適用後の <target> と byte-for-byte 一致することまで確認する。pam.zsh は自前の
#   固定テンプレートで <target> を書き直すので、この PC で手書き追加したルール
#   （pam_reattach 行など）は退避コピーの側にしか残らない。一致しないものを消すと、
#   その内容の唯一の控えを破壊することになる。一致しなければ削除せず警告を残すが、
#   pam ステップ自体は success のまま扱う（掃除の見送りは失敗ではない）。
migrate::pam_discard_vacated() {
    local vacated="${MIGRATE_PAM_VACATED_PATH}"
    [[ -n "${vacated}" ]] || return 0
    MIGRATE_PAM_VACATED_PATH=""

    if [[ ! -f "${vacated}" || -L "${vacated}" ]]; then
        util::warning "pam: 退避ファイル ${vacated} が想定外の形のため削除しません（手動で確認してください）"
        migrate::log_event "pam" "vacated-kept" "${vacated} left in place (unexpected shape)"
        return 0
    fi

    # `cmp` の非ゼロ終了（内容不一致=1 / 読めない等のエラー=2）で set -e に
    # 巻き込まれないよう、|| で受けてから判定する。
    local target="${SUDO_LOCAL_PATH:-/etc/pam.d/sudo_local}"
    local cmp_rc=0
    cmp -s "${vacated}" "${target}" || cmp_rc=$?
    if (( cmp_rc != 0 )); then
        util::warning "pam: 退避ファイル ${vacated} の内容が現在の ${target} と一致しないため削除しません（この PC 固有の手書き設定が含まれている可能性があります）"
        migrate::log_event "pam" "vacated-kept" "${vacated} differs from ${target}; left in place"
        return 0
    fi

    util::action "pam: 再適用後の ${target} と同内容のため退避ファイル ${vacated} を削除します"
    /bin/rm -f "${vacated}"
    migrate::log_event "pam" "vacated-discarded" "${vacated} removed after pam reapplied"
}

# migrate::run_as_original_user <user> <script>
#   非 root ステップを root 起動から元ユーザーへ委譲実行する。`-H` で HOME も元ユーザーの
#   ものに補正する（sudo の env_reset で $HOME が /var/root 化する事故を避けるため）。
#   ここで渡す PATH（sudo の env_reset で失われる Homebrew prefix の補い）は気休め程度の
#   防御に過ぎない: 委譲先で実行される zsh 自身が nix-darwin 生成の /etc/zshenv を必ず
#   source し、そこが PATH を無条件で上書きするため、~/.zshenv より前にここで足した値は
#   実際には失われる（実機インシデントで確認済み、2026-08-22）。Homebrew 経由の実行体
#   （mise/corepack 等）に依存するスクリプト側が util::ensure_homebrew_path で自衛するのが
#   唯一の保証になる（setup/languages.zsh 参照）。ここでの付与は非 zsh スクリプトを
#   委譲する将来のケースへの保険として残す。
migrate::run_as_original_user() {
    local user="${1}" script="${2}"
    local homebrew_paths="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin"
    sudo -u "${user}" -H env "PATH=${homebrew_paths}:${PATH}" zsh "${script}"
}

# ---------------------------------------------------------------------------
# 1 ステップの実行（apply モード）
#   戻り値: 0=success(または既に success で skip) / 1=実失敗 / 2=blocked
# ---------------------------------------------------------------------------
migrate::run_step() {
    local step="${1}"

    if migrate::skippable "${step}"; then
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

    if [[ "$(migrate::latest_status "${step}")" == "success" ]]; then
        # skippable が false なのに manifest は success = postcondition 不一致
        # （現状 cutover のみ該当）。success のまま黙って再実行はせず、manifest に
        # 理由を残してから通常の実行フローに合流する。
        local reason
        reason="$(migrate::cutover_rerun_reason)"
        util::warning "${step}: 既に success ですが postcondition 未達成のため再実行します (${reason})"
        migrate::log_event "${step}" "postcondition-unmet" "${reason}"
    fi

    local script euid_val rc
    script="$(migrate::script_for "${step}")"
    euid_val="$(migrate::euid)"
    # cutover の success に記録する fingerprint は、switch を起動する直前に確定させる
    # （下の cutover 分岐を参照）。switch 完了後に取ると、switch 実行中に宣言が変わった
    # 場合（switch の最中に git pull が着地する等）その変更を「適用済み」として記録して
    # しまい、次回以降 skip され続けて永遠に適用されない。
    local cutover_fingerprint=""

    util::action "${step}: 実行開始 (${script})"
    migrate::log_event "${step}" "start"

    if migrate::requires_root "${step}"; then
        if [[ "${step}" == "cutover" ]]; then
            # cutover.zsh は root のまま実行するが、USER（nix build --impure の
            # ユーザー名解決）と HOME（~/.dotfiles-cutover-backup の書き込み先）の
            # 両方を元ユーザーに補正して渡す。sudo 単体起動だと両方 root に
            # リセットされており、HOME を放置すると health check が実際の書き込み
            # 先（元ユーザーの実ホーム）と食い違う場所を見に行ってしまう。
            local pam_target="${SUDO_LOCAL_PATH:-/etc/pam.d/sudo_local}"
            if migrate::pam_restore_pristine_if_safe "${pam_target}"; then
                cutover_fingerprint="$(migrate::cutover_fingerprint)"
                if USER="$(migrate::original_user)" HOME="$(migrate::effective_home)" zsh "${script}"; then
                    rc=0
                    # switch は pam.d/sudo_local を pristine でないと受け付けないため
                    # （nix-darwin の baseline 管理。実機インシデント、2026-08-22）、
                    # switch のたびに setup/pam.zsh の Touch ID 内容は失われうる。
                    # pam の manifest success を無条件で無効化し、同じ Phase 内で
                    # 必ず再実行させる（migrate::skippable が success 以外を
                    # 再実行対象として扱う既存ロジックに乗せる。pam 自身に
                    # postcondition チェックを持たせる必要はない）。
                    migrate::log_event "pam" "invalidated" "cutover re-ran; pam must reapply after switch"
                else
                    rc=1
                fi
            else
                util::error "${step}: PAM の pristine 復元に失敗したため switch を実行しません"
                rc=1
            fi
        else
            # pam は USER/HOME どちらも参照しないため、root のまま素で実行する。
            if zsh "${script}"; then rc=0; else rc=1; fi
        fi
    elif (( euid_val == 0 )); then
        # 非 root ステップだが単一 sudo 起動で root として走っている。
        # 元ユーザーへ委譲実行する（privilege_ok 済みなので特定できている）。
        if migrate::run_as_original_user "$(migrate::original_user)" "${script}"; then rc=0; else rc=1; fi
    else
        if zsh "${script}"; then rc=0; else rc=1; fi
    fi

    if (( rc == 0 )); then
        util::info "${step}: success"
        # cutover の success には、その switch が実際に読んだ desired-input fingerprint
        # （switch 起動直前に確定させた値）を併記する。次回以降の skip 判定はこの記録と
        # 現在値の一致で行う（migrate::cutover_rerun_reason）。
        local success_detail=""
        if [[ "${step}" == "cutover" ]]; then
            success_detail="fingerprint=${cutover_fingerprint}"
        fi
        migrate::log_event "${step}" "success" "${success_detail}"
        if [[ "${step}" == "pam" ]]; then
            migrate::pam_discard_vacated
        fi
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
    local home_dir
    home_dir="$(migrate::effective_home)"
    if [[ -z "${home_dir}" ]]; then
        util::error "元ユーザー($(migrate::original_user))の実ホームディレクトリを解決できませんでした（dscl 失敗）"
        return 1
    fi

    [[ -L "${home_dir}/.zshrc" ]] || failures+=("link: ${home_dir}/.zshrc が symlink ではありません")

    local pam_target="${SUDO_LOCAL_PATH:-/etc/pam.d/sudo_local}"
    [[ -f "${pam_target}" ]] || failures+=("pam: ${pam_target} が存在しません")

    local backup_glob=("${home_dir}"/.dotfiles-cutover-backup/pre-cutover-generations-*.txt(N))
    (( ${#backup_glob[@]} >= 1 )) || failures+=("cutover: ${home_dir}/.dotfiles-cutover-backup/ に世代バックアップがありません")

    # migrate::command_available は root（sudo）の PATH が env_reset で Homebrew の bin を
    # 含まない状態でも Homebrew prefix フォールバックで再確認する。
    migrate::command_available mise || failures+=("languages: mise が PATH 上に見つかりません")
    migrate::command_available starship || failures+=("cutover: starship が PATH 上に見つかりません")

    [[ -d "${home_dir}/.dotfiles-defaults-backup" ]] || failures+=("defaults: ${home_dir}/.dotfiles-defaults-backup/ がありません（初回スナップショット未取得）")

    [[ -f "${home_dir}/.claude.json" ]] || failures+=("claude-sync: ${home_dir}/.claude.json がありません")

    [[ -f "${home_dir}/.codex/config.toml" ]] || failures+=("codex-sync: ${home_dir}/.codex/config.toml がありません")

    # herdr plugin の allowlist。パスは herdr-sync.zsh と同じ setup/lib/herdr.zsh の
    # 解決関数から引く（配置する側と確認する側で別々にパスを組み立てると、Herdr が
    # 設定ディレクトリの位置を変えたときに health check だけが古い場所を見に行く）。
    #
    # 要求する条件も herdr-sync.zsh と揃える。何も配置しないのは「primary チェックアウト
    # 以外からの実行」のときだけで、そこで symlink を要求すると manifest の success と
    # health check が食い違う。herdr の有無では gate しない — herdr が無くても
    # herdr-sync.zsh は既定パスへ allowlist を配置して成功するので、そこを飛ばすと
    # 「配置されているのに検証しない」死角になる。
    local dotfiles_root="${SETUP_DIR:h}"
    if herdr::is_primary_root "${dotfiles_root}" "${home_dir}"; then
        local swt_config
        swt_config="$(herdr::allowlist_link "${home_dir}")"
        [[ -L "${swt_config}" ]] || failures+=("herdr-sync: ${swt_config} が symlink ではありません")
    fi

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
    local phase_name step
    for phase_name in phase1 phase2 phase3; do
        local -a steps
        steps=(${(z)$(migrate::steps_for "${phase_name}")})
        echo "--- ${phase_name} ---"
        for step in "${steps[@]}"; do
            if migrate::skippable "${step}"; then
                echo "  [SKIP] ${step}: 既に success です"
            elif ! migrate::privilege_ok "${step}"; then
                echo "  [BLOCKED] ${step}: $(migrate::privilege_hint "${step}")"
            elif [[ "$(migrate::latest_status "${step}")" == "success" ]]; then
                echo "  [WOULD RUN] ${step}: postcondition 未達成のため再実行 ($(migrate::cutover_rerun_reason))"
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
使い方: sudo zsh ${SETUP_DIR}/migrate.zsh (--dry-run|--apply)

  --dry-run   現在の状態と実行計画を表示する（副作用なし、manifest も書かない）
  --apply     計画を実際に実行する（Phase 1 -> Phase 2 -> Phase 3 の順、manifest に記録）

単一の root 起動で全 Phase が完結する。sudo が自動設定する SUDO_USER から元ユーザーを
特定し、非 root ステップ（Phase 1/3）は元ユーザーへ委譲実行する。

Phase 1: link (root 起動時は元ユーザーへ委譲)
Phase 2: cutover, pam (root 必須)
Phase 3: languages, defaults, claude-sync, codex-sync, herdr-sync (root 起動時は元ユーザーへ委譲)

個別スクリプト（link.zsh 等）は内部実装です。実機での実行はこのスクリプトからのみ
行ってください。詳細は setup/README.md を参照。
EOF
}

MODE="${1:-}"

case "${MODE}" in
    --dry-run)
        migrate::preflight || exit 1
        migrate::bootstrap_state_dir || exit 1
        migrate::dry_run
        exit 0
        ;;
    --apply)
        migrate::preflight || exit 1
        migrate::bootstrap_state_dir || exit 1
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
