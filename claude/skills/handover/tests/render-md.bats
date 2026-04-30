#!/usr/bin/env bats

load helpers

setup() {
  setup_handover_env
  TARGET_DIR="${HOME}/.claude/handover/test/main/20260430-100000"
  mkdir -p "${TARGET_DIR}"
}

teardown() {
  teardown_handover_env
}

@test "renders expected markdown from a standard state.json" {
  cat > "${TARGET_DIR}/state.json" <<'JSON'
{
  "version": 1,
  "session_id": "abc",
  "created_at": "2026-04-30T15:30:00+09:00",
  "updated_at": "2026-04-30T15:30:00+09:00",
  "consumed": false,
  "status": "READY",
  "project": {
    "path": "/Users/goto/.dotfiles",
    "hash": "dotfiles-a1b2c3d4",
    "branch": "main"
  },
  "session_summary": "handover の設計を進行中",
  "tasks": [
    {
      "id": "T1",
      "description": "実装する",
      "status": "in_progress",
      "next_action": "SKILL.md を書く"
    }
  ],
  "decisions": [
    {
      "topic": "保存先",
      "chosen": "~/.claude/handover/",
      "rejected": [".agents/"],
      "rationale": "プロジェクト側を汚さない"
    }
  ],
  "blockers": ["jq インストール待ち"]
}
JSON

  run "${SCRIPTS_DIR}/render-md.sh" "${TARGET_DIR}/state.json"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"# Handover: 2026-04-30 15:30"* ]]
  [[ "${output}" == *"**Project**: /Users/goto/.dotfiles"* ]]
  [[ "${output}" == *"**Branch**: main"* ]]
  [[ "${output}" == *"**Status**: READY"* ]]
  [[ "${output}" == *"**Session**: abc"* ]]
  [[ "${output}" == *"## Session Summary"* ]]
  [[ "${output}" == *"handover の設計を進行中"* ]]
  [[ "${output}" == *"T1: 実装する (in_progress)"* ]]
  [[ "${output}" == *"Next: SKILL.md を書く"* ]]
  [[ "${output}" == *"**保存先**: ~/.claude/handover/"* ]]
  [[ "${output}" == *"却下: .agents/"* ]]
  [[ "${output}" == *"理由: プロジェクト側を汚さない"* ]]
  [[ "${output}" == *"jq インストール待ち"* ]]
}

@test "shows nashi for empty tasks array" {
  cat > "${TARGET_DIR}/state.json" <<'JSON'
{
  "version": 1, "session_id": "x", "created_at": "2026-04-30T10:00:00+09:00",
  "updated_at": "2026-04-30T10:00:00+09:00", "consumed": false, "status": "ALL_COMPLETE",
  "project": {"path": "/p", "hash": "p-1", "branch": "main"},
  "session_summary": "done", "tasks": [], "decisions": [], "blockers": []
}
JSON
  run "${SCRIPTS_DIR}/render-md.sh" "${TARGET_DIR}/state.json"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"## Tasks"* ]]
  [[ "${output}" == *"なし"* ]]
}

@test "exits 1 for nonexistent file" {
  run "${SCRIPTS_DIR}/render-md.sh" "${HOME}/nonexistent.json"
  [ "${status}" -ne 0 ]
}
