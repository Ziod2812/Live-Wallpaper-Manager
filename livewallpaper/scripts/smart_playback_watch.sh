#!/usr/bin/env bash
#
# smart_playback_watch.sh
# -------------------------------------------------------
# Long-running launcher for Smart Playback's fullscreen detector. Started
# once by Services/SmartPlaybackService.qml and left running for as long
# as Smart Playback AND "Pause when fullscreen application is active"
# are both enabled -- same "start once, Quickshell restarts it if it
# ever exits" pattern Services/WatcherService.qml already uses for
# watch_wallpaper_dir.sh.
#
# Delegates to _hypr_fullscreen_watch.py, which does the real work: it
# blocks on Hyprland's own IPC event socket instead of polling, so CPU
# usage sits at ~0 whenever nothing on screen is changing, and reacts
# the instant Hyprland reports a window/fullscreen/workspace change --
# not on some fixed timer. See that file's header for the full design.
#
# Prints one line of JSON per monitor-fullscreen-state change, e.g.:
#   {"DP-1": true, "eDP-1": false}
# and a single "MISSING_DEPENDENCY" line + exits immediately if
# hyprctl/Hyprland or python3 aren't available -- fullscreen detection
# is Hyprland-specific, but every other Smart Playback option (battery,
# screen lock, monitor sleep, gaming) keeps working without it, exactly
# like auto-refresh degrading gracefully without inotify-tools.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

if ! command -v hyprctl >/dev/null 2>&1 || [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    echo "MISSING_DEPENDENCY"
    lw_log_info "smart_playback_watch.sh: not running under Hyprland -- Smart Playback's fullscreen detection is disabled (other Smart Playback options still work)"
    # RELIABILITY FIX: this exits almost instantly, and Quickshell (see
    # SmartPlaybackService.qml's watcherRestartTimer) restarts anything
    # that exits while the option is still enabled -- 2s later, forever.
    # On a permanently non-Hyprland system with "Pause when fullscreen"
    # left on, that used to mean a fresh bash+python3 spawn plus a log
    # line every 2 seconds for as long as the shell runs (unbounded log
    # growth over a long session). Sleeping here first cuts that to
    # roughly once every 30s -- still self-healing (e.g. Hyprland
    # starting later in the same login session) without the tight loop.
    # `sleep` exits immediately on the SIGTERM Quickshell sends when the
    # option/Smart Playback is turned off, so toggling it off is still
    # instant, not stuck waiting out the 30s.
    sleep 30
    exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "MISSING_DEPENDENCY"
    lw_log_info "smart_playback_watch.sh: python3 not found -- Smart Playback's fullscreen detection is disabled (other Smart Playback options still work)"
    sleep 30 # same tight-respawn-loop fix as the Hyprland check above
    exit 0
fi

# Reap any fullscreen watcher left running from a previous session that
# never got a chance to exit cleanly (Quickshell force-killed/crashed) --
# same "clean up any orphaned instance from a previous session before
# starting a new one" pattern TrayService.qml's trayProc already uses for
# _tray_icon.py. SmartPlaybackService.qml never starts a second watcher
# while one is already running, so it's safe to sweep unconditionally.
for _pid in $(pgrep -f "_hypr_fullscreen_watch.py" 2>/dev/null); do
    [ "$_pid" != "$$" ] && kill "$_pid" 2>/dev/null
done

# exec (not a plain call) so this script's own pid BECOMES the python
# process -- Quickshell's watcherProc.running = false then signals the
# real watcher directly, with no wrapper layer left behind to orphan it.
exec python3 "$SCRIPT_DIR/_hypr_fullscreen_watch.py"
