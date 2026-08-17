#!/usr/bin/env bash
#
# start_cava.sh <fifo> <config> [bars] [framerate] [sensitivity]
# -------------------------------------------------------------------------
# Launches `cava` (real PipeWire audio capture via its pulse input --
# PipeWire's pipewire-pulse server speaks the PulseAudio protocol) writing
# raw binary bar levels into <fifo>, for CavaService.qml/_cava_reader.py
# to stream into Music Dock's visualizer.
#
# Non-blocking / async, matching every other *_worker-style dispatch in
# this project: writes the resolved cava.conf, (re)creates the FIFO,
# detaches cava into the background, records its pid, and returns
# immediately. cava itself will block on opening the FIFO for writing
# until a reader (Paths.script("_cava_reader.py")) opens the other end --
# CavaService.qml starts that reader right after this script exits 0.
#
# Prints exactly one line: "STARTED" on success, "MISSING_DEPENDENCY" if
# cava isn't installed (never crashes the caller -- Music Dock simply
# hides the visualizer and shows a one-time notice in that case).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

FIFO="$1"
CONF="$2"
BARS="${3:-48}"
FRAMERATE="${4:-60}"
SENSITIVITY="${5:-100}"

if [ -z "$FIFO" ] || [ -z "$CONF" ]; then
    echo "Usage: start_cava.sh <fifo> <config> [bars] [framerate] [sensitivity]" >&2
    exit 1
fi

if ! command -v cava >/dev/null 2>&1; then
    echo "MISSING_DEPENDENCY"
    exit 0
fi

PID_FILE="$LW_CACHE_DIR/musicdock/cava.pid"
mkdir -p "$(dirname "$PID_FILE")" "$(dirname "$FIFO")" "$(dirname "$CONF")"

# Stop any stale instance from a previous session/crash before recreating
# the FIFO out from under it.
if [ -s "$PID_FILE" ]; then
    old_pid="$(cat "$PID_FILE" 2>/dev/null)"
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
        kill "$old_pid" 2>/dev/null
        sleep 0.2
    fi
    rm -f "$PID_FILE"
fi
pkill -x cava 2>/dev/null || true

rm -f "$FIFO"
mkfifo "$FIFO" || { echo "MISSING_DEPENDENCY"; exit 0; }

sed \
    -e "s/__BARS__/$BARS/" \
    -e "s/__FRAMERATE__/$FRAMERATE/" \
    -e "s/__SENSITIVITY__/$SENSITIVITY/" \
    -e "s#__FIFO__#$FIFO#" \
    "$SCRIPT_DIR/cava.conf" > "$CONF"

setsid cava -p "$CONF" >> "$LW_CACHE_DIR/musicdock/cava.log" 2>&1 < /dev/null &
disown
echo $! > "$PID_FILE"

lw_log_info "start_cava.sh: cava started (bars: $BARS, fps: $FRAMERATE, sensitivity: $SENSITIVITY, fifo: $FIFO, pid: $(cat "$PID_FILE"))"
echo "STARTED"
