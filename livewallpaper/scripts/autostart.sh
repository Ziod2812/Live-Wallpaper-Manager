#!/usr/bin/env bash
#
# autostart.sh
# -------------------------------------------------------
# Optional CLI fallback for replaying the last wallpaper on login.
#
# In the Eww version this had to run from Hyprland's exec-once, because
# eww's daemon didn't know to do it on its own. Under Quickshell the shell
# process itself is the long-running daemon (started by Hyprland's own
# exec-once for Quickshell/Caelestia), so PlaybackService now does this
# check natively in QML on startup (see Services/PlaybackService.qml,
# Component.onCompleted). This script is kept only for people who want to
# trigger the same behavior manually or from a non-Quickshell context
# (systemd unit, a different compositor, testing, ...).
#
# Can be disabled independently via:
#   scripts/settings.sh set autostart false
# -------------------------------------------------------
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

lw_ensure_dirs

AUTOSTART="$("$SCRIPT_DIR/settings.sh" get autostart 2>/dev/null || echo true)"
if [ "$AUTOSTART" = "false" ]; then
    lw_log_info "autostart.sh: autostart=false in settings -> skipping wallpaper replay"
    exit 0
fi

if pgrep -x mpvpaper >/dev/null 2>&1; then
    lw_log_info "autostart.sh: mpvpaper already running, nothing to do"
    exit 0
fi

if [ ! -s "$LW_LAST_FILE" ]; then
    lw_log_info "autostart.sh: no wallpaper has ever been selected, skipping"
    exit 0
fi

# Give Hyprland a moment to settle its monitor list before mpvpaper attaches
# -- running this too early at boot risks a "monitor not found" error if the
# output isn't initialized yet.
sleep 2

"$SCRIPT_DIR/start_wallpaper.sh" >/dev/null 2>&1 &
disown

lw_log_info "autostart.sh: triggered replay of last-used wallpaper"
