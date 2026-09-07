#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"
lw_ensure_dirs
[ -s "$LW_DB_FILE" ] || exit 1
# Prefer favorites, then the least-used wallpaper; random tie-breaking keeps
# automatic selection from cycling alphabetically forever.
jq -r --slurpfile history "$LW_HISTORY_FILE" '
  . as $all |
  ($history[0] // []) as $h |
  ($h | group_by(.path) | map({key:.[0].path,value:length}) | from_entries) as $counts |
  ($all | map(. + {uses:($counts[.path] // 0)}) |
   sort_by((if .favorite then 0 else 1 end), .uses, .path) | .[0].path // empty)
' "$LW_DB_FILE"