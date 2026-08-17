#!/usr/bin/env bash
#
# start_wallpaper.sh [monitor]
# --------------------
# Replays the wallpaper that was last Stopped/Applied on [monitor] (read
# from that monitor's "last"/"resolution"/"fps" state, written by
# apply_wallpaper.sh on every Apply and NOT cleared by Stop). Used by the
# "Start Wallpaper" button, and by PlaybackService's own startup-autostart
# check.
#
# [monitor] omitted -> uses the focused monitor and the legacy global
# "last" state, i.e. the exact original single-monitor behavior.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

MONITOR="${1:-}"
[ -z "$MONITOR" ] && MONITOR="$(lw_detect_monitor)"

lw_ensure_dirs

last_file="$(lw_monitor_state_file "$MONITOR" "last")"
resolution_file="$(lw_monitor_state_file "$MONITOR" "resolution")"
fps_file="$(lw_monitor_state_file "$MONITOR" "fps")"

# Fall back to the legacy global state if this monitor has no recorded
# history of its own yet (e.g. first time multi-monitor is used, or
# upgrading from a single-monitor install) -- avoids "No wallpaper was
# previously selected" for users who already had one going globally.
if [ ! -s "$last_file" ] && [ -s "$LW_LAST_FILE" ]; then
    last_file="$LW_LAST_FILE"
    resolution_file="$LW_RESOLUTION_FILE"
    fps_file="$LW_FPS_FILE"
fi

if [ ! -s "$last_file" ]; then
    lw_log_warn "start_wallpaper.sh: no wallpaper was previously selected for monitor $MONITOR"
    echo "No wallpaper was previously selected. Pick one from the list first." >&2
    exit 1
fi

VIDEO="$(cat "$last_file")"
RESOLUTION="1080p"
[ -s "$resolution_file" ] && RESOLUTION="$(cat "$resolution_file")"
FPS="original"
[ -s "$fps_file" ] && FPS="$(cat "$fps_file")"

if [ ! -f "$VIDEO" ]; then
    lw_log_error "start_wallpaper.sh: saved video no longer exists: $VIDEO"
    echo "Error: saved video no longer exists: $VIDEO" >&2
    exit 1
fi

exec "$SCRIPT_DIR/apply_wallpaper.sh" "$VIDEO" "$RESOLUTION" "$FPS" "$MONITOR"
