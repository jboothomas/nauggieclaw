#!/bin/bash
#
# Prune stale session artifacts (Auggie session JSONs, group logs).
# Safe to run while NauggieClaww is live — active sessions are read from the DB.
#
# Usage:  ./scripts/cleanup-sessions.sh [--dry-run]
#
# Retention:
#   Auggie session JSON files:  7 days  (active session always kept)
#   Group logs:                 7 days

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

STORE_DB="$PROJECT_ROOT/store/messages.db"
SESSIONS_DIR="$PROJECT_ROOT/data/sessions"
GROUPS_DIR="$PROJECT_ROOT/groups"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

TOTAL_FREED=0

log() { echo "[cleanup] $*"; }

remove() {
  local target="$1"
  if $DRY_RUN; then
    if [ -d "$target" ]; then
      size=$(du -sk "$target" 2>/dev/null | cut -f1)
    else
      size=$(wc -c < "$target" 2>/dev/null || echo 0)
      size=$((size / 1024))
    fi
    TOTAL_FREED=$((TOTAL_FREED + size))
    log "would remove: $target (${size}K)"
  else
    if [ -d "$target" ]; then
      size=$(du -sk "$target" 2>/dev/null | cut -f1)
      rm -rf "$target"
    else
      size=$(wc -c < "$target" 2>/dev/null || echo 0)
      size=$((size / 1024))
      rm -f "$target"
    fi
    TOTAL_FREED=$((TOTAL_FREED + size))
  fi
}

# --- Collect active session IDs from the database ---

if [ ! -f "$STORE_DB" ]; then
  log "ERROR: database not found at $STORE_DB"
  exit 1
fi

ACTIVE_IDS=$(sqlite3 "$STORE_DB" "SELECT session_id FROM sessions;" 2>/dev/null || true)

is_active() {
  echo "$ACTIVE_IDS" | grep -qF "$1"
}

# --- Prune Auggie session JSON files (>7 days, active sessions always kept) ---
# Sessions are stored at data/sessions/{group}/.augment/sessions/{id}.json

for group_dir in "$SESSIONS_DIR"/*/; do
  [ -d "$group_dir" ] || continue
  augment_sessions_dir="$group_dir/.augment/sessions"
  [ -d "$augment_sessions_dir" ] || continue

  for session_json in "$augment_sessions_dir"/*.json; do
    [ -f "$session_json" ] || continue
    id=$(basename "$session_json" .json)

    # Never delete the active session
    if is_active "$id"; then
      continue
    fi

    # Only delete if older than 7 days
    if [ -n "$(find "$session_json" -mtime +7 2>/dev/null)" ]; then
      remove "$session_json"
    fi
  done
done

# --- Prune group logs (>7 days) ---

while IFS= read -r -d '' f; do
  remove "$f"
done < <(find "$GROUPS_DIR"/*/logs -type f -mtime +7 -print0 2>/dev/null)

# --- Summary ---

if $DRY_RUN; then
  log "DRY RUN complete — would free ~${TOTAL_FREED}K"
else
  log "Done — freed ~${TOTAL_FREED}K"
fi
