#!/usr/bin/env bash
#
# _stream_worker.sh <url> <monitor> [loop] [mute] [quality]
# -------------------------------------------------------
# Internal script — not meant to be run by hand (use stream_wallpaper.sh).
#
# Waits 1 second (debounce), then:
#   1. Stops any previous mpvpaper instance on the monitor.
#   2. Resolves supported YouTube streams with yt-dlp, then launches mpvpaper
#      with the resolved media URL and the selected quality constraint.
#   3. Writes the result to apply_status so PlaybackService picks it up.
#
# The launch model is based on Manpaper, while YouTube extraction is handled
# explicitly so mpv cannot fall back to the ANDROID_VR client that can return 403.

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
mpv_ipc_sock="$(lw_monitor_state_file "$MONITOR" "mpv_ipc")"
# Remove worker_pid on exit so the next apply does not try to cancel a
# process that has already finished.
cleanup_worker_pid() {
    if [ -s "$worker_pid_file" ] && [ "$(cat "$worker_pid_file" 2>/dev/null)" = "$$" ]; then
        rm -f "$worker_pid_file"
    fi
}
trap cleanup_worker_pid EXIT

# mpvpaper needs a Wayland session (wlr-layer-shell) -- on X11 (e.g.
# Plasma X11) it can't connect to anything and would otherwise just die
# with an opaque error. Fail fast with a clear, actionable message
# instead. See lw_wayland_required_error in utils.sh.
lw_wayland_session_ok || { lw_wayland_required_error "$status_file" "$URL"; exit 1; }

# ── 1-second debounce ────────────────────────────────────────────────────
# Wallpaper applies no longer debounce at all (video->video switches reuse
# the live mpv process over IPC, see _apply_worker.sh). Streams cannot take
# that path -- every new URL needs a fresh yt-dlp resolve plus an mpvpaper
# kill/relaunch -- so this short window lets a quickly-superseded request
# get cancelled (lw_cancel_inflight_apply_worker) instead of paying for a
# teardown/relaunch the user already moved on from.
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

# ── Stream resolution + Manpaper-style launch ─────────────────────────────
# Resolve YouTube streams ourselves instead of relying on mpv's bundled
# ytdl_hook. This avoids environments where ytdl_hook selects ANDROID_VR and
# the resulting googlevideo URLs return HTTP 403.
# The resolver in utils.sh uses only web_embedded/web_safari and returns
# either a direct progressive URL or an edl:// combining exact video+audio.
PLAYBACK_URL="$URL"
if echo "$URL" | grep -qiE 'youtu\.?be'; then
    resolved_url="$(lw_resolve_stream_playback_url "$URL" "$QUALITY" 2>/dev/null || true)"
    if [ -n "$resolved_url" ]; then
        PLAYBACK_URL="$resolved_url"
        lw_log_info "_stream_worker.sh: yt-dlp resolved YouTube stream without mpv ytdl_hook (quality=$QUALITY)"
    else
        lw_write_apply_status "$status_file" "error" "$URL" \
            "yt-dlp could not resolve the YouTube stream with web_embedded/web_safari."
        lw_log_error "_stream_worker.sh: YouTube resolution failed (url: $URL, quality: $QUALITY)"
        exit 1
    fi
fi

# Stop any previous player on this monitor before launching the stream.
lw_kill_mpvpaper_for_monitor "$MONITOR"
rm -f "$mpv_ipc_sock" 2>/dev/null

# Read the same settings used by the rest of the app.
hwdec="auto-safe"
volume="100"
fill_type="Fit"
if [ -s "$LW_SETTINGS_FILE" ] && command -v jq >/dev/null 2>&1; then
    _hwdec="$(jq -r '.hwdec // empty' "$LW_SETTINGS_FILE" 2>/dev/null)"
    _volume="$(jq -r '.video_volume // empty' "$LW_SETTINGS_FILE" 2>/dev/null)"
    _fill="$(jq -r '.mpvpaper_fill_type // empty' "$LW_SETTINGS_FILE" 2>/dev/null)"
    [ -n "$_hwdec" ] && hwdec="$_hwdec"
    [ -n "$_volume" ] && volume="$_volume"
    [ -n "$_fill" ] && fill_type="$_fill"
fi

mpv_stream_opts="loop"
# The stream mute argument is authoritative. Older settings files may not
# contain enable_video_sound/video_volume, so default to audible playback.
if [ "$MUTE" = "yes" ]; then
    mpv_stream_opts="$mpv_stream_opts volume=0 mute=yes"
else
    mpv_stream_opts="$mpv_stream_opts volume=$volume mute=no"
fi

if [ "$fill_type" = "Crop" ]; then
    mpv_stream_opts="$mpv_stream_opts --panscan=1 --window-maximized=yes"
fi

mpv_stream_opts="$mpv_stream_opts hwdec=$hwdec"
# URL is already resolved for YouTube, so do NOT let ytdl_hook inspect it again.
# This prevents mpv from re-extracting the original YouTube URL with ANDROID_VR.
if [[ "$PLAYBACK_URL" == edl://* || "$PLAYBACK_URL" == http://* || "$PLAYBACK_URL" == https://* ]]; then
    mpv_stream_opts="$mpv_stream_opts script-opts=ytdl_hook-exclude=all"
fi

mpv_stream_opts="$mpv_stream_opts input-ipc-server=$mpv_ipc_sock"

mpv_log="$LW_CACHE_DIR/mpvpaper_stream.log"
: > "$mpv_log"
before_pids="$(pgrep -x mpvpaper 2>/dev/null | sort -u)"

# Manpaper command shape, but with the resolved media source for YouTube.
# Use -f (fork to background) to match the flag used by every other
# wallpaper mode (see apply_wallpaper.sh / _web_worker.sh). The previous
# "-vs" here added mpvpaper's -s "stop drawing when the wallpaper output
# is covered" behavior, which this was the only launch path to use --
# a stray desktop click can register as the output being covered and
# blanks the stream. -f keeps background/log-capture behavior identical
# to the other two modes without that auto-stop side effect.
#
# Target "$MONITOR" (the single output resolved above and used for every
# state file: pid, mpv_ipc, current, apply_status), NOT the literal "ALL".
# Every other mpvpaper launch path in this project targets one specific
# output name -- launching across every output in one mpvpaper process
# while only tracking state for one of them was a mismatch, and asking
# mpvpaper to manage a layer-shell surface per output make it far more
# exposed to a compositor reconfigure event (e.g. KWin/Plasma re-issuing
# layer-shell configure on every output when the desktop regains input
# focus from a click) taking down the whole process instead of just one
# surface.
setsid mpvpaper -f -o "$mpv_stream_opts" "$MONITOR" "$PLAYBACK_URL" \
    >> "$mpv_log" 2>&1 < /dev/null &
disown 2>/dev/null || true

lw_new_stream_pid() {
    comm -13 <(printf '%s\n' "$before_pids" | sort -u) \
             <(pgrep -x mpvpaper 2>/dev/null | sort -u) 2>/dev/null | head -1
}

# ── Wait for mpvpaper to come up ─────────────────────────────────────────
# Streaming startup is typically faster than local video (no demuxer probe
# of a large file), but yt-dlp resolution adds some latency.
new_pid=""
for _i in $(seq 1 150); do
    new_pid="$(lw_new_stream_pid)"
    [ -n "$new_pid" ] && break
    sleep 0.2
done

# pgrep can catch mpvpaper's pid for a brief moment even when it's about
# to fail -- compositor-connect failure time varies from well under a
# second to a few seconds depending on system state, so a single quick
# check isn't reliable. Poll for up to 4s and only trust this as a real
# success if the process is still alive at the end of that window (it
# exits immediately, breaking out of this loop early, if it does die).
# Without this, a compositor-connect failure gets reported as "Stream
# started" while nothing is actually playing.
if [ -n "$new_pid" ]; then
    still_alive=true
    for _s in $(seq 1 20); do
        sleep 0.2
        if ! kill -0 "$new_pid" 2>/dev/null; then
            still_alive=false
            break
        fi
    done
    [ "$still_alive" = "false" ] && new_pid=""
fi

if [ -n "$new_pid" ]; then
    lw_write_text_atomic_fast "$pid_file" "$new_pid"
    lw_mpv_write_launch_sig "$MONITOR" "mode=stream loop=$LOOP mute=$MUTE quality=$QUALITY"

    # Record the original URL as the current stream identity.
    lw_write_text_atomic_fast "$(lw_monitor_state_file "$MONITOR" "current")" "stream:$URL"
    ipc_ready=false
    for _k in $(seq 1 100); do
        if [ -S "$mpv_ipc_sock" ]; then ipc_ready=true; break; fi
        sleep 0.2
    done
    if $ipc_ready; then
        lw_write_apply_status "$status_file" "success" "stream:$URL" "Stream is playing"
    else
        lw_write_apply_status "$status_file" "success" "stream:$URL" "Stream started (IPC pending)"
    fi
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
