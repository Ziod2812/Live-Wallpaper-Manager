#!/usr/bin/env bash
#
# stop_wallpaper.sh [monitor]
# ------------------
# Stops mpvpaper and clears the current-wallpaper cache so the UI shows
# "Current: None".
#
# [monitor] omitted -> stops EVERY monitor and clears the legacy global "current" file.
# [monitor] given   -> stops ONLY that monitor, leaving every other running.
#
# Does NOT clear "last"/"resolution" (used by "Start Wallpaper" to replay
# the same video + resolution).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

MONITOR="${1:-}"

lw_ensure_dirs

if [ -z "$MONITOR" ]; then
    # Cancel every monitor's in-flight apply worker first, then kill
    # whatever is actually recorded as running on that monitor
    # by its tracked PID. lw_stop_persistent_mpv is source-type
    # agnostic -- it kills mpvpaper OR the kiosk browser process used for
    # a web wallpaper, whichever PID was actually recorded there, and it
    # removes that monitor's pid file itself once done.
    #
    # (Previously this loop only deleted each monitor's "pid"/"current"
    # files without killing the process they pointed to, which left a
    # web wallpaper's browser process running as an orphan after a
    # global stop -- fixed here.)
    for m in $(lw_list_active_monitors); do
        lw_cancel_inflight_apply_worker "$m"
        lw_stop_persistent_mpv "$m"
        rm -f "$(lw_monitor_state_file "$m" "current")"
    done
    # Legacy single-display slot (installs that predate multi-monitor
    # support store their state directly under $LW_CACHE_DIR rather than
    # a per-monitor subdirectory) -- same by-PID, source-type-agnostic kill.
    lw_cancel_inflight_apply_worker ""
    lw_stop_persistent_mpv ""
    # Belt-and-suspenders: catches any mpvpaper instance that somehow
    # isn't tracked in a pid file at all (this used to be the ONLY kill
    # mechanism, before per-monitor PID tracking existed -- kept as a
    # safety net, harmless no-op when everything above already worked).
    lw_kill_mpvpaper
    rm -f "$LW_CURRENT_FILE"
    lw_write_apply_status "$(lw_monitor_state_file "" "apply_status")" "success" "" "Stopped"
    lw_log_info "Stopped live wallpaper on all monitors."
    echo "Stopped live wallpaper."
else
    # Cancel a pending worker for this monitor, if any.
    lw_cancel_inflight_apply_worker "$MONITOR"
    lw_stop_persistent_mpv "$MONITOR"
    rm -f "$(lw_monitor_state_file "$MONITOR" "current")"
    status_file="$(lw_monitor_state_file "$MONITOR" "apply_status")"
    lw_write_apply_status "$status_file" "success" "" "Stopped"
    legacy_status_file="$LW_CACHE_DIR/apply_status"
    if [ "$status_file" != "$legacy_status_file" ]; then
        lw_write_apply_status "$legacy_status_file" "success" "" "Stopped"
    fi
    lw_log_info "Stopped live wallpaper on monitor: $MONITOR"
    echo "Stopped live wallpaper on $MONITOR."
fi
