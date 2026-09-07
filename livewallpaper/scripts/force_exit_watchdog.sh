#!/usr/bin/env bash
#
# force_exit_watchdog.sh
# -----------------------
# Guaranteed-exit safety net for "Exit Application".
#
# ApplicationService.exit() asks the Qt event loop to stop via Qt.quit()
# once teardown (mpvpaper/tray/awww-daemon/timers) is confirmed done. That
# is normally enough, but Qt.quit() only *schedules* the loop to stop --
# on some Debian/Wayland + Qt combinations a stuck native window, a
# lingering Wayland roundtrip, or a non-detached child process can keep
# the process alive indefinitely afterward, which is exactly the bug this
# script exists to guarantee against.
#
# Started via Quickshell.execDetached() from inside ApplicationService.exit()
# itself, at the very start of teardown -- so it is a normal OS child of
# THIS quickshell process at spawn time ($PPID below is captured once,
# correctly, before any re-parenting could happen) but, per Quickshell's
# own docs, immune to being killed when quickshell dies (unlike a plain
# Process {} item -- see restart_app.sh's header for the same distinction).
#
# Deliberately targets this one exact PID rather than `pkill quickshell` /
# `pkill -f livewallpaper`: a blanket kill-by-name would also take down any
# unrelated quickshell config running alongside this one (e.g. a
# Caelestia/other desktop shell embedding LiveWallpaperPanel.qml -- see
# CAELESTIA_INTEGRATION.md), which this app must never touch.
#
# Usage: force_exit_watchdog.sh [quickshell_pid]
# Falls back to $PPID (this script's own parent at spawn time) if no PID
# is passed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

PID="${1:-$PPID}"
if ! [[ "$PID" =~ ^[0-9]+$ ]]; then
    lw_log_warn "[EXIT-WATCHDOG] no valid pid given/derived ('$PID'); aborting"
    exit 1
fi

# Sanity check: only ever act on an actual `quickshell -c livewallpaper`
# process, never on whatever unrelated PID happens to occupy that number
# by the time we get around to checking it (PIDs get reused).
_is_our_quickshell() {
    local args
    args="$(ps -o args= -p "$1" 2>/dev/null)" || return 1
    [[ "$args" == *quickshell*-c*livewallpaper* || "$args" == *"quickshell -c livewallpaper"* ]]
}

waited_ms=0
timeout_ms=30000
poll_ms=200

while kill -0 "$PID" 2>/dev/null; do
    sleep 0.2
    waited_ms=$((waited_ms + poll_ms))
    if [ "$waited_ms" -ge "$timeout_ms" ]; then
        if ! _is_our_quickshell "$PID"; then
            lw_log_warn "[EXIT-WATCHDOG] pid=$PID no longer looks like our quickshell process; not touching it"
            exit 0
        fi
        lw_log_warn "[EXIT-WATCHDOG] pid=$PID still alive ${timeout_ms}ms after Exit Application; forcing SIGTERM"
        kill -TERM "$PID" 2>/dev/null || true
        sleep 1
        if kill -0 "$PID" 2>/dev/null && _is_our_quickshell "$PID"; then
            lw_log_warn "[EXIT-WATCHDOG] pid=$PID survived SIGTERM; forcing SIGKILL"
            kill -KILL "$PID" 2>/dev/null || true
            sleep 0.3
        fi

        # LAST RESORT: if this exact pid is somehow still around (or a
        # second `quickshell -c livewallpaper` instance exists alongside
        # it -- e.g. a stray leftover from a previous crashed/duplicate
        # launch), sweep by command line as a final guarantee. Still
        # anchored to this app's own config name/word boundaries (same
        # pattern _tray_icon.py's _find_livewallpaper_pid() uses), so it
        # can only ever match "quickshell -c livewallpaper" processes --
        # never an unrelated quickshell config (e.g. Caelestia/other shell
        # embedding LiveWallpaperPanel.qml under a different -c name).
        if pgrep -f '(^|[ /])quickshell[ ]+-c[ ]+livewallpaper([ ]|$)' >/dev/null 2>&1; then
            lw_log_warn "[EXIT-WATCHDOG] a quickshell -c livewallpaper process is still present after targeted kill; sweeping by command line as a last resort"
            pkill -f '(^|[ /])quickshell[ ]+-c[ ]+livewallpaper([ ]|$)' 2>/dev/null || true
            sleep 0.5
            pkill -9 -f '(^|[ /])quickshell[ ]+-c[ ]+livewallpaper([ ]|$)' 2>/dev/null || true
        fi
        exit 0
    fi
done

lw_log_info "[EXIT-WATCHDOG] pid=$PID exited cleanly after ${waited_ms}ms; no force-kill needed"
