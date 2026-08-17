#!/usr/bin/env bash
#
# stream_wallpaper.sh <url> [loop] [mute] [quality] [monitor]
# -------------------------------------------------------
# Dispatches a streaming wallpaper from a remote URL (YouTube, Twitch,
# Vimeo, direct HLS/MP4) and returns IMMEDIATELY. The actual work
# (resolving the stream URL via mpv's built-in yt-dlp, killing the
# previous mpvpaper instance, launching + monitoring the new one) is
# handed off to a detached background worker (_stream_worker.sh).
#
# Unlike apply_wallpaper.sh, this accepts URLs -- no local file check.
# A short 1-second debounce is used (vs. 3s for wallpapers) since
# stream resolution is faster and the user expects quicker feedback.
#
# Param 1 <url>       : the streaming URL or direct media URL
# Param 2 [loop]      : "yes" (default) or "no" -- loop VOD content;
#                        silently ignored by mpv for live streams
# Param 3 [mute]      : "yes" or "no" (default) -- initial audio mute state
# Param 4 [quality]   : "auto" (default) or a max height in px
#                        (360|480|720|1080|1440|2160) -- caps yt-dlp's
#                        format selection, does not upscale past what
#                        the source actually offers
# Param 5 [monitor]   : output name (e.g. "eDP-1") or omitted for auto
#                        -- kept LAST to match PlaybackService._dispatch(),
#                        which always appends the monitor arg after
#                        whatever extraArgs the caller passed (see
#                        apply_wallpaper.sh's <path> [res] [fps] [monitor]
#                        for the same convention).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

URL="$1"
LOOP="${2:-yes}"
MUTE="${3:-no}"
QUALITY="${4:-auto}"
MONITOR="${5:-}"

lw_ensure_dirs

if [ -z "$URL" ]; then
    lw_log_error "stream_wallpaper.sh: no URL given"
    echo "Error: no URL given" >&2
    exit 1
fi

[ -z "$MONITOR" ] && MONITOR="$(lw_detect_monitor)"

# Cancel any still-running worker for this monitor (wallpaper or stream).
lw_cancel_inflight_apply_worker "$MONITOR"

status_file="$(lw_monitor_state_file "$MONITOR" "apply_status")"
lw_write_apply_status "$status_file" "pending" "$URL" "Connecting..."

# Detach background worker and return immediately.
setsid bash "$SCRIPT_DIR/_stream_worker.sh" "$URL" "$MONITOR" "$LOOP" "$MUTE" "$QUALITY" \
    > /dev/null 2>&1 < /dev/null &
worker_pid=$!
disown

lw_write_text_atomic "$(lw_monitor_state_file "$MONITOR" "worker_pid")" "$worker_pid"

lw_log_info "stream_wallpaper.sh: dispatched (monitor: $MONITOR, url: $URL, loop: $LOOP, mute: $MUTE, quality: $QUALITY, worker_pid: $worker_pid)"
echo "Streaming $URL on $MONITOR..."
