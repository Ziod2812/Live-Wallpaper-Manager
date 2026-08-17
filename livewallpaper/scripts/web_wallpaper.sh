#!/usr/bin/env bash
#
# web_wallpaper.sh <source> <type> [monitor]
# -------------------------------------------------------
# Dispatches a web-based wallpaper and returns IMMEDIATELY.
#
# <type> is one of:
#   url   — an http/https URL (video or streamable content via yt-dlp/mpv)
#   local — an absolute path to a local HTML file
#
# For "url" type, this uses the same mpvpaper/mpv path as stream_wallpaper.sh.
# For "local" HTML files, mpvpaper cannot render HTML; the script checks for
# a Wayland-compatible browser (chromium/firefox) and launches it in kiosk
# mode. The browser PID is stored in the monitor's state directory so
# stop_wallpaper.sh can terminate it cleanly on the next mode switch.
#
# Param 1 <source>  : URL or absolute file path
# Param 2 <type>    : "url" | "local"
# Param 3 [monitor] : output name or omitted for auto

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

SOURCE="$1"
TYPE="${2:-url}"
MONITOR="${3:-}"

lw_ensure_dirs

if [ -z "$SOURCE" ]; then
    lw_log_error "web_wallpaper.sh: no source given"
    echo "Error: no source given" >&2
    exit 1
fi

[ -z "$MONITOR" ] && MONITOR="$(lw_detect_monitor)"

lw_cancel_inflight_apply_worker "$MONITOR"

status_file="$(lw_monitor_state_file "$MONITOR" "apply_status")"
lw_write_apply_status "$status_file" "pending" "$SOURCE" "Loading..."

setsid bash "$SCRIPT_DIR/_web_worker.sh" "$SOURCE" "$TYPE" "$MONITOR" \
    > /dev/null 2>&1 < /dev/null &
worker_pid=$!
disown

lw_write_text_atomic "$(lw_monitor_state_file "$MONITOR" "worker_pid")" "$worker_pid"

lw_log_info "web_wallpaper.sh: dispatched (monitor: $MONITOR, type: $TYPE, source: $SOURCE, worker_pid: $worker_pid)"
echo "Web wallpaper ($TYPE) $SOURCE on $MONITOR..."
