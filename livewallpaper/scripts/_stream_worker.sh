#!/usr/bin/env bash
#
# _stream_worker.sh <url> <monitor> [loop] [mute] [quality]
# -------------------------------------------------------
# Internal script — not meant to be run by hand (use stream_wallpaper.sh).
#
# Waits 1 second (debounce), then:
#   1. Tries to reuse the already-running mpvpaper on this monitor via IPC
#      (lw_mpv_try_reuse) — same single-persistent-mpv mechanism as local
#      wallpapers. Only kills/relaunches if the tracked mpv has genuinely
#      exited (nothing left alive to reuse).
#   2. Launches mpvpaper with the URL — mpv's built-in yt-dlp handles
#      stream resolution for YouTube/Twitch/Vimeo/etc automatically.
#      Direct HLS/MP4 URLs are played as-is.
#   3. Writes the result to apply_status so PlaybackService picks it up.
#
# Design note: we pass the ORIGINAL user-supplied URL to mpvpaper/mpv,
# NOT a pre-resolved CDN URL from yt-dlp. This is intentional:
#   - mpv's yt-dlp hook selects the best quality for the current screen.
#   - Pre-resolved YouTube CDN URLs expire in ~6 hours; the original URL
#     can be re-resolved on restart without user intervention.
#   - Avoids running two yt-dlp processes (one here, one inside mpv).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

URL="$1"
MONITOR="$2"
LOOP="${3:-yes}"
MUTE="${4:-no}"
QUALITY="${5:-auto}"

status_file="$(lw_monitor_state_file "$MONITOR" "apply_status")"
worker_pid_file="$(lw_monitor_state_file "$MONITOR" "worker_pid")"
pid_file="$(lw_monitor_state_file "$MONITOR" "pid")"

# Remove worker_pid on exit so the next apply does not try to cancel a
# process that has already finished.
cleanup_worker_pid() {
    if [ -s "$worker_pid_file" ] && [ "$(cat "$worker_pid_file" 2>/dev/null)" = "$$" ]; then
        rm -f "$worker_pid_file"
    fi
}
trap cleanup_worker_pid EXIT

# ── 1-second debounce ────────────────────────────────────────────────────
# Shorter than the 3s wallpaper debounce — stream switching is faster
# because mpvpaper startup dominates; the URL is already known.
sleep 1

# ── Verify mpv can play streaming URLs ──────────────────────────────────
# mpv must be installed with yt-dlp support for YouTube/Twitch/Vimeo.
if ! command -v mpvpaper >/dev/null 2>&1; then
    lw_write_apply_status "$status_file" "error" "$URL" \
        "mpvpaper not found. Install mpvpaper to play streaming."
    exit 1
fi

# For non-standard direct URLs (HLS/MP4/etc), skip the yt-dlp check;
# mpv handles them natively via libavformat.
if echo "$URL" | grep -qiE 'youtu\.?be|twitch\.tv|vimeo\.com|nicovideo\.jp|bilibili\.com|dailymotion\.com' ; then
    if ! command -v yt-dlp >/dev/null 2>&1; then
        lw_write_apply_status "$status_file" "error" "$URL" \
            "yt-dlp not found. Install yt-dlp to play YouTube/Twitch/Vimeo."
        exit 1
    fi
fi

# ── Try to reuse the already-running mpv on this monitor ─────────────────
# Same single-persistent-mpv mechanism as local wallpapers (see
# lw_mpv_try_reuse in utils.sh): swap the URL in place over IPC instead of
# killing and relaunching mpvpaper. lw_mpv_try_reuse retries internally
# against that SAME pid for any transient IPC trouble and only reports
# "false" when there was genuinely nothing alive to reuse.
mode_sig="mode=stream loop=$LOOP mute=$MUTE quality=$QUALITY"
if [ "$(lw_mpv_try_reuse "$URL" "$MONITOR" "original" "original" "$mode_sig")" = "true" ]; then
    lw_write_text_atomic "$(lw_monitor_state_file "$MONITOR" "current")" "stream:$URL"
    lw_write_apply_status "$status_file" "success" "stream:$URL" "Stream is playing"
    lw_log_info "_stream_worker.sh: reused existing mpv for new URL (url: $URL, monitor: $MONITOR, loop: $LOOP, mute: $MUTE, quality: $QUALITY)"
    exit 0
fi

# ── ONLY create a new mpv if the tracked one has ACTUALLY exited ─────────
# A live tracked mpvpaper is never killed here just because reuse reported
# "false" -- same guarantee as _apply_worker.sh. See its comment for the
# full reasoning.
_stream_pid_file="$(lw_monitor_state_file "$MONITOR" "pid")"
_stream_tracked_pid=""
[ -s "$_stream_pid_file" ] && _stream_tracked_pid="$(cat "$_stream_pid_file" 2>/dev/null)"
if [ -n "$_stream_tracked_pid" ] && kill -0 "$_stream_tracked_pid" 2>/dev/null; then
    lw_log_warn "_stream_worker.sh: reuse failed but mpvpaper (pid $_stream_tracked_pid, monitor: $MONITOR) is still alive -- leaving it running untouched, NOT killing/relaunching (url: $URL)"
    lw_write_apply_status "$status_file" "error" "$URL" "Failed to change stream via IPC (mpv is still running, not killed). Try again."
    exit 1
fi

# ── Kill existing wallpaper/stream on this monitor ───────────────────────
# Only reached when nothing was tracked, or the tracked pid has actually
# exited -- a genuine "no persistent mpv to reuse" case.
lw_kill_mpvpaper_for_monitor "$MONITOR"

# ── Build mpv options for streaming ──────────────────────────────────────
# Read hwdec preference from settings (same as lw_launch_mpvpaper).
hwdec="auto-safe"
if [ -s "$LW_SETTINGS_FILE" ] && command -v jq >/dev/null 2>&1; then
    _hwdec="$(jq -r '.hwdec // empty' "$LW_SETTINGS_FILE" 2>/dev/null)"
    [ -n "$_hwdec" ] && hwdec="$_hwdec"
fi

# For streaming: no scale/fps filter (bandwidth-constrained; let yt-dlp
# pick the best quality for this connection).
# --loop-playlist is silently ignored by mpv for live streams (Twitch,
# YouTube Live) regardless of LOOP -- mpv/yt-dlp auto-detects live vs VOD.
mpv_stream_opts="--hwdec=$hwdec --profile=fast"
mpv_stream_opts="$mpv_stream_opts --no-terminal --no-input-default-bindings"
if [ "$LOOP" = "yes" ]; then
    mpv_stream_opts="$mpv_stream_opts --loop-playlist=inf"
fi
if [ "$MUTE" = "yes" ]; then
    mpv_stream_opts="$mpv_stream_opts --mute=yes"
else
    mpv_stream_opts="$mpv_stream_opts --mute=no"
fi
# QUALITY caps the yt-dlp format selection at a max height -- it can
# only ever pick a SMALLER/equal format than what the source offers,
# never upscale past it. "auto" (default) leaves mpv/yt-dlp's own
# default selection untouched. No spaces in the selector string, so it
# stays safe inside the single mpv_stream_opts token mpvpaper receives.
if [ "$QUALITY" != "auto" ] && [ -n "$QUALITY" ]; then
    mpv_stream_opts="$mpv_stream_opts --ytdl-format=bestvideo[height<=?${QUALITY}]+bestaudio/best[height<=?${QUALITY}]/best"
fi
mpv_stream_opts="$mpv_stream_opts --script-opts=ytdl_hook-exclude=none"

# ── IPC socket (additive, streaming-only) ────────────────────────────────
# Exposes mpv's JSON IPC protocol so the panel can show real position/
# duration/pause/buffering and issue pause/resume/seek commands via
# stream_ipc.sh — see PlaybackService's streamPosition/streamDuration/
# streamPaused/streamBuffering + pauseStream()/resumeStream()/seekStreamTo().
# Purely additive: nothing else reads or requires this socket, so an old
# mpv build that doesn't support it simply leaves the feature inert
# (stream_ipc.sh already degrades to "{}" when the socket is missing).
mpv_ipc_sock="$(lw_monitor_state_file "$MONITOR" "mpv_ipc")"
rm -f "$mpv_ipc_sock" 2>/dev/null
mpv_stream_opts="$mpv_stream_opts --input-ipc-server=$mpv_ipc_sock"

# Capture mpvpaper output for diagnostics.
mpv_log="$LW_CACHE_DIR/mpvpaper_stream.log"

# Record PIDs running before this launch so we can identify the new one
# in a multi-monitor setup (same logic as lw_launch_mpvpaper).
before_pids="$(pgrep -x mpvpaper 2>/dev/null | sort -u)"

# Try hyprctl dispatch first (same preference logic as lw_launch_mpvpaper).
method_file="$(lw_monitor_state_dir "$MONITOR")/launch_method"
use_hyprctl=false
if [ -f "$method_file" ]; then
    [ "$(cat "$method_file")" = "hyprctl" ] && use_hyprctl=true
fi

launched_via_hyprctl=false
if $use_hyprctl && command -v hyprctl >/dev/null 2>&1; then
    launcher="$(mktemp /tmp/lwm_stream_launch_XXXXXX.sh)"
    {
        printf '#!/usr/bin/env bash\n'
        printf 'exec mpvpaper -f -o %q %q %q >> %q 2>&1\n' \
            "$mpv_stream_opts" "$MONITOR" "$URL" "$mpv_log"
    } > "$launcher"
    chmod +x "$launcher"
    hyprctl dispatch exec "$launcher" >/dev/null 2>&1
    launched_via_hyprctl=true

    for _j in $(seq 1 15); do
        pgrep -x mpvpaper >/dev/null 2>&1 && break
        sleep 0.1
    done
fi

lw_new_stream_pid() {
    comm -13 <(printf '%s\n' "$before_pids" | sort -u) \
             <(pgrep -x mpvpaper 2>/dev/null | sort -u) 2>/dev/null | head -1
}

if [ -z "$(lw_new_stream_pid)" ]; then
    [ "$launched_via_hyprctl" = "true" ] && echo "direct" > "$method_file"
    setsid mpvpaper -f -o "$mpv_stream_opts" "$MONITOR" "$URL" \
        >> "$mpv_log" 2>&1 < /dev/null &
    disown
fi

# ── Wait for mpvpaper to come up ─────────────────────────────────────────
# Streaming startup is typically faster than local video (no demuxer probe
# of a large file), but yt-dlp resolution adds some latency.
new_pid=""
for _i in $(seq 1 60); do
    new_pid="$(lw_new_stream_pid)"
    [ -n "$new_pid" ] && break
    sleep 0.2
done

if [ -n "$new_pid" ]; then
    lw_write_text_atomic "$pid_file" "$new_pid"
    [ "$launched_via_hyprctl" = "true" ] && echo "hyprctl" > "$method_file"
    lw_mpv_write_launch_sig "$MONITOR" "$mode_sig"

    # Record URL as current (the original URL, not a resolved CDN link)
    lw_write_text_atomic "$(lw_monitor_state_file "$MONITOR" "current")" "stream:$URL"
    lw_write_apply_status "$status_file" "success" "stream:$URL" "Stream is playing"
    lw_log_info "_stream_worker.sh: streaming started (url: $URL, pid: $new_pid, monitor: $MONITOR, loop: $LOOP, mute: $MUTE, quality: $QUALITY, ipc: $mpv_ipc_sock)"
else
    real_error=""
    [ -s "$mpv_log" ] && real_error="$(tail -n 6 "$mpv_log" | tr '\n' ' ')"
    rm -f "$mpv_ipc_sock" 2>/dev/null
    lw_write_apply_status "$status_file" "error" "$URL" \
        "mpvpaper failed to start.${real_error:+ $real_error}"
    lw_log_error "_stream_worker.sh: mpvpaper exited immediately (url: $URL, monitor: $MONITOR). ${real_error}"
    exit 1
fi
