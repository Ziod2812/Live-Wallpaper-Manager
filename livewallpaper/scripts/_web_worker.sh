#!/usr/bin/env bash
#
# _web_worker.sh <source> <type> <monitor>
# -------------------------------------------------------
# Internal script — not meant to be run by hand (use web_wallpaper.sh).
#
# Handles two paths depending on <type>:
#
#   url   — Passes the URL to mpvpaper/mpv exactly like _stream_worker.sh.
#            Works for any URL mpv can play (yt-dlp sites, direct HLS/MP4,
#            WebM, etc.). Pure-HTML URLs (no embeddable media) will fail at
#            the mpv level and surface as an error status.
#
#   local — Resolves to a file:// URL and launches a Wayland-compatible
#            browser (chromium → google-chrome → firefox) in kiosk mode.
#            Records the browser PID in the monitor's state dir so
#            lw_kill_mpvpaper_for_monitor can terminate it on the next
#            stop/mode-switch (that function kills by PID, not by name).
#            If no browser is found, writes an error status.
#
# 1-second debounce (same as _stream_worker.sh).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

SOURCE="$1"
TYPE="$2"
MONITOR="$3"

status_file="$(lw_monitor_state_file "$MONITOR" "apply_status")"
worker_pid_file="$(lw_monitor_state_file "$MONITOR" "worker_pid")"
pid_file="$(lw_monitor_state_file "$MONITOR" "pid")"

cleanup_worker_pid() {
    if [ -s "$worker_pid_file" ] && [ "$(cat "$worker_pid_file" 2>/dev/null)" = "$$" ]; then
        rm -f "$worker_pid_file"
    fi
}
trap cleanup_worker_pid EXIT

sleep 1

# ── Kill whatever is currently playing on this monitor ───────────────────
# (Local-HTML/browser kiosk path still needs this unconditionally, since
# a browser process has no IPC reuse mechanism. The URL path below tries
# reuse FIRST and only falls through to this kill if that isn't possible.)
if [ "$TYPE" = "url" ]; then
    if command -v mpvpaper >/dev/null 2>&1; then
        # Same single-persistent-mpv mechanism as local wallpapers/streams
        # (see lw_mpv_try_reuse in utils.sh): swap the URL in place over
        # IPC instead of killing and relaunching mpvpaper, when possible.
        # lw_mpv_try_reuse retries internally against the SAME pid for any
        # transient IPC trouble and only reports "false" when there was
        # genuinely nothing alive to reuse.
        if [ "$(lw_mpv_try_reuse "$SOURCE" "$MONITOR" "original" "original" "mode=web")" = "true" ]; then
            lw_write_text_atomic "$(lw_monitor_state_file "$MONITOR" "current")" "web:$SOURCE"
            lw_write_apply_status "$status_file" "success" "web:$SOURCE" "Web is playing"
            lw_log_info "_web_worker.sh: reused existing mpv for new URL (url: $SOURCE, monitor: $MONITOR)"
            exit 0
        fi

        # ── ONLY create a new mpv if the tracked one has ACTUALLY exited ─
        # A live tracked mpvpaper is never killed here just because reuse
        # reported "false" -- same guarantee as _apply_worker.sh.
        _web_tracked_pid=""
        [ -s "$pid_file" ] && _web_tracked_pid="$(cat "$pid_file" 2>/dev/null)"
        if [ -n "$_web_tracked_pid" ] && kill -0 "$_web_tracked_pid" 2>/dev/null; then
            lw_log_warn "_web_worker.sh: reuse failed but mpvpaper (pid $_web_tracked_pid, monitor: $MONITOR) is still alive -- leaving it running untouched, NOT killing/relaunching (url: $SOURCE)"
            lw_write_apply_status "$status_file" "error" "$SOURCE" "Failed to change web URL via IPC (mpv is still running, not killed). Try again."
            exit 1
        fi
    fi
fi
# Reached only for: the "local" (browser kiosk) type, which always needs a
# fresh kill+relaunch (browsers have no IPC reuse mechanism); or the "url"
# type when nothing was tracked / the tracked mpv has actually exited.
lw_kill_mpvpaper_for_monitor "$MONITOR"

# ═══════════════════════════════════════════════════════════════════════════
# PATH A: URL → mpvpaper/mpv (same mechanism as _stream_worker.sh)
# ═══════════════════════════════════════════════════════════════════════════
if [ "$TYPE" = "url" ]; then
    if ! command -v mpvpaper >/dev/null 2>&1; then
        lw_write_apply_status "$status_file" "error" "$SOURCE" \
            "mpvpaper not found. Install mpvpaper to play a web URL."
        exit 1
    fi

    hwdec="auto-safe"
    if [ -s "$LW_SETTINGS_FILE" ] && command -v jq >/dev/null 2>&1; then
        _hwdec="$(jq -r '.hwdec // empty' "$LW_SETTINGS_FILE" 2>/dev/null)"
        [ -n "$_hwdec" ] && hwdec="$_hwdec"
    fi

    mpv_opts="--hwdec=$hwdec --profile=fast"
    mpv_opts="$mpv_opts --no-terminal --no-input-default-bindings"
    mpv_opts="$mpv_opts --loop-playlist=inf"
    mpv_opts="$mpv_opts --script-opts=ytdl_hook-exclude=none"

    mpv_log="$LW_CACHE_DIR/mpvpaper_web.log"
    before_pids="$(pgrep -x mpvpaper 2>/dev/null | sort -u)"

    method_file="$(lw_monitor_state_dir "$MONITOR")/launch_method"
    use_hyprctl=false
    [ -f "$method_file" ] && [ "$(cat "$method_file")" = "hyprctl" ] && use_hyprctl=true

    launched_via_hyprctl=false
    if $use_hyprctl && command -v hyprctl >/dev/null 2>&1; then
        launcher="$(mktemp /tmp/lwm_web_launch_XXXXXX.sh)"
        {
            printf '#!/usr/bin/env bash\n'
            printf 'exec mpvpaper -f -o %q %q %q >> %q 2>&1\n' \
                "$mpv_opts" "$MONITOR" "$SOURCE" "$mpv_log"
        } > "$launcher"
        chmod +x "$launcher"
        hyprctl dispatch exec "$launcher" >/dev/null 2>&1
        launched_via_hyprctl=true
        for _j in $(seq 1 15); do pgrep -x mpvpaper >/dev/null 2>&1 && break; sleep 0.1; done
    fi

    lw_new_web_pid() {
        comm -13 <(printf '%s\n' "$before_pids" | sort -u) \
                 <(pgrep -x mpvpaper 2>/dev/null | sort -u) 2>/dev/null | head -1
    }

    if [ -z "$(lw_new_web_pid)" ]; then
        [ "$launched_via_hyprctl" = "true" ] && echo "direct" > "$method_file"
        setsid mpvpaper -f -o "$mpv_opts" "$MONITOR" "$SOURCE" \
            >> "$mpv_log" 2>&1 < /dev/null &
        disown
    fi

    new_pid=""
    for _i in $(seq 1 60); do
        new_pid="$(lw_new_web_pid)"
        [ -n "$new_pid" ] && break
        sleep 0.2
    done

    if [ -n "$new_pid" ]; then
        lw_write_text_atomic "$pid_file" "$new_pid"
        [ "$launched_via_hyprctl" = "true" ] && echo "hyprctl" > "$method_file"
        lw_mpv_write_launch_sig "$MONITOR" "mode=web"
        lw_write_text_atomic "$(lw_monitor_state_file "$MONITOR" "current")" "web:$SOURCE"
        lw_write_apply_status "$status_file" "success" "web:$SOURCE" "Web is playing"
        lw_log_info "_web_worker.sh: URL playing (url: $SOURCE, pid: $new_pid, monitor: $MONITOR)"
    else
        real_error=""
        [ -s "$mpv_log" ] && real_error="$(tail -n 6 "$mpv_log" | tr '\n' ' ')"
        lw_write_apply_status "$status_file" "error" "$SOURCE" \
            "mpvpaper failed to start.${real_error:+ $real_error}"
        lw_log_error "_web_worker.sh: mpvpaper failed for URL (url: $SOURCE, monitor: $MONITOR)"
        exit 1
    fi

# ═══════════════════════════════════════════════════════════════════════════
# PATH B: Local HTML → browser kiosk mode
# ═══════════════════════════════════════════════════════════════════════════
elif [ "$TYPE" = "local" ]; then
    # Resolve to absolute path
    if [ ! -f "$SOURCE" ]; then
        lw_write_apply_status "$status_file" "error" "$SOURCE" \
            "File does not exist: $SOURCE"
        exit 1
    fi

    abs_path="$(realpath "$SOURCE" 2>/dev/null)"
    if [ -z "$abs_path" ]; then
        lw_write_apply_status "$status_file" "error" "$SOURCE" \
            "Could not resolve file path: $SOURCE"
        exit 1
    fi
    file_url="file://$abs_path"

    # Find a Wayland-compatible browser
    BROWSER=""
    BROWSER_NAME=""
    for b in chromium chromium-browser google-chrome-stable google-chrome firefox; do
        if command -v "$b" >/dev/null 2>&1; then
            BROWSER="$b"
            BROWSER_NAME="$b"
            break
        fi
    done

    if [ -z "$BROWSER" ]; then
        lw_write_apply_status "$status_file" "error" "$SOURCE" \
            "No browser found. Install chromium or firefox to use Local HTML."
        exit 1
    fi

    # Get monitor geometry for --window-size (best-effort via hyprctl)
    mon_width=1920
    mon_height=1080
    if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        mon_info="$(hyprctl monitors -j 2>/dev/null | \
            jq -r ".[] | select(.name==\"$MONITOR\") | \"\(.width)x\(.height)\"" 2>/dev/null | head -1)"
        if [ -n "$mon_info" ]; then
            mon_width="${mon_info%x*}"
            mon_height="${mon_info#*x}"
        fi
    fi

    # Launch browser in kiosk mode
    if echo "$BROWSER_NAME" | grep -qE 'chromium|chrome'; then
        setsid "$BROWSER" \
            --app="$file_url" \
            --kiosk \
            --window-position=0,0 \
            --window-size="${mon_width},${mon_height}" \
            --disable-extensions \
            --no-first-run \
            --no-default-browser-check \
            --disable-background-networking \
            --disable-sync \
            > "$LW_CACHE_DIR/web_browser.log" 2>&1 &
    else
        # Firefox kiosk mode
        setsid "$BROWSER" \
            --kiosk \
            "$file_url" \
            > "$LW_CACHE_DIR/web_browser.log" 2>&1 &
    fi
    browser_pid=$!
    disown

    sleep 1.5

    if kill -0 "$browser_pid" 2>/dev/null; then
        lw_write_text_atomic "$pid_file" "$browser_pid"
        lw_write_text_atomic "$(lw_monitor_state_file "$MONITOR" "current")" "web-local:$SOURCE"
        lw_write_apply_status "$status_file" "success" "web-local:$SOURCE" \
            "Local HTML is displayed"
        lw_log_info "_web_worker.sh: local HTML browser launched (file: $SOURCE, pid: $browser_pid, monitor: $MONITOR)"
    else
        browser_log="$LW_CACHE_DIR/web_browser.log"
        real_error=""
        [ -s "$browser_log" ] && real_error="$(tail -n 4 "$browser_log" | tr '\n' ' ')"
        lw_write_apply_status "$status_file" "error" "$SOURCE" \
            "Browser exited immediately.${real_error:+ $real_error}"
        lw_log_error "_web_worker.sh: browser exited immediately (file: $SOURCE, monitor: $MONITOR)"
        exit 1
    fi

else
    lw_write_apply_status "$status_file" "error" "$SOURCE" \
        "Invalid source type: $TYPE (must be 'url' or 'local')"
    exit 1
fi
