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
    valid_thumbs="$(echo "$json" | jq -r '.[].thumb' 2>/dev/null)"
    for t in "$LW_THUMB_DIR"/*.png; do
        [ -f "$t" ] || continue
        if ! grep -qxF "$t" <<< "$valid_thumbs"; then
            rm -f "$t"
        fi
    done
fi

lw_cleanup_orphan_monitor_state

lw_log_info "Refreshed wallpaper list ($(echo "$json" | jq 'length' 2>/dev/null) videos)."
echo "Refreshed wallpaper list."
