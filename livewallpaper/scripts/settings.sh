#!/usr/bin/env bash
#
# settings.sh <get|set|mset|reset> [key] [value]
# ---------------------------------------------
# Reads/writes settings.json — backs the Settings/Directory panel in QML.
#
#   settings.sh get               Print all settings as JSON
#   settings.sh get <key>         Print a single key's value
#   settings.sh set <key> <val>   Write a single key
#   settings.sh mset <json-obj>   Write several keys in one atomic replace
#   settings.sh reset             Reset settings to defaults
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
    "gif_wallpaper_directory": "~/Pictures/GIF Wallpaper",
    "playlist_enabled": false,
    "playlist_interval_minutes": 30,
    "playlist_mode": "sequential",
    "playlist_custom_paths": "[]",
    "gif_playlist_enabled": false,
    "gif_playlist_interval_minutes": 30,
    "gif_playlist_mode": "sequential",
    "battery_resolution": "720p",
    "battery_fps": "30",
    "adaptive_fps_enabled": false,
    "adaptive_fps_min": 24,
    "adaptive_fps_max": 60,
    "adaptive_gpu_low": 30,
    "adaptive_gpu_high": 75,
    "thermal_protection_enabled": true,
    "thermal_warning_c": 75,
    "thermal_critical_c": 85,
    "thermal_warning_fps": 30,
    "battery_profiles_enabled": true,
    "low_battery_threshold": 20,
    "low_battery_fps": 20,
    "music_dock_draggable": true,
    "music_dock_free_position": false,
    "music_dock_pos_x": -1,
    "music_dock_pos_y": -1,
    "location_lat": "",
    "location_lng": "",
    "schedule_enabled": false,
    "schedule_rules": "[]",
    "weather_enabled": false,
    "weather_rules": "{}",
     "weather_poll_minutes": 20,
     "smart_selection_enabled": false,
     "smart_accent_enabled": false,
     "active_accent_color": "#353446",
     "ui_bg_opacity": 0.15,
     "transition_enabled": true,
     "transition_type": "fade",
     "transition_duration": 1.0,
    "tray_enabled": true,
    "notifications_enabled": true
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
    mset)
        # Same job as `set` above, but for several keys that must land on
        # disk TOGETHER as one atomic replace -- $KEY here is a single
        # JSON object argument (e.g. QML passes
        # JSON.stringify({a: 1, b: true})), not a plain key name. Needed
        # because plain `set` writes one key per invocation: calling it N
        # times in a row produces N separate file replacements, and
        # SettingsService's watchChanges reload can fire in the gap
        # between them, briefly reading a PARTIALLY applied state back
        # into QML (e.g. Music Dock's drag-save writing
        # free_position/pos_x/pos_y as three plain `set` calls could
        # reload with free_position already true but pos_x/pos_y still
        # the pre-drag values, which re-seeds the drag margins from stale
        # coordinates and visibly snaps the dock back). `mset` merges the
        # whole patch with one jq call and one lw_atomic_commit, so there
        # is only ever one file-change event and it always reflects every
        # key at once.
        if [ -z "$KEY" ]; then
            echo "Usage: settings.sh mset <json-object>" >&2
            exit 1
        fi
        if ! jq -e 'type == "object"' >/dev/null 2>&1 <<< "$KEY"; then
            echo "Error: mset argument must be a JSON object" >&2
            exit 1
        fi
        lw_lock_or_skip "settings_db" 5 || exit 1
        tmp="$(lw_atomic_tmp_for "$LW_SETTINGS_FILE")" || exit 1
        jq --argjson patch "$KEY" '. * $patch' "$LW_SETTINGS_FILE" > "$tmp"
        if [ -s "$tmp" ] && jq empty "$tmp" >/dev/null 2>&1; then
            lw_atomic_commit "$tmp" "$LW_SETTINGS_FILE"
        else
            rm -f "$tmp"
            echo "Error: failed to update settings.json" >&2
            exit 1
        fi
        lw_log_info "settings.sh: mset $(jq -c 'keys' <<< "$KEY")"
        ;;
    reset)
        lw_lock_or_skip "settings_db" 5 || exit 1
        tmp="$(lw_atomic_tmp_for "$LW_SETTINGS_FILE")" || exit 1
        printf '%s\n' "$DEFAULT_SETTINGS" > "$tmp" && lw_atomic_commit "$tmp" "$LW_SETTINGS_FILE"
        lw_log_info "settings.sh: reset to defaults"
        echo "Settings reset to defaults."
        ;;
    *)
        echo "Usage: settings.sh <get|set|mset|reset> [key] [value]" >&2
        exit 1
        ;;
esac
