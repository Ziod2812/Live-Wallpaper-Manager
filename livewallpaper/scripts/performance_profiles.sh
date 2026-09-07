#!/usr/bin/env bash
#
# performance_profiles.sh <action> [args...]
# -------------------------------------------
# CRUD for per-wallpaper / per-monitor performance profiles (FPS +
# Resolution override), backing Services/WallpaperProfileService.qml.
# Same conventions as collections.sh / favorite.sh: jq for the JSON
# edit, utils.sh's lock + atomic-write helpers so a crash or a racing
# write can never leave performance_profiles.json half-written.
#
# Storage shape ($LW_PERF_PROFILES_FILE, data/performance_profiles.json):
#   {
#     "wallpapers": { "/abs/path.mp4": { "fps": "30", "resolution": "1080p" }, ... },
#     "monitors":   { "eDP-1":          { "fps": "60", "resolution": "720p"  }, ... }
#   }
#
# A profile entry only stores the keys the user actually overrode --
# "fps"/"resolution" absent (or set to "") means "inherit the next level
# down" (wallpaper -> monitor -> the user's global selectedFps/
# selectedResolution). This mirrors how apply_wallpaper.sh's own
# resolution/fps params already default when omitted.
#
#   performance_profiles.sh list                                     Print the whole file
#   performance_profiles.sh get_wallpaper <path>                      Print one wallpaper's profile (or {})
#   performance_profiles.sh set_wallpaper <path> <fps> <resolution>   Set/patch (pass "" to leave a field unset)
#   performance_profiles.sh clear_wallpaper <path>                    Remove a wallpaper's profile entirely
#   performance_profiles.sh get_monitor <monitor>                     Print one monitor's profile (or {})
#   performance_profiles.sh set_monitor <monitor> <fps> <resolution>  Set/patch
#   performance_profiles.sh clear_monitor <monitor>                   Remove a monitor's profile entirely

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

LW_PERF_PROFILES_FILE="$LW_DATA_DIR/performance_profiles.json"

lw_ensure_dirs
lw_json_init_if_missing "$LW_PERF_PROFILES_FILE" '{"wallpapers":{},"monitors":{}}'
lw_json_validate_or_reset "$LW_PERF_PROFILES_FILE" '{"wallpapers":{},"monitors":{}}'

ACTION="${1:-list}"
ARG1="$2"
ARG2="$3"
ARG3="$4"

_write() {
    # _write <jq filter> [--arg name value]... -- runs under the lock,
    # commits atomically, identical shape to collections.sh's _write.
    local filter="$1"; shift
    lw_lock_or_skip "performance_profiles_db" 5 || exit 1
    local tmp
    tmp="$(lw_atomic_tmp_for "$LW_PERF_PROFILES_FILE")" || {
        echo "Error: could not create a temp file for performance_profiles.json" >&2
        exit 1
    }
    if ! jq "$@" "$filter" "$LW_PERF_PROFILES_FILE" > "$tmp"; then
        rm -f "$tmp"
        echo "Error: could not update performance_profiles.json" >&2
        exit 1
    fi
    if [ ! -s "$tmp" ] || ! jq empty "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"
        echo "Error: performance_profiles.json update produced invalid JSON" >&2
        exit 1
    fi
    lw_atomic_commit "$tmp" "$LW_PERF_PROFILES_FILE"
}

# _set_entry <section: wallpapers|monitors> <key> <fps> <resolution>
# Builds { fps?, resolution? } from whichever of fps/resolution is
# non-empty and merges it into section[key]. If BOTH are empty, this is
# equivalent to clearing the entry (nothing left to override).
_set_entry() {
    local section="$1" key="$2" fps="$3" resolution="$4"

    if [ -z "$fps" ] && [ -z "$resolution" ]; then
        _write '.[$s][$k] = {}' --arg s "$section" --arg k "$key"
        lw_log_info "performance_profiles.sh: cleared $section entry for '$key'"
        return
    fi

    local filter='.[$s][$k] = ((.[$s][$k] // {}) as $cur |
        (if $fps == "" then ($cur | del(.fps)) else ($cur + {fps: $fps}) end) as $a |
        (if $res == "" then ($a | del(.resolution)) else ($a + {resolution: $res}) end))'
    _write "$filter" --arg s "$section" --arg k "$key" --arg fps "$fps" --arg res "$resolution"
    lw_log_info "performance_profiles.sh: set $section entry for '$key' (fps='$fps' resolution='$resolution')"
}

case "$ACTION" in
    list)
        cat "$LW_PERF_PROFILES_FILE"
        ;;

    get_wallpaper)
        [ -z "$ARG1" ] && { echo "Usage: performance_profiles.sh get_wallpaper <path>" >&2; exit 1; }
        jq -c --arg p "$ARG1" '.wallpapers[$p] // {}' "$LW_PERF_PROFILES_FILE"
        ;;

    set_wallpaper)
        [ -z "$ARG1" ] && { echo "Usage: performance_profiles.sh set_wallpaper <path> <fps> <resolution>" >&2; exit 1; }
        _set_entry "wallpapers" "$ARG1" "$ARG2" "$ARG3"
        ;;

    clear_wallpaper)
        [ -z "$ARG1" ] && { echo "Usage: performance_profiles.sh clear_wallpaper <path>" >&2; exit 1; }
        _write 'del(.wallpapers[$p])' --arg p "$ARG1"
        lw_log_info "performance_profiles.sh: removed wallpaper profile for '$ARG1'"
        ;;

    get_monitor)
        [ -z "$ARG1" ] && { echo "Usage: performance_profiles.sh get_monitor <monitor>" >&2; exit 1; }
        jq -c --arg m "$ARG1" '.monitors[$m] // {}' "$LW_PERF_PROFILES_FILE"
        ;;

    set_monitor)
        [ -z "$ARG1" ] && { echo "Usage: performance_profiles.sh set_monitor <monitor> <fps> <resolution>" >&2; exit 1; }
        _set_entry "monitors" "$ARG1" "$ARG2" "$ARG3"
        ;;

    clear_monitor)
        [ -z "$ARG1" ] && { echo "Usage: performance_profiles.sh clear_monitor <monitor>" >&2; exit 1; }
        _write 'del(.monitors[$m])' --arg m "$ARG1"
        lw_log_info "performance_profiles.sh: removed monitor profile for '$ARG1'"
        ;;

    *)
        echo "Usage: performance_profiles.sh <list|get_wallpaper|set_wallpaper|clear_wallpaper|get_monitor|set_monitor|clear_monitor> [args...]" >&2
        exit 1
        ;;
esac

exit 0
