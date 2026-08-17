#!/usr/bin/env bash
#
# random_wallpaper.sh [monitor]
# ----------------------
# Switches to a random wallpaper in the database, avoiding a repeat of the
# currently playing video (if there are 2 or more videos). Keeps that
# monitor's currently selected resolution/fps. [monitor] omitted ->
# focused monitor + legacy global state (original single-monitor
# behavior).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

MONITOR="${1:-}"
target="$(lw_neighbor_wallpaper "random" "$MONITOR")"

if [ -z "$target" ]; then
    lw_log_warn "random_wallpaper.sh: database empty, nothing to pick"
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
