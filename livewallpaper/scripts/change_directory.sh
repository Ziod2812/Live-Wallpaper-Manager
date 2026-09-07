#!/usr/bin/env bash
#
# change_directory.sh <new_path>
# -------------------------------------------------------
# Changes the wallpaper directory (default ~/Pictures/Live Wallpaper) to
# another directory, writes it to settings.json, then immediately
# refreshes the wallpaper list — the user doesn't need to press Refresh
# afterwards.
#
# Used by the "Change directory" panel in the QML UI, or by hand:
#
#   scripts/change_directory.sh "/home/user/Videos/Wallpapers"
#
# Prints a result message (success or error reason) that the UI/
# notify-send can surface.
# -------------------------------------------------------
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

NEW_DIR="${1:-}"

if [ -z "$NEW_DIR" ]; then
    echo "Usage: change_directory.sh <directory_path>" >&2
    exit 1
fi

OLD_DIR="$LW_WALLPAPER_DIR"

result="$(lw_set_wallpaper_dir "$NEW_DIR" 2>&1)"
if [ "$result" != "OK" ]; then
    lw_log_error "change_directory.sh: failed to change directory: $result"
    command -v notify-send >/dev/null 2>&1 && \
        notify-send -u critical "Live Wallpaper" "Could not change directory: $result"
    echo "$result" >&2
    exit 1
fi

CONFIRMED_DIR="$(jq -r '.wallpaper_directory' "$LW_SETTINGS_FILE")"

"$SCRIPT_DIR/refresh.sh" >/dev/null 2>&1

count="$(jq 'length' "$LW_DB_FILE" 2>/dev/null || echo 0)"

lw_log_info "change_directory.sh: changed from '$OLD_DIR' to '$CONFIRMED_DIR' ($count videos)"
command -v notify-send >/dev/null 2>&1 && \
    notify-send "Live Wallpaper" "Directory changed: $CONFIRMED_DIR ($count videos)"

echo "Wallpaper directory changed to: $CONFIRMED_DIR ($count videos found)"
