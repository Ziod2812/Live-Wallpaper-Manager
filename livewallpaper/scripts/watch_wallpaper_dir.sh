#!/usr/bin/env bash
#
# watch_wallpaper_dir.sh
# -------------------------------------------------------
# Watches the wallpaper directory for changes (new/removed/renamed video
# files) and automatically re-runs refresh.sh, instead of requiring the
# user to press the Refresh button by hand every time they drop a new
# video in.
#
# Long-running: meant to be launched once by Quickshell's WatcherService
# and left running for the lifetime of the shell session (Quickshell
# restarts it automatically if it ever exits, and relaunches it pointed at
# the new directory whenever the user changes the wallpaper folder in
# Settings).
#
# Debounced: copying/downloading many files at once fires many inotify
# events in a burst; this waits for a short quiet period (no new events
# for $DEBOUNCE_SECONDS) before actually refreshing, so a batch of 50 new
# videos triggers ONE refresh instead of 50.
#
# Prints one line to stdout each time it actually triggers a refresh
# (Quickshell logs/reacts to this), and a single "MISSING_DEPENDENCY" line
# + exits immediately if inotify-tools isn't installed, instead of busy
# looping or spamming errors.
#
# ── Zombie/orphan fix ────────────────────────────────────────────────────
# This used to be `inotifywait | while read ...; do ...; done`: a plain
# shell PIPELINE runs inotifywait as a SIBLING process of the while-loop,
# not a child of it. WatcherService.qml stops/restarts this script by
# setting watcherProc.running = false (on Settings > Auto-Refresh off, on
# every wallpaper-directory change, and on app exit) -- Quickshell only
# ever signals THIS script's own pid. With the old pipeline, that signal
# never reached inotifywait: the while-loop side died, inotifywait kept
# running completely undetected, orphaned, still watching a directory
# nothing was reading events from anymore -- one leaked inotifywait per
# restart/directory-change/session. Fixed below by running inotifywait as
# an actual tracked child (`coproc`) and killing it explicitly on any exit
# path.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

DEBOUNCE_SECONDS="${LW_WATCHER_DEBOUNCE:-2}"

if ! command -v inotifywait >/dev/null 2>&1; then
    echo "MISSING_DEPENDENCY"
    lw_log_watcher "watch_wallpaper_dir.sh: [WARN] inotifywait not found (install inotify-tools) -- auto-refresh disabled, use the Refresh button instead"
    exit 0
fi

lw_ensure_dirs

# Reap any inotifywait left running from a previous session that never
# got a chance to clean up after itself (Quickshell force-killed/crashed
# before this script's own trap below could run) -- same "clean up any
# orphaned instance from a previous session before starting a new one"
# pattern TrayService.qml's trayProc already uses for _tray_icon.py.
# WatcherService.qml never runs two of these at once (it checks
# watcherProc.running before starting another), so it's safe to sweep for
# ANY leftover inotifywait matching this exact invocation.
pkill -f "inotifywait -m -r -e create -e delete -e moved_to -e moved_from -e close_write" 2>/dev/null

lw_log_watcher "watch_wallpaper_dir.sh: watching '$LW_WALLPAPER_DIR' for changes (debounce ${DEBOUNCE_SECONDS}s)"

# -m (monitor mode, keep running) -r (recursive, in case of subfolders)
# -e ... (only the event types that actually mean "the video list changed")
# --format '%f' (just the filename, we don't need more)
#
# Launched as a coproc (not the left side of a pipe) specifically so we
# get its real pid in $INOTIFY_PID -- required for the cleanup trap below
# to actually be able to stop it.
coproc INOTIFY {
    inotifywait -m -r \
        -e create -e delete -e moved_to -e moved_from -e close_write \
        --format '%f' \
        "$LW_WALLPAPER_DIR" 2>/dev/null
}

# Runs on every exit path (normal loop exit via `break`, this script
# being killed by WatcherService, or an unexpected error under `set -u`)
# -- guarantees inotifywait never outlives this script.
#
# Two kills, deliberately: `coproc` never execs the command directly into
# its own pid -- $INOTIFY_PID is always a small bash SUBSHELL wrapping
# inotifywait as its own child (verified empirically: comm for
# $INOTIFY_PID is "bash", inotifywait shows up one level further down).
# Killing only $INOTIFY_PID would therefore kill that wrapper subshell
# and leave the real inotifywait process behind, re-orphaned one level
# up -- exactly the bug this rewrite exists to fix, just moved down one
# level. The pkill (same exact pattern the startup reap above uses)
# reaches the real inotifywait process regardless of that wrapping;
# killing $INOTIFY_PID too cleans up the subshell and its end of the pipe.
cleanup() {
    pkill -f "inotifywait -m -r -e create -e delete -e moved_to -e moved_from -e close_write" 2>/dev/null
    if [ -n "${INOTIFY_PID:-}" ]; then
        kill "$INOTIFY_PID" 2>/dev/null
        wait "$INOTIFY_PID" 2>/dev/null
    fi
}
trap cleanup EXIT
# INT/TERM (what WatcherService.qml's watcherProc.running = false actually
# sends) additionally force an immediate exit: without this, a signal
# arriving while blocked in the `read -u "${INOTIFY[0]}"` below runs the
# trap and then falls back into the *same* read/loop, now referencing a
# coproc that cleanup() just tore down -- harmless in effect (the loop
# exits on the next failed read anyway) but noisy ("unbound variable"/
# "bad file descriptor" on stderr). Exiting straight from the trap avoids
# that resumed, doomed read entirely.
trap 'cleanup; exit 0' INT TERM

while true; do
    # Block for the first event of a batch...
    read -r -u "${INOTIFY[0]}" _first || break

    # ...then keep draining any further events that arrive within the
    # debounce window (a burst from copying many files at once), so the
    # whole batch collapses into a single refresh instead of one per file.
    while read -r -t "$DEBOUNCE_SECONDS" -u "${INOTIFY[0]}" _next; do :; done

    "$SCRIPT_DIR/refresh.sh" >/dev/null 2>&1
    echo "REFRESHED"
    lw_log_watcher "watch_wallpaper_dir.sh: auto-refreshed after detecting changes in '$LW_WALLPAPER_DIR'"
done
