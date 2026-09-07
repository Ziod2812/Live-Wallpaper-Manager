#!/usr/bin/env bash
#
# tag.sh <video_path> add|remove <tag>
# --------------------------------------
# Adds or removes a single tag on a video's record in wallpapers.json.
# Same shape as favorite.sh: writing to wallpapers.json is enough for
# Quickshell to pick up the change (FileView watchChanges) — no extra
# push needed.
#
# - "add": tag is trimmed and appended if not already present (case-
#   sensitive exact match, same as WallpaperService.allTags/selectedTag
#   compare tags today). No-op if it's already there.
# - "remove": drops the tag if present. No-op if it isn't there.
#
# Empty/whitespace-only tags are rejected instead of silently stored,
# since an empty string would otherwise show up as a blank chip in the
# UI and break the TagFilterBar "hide row if no tags" check.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

VIDEO="$1"
MODE="$2"
TAG="$3"

if [ -z "$VIDEO" ] || [ -z "$MODE" ] || [ -z "$TAG" ]; then
    echo "Usage: tag.sh <video_path> add|remove <tag>" >&2
    exit 1
fi

if [ "$MODE" != "add" ] && [ "$MODE" != "remove" ]; then
    echo "Usage: tag.sh <video_path> add|remove <tag>" >&2
    exit 1
fi

# Trim leading/trailing whitespace.
TAG="$(printf '%s' "$TAG" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
if [ -z "$TAG" ]; then
    echo "Error: tag must not be empty" >&2
    exit 1
fi

lw_ensure_dirs
lw_json_init_if_missing "$LW_DB_FILE" "[]"
lw_lock_or_skip "wallpaper_db" 5 || exit 1

tmp="$(lw_atomic_tmp_for "$LW_DB_FILE")" || {
    echo "Error: could not create a temp file for the wallpaper database" >&2
    exit 1
}
if ! jq --arg path "$VIDEO" --arg mode "$MODE" --arg tag "$TAG" '
    map(
        if .path == $path then
            .tags = (
                ((.tags // []) as $t |
                    if $mode == "add" then
                        (if ($t | index($tag)) then $t else $t + [$tag] end)
                    else
                        ($t - [$tag])
                    end
                )
            )
        else . end
    )
' "$LW_DB_FILE" > "$tmp"; then
    rm -f "$tmp"
    echo "Error: could not update wallpaper database" >&2
    exit 1
fi
lw_atomic_commit "$tmp" "$LW_DB_FILE"

new_tags="$(jq -c --arg path "$VIDEO" '.[] | select(.path == $path) | .tags' "$LW_DB_FILE")"

if [ -z "$new_tags" ]; then
    lw_log_warn "tag.sh: video not found in database: $VIDEO"
    echo "Error: video not found in database (run refresh.sh first)" >&2
    exit 1
fi

lw_log_info "tag.sh: $VIDEO -> $MODE \"$TAG\" -> tags=$new_tags"
echo "$new_tags"
