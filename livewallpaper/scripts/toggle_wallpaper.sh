#!/usr/bin/env bash
#
# toggle_wallpaper.sh [monitor]
# ----------------------
# Single button on the panel: if mpvpaper is running (on [monitor], or
# anywhere if [monitor] omitted) -> Stop, otherwise -> Start the wallpaper
# that was last stopped.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

MONITOR="${1:-}"

is_running=false
if [ -n "$MONITOR" ]; then
    pid_file="$(lw_monitor_state_file "$MONITOR" "pid")"
    if [ -s "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        is_running=true
    fi
else
    pgrep -x mpvpaper >/dev/null 2>&1 && is_running=true
fi

if [ "$is_running" = "true" ]; then
    exec "$SCRIPT_DIR/stop_wallpaper.sh" "$MONITOR"
else
    exec "$SCRIPT_DIR/start_wallpaper.sh" "$MONITOR"
fi
