#!/usr/bin/env bash
#
# refresh.sh
# -----------
# Rescans the wallpaper directory, updates wallpapers.json (via
# wallpaper_list.sh — generates thumbnail/metadata for new videos, keeps
# records for unchanged videos, drops deleted ones), sweeps orphaned
# thumbnails, then just... stops. Quickshell's WallpaperService watches
# wallpapers.json directly and reloads the instant this script writes to
# it, so no explicit "push to UI" step is needed (unlike the old eww
# version, which had to call `eww update`).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

lw_ensure_dirs

json="$("$SCRIPT_DIR/wallpaper_list.sh")"

if [ -d "$LW_THUMB_DIR" ]; then
    # Single-pass sweep instead of the old per-file `grep -qxF` loop,
    # which forked an external grep (plus a full-list here-string copy on
    # every iteration) for EACH thumbnail -- O(n) subprocess spawns per
    # refresh, and refresh runs both on every manual Refresh and after
    # every watcher debounce. Now: sorted set of all current thumb
    # files vs sorted set of still-valid thumb paths, diffed ONCE with
    # `comm`, deleting only the leftovers.
    all_thumbs="$(find "$LW_THUMB_DIR" -maxdepth 1 -name '*.png' -type f -printf '%p\n' 2>/dev/null | LC_ALL=C sort)"
    if [ -n "$all_thumbs" ]; then
        valid_thumbs="$(echo "$json" | jq -r '.[].thumb' 2>/dev/null | LC_ALL=C sort -u)"
        while IFS= read -r stale; do
            [ -n "$stale" ] && rm -f -- "$stale"
        done < <(comm -23 <(printf '%s\n' "$all_thumbs") <(printf '%s\n' "$valid_thumbs"))
    fi
fi

lw_cleanup_orphan_monitor_state

lw_log_info "Refreshed wallpaper list ($(echo "$json" | jq 'length' 2>/dev/null) videos)."
echo "Refreshed wallpaper list."
