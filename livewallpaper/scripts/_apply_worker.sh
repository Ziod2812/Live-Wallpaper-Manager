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

# Play the requested wallpaper directly.
PLAYBACK_VIDEO="$VIDEO"

# ── Single persistent mpv (per monitor) ──────────────────────────────────
# Structural contract (see the "PERSISTENT-MPV CONTRACT" block in
# utils.sh): this is the ONLY decision a normal wallpaper switch makes.
#
#   pid tracked and alive  -> lw_switch_wallpaper_via_ipc (IPC loadfile,
#                              same process, retries internally, NEVER
#                              kills even if every retry is exhausted)
#   pid not tracked/dead   -> lw_start_persistent_mpv (starts the ONE
#                              player; refuses to touch anything live)
#
# There is no third branch and no kill call written directly in this
# script -- lw_kill_mpvpaper_for_monitor is not named anywhere below.
pid_file="$(lw_monitor_state_file "$MONITOR" "pid")"
tracked_pid=""
[ -s "$pid_file" ] && tracked_pid="$(cat "$pid_file" 2>/dev/null)"
tracked_alive=false
[ -n "$tracked_pid" ] && kill -0 "$tracked_pid" 2>/dev/null && tracked_alive=true

if [ "$tracked_alive" = "true" ]; then
    started="$(lw_switch_wallpaper_via_ipc "$PLAYBACK_VIDEO" "$MONITOR" "$RESOLUTION" "$FPS")"

    if [ "$started" != "true" ]; then
        lw_log_warn "_apply_worker.sh: IPC switch failed but mpvpaper (pid $tracked_pid, monitor: $MONITOR) is still alive -- leaving it running untouched, NOT killing/relaunching (video: $VIDEO)"
        lw_write_apply_status "$status_file" "error" "$VIDEO" "Failed to change wallpaper via IPC (mpv is still running, not killed). Try again."
        exit 1
    fi
else
    # Nothing tracked, or the tracked pid has actually exited: this is a
    # genuine "no persistent mpv to reuse" case (first run, explicit Stop,
    # or a real crash) -- starting the one player is the correct and only
    # option. lw_start_persistent_mpv itself refuses to run if it finds a
    # live process after all (defensive; should never trigger here).
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

# Per-monitor state
lw_write_text_atomic "$(lw_monitor_state_file "$MONITOR" "current")" "$VIDEO"
lw_write_text_atomic "$(lw_monitor_state_file "$MONITOR" "last")" "$VIDEO"
lw_write_text_atomic "$(lw_monitor_state_file "$MONITOR" "resolution")" "$RESOLUTION"
lw_write_text_atomic "$(lw_monitor_state_file "$MONITOR" "fps")" "$FPS"

# Legacy global mirror for single-monitor setups
lw_write_text_atomic "$LW_CURRENT_FILE" "$VIDEO"
lw_write_text_atomic "$LW_LAST_FILE" "$VIDEO"
lw_write_text_atomic "$LW_RESOLUTION_FILE" "$RESOLUTION"
lw_write_text_atomic "$LW_FPS_FILE" "$FPS"

lw_add_history "$VIDEO"
lw_write_apply_status "$status_file" "success" "$VIDEO" "Applied wallpaper: $VIDEO"

lw_log_info "Applied wallpaper: $VIDEO (monitor: $MONITOR, resolution: $RESOLUTION, fps: $FPS)"
