#!/usr/bin/env bash
#
# stream_ipc.sh <monitor> <action> [value]
# -------------------------------------------------------
# Bridges PlaybackService's playback-control calls to the mpv JSON IPC
# socket _stream_worker.sh launches mpvpaper with (--input-ipc-server).
# Streaming-mode only — Wallpapers and Web mode never call this.
#
# Param 1 <monitor> : output name, or "" / "auto" for the focused monitor
#                      (same convention as every other script here).
# Param 2 <action>  : get-progress | pause | resume | toggle-pause | seek
# Param 3 [value]   : seek target in seconds (only used by "seek")
#
# Always prints exactly one line of JSON. get-progress prints
#   {"position":12.3,"duration":345.0,"paused":false,"buffering":false}
# every other action prints {} on completion. Never fails loudly: a
# missing/stale socket (mpv not up yet, mpv without IPC support, or no
# stream currently playing) just means "no data" / "no-op" — the actual
# stream keeps playing either way, this only affects the controls' UI.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

MONITOR="${1:-}"
ACTION="${2:-get-progress}"
VALUE="${3:-}"

[ -z "$MONITOR" ] && MONITOR="$(lw_detect_monitor)"

sock="$(lw_monitor_state_file "$MONITOR" "mpv_ipc")"

if [ ! -S "$sock" ] || ! command -v python3 >/dev/null 2>&1; then
    echo "{}"
    exit 1
fi

python3 "$SCRIPT_DIR/_mpv_ipc.py" "$sock" "$ACTION" "$VALUE"
