#!/usr/bin/env bash
#
# manage_autostart.sh
# ----------------------
# PHASE 4 -- "Autostart" (launch the Quickshell shell itself on login).
#
# Manages a standard XDG autostart entry at
# ~/.config/autostart/live-wallpaper-manager.desktop, which every major
# desktop environment/session manager that follows the freedesktop
# autostart spec picks up automatically. (Hyprland itself does not read
# ~/.config/autostart by default -- install.sh separately OFFERS, but
# never silently makes, a Hyprland-native `hl.on("hyprland.start", ...)`
# wrapper (or legacy `exec-once` line) for hyprland.conf/hyprland.lua; see
# that file's "Autostart" step.)
#
# Usage:
#   manage_autostart.sh status            -> prints "enabled" or "disabled"
#   manage_autostart.sh enable
#   manage_autostart.sh disable
#
# Idempotent, no side effects beyond the one file below.
#
# -n/--no-duplicate on the generated Exec line below: if the user ALSO
# has a Hyprland-native `hl.on("hyprland.start", function() hl.exec_cmd(...)
# end)` wrapper (or legacy `exec-once = quickshell -c livewallpaper`) in
# their compositor config (see README's "Autostart" section) and enables
# this XDG autostart entry too, both can fire at login. Without -n,
# quickshell has no default single-instance guard of its own and would
# happily start a second, independent process -- two ManagerWindows, two
# tray icons, and `ipc call` becoming ambiguous between them. -n makes the
# loser of that race exit immediately instead, which is a correct no-op
# since the other instance is already up.

set -uo pipefail

AUTOSTART_DIR="$HOME/.config/autostart"
AUTOSTART_FILE="$AUTOSTART_DIR/live-wallpaper-manager.desktop"

cmd="${1:-status}"

case "$cmd" in
    status)
        if [ -f "$AUTOSTART_FILE" ]; then
            echo "enabled"
        else
            echo "disabled"
        fi
        ;;
    enable)
        mkdir -p "$AUTOSTART_DIR"
        cat > "$AUTOSTART_FILE" << 'DESKTOP'
[Desktop Entry]
Type=Application
Name=Live Wallpaper Manager
Comment=Start the Live Wallpaper Manager background shell on login
Exec=quickshell -c livewallpaper -n
Icon=video-x-generic
Terminal=false
X-GNOME-Autostart-enabled=true
NoDisplay=true
DESKTOP
        echo "enabled"
        ;;
    disable)
        rm -f "$AUTOSTART_FILE"
        echo "disabled"
        ;;
    *)
        echo "Usage: manage_autostart.sh {status|enable|disable}" >&2
        exit 1
        ;;
esac
