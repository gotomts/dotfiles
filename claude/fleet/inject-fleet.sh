#!/bin/bash
# inject-fleet.sh — Claude Code on the web 用 SessionStart hook（canonical）
set -euo pipefail
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then exit 0; fi
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/gotomts/dotfiles}"
DOTFILES_REF="${DOTFILES_REF:-main}"
DEST="${HOME}/.claude"
log() { echo "[inject-fleet] $*"; }
git config --global --add safe.directory '*' >/dev/null 2>&1 || true
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
log "cloning dotfiles ($DOTFILES_REF) ..."
git clone --depth 1 --filter=blob:none --sparse --branch "$DOTFILES_REF" "$DOTFILES_REPO" "$TMP/dotfiles"
git -C "$TMP/dotfiles" sparse-checkout set claude
SRC="$TMP/dotfiles/claude"; mkdir -p "$DEST"
rm -rf "${DEST:?}/skills"; mkdir -p "$DEST/skills"
[ -d "$SRC/skills" ]       && cp -R "$SRC/skills/."       "$DEST/skills/"
[ -d "$SRC/fleet/skills" ] && cp -R "$SRC/fleet/skills/." "$DEST/skills/"
rm -rf "${DEST:?}/agents"; mkdir -p "$DEST/agents"
[ -d "$SRC/agents" ]       && cp -R "$SRC/agents/."       "$DEST/agents/"
[ -d "$SRC/fleet/agents" ] && cp -R "$SRC/fleet/agents/." "$DEST/agents/"
[ -f "$SRC/CLAUDE.md" ]     && cp "$SRC/CLAUDE.md"     "$DEST/CLAUDE.md"
[ -f "$SRC/AGENTS.md" ]     && cp "$SRC/AGENTS.md"     "$DEST/AGENTS.md"
[ -f "$SRC/settings.json" ] && cp "$SRC/settings.json" "$DEST/settings.json"
n_skills=$(find "$DEST/skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
n_agents=$(find "$DEST/agents" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
log "ready: ~/.claude (skills=$n_skills, agents=$n_agents)"
