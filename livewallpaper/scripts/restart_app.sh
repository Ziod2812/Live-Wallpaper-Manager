#!/usr/bin/env bash
#
# restart_app.sh
# -----------------
# Reliable System Tray restart watchdog.
#
# Usage:
#   restart_app.sh [old_quickshell_pid]
#
# The tray helper starts this script OUTSIDE the Quickshell process lifecycle.
# It waits for the exact old Quickshell PID to exit, then starts exactly one
# fresh `quickshell -c livewallpaper` instance.
#
# Never start the replacement while the old PID is still alive.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

find_livewallpaper_pid() {
    ps -eo pid=,args= 2>/dev/null |
        awk '$2 == "quickshell" && $3 == "-c" && $4 == "livewallpaper" { print $1; exit }'
}

OLD_PID="${1:-}"
if ! [[ "$OLD_PID" =~ ^[0-9]+$ ]]; then
    OLD_PID="$(find_livewallpaper_pid || true)"
fi

if [ -z "$OLD_PID" ]; then
    lw_log_warn "[RESTART] no running quickshell -c livewallpaper instance found; starting one fresh"
else
    lw_log_info "[RESTART] waiting for old_pid=$OLD_PID to exit"

    waited_ms=0
    timeout_ms=20000
    poll_ms=100

    while kill -0 "$OLD_PID" 2>/dev/null; do
        sleep 0.1
        waited_ms=$((waited_ms + poll_ms))
        if [ "$waited_ms" -ge "$timeout_ms" ]; then
            lw_log_error "[RESTART] old_pid=$OLD_PID still alive after ${timeout_ms}ms; aborting restart"
            exit 1
        fi
    done

    lw_log_info "[RESTART] old_pid=$OLD_PID confirmed exited after ${waited_ms}ms"
fi

lw_log_info "[RESTART] launching one fresh livewallpaper instance"
setsid quickshell -c livewallpaper -n < /dev/null > /dev/null 2>&1 &

# Give Quickshell a moment to register its config/IPC target.
sleep 1

NEW_PID="$(find_livewallpaper_pid || true)"
if [ -n "$NEW_PID" ] && kill -0 "$NEW_PID" 2>/dev/null; then
    lw_log_info "[RESTART] success new_pid=$NEW_PID old_pid=${OLD_PID:-unknown}"
    exit 0
fi

# One short retry catches slow Quickshell startup without ever creating a
# second instance because -n prevents duplicate configs.
sleep 1
NEW_PID="$(find_livewallpaper_pid || true)"
if [ -n "$NEW_PID" ] && kill -0 "$NEW_PID" 2>/dev/null; then
    lw_log_info "[RESTART] success after retry new_pid=$NEW_PID old_pid=${OLD_PID:-unknown}"
    exit 0
fi

lw_log_error "[RESTART] failed: no live quickshell -c livewallpaper process after launch"
exit 1
