#!/usr/bin/env bash
#
# stop_cava.sh [fifo]
# -------------------------------------------------------------------------
# Stops the cava instance started by start_cava.sh and removes its FIFO.
# Safe to call even if cava was never started (e.g. dependency missing) --
# never fails loudly, matching stop_wallpaper.sh's tolerant style.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

FIFO="${1:-}"
PID_FILE="$LW_CACHE_DIR/musicdock/cava.pid"

if [ -s "$PID_FILE" ]; then
    pid="$(cat "$PID_FILE" 2>/dev/null)"
    if [ -n "$pid" ]; then
        kill "$pid" 2>/dev/null || true
        for _i in $(seq 1 10); do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.1
        done
        kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
fi

# Safety net in case the pid file was stale/missing.
pkill -x cava 2>/dev/null || true

[ -n "$FIFO" ] && rm -f "$FIFO"

lw_log_info "stop_cava.sh: cava stopped"
echo "STOPPED"
