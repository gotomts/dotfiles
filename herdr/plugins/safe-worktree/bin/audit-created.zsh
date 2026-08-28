#!/bin/zsh
# herdr/plugins/safe-worktree/bin/audit-created.zsh
#
# worktree.created イベントフック。作成された worktree を「この plugin 経由か」
# 「base は妥当か」の 2 軸で記録する。
#
# このスクリプトは監査だけを行う。worktree の削除・base の付け替え・ブランチの
# 作り直しといった修復操作は一切しない。判断材料を残して人間に返すのが役目で、
# 自動修復は「気づかないうちに作業が消える」事故の側に倒れるため意図的に持たない。
#
# base の妥当性判定はローカルに既知の refs/remotes/<remote>/HEAD を使う。
# イベントフックは Herdr の worktree 作成直後に走るため、ここでネットワーク I/O を
# して待たせない（= 判定は「最後に fetch した時点のリモート像」に対するもの）。

set -u

SWT_ROOT="${0:A:h:h}"
source "${SWT_ROOT}/lib/common.zsh"

event_json="${HERDR_PLUGIN_EVENT_JSON:-}"
[[ -n "${event_json}" ]] || exit 0

# 公式スキーマ上、worktree_created イベントの必須フィールドは type/workspace/worktree。
# .data.worktree.path は WorktreeInfo の必須フィールドなので必ず取れる。
# 一方 .data.workspace.worktree は WorkspaceInfo 上 nullable なので、repo_root は
# 取れないことがある。その場合はチェックアウト先から自分でメイン作業ツリーを引く。
checkout_path="$(printf '%s' "${event_json}" | jq -r '.data.worktree.path // empty')"
branch="$(printf '%s' "${event_json}" | jq -r '.data.worktree.branch // empty')"
workspace_id="$(printf '%s' "${event_json}" | jq -r '.data.workspace.workspace_id // empty')"
repo_root="$(printf '%s' "${event_json}" | jq -r '.data.workspace.worktree.repo_root // empty')"

[[ -n "${checkout_path}" ]] || exit 0
if [[ -z "${repo_root}" ]]; then
    repo_root="$(swt::main_worktree_root "${checkout_path}" 2>/dev/null || true)"
fi
[[ -n "${repo_root}" ]] || exit 0
# 作成側 (create.zsh) と同じ正規形に揃える。ここがずれると pending マーカーのキーが
# 一致せず、plugin 経由の作成が直接作成として誤検出される。
repo_root="${repo_root:A}"

# 状態ディレクトリが用意できなければ、記録先が無いので何もせず抜ける。
# ここで戻り値を見ないと state_dir が空のまま "/audit.jsonl" を書きに行く。
# イベントフックなので失敗を騒がず静かに終わる（Herdr の worktree 作成自体は
# 成功しており、監査できないことを理由に利用者の操作を止める筋合いはない）。
if ! state_dir="$(swt::ensure_state_dir)"; then
    exit 0
fi
audit_log="${state_dir}/audit.jsonl"
swt::rotate_audit_log "${audit_log}"

head_sha="$(swt::resolve_commit "${checkout_path}" HEAD 2>/dev/null || true)"

# ---------------------------------------------------------------------------
# allowlist 上のリポジトリか（設定が読めない場合は「対象外」として静かに記録する）
# ---------------------------------------------------------------------------
allowlisted=false
remote="origin"
if allowlist="$(swt::load_allowlist 2>/dev/null)"; then
    if matched="$(swt::match_repo "${allowlist}" "${repo_root}")"; then
        allowlisted=true
        remote="${matched%%$'\t'*}"
    fi
fi

# ---------------------------------------------------------------------------
# この plugin が置いたマーカーがあるか
# ---------------------------------------------------------------------------
# TTL 内のマーカーだけを信用する。期限切れのものは swt::pending_take が捨てる。
# 古い残骸を承認してしまうと、あとから同じ repo + branch で直接作られた worktree が
# plugin 経由として通ってしまう。
via_plugin=false
expected_sha=""
base_desc=""
if marker_json="$(swt::pending_take "${repo_root}" "${branch}")"; then
    via_plugin=true
    expected_sha="$(printf '%s' "${marker_json}" | jq -r '.base_sha // empty')"
    base_desc="$(printf '%s' "${marker_json}" | jq -r '.base_desc // empty')"
fi

# ---------------------------------------------------------------------------
# 判定
# ---------------------------------------------------------------------------
known_tip=""
if [[ "${via_plugin}" == true ]]; then
    if [[ -n "${expected_sha}" && "${head_sha}" == "${expected_sha}" ]]; then
        verdict="plugin_ok"
    else
        verdict="plugin_sha_mismatch"
    fi
else
    default_ref="$(git -C "${repo_root}" symbolic-ref --quiet "refs/remotes/${remote}/HEAD" 2>/dev/null || true)"
    if [[ -z "${default_ref}" ]]; then
        verdict="direct_create_unverified"
    else
        known_tip="$(swt::resolve_commit "${repo_root}" "${default_ref}" 2>/dev/null || true)"
        base_desc="${default_ref#refs/remotes/}"
        if [[ -z "${known_tip}" || -z "${head_sha}" ]]; then
            verdict="direct_create_unverified"
        elif [[ "${head_sha}" == "${known_tip}" ]]; then
            verdict="direct_create_at_known_tip"
        elif git -C "${repo_root}" merge-base --is-ancestor "${head_sha}" "${known_tip}" 2>/dev/null; then
            verdict="direct_create_stale_base"
        else
            verdict="direct_create_unexpected_base"
        fi
    fi
fi

jq -n -c \
    --arg at "$(date -u +%FT%TZ)" \
    --arg verdict "${verdict}" \
    --argjson via_plugin "${via_plugin}" \
    --argjson allowlisted "${allowlisted}" \
    --arg repo_root "${repo_root}" \
    --arg checkout_path "${checkout_path}" \
    --arg branch "${branch}" \
    --arg workspace_id "${workspace_id}" \
    --arg remote "${remote}" \
    --arg head_sha "${head_sha}" \
    --arg expected_sha "${expected_sha}" \
    --arg known_tip "${known_tip}" \
    --arg base_desc "${base_desc}" \
    '{at: $at, verdict: $verdict, via_plugin: $via_plugin, allowlisted: $allowlisted,
      repo_root: $repo_root, checkout_path: $checkout_path, branch: $branch,
      workspace_id: $workspace_id, remote: $remote, head_sha: $head_sha,
      expected_sha: $expected_sha, known_tip: $known_tip, base_desc: $base_desc}' \
    >> "${audit_log}"

# ---------------------------------------------------------------------------
# 通知
#   allowlist 対象のリポジトリだけを通知する。管理対象外のリポジトリで worktree を
#   作るたびに鳴らすと、通知そのものが読まれなくなるため。監査ログには全件残す。
# ---------------------------------------------------------------------------
[[ "${allowlisted}" == true ]] || exit 0
[[ "${verdict}" == "plugin_ok" ]] && exit 0

case "${verdict}" in
    plugin_sha_mismatch)
        title="worktree の base が期待と違います"
        body="${branch}: 期待 ${expected_sha[1,12]} / 実際 ${head_sha[1,12]}"
        ;;
    direct_create_stale_base)
        title="safe-worktree を経由しない worktree 作成"
        body="${branch}: base が既知の ${base_desc} より古い（${head_sha[1,12]}）"
        ;;
    direct_create_unexpected_base)
        title="safe-worktree を経由しない worktree 作成"
        body="${branch}: base が既知の ${base_desc} の履歴上にない（${head_sha[1,12]}）"
        ;;
    direct_create_unverified)
        title="safe-worktree を経由しない worktree 作成"
        body="${branch}: base を検証できません（${remote}/HEAD が未取得）"
        ;;
    *)
        title="safe-worktree を経由しない worktree 作成"
        body="${branch}: base は既知の ${base_desc} と一致"
        ;;
esac

"$(swt::herdr_bin)" notification show "${title}" --body "${body}" --sound none >/dev/null 2>&1 || true
