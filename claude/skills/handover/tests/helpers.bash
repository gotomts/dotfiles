#!/usr/bin/env bash
# bats 共通ヘルパー
# 各テストファイルから `load helpers` で読み込む。

# 一時 HOME を設定し、テスト後に削除する setup/teardown
setup_handover_env() {
  TEST_TMP_HOME="$(mktemp -d)"
  export HOME="${TEST_TMP_HOME}"
  export TMPDIR="${TEST_TMP_HOME}/tmp"
  mkdir -p "${TMPDIR}"
  mkdir -p "${HOME}/.claude/handover"
  # Make scripts/ reachable from ${HOME}/.claude/... so hooks can find them
  mkdir -p "${HOME}/.claude/skills/handover"
  ln -s "${BATS_TEST_DIRNAME}/../scripts" "${HOME}/.claude/skills/handover/scripts"
  # スクリプト群への絶対パス
  SCRIPTS_DIR="${BATS_TEST_DIRNAME}/../scripts"
  HOOKS_DIR="${BATS_TEST_DIRNAME}/../../../hooks"
  export SCRIPTS_DIR HOOKS_DIR
}

teardown_handover_env() {
  if [ -n "${TEST_TMP_HOME:-}" ] && [ -d "${TEST_TMP_HOME}" ]; then
    rm -rf "${TEST_TMP_HOME}"
  fi
}

# 与えた条件の state.json を作る簡易関数
# Usage: write_state <dir> <session_id> <status> <created_at> [consumed]
write_state() {
  local dir="$1" sid="$2" status="$3" created="$4" consumed="${5:-false}"
  mkdir -p "${dir}"
  cat > "${dir}/state.json" <<EOF
{
  "version": 1,
  "session_id": "${sid}",
  "created_at": "${created}",
  "updated_at": "${created}",
  "consumed": ${consumed},
  "status": "${status}",
  "project": {
    "path": "/tmp/test-project",
    "hash": "test-12345678",
    "branch": "main"
  },
  "session_summary": "test summary",
  "tasks": [],
  "decisions": [],
  "blockers": []
}
EOF
}

# 7 日前 ISO8601 を返す（macOS / Linux 両対応）
iso_days_ago() {
  local days="$1"
  if date -v -1d >/dev/null 2>&1; then
    date -v "-${days}d" -Iseconds
  else
    date -d "${days} days ago" -Iseconds
  fi
}
