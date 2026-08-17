#!/usr/bin/env bash
#
# favorite.sh <video_path> [on|off|toggle]
# --------------------------------------------
# Toggles the favorite state of a video in wallpapers.json. Defaults to
# "toggle" if param 2 is omitted. Writing to wallpapers.json is enough for
# Quickshell to pick up the change (FileView watchChanges) — no extra push
# needed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

VIDEO="$1"
MODE="${2:-toggle}"

if [ -z "$VIDEO" ]; then
    echo "Usage: favorite.sh <video_path> [on|off|toggle]" >&2
    exit 1
fi

lw_ensure_dirs
lw_json_init_if_missing "$LW_DB_FILE" "[]"
lw_lock_or_skip "wallpaper_db" 5 || exit 1

tmp="$(lw_atomic_tmp_for "$LW_DB_FILE")" || {
    echo "Error: could not create a temp file for the wallpaper database" >&2
    exit 1
}
if ! jq --arg path "$VIDEO" --arg mode "$MODE" '
    map(
        if .path == $path then
            .favorite = (
                if $mode == "on" then true
                elif $mode == "off" then false
                else (.favorite | not)
                end
            )
        else . end
    )
' "$LW_DB_FILE" > "$tmp"; then
    rm -f "$tmp"
    echo "Error: could not update wallpaper database" >&2
    exit 1
fi
lw_atomic_commit "$tmp" "$LW_DB_FILE"

new_state="$(jq -r --arg path "$VIDEO" '.[] | select(.path == $path) | .favorite' "$LW_DB_FILE")"

if [ -z "$new_state" ]; then
    lw_log_warn "favorite.sh: video not found in database: $VIDEO"
    echo "Error: video not found in database (run refresh.sh first)" >&2
    exit 1
fi

lw_log_info "favorite.sh: $VIDEO -> favorite=$new_state"
echo "$new_state"
