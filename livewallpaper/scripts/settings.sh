#!/usr/bin/env bash
#
# settings.sh <get|set|reset> [key] [value]
# ---------------------------------------------
# Reads/writes settings.json — backs the Settings/Directory panel in QML.
#
#   settings.sh get              Print all settings as JSON
#   settings.sh get <key>        Print a single key's value
#   settings.sh set <key> <val>  Write a single key
#   settings.sh reset            Reset settings to defaults
#
# Default keys: theme, opacity, blur, radius, resolution, fps, language,
# monitor, performance, autostart, wallpaper_directory

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

DEFAULT_SETTINGS='{
    "theme": "catppuccin-mocha",
    "opacity": 0.72,
    "blur": true,
    "radius": 20,
    "resolution": "1080p",
    "fps": "original",
    "hwdec": "auto-safe",
    "gpu_profile": "fast",
    "gpu_mode": "auto",
    "language": "en",
    "monitor": "auto",
    "performance": "balanced",
    "autostart": true,
    "auto_refresh": true,
    "wallpaper_directory": "~/Pictures/Live Wallpaper",
    "playlist_enabled": false,
    "playlist_interval_minutes": 30,
    "playlist_mode": "sequential",
    "battery_resolution": "720p",
    "battery_fps": "30"
}'

lw_ensure_dirs
lw_json_validate_or_reset "$LW_SETTINGS_FILE" "$DEFAULT_SETTINGS"
lw_json_init_if_missing "$LW_SETTINGS_FILE" "$DEFAULT_SETTINGS"

ACTION="${1:-get}"
KEY="$2"
VALUE="$3"

case "$ACTION" in
    get)
        if [ -z "$KEY" ]; then
            cat "$LW_SETTINGS_FILE"
        else
            jq -r --arg k "$KEY" '.[$k]' "$LW_SETTINGS_FILE"
        fi
        ;;
    set)
        if [ -z "$KEY" ]; then
            echo "Usage: settings.sh set <key> <value>" >&2
            exit 1
        fi
        lw_lock_or_skip "settings_db" 5 || exit 1
        tmp="$(lw_atomic_tmp_for "$LW_SETTINGS_FILE")" || exit 1
        case "$VALUE" in
            true|false)
                jq --arg k "$KEY" --argjson v "$VALUE" '.[$k] = $v' "$LW_SETTINGS_FILE" > "$tmp"
                ;;
            ''|*[!0-9.]*)
                jq --arg k "$KEY" --arg v "$VALUE" '.[$k] = $v' "$LW_SETTINGS_FILE" > "$tmp"
                ;;
            *)
                jq --arg k "$KEY" --argjson v "$VALUE" '.[$k] = $v' "$LW_SETTINGS_FILE" > "$tmp"
                ;;
        esac
        if [ -s "$tmp" ] && jq empty "$tmp" >/dev/null 2>&1; then
            lw_atomic_commit "$tmp" "$LW_SETTINGS_FILE"
        else
            rm -f "$tmp"
            echo "Error: failed to update settings.json" >&2
            exit 1
        fi
        lw_log_info "settings.sh: set $KEY=$VALUE"
        ;;
    reset)
        lw_lock_or_skip "settings_db" 5 || exit 1
        tmp="$(lw_atomic_tmp_for "$LW_SETTINGS_FILE")" || exit 1
        printf '%s\n' "$DEFAULT_SETTINGS" > "$tmp" && lw_atomic_commit "$tmp" "$LW_SETTINGS_FILE"
        lw_log_info "settings.sh: reset to defaults"
        echo "Settings reset to defaults."
        ;;
    *)
        echo "Usage: settings.sh <get|set|reset> [key] [value]" >&2
        exit 1
        ;;
esac
