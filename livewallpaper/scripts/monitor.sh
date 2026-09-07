#!/usr/bin/env bash
#
# monitor.sh <list|current>
# ----------------------------
# Monitor information, kept separate from utils.sh to make multi-monitor
# support easier to extend later without touching the mpvpaper launch logic.
#
#   monitor.sh list      Prints JSON of all monitors (hyprctl monitors -j)
#   monitor.sh current   Prints the name of the focused monitor

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

ACTION="${1:-current}"

case "$ACTION" in
    list)
        if command -v hyprctl >/dev/null 2>&1; then
            hyprctl monitors -j 2>/dev/null | jq -c '[.[] | {name: .name, width: .width, height: .height, focused: .focused}]'
        else
            echo "[]"
        fi
        ;;
    current)
        lw_detect_monitor
        ;;
    *)
        echo "Usage: monitor.sh <list|current>" >&2
        exit 1
        ;;
esac
