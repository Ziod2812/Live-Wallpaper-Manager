#!/usr/bin/env bash
#
# _apply_worker.sh <video_path> <resolution> <fps> <monitor>
# -------------------------------------------------------
# Internal script -- not meant to be run by hand (use apply_wallpaper.sh).
#
# Runs immediately (no artificial debounce/delay) -- normal wallpaper
# switching (Next/Previous/Random/manual/auto-rotation/playlist/preset)
# is handled via lw_switch_wallpaper_via_ipc, which swaps the file on the
# ALREADY-RUNNING mpvpaper process over IPC instead of killing and
# relaunching it. Since this no longer spawns a new mpvpaper process on
# every click, no debounce is needed for that purpose.
#
# Rapid-click safety is instead provided by lw_cancel_inflight_apply_worker
# (called from apply_wallpaper.sh before dispatching a new worker), which
# terminates this worker's entire process group -- including any in-flight
# IPC helper call -- the instant a newer selection supersedes it.
#
# See the "PERSISTENT-MPV CONTRACT" block in utils.sh for the full
# three-function architecture (lw_switch_wallpaper_via_ipc /
# lw_start_persistent_mpv / lw_stop_persistent_mpv) this script follows.
# The result is written to apply_status either way.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

VIDEO="$1"
RESOLUTION="$2"
FPS="$3"
MONITOR="$4"

status_file="$(lw_monitor_state_file "$MONITOR" "apply_status")"

# Clean up the worker_pid file on exit so a subsequent apply does not
# try to cancel a process that has already finished.
worker_pid_file="$(lw_monitor_state_file "$MONITOR" "worker_pid")"
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
lw_wayland_session_ok || { lw_wayland_required_error "$status_file" "$VIDEO"; exit 1; }

# Play the requested wallpaper directly.
PLAYBACK_VIDEO="$VIDEO"

# ── AWWW backend for animated GIFs only ─────────────────────────────────
# AWWW is intentionally limited to GIF wallpapers in this build. PNG/JPG/WEBP
# and all video formats continue through their existing MPV/mpvpaper path, so
# the AWWW transition controls never affect MP4/live wallpaper playback.
awww_backend=false
case "${VIDEO##*.}" in
    gif|GIF)
        if lw_transition_enabled && lw_awww_available && lw_ensure_awww_daemon; then
            awww_backend=true
        fi
        ;;
esac

if [ "$awww_backend" = "true" ]; then
    # ── GRACEFUL TRANSITION (video -> awww) ─────────────────────────────
    # FORMERLY: the live mpv layer-shell surface was torn down (via
    # lw_stop_persistent_mpv) BEFORE the AWWW frame was drawn. Killing
    # mpvpaper is not instant -- lw_kill_mpvpaper_for_monitor waits out a
    # SIGTERM poll loop and a compositor-cleanup sleep (can run past half
    # a second in the SIGKILL-escalation case, see lw_kill_mpvpaper in
    # utils.sh) -- so for that whole window nothing was attached to the
    # background layer at all: a real "no surface attached" gap, not just
    # a slow paint. This is also a direct violation of lw_stop_persistent_mpv's
    # own contract comment in utils.sh ("Never call this from a
    # wallpaper-switch code path").
    #
    # FIX: draw the new AWWW frame FIRST, while the outgoing mpv surface
    # is still alive and attached underneath it. Only after that draw is
    # confirmed successful -- plus a short buffer delay so the compositor
    # has actually committed the new frame, not just acknowledged the IPC
    # call -- is the old mpv layer released. If the AWWW draw fails for
    # any reason, mpv is deliberately left running untouched and control
    # falls through to the ordinary mpvpaper path below, so a failed
    # switch never leaves the screen with nothing valid attached.
    if lw_apply_awww_wallpaper "$VIDEO" "$MONITOR"; then
        # Grace buffer: `awww img` returning success only means the awww
        # daemon accepted+processed the command over its own IPC socket,
        # not that the compositor has necessarily painted/committed the
        # resulting frame yet. 80ms sits inside the requested 50-100ms
        # window -- long enough to cover that commit, short enough to be
        # imperceptible as a switch delay.
        sleep 0.08

        pid_file="$(lw_monitor_state_file "$MONITOR" "pid")"
        if [ -s "$pid_file" ]; then
            tracked_pid="$(cat "$pid_file" 2>/dev/null)"
            if [ -n "$tracked_pid" ] && kill -0 "$tracked_pid" 2>/dev/null; then
                lw_stop_persistent_mpv "$MONITOR"
            fi
        fi

        lw_write_text_atomic_fast "$(lw_monitor_state_file "$MONITOR" "current")" "$VIDEO"
        lw_write_text_atomic_fast "$(lw_monitor_state_file "$MONITOR" "last")" "$VIDEO"
        lw_write_text_atomic_fast "$LW_CURRENT_FILE" "$VIDEO"
        lw_write_text_atomic_fast "$LW_LAST_FILE" "$VIDEO"
        lw_add_history "$VIDEO"
        lw_write_apply_status "$status_file" "success" "$VIDEO" "Applied wallpaper with AWWW transition: $VIDEO"
        lw_log_info "Applied AWWW wallpaper: $VIDEO (monitor: $MONITOR, transition: $(lw_transition_type), duration: $(lw_transition_duration)s)"
        # Smart Accent Color: GIF first-frame extraction happens inside
        # apply_smart_color.py itself (Pillow) -- dispatched here, AFTER
        # the wallpaper is already confirmed applied, never blocking it.
        lw_trigger_smart_accent "$VIDEO" "$MONITOR"
        exit 0
    fi

    lw_log_warn "AWWW was available but failed to apply GIF '$VIDEO'; falling back to mpvpaper. mpv (if any) was left running untouched."
fi

# ── Video extension check (shared with wallpaper_list.sh's scan list) ───
# Used below to tell an actual video file apart from a static image
# (png/jpg/webp) that also plays through mpvpaper -- "Video -> Video" only
# means something when BOTH the outgoing and incoming files are real
# video containers, not just "not a gif".
_lw_is_video_ext() {
    case "${1##*.}" in
        [Mm][Pp]4|[Ww][Ee][Bb][Mm]|[Mm][Kk][Vv]|[Mm][Oo][Vv]|[Aa][Vv][Ii]|\
        [Mm]4[Vv]|[Mm][Pp][Ee][Gg]|[Mm][Pp][Gg]|[Ww][Mm][Vv]|[Ff][Ll][Vv]|\
        [Tt][Ss]|[Mm][Tt][Ss]|[Mm]2[Tt][Ss]|3[Gg][Pp]|[Oo][Gg][Vv])
            return 0 ;;
    esac
    return 1
}

# ── Single persistent mpv (per monitor) -- determined EARLY ──────────────
# Needs to be known before deciding how to handle the transition below, so
# the video->video-with-live-mpv case can route straight to the native MPV
# fade instead of also going through the AWWW frame-cover path.
pid_file="$(lw_monitor_state_file "$MONITOR" "pid")"
tracked_pid=""
[ -s "$pid_file" ] && tracked_pid="$(cat "$pid_file" 2>/dev/null)"
tracked_alive=false
[ -n "$tracked_pid" ] && kill -0 "$tracked_pid" 2>/dev/null && tracked_alive=true

# What was actually playing on this monitor before this switch (used only
# to test "was the outgoing wallpaper a video", never written to below).
current_file_path="$(lw_monitor_state_file "$MONITOR" "current")"
PREVIOUS_VIDEO=""
[ -s "$current_file_path" ] && PREVIOUS_VIDEO="$(cat "$current_file_path" 2>/dev/null)"

use_native_mpv_transition=false
if [ "$tracked_alive" = "true" ] && lw_transition_enabled \
    && _lw_is_video_ext "$VIDEO" && [ -n "$PREVIOUS_VIDEO" ] && _lw_is_video_ext "$PREVIOUS_VIDEO"; then
    use_native_mpv_transition=true
fi

video_transition_duration=""
if [ "$use_native_mpv_transition" = "true" ]; then
    # ── Video -> Video, transitions enabled, mpv already alive ──────────
    # Skip the AWWW frame-extraction cover entirely: no ffmpeg first-frame
    # grab, no `awww img` call, no temporary overlay layer at all. The
    # fade is instead handled entirely inside the SAME mpv process via
    # IPC (lw_switch_wallpaper_via_ipc -> lw_mpv_try_reuse), which already
    # forwards the user's transition type/duration from settings.json
    # into `_mpv_ipc.py apply-wallpaper` -- see _transition_before_load /
    # _transition_after_load there, which cross-fade old->new entirely
    # inside mpv's own lavfi filter chain. This removes the redundant
    # second transition layer (AWWW overlay running on its own bash-side
    # timer, on top of mpv's independent internal fade) that was slowing
    # the switch down and going out of sync with it -- the actual cause
    # of the black/stutter reported for Enable-transitions video->video
    # switches. No UI/.qml changes: this only changes which internal path
    # carries out the same "Enable transitions" setting the user already
    # sees and controls in Settings.
    lw_log_info "_apply_worker.sh: video->video with live mpv + transitions enabled -- using native MPV fade via IPC, skipping AWWW overlay (monitor: $MONITOR, video: $VIDEO)"
else
    # Live/video wallpapers: use AWWW only as a temporary transition layer fed
    # by a frame extracted from the NEW video. This matches the proven manual flow:
    #
    #   video -> ffmpeg first frame -> awww transition -> existing MPV loadfile
    #
    # No desktop screenshot is taken, and the existing mpvpaper process is kept
    # alive. If AWWW/ffmpeg is unavailable, fall back to a direct IPC swap.
    #
    # This path still covers every case that ISN'T a live video->video
    # switch: transitions disabled (lw_apply_awww_video_transition itself
    # returns 1 immediately in that case -- no behavior change there),
    # switching from/to a static image, or no mpv alive yet to fade from
    # (first launch / explicit Stop / crash recovery) -- in all of those
    # there either is nothing to natively cross-fade against yet, or the
    # user hasn't asked for a fade at all.
    if lw_apply_awww_video_transition "$VIDEO" "$MONITOR" >/tmp/lwm-transition-duration-$$ 2>/dev/null; then
        video_transition_duration="$(cat /tmp/lwm-transition-duration-$$ 2>/dev/null)"
    fi
    rm -f /tmp/lwm-transition-duration-$$
fi

# Keep AWWW visible until the new media is loaded, then reveal the live video.
# This is deliberately not a stop/relaunch cycle: the same mpvpaper surface
# is reused below via MPV IPC.

if [ "$tracked_alive" = "true" ]; then
    started="$(lw_switch_wallpaper_via_ipc "$PLAYBACK_VIDEO" "$MONITOR" "$RESOLUTION" "$FPS" "mode=wallpaper")"

    if [ "$started" != "true" ]; then
        lw_log_warn "_apply_worker.sh: IPC switch failed but mpvpaper (pid $tracked_pid, monitor: $MONITOR) is still alive -- leaving it running untouched, NOT killing/relaunching (video: $VIDEO)"
        lw_write_apply_status "$status_file" "error" "$VIDEO" "Failed to change wallpaper via IPC (mpv is still running, not killed). Try again."
        exit 1
    fi
else
    # First run / explicit Stop / genuine crash: start the one player.
    started="$(lw_start_persistent_mpv "$PLAYBACK_VIDEO" "$MONITOR" "$RESOLUTION" "$FPS")"

    if [ "$started" != "true" ]; then
        mpv_log="$LW_CACHE_DIR/mpvpaper.log"
        real_error=""
        [ -s "$mpv_log" ] && real_error="$(tail -n 8 "$mpv_log" | tr '\n' ' ')"
        lw_log_error "_apply_worker.sh: mpvpaper exited immediately after 3 attempts (monitor: $MONITOR, resolution: $RESOLUTION, fps: $FPS, video: $VIDEO, actually attempted: $PLAYBACK_VIDEO). mpvpaper said: $real_error"

        if [ -n "$real_error" ]; then
            lw_write_apply_status "$status_file" "error" "$VIDEO" "mpvpaper failed: $real_error"
        else
            lw_write_apply_status "$status_file" "error" "$VIDEO" "mpvpaper exited immediately after 3 attempts (monitor: $MONITOR). No output captured -- check that mpvpaper/mpv are installed correctly."
        fi
        exit 1
    fi
fi

# Reveal the freshly loaded video after the AWWW transition layer finishes.
# Not reached at all when use_native_mpv_transition=true above, since
# video_transition_duration is left empty in that branch -- AWWW was never
# touched for this switch, so there is nothing here to clear.
#
# GRACE FLOOR: video_transition_duration comes straight from the user's
# "Enable transitions" duration setting (lw_apply_awww_video_transition ->
# lw_transition_duration), which can be configured arbitrarily small (or
# technically 0). Sleeping for exactly that value would clear the AWWW
# overlay the instant it expires, with no guarantee mpvpaper has actually
# committed its first decoded frame to the compositor by then -- the same
# "surface swapped before the next one is ready" race as the video->awww
# direction above, just triggered by a user setting instead of a fixed
# kill delay. Floor the wait at 80ms (same grace window used above) so the
# overlay can never be cleared sooner than that, regardless of what the
# user has the transition duration set to.
if [ -n "$video_transition_duration" ]; then
    grace_wait="$(awk -v d="$video_transition_duration" 'BEGIN { print (d < 0.08) ? 0.08 : d }' 2>/dev/null)"
    [ -n "$grace_wait" ] || grace_wait=0.08
    sleep "$grace_wait"
    lw_clear_awww_output "$MONITOR"
fi

# Per-monitor state -- regenerable runtime cache, ATOMIC-ONLY tier (see
# the CRASH-SAFE ATOMIC WRITES header in utils.sh): the atomic rename is
# what readers depend on; the two `sync -f` subprocesses per file were the
# main per-switch cost before the fast tier existed.
lw_write_text_atomic_fast "$(lw_monitor_state_file "$MONITOR" "current")" "$VIDEO"
lw_write_text_atomic_fast "$(lw_monitor_state_file "$MONITOR" "last")" "$VIDEO"
lw_write_text_atomic_fast "$(lw_monitor_state_file "$MONITOR" "resolution")" "$RESOLUTION"
lw_write_text_atomic_fast "$(lw_monitor_state_file "$MONITOR" "fps")" "$FPS"

# Legacy global mirror for single-monitor setups
lw_write_text_atomic_fast "$LW_CURRENT_FILE" "$VIDEO"
lw_write_text_atomic_fast "$LW_LAST_FILE" "$VIDEO"
lw_write_text_atomic_fast "$LW_RESOLUTION_FILE" "$RESOLUTION"
lw_write_text_atomic_fast "$LW_FPS_FILE" "$FPS"

lw_add_history "$VIDEO"
lw_write_apply_status "$status_file" "success" "$VIDEO" "Applied wallpaper: $VIDEO"

lw_log_info "Applied wallpaper: $VIDEO (monitor: $MONITOR, resolution: $RESOLUTION, fps: $FPS)"

# Smart Accent Color: video -> thumbnail (ffmpeg) -> dominant color, image ->
# direct. Dispatched last, AFTER every state file above is already written
# and the switch is confirmed applied -- see lw_trigger_smart_accent's own
# header (utils.sh) for the fire-and-forget/no-block contract.
lw_trigger_smart_accent "$VIDEO" "$MONITOR"
