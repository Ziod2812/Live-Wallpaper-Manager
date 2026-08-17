#!/usr/bin/env bash
#
# next_wallpaper.sh [monitor]
# -------------------
# Switches to the next wallpaper in the database (in display order),
# wrapping to the start of the list if at the end. Keeps that monitor's
# currently selected resolution/fps. [monitor] omitted -> focused monitor
# + legacy global state (original single-monitor behavior).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

MONITOR="${1:-}"
target="$(lw_neighbor_wallpaper "next" "$MONITOR")"

if [ -z "$target" ]; then
    lw_log_warn "next_wallpaper.sh: database empty, nothing to switch to"
    echo "No wallpapers in the list yet." >&2
    exit 1
fi

[ -z "$MONITOR" ] && MONITOR="$(lw_detect_monitor)"
resolution_file="$(lw_monitor_state_file "$MONITOR" "resolution")"
fps_file="$(lw_monitor_state_file "$MONITOR" "fps")"
[ ! -s "$resolution_file" ] && [ -s "$LW_RESOLUTION_FILE" ] && resolution_file="$LW_RESOLUTION_FILE"
[ ! -s "$fps_file" ] && [ -s "$LW_FPS_FILE" ] && fps_file="$LW_FPS_FILE"

resolution="1080p"
[ -s "$resolution_file" ] && resolution="$(cat "$resolution_file")"
fps="original"
[ -s "$fps_file" ] && fps="$(cat "$fps_file")"

exec "$SCRIPT_DIR/apply_wallpaper.sh" "$target" "$resolution" "$fps" "$MONITOR"
