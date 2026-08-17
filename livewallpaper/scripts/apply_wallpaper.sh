#!/usr/bin/env bash
#
# apply_wallpaper.sh <video_path> [resolution] [fps] [monitor]
# -------------------------------------------------------
# Dispatches a wallpaper change and returns IMMEDIATELY (no sleeping, no
# waiting on mpvpaper to actually come up) -- the real work happens in a
# detached background worker (_apply_worker.sh), which runs right away
# (no artificial debounce/delay).
#
# The worker reuses the ALREADY-RUNNING mpvpaper process for this monitor
# via IPC (lw_mpv_try_reuse in utils.sh) instead of killing and relaunching
# it, so the mpvpaper PID stays the same across normal wallpaper changes.
# Rapid switching is still safe: any still-pending worker for this monitor
# is cancelled (whole process group) before a new one is dispatched, so
# only the last selection in a rapid burst ever actually reaches mpv.
#
# Param 2 [resolution] (optional): 480p | 720p | 1080p | 2k | 4k | original
# Default "1080p".
#
# Param 3 [fps] (optional): 24 | 30 | 60 | original
# Default "original" (unchanged).
#
# Param 4 [monitor] (optional): a specific output name (e.g. "eDP-1").
# Default: the currently focused monitor.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

VIDEO="$1"
RESOLUTION="${2:-1080p}"
FPS="${3:-original}"
MONITOR="${4:-}"

lw_ensure_dirs

if [ -z "$VIDEO" ]; then
    lw_log_error "apply_wallpaper.sh: no video path given"
    exit 1
fi

if [ ! -f "$VIDEO" ]; then
    lw_log_error "apply_wallpaper.sh: video does not exist: $VIDEO"
    exit 1
fi

[ -z "$MONITOR" ] && MONITOR="$(lw_detect_monitor)"

# Cancel any still-running worker for this monitor before dispatching a
# new one, so a rapid burst of clicks only ever lets the LAST selection
# reach mpv (the worker itself runs immediately -- no artificial delay --
# but IPC reuse can still take a moment, so this avoids two workers
# racing to loadfile against the same mpv process).
lw_cancel_inflight_apply_worker "$MONITOR"

status_file="$(lw_monitor_state_file "$MONITOR" "apply_status")"
lw_write_apply_status "$status_file" "pending" "$VIDEO" "Applying..."

# Hand off to the background worker and return immediately.
setsid bash "$SCRIPT_DIR/_apply_worker.sh" "$VIDEO" "$RESOLUTION" "$FPS" "$MONITOR" \
    > /dev/null 2>&1 < /dev/null &
worker_pid=$!
disown

# Record so a subsequent apply on this monitor (or Stop) can cancel this
# exact worker during its 3-second debounce window.
lw_write_text_atomic "$(lw_monitor_state_file "$MONITOR" "worker_pid")" "$worker_pid"

lw_log_info "apply_wallpaper.sh: dispatched (monitor: $MONITOR, resolution: $RESOLUTION, fps: $FPS, video: $VIDEO, worker_pid: $worker_pid)"
echo "Applying $VIDEO on $MONITOR..."
