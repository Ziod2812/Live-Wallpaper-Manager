#!/usr/bin/env bash
#
# collections.sh <action> [args...]
# -----------------------------------
# CRUD for wallpaper "collections" (named groups, e.g. Anime / Nature /
# Cyberpunk / Minimal), backing Pages/CollectionsPage.qml and the
# "Add to collection" action on WallpaperCard.qml. Same conventions as
# favorite.sh / settings.sh: jq for the JSON edit, utils.sh's lock +
# atomic-write helpers so a crash or a racing write can never leave
# collections.json half-written or corrupt.
#
# Storage shape ($LW_COLLECTIONS_FILE, data/collections.json):
#   {
#     "Anime": { "paths": ["/abs/path1.mp4", ...], "color": "#89b4fa", "created": 1737000000 },
#     ...
#   }
#
#   collections.sh list                          Print the whole collections.json
#   collections.sh create <name> [color]          Create an empty collection
#   collections.sh delete <name>                  Delete a collection
#   collections.sh rename <old> <new>              Rename a collection (keeps paths/color)
#   collections.sh set_color <name> <color>        Change a collection's color tag
#   collections.sh add <name> <path>               Add a wallpaper to a collection
#   collections.sh remove <name> <path>            Remove a wallpaper from a collection
#   collections.sh toggle <name> <path>            Add if absent, remove if present
#   collections.sh random <name>                   Print one random path from <name> (empty if none)
#   collections.sh for_path <path>                 Print JSON array of collection names containing <path>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

LW_COLLECTIONS_FILE="$LW_DATA_DIR/collections.json"

lw_ensure_dirs
lw_json_init_if_missing "$LW_COLLECTIONS_FILE" "{}"
lw_json_validate_or_reset "$LW_COLLECTIONS_FILE" "{}"

ACTION="${1:-list}"
ARG1="$2"
ARG2="$3"

_write() {
    # _write <jq filter> [--argjson name value]... — runs under the lock,
    # commits atomically, same shape as favorite.sh's inline pattern.
    local filter="$1"; shift
    lw_lock_or_skip "collections_db" 5 || exit 1
    local tmp
    tmp="$(lw_atomic_tmp_for "$LW_COLLECTIONS_FILE")" || {
        echo "Error: could not create a temp file for collections.json" >&2
        exit 1
    }
    if ! jq "$@" "$filter" "$LW_COLLECTIONS_FILE" > "$tmp"; then
        rm -f "$tmp"
        echo "Error: could not update collections.json" >&2
        exit 1
    fi
    if [ ! -s "$tmp" ] || ! jq empty "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"
        echo "Error: collections.json update produced invalid JSON" >&2
        exit 1
    fi
    lw_atomic_commit "$tmp" "$LW_COLLECTIONS_FILE"
}

case "$ACTION" in
    list)
        cat "$LW_COLLECTIONS_FILE"
        ;;

    create)
        [ -z "$ARG1" ] && { echo "Usage: collections.sh create <name> [color]" >&2; exit 1; }
        if jq -e --arg n "$ARG1" 'has($n)' "$LW_COLLECTIONS_FILE" >/dev/null 2>&1; then
            echo "Error: a collection named '$ARG1' already exists" >&2
            exit 1
        fi
        color="${ARG2:-#89b4fa}"
        _write '.[$n] = {"paths": [], "color": $c, "created": (now | floor)}' \
            --arg n "$ARG1" --arg c "$color"
        lw_log_info "collections.sh: created '$ARG1'"
        ;;

    delete)
        [ -z "$ARG1" ] && { echo "Usage: collections.sh delete <name>" >&2; exit 1; }
        _write 'del(.[$n])' --arg n "$ARG1"
        lw_log_info "collections.sh: deleted '$ARG1'"
        ;;

    rename)
        [ -z "$ARG1" ] && { echo "Usage: collections.sh rename <old> <new>" >&2; exit 1; }
        [ -z "$ARG2" ] && { echo "Usage: collections.sh rename <old> <new>" >&2; exit 1; }
        if ! jq -e --arg n "$ARG1" 'has($n)' "$LW_COLLECTIONS_FILE" >/dev/null 2>&1; then
            echo "Error: no collection named '$ARG1'" >&2
            exit 1
        fi
        if jq -e --arg n "$ARG2" 'has($n)' "$LW_COLLECTIONS_FILE" >/dev/null 2>&1; then
            echo "Error: a collection named '$ARG2' already exists" >&2
            exit 1
        fi
        _write '. as $root | ($root[$old]) as $val | ($root | del(.[$old])) + {($new): $val}' \
            --arg old "$ARG1" --arg new "$ARG2"
        lw_log_info "collections.sh: renamed '$ARG1' -> '$ARG2'"
        ;;

    set_color)
        [ -z "$ARG1" ] && { echo "Usage: collections.sh set_color <name> <color>" >&2; exit 1; }
        _write '.[$n].color = $c' --arg n "$ARG1" --arg c "$ARG2"
        ;;

    add)
        [ -z "$ARG1" ] && { echo "Usage: collections.sh add <name> <path>" >&2; exit 1; }
        [ -z "$ARG2" ] && { echo "Usage: collections.sh add <name> <path>" >&2; exit 1; }
        if ! jq -e --arg n "$ARG1" 'has($n)' "$LW_COLLECTIONS_FILE" >/dev/null 2>&1; then
            echo "Error: no collection named '$ARG1'" >&2
            exit 1
        fi
        _write '.[$n].paths = ((.[$n].paths // []) + [$p] | unique)' --arg n "$ARG1" --arg p "$ARG2"
        ;;

    remove)
        [ -z "$ARG1" ] && { echo "Usage: collections.sh remove <name> <path>" >&2; exit 1; }
        [ -z "$ARG2" ] && { echo "Usage: collections.sh remove <name> <path>" >&2; exit 1; }
        _write '.[$n].paths = ((.[$n].paths // []) - [$p])' --arg n "$ARG1" --arg p "$ARG2"
        ;;

    toggle)
        [ -z "$ARG1" ] && { echo "Usage: collections.sh toggle <name> <path>" >&2; exit 1; }
        [ -z "$ARG2" ] && { echo "Usage: collections.sh toggle <name> <path>" >&2; exit 1; }
        if ! jq -e --arg n "$ARG1" 'has($n)' "$LW_COLLECTIONS_FILE" >/dev/null 2>&1; then
            echo "Error: no collection named '$ARG1'" >&2
            exit 1
        fi
        _write '.[$n].paths = (if ((.[$n].paths // []) | index($p)) then ((.[$n].paths // []) - [$p]) else ((.[$n].paths // []) + [$p]) end)' \
            --arg n "$ARG1" --arg p "$ARG2"
        ;;

    random)
        [ -z "$ARG1" ] && { echo "Usage: collections.sh random <name>" >&2; exit 1; }
        count="$(jq -r --arg n "$ARG1" '(.[$n].paths // []) | length' "$LW_COLLECTIONS_FILE")"
        if [ -z "$count" ] || [ "$count" -eq 0 ] 2>/dev/null; then
            echo ""
            exit 0
        fi
        idx=$(( RANDOM % count ))
        jq -r --arg n "$ARG1" --argjson i "$idx" '.[$n].paths[$i]' "$LW_COLLECTIONS_FILE"
        ;;

    for_path)
        [ -z "$ARG1" ] && { echo "Usage: collections.sh for_path <path>" >&2; exit 1; }
        jq -c --arg p "$ARG1" '[to_entries[] | select(.value.paths // [] | index($p)) | .key]' "$LW_COLLECTIONS_FILE"
        ;;

    *)
        echo "Usage: collections.sh <list|create|delete|rename|set_color|add|remove|toggle|random|for_path> [args...]" >&2
        exit 1
        ;;
esac

# Explicit success exit -- several branches above end on lw_log_info,
# whose own exit status (from a `[ level = ERROR ] &&` internal check
# in utils.sh) is 1 when nothing gets logged as an error, which would
# otherwise leak out as this script's exit code on an otherwise-
# successful call.
exit 0
