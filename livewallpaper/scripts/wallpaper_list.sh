#!/usr/bin/env bash
#
# wallpaper_list.sh
# -------------------
# Scans the wallpaper directory, builds/updates the wallpapers.json
# database (incrementally, instead of rescanning from scratch every time),
# then prints the resulting JSON. This file is watched directly by the
# Quickshell WallpaperService (FileView + watchChanges), so writing to it
# is all that's needed to refresh the UI — no explicit "push" call needed.
#
# For each video:
#   - Already in the database AND file unchanged -> keep the old record
#     (skip ffprobe/ffmpeg entirely, much faster than a naive rescan).
#   - NEW video -> generate a thumbnail (if missing) + extract metadata via
#     ffprobe, add a new record.
#   - In the database but no longer on disk -> drop it.
#
# "favorite" state is preserved when a record is refreshed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

lw_ensure_dirs
lw_json_init_if_missing "$LW_DB_FILE" "[]"

# Spam-guard: two full scans (button mash on Refresh, the auto-watcher
# firing while a manual refresh is still mid-scan, change_directory.sh,
# etc.) must never run at once -- they'd both read/write LW_DB_FILE and
# could interleave into a half-merged result. If a scan is already
# running, this one just prints whatever's currently on disk (which the
# in-progress scan is about to update anyway) and exits, instead of
# duplicating the work or racing it.
if ! lw_lock_or_skip "wallpaper_scan" 0; then
    cat "$LW_DB_FILE"
    exit 0
fi

# Serialize every writer of wallpapers.json, including favorites. The
# scan lock only protects scans from other scans.
if ! lw_lock_or_skip "wallpaper_db" 5; then
    cat "$LW_DB_FILE"
    exit 0
fi

shopt -s nullglob nocaseglob
files=(
    "$LW_WALLPAPER_DIR"/*.mp4 "$LW_WALLPAPER_DIR"/*.webm "$LW_WALLPAPER_DIR"/*.mkv "$LW_WALLPAPER_DIR"/*.mov
    # Added: extra video containers played directly by mpv/mpvpaper,
    # same as the four above.
    "$LW_WALLPAPER_DIR"/*.avi "$LW_WALLPAPER_DIR"/*.m4v "$LW_WALLPAPER_DIR"/*.mpeg "$LW_WALLPAPER_DIR"/*.mpg
    "$LW_WALLPAPER_DIR"/*.wmv "$LW_WALLPAPER_DIR"/*.flv "$LW_WALLPAPER_DIR"/*.ts "$LW_WALLPAPER_DIR"/*.mts
    "$LW_WALLPAPER_DIR"/*.m2ts "$LW_WALLPAPER_DIR"/*.3gp "$LW_WALLPAPER_DIR"/*.ogv
    # NOTE: .gif/.apng/.webp (animated) are deliberately NOT scanned here
    # because the manager catalogs the video containers above.
)
shopt -u nocaseglob nullglob

if [ "${#files[@]}" -eq 0 ]; then
    if [ "$(cat "$LW_DB_FILE" 2>/dev/null)" != "[]" ]; then
        empty_tmp="$(lw_atomic_tmp_for "$LW_DB_FILE")"
        if [ -n "$empty_tmp" ]; then
            printf '[]\n' > "$empty_tmp" && lw_atomic_commit "$empty_tmp" "$LW_DB_FILE"
        fi
    fi
    echo "[]"
    exit 0
fi

old_db="$(cat "$LW_DB_FILE" 2>/dev/null || echo "[]")"
tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT

# Build the id -> existing-record lookup ONCE, instead of re-parsing the
# entire (potentially large) old_db with a fresh jq process for every
# single file in the loop below (that was an O(n^2) cost: N files each
# scanning all N old records). Entries are base64-encoded per line so a
# filename containing tabs/newlines can never corrupt the table.
declare -A old_by_id
declare -A old_by_path
while IFS=$'\t' read -r _id _path_b64 _record_b64; do
    [ -n "$_id" ] || continue
    _record="$(printf '%s' "$_record_b64" | base64 -d 2>/dev/null)"
    old_by_id["$_id"]="$_record"
    _old_path="$(printf '%s' "$_path_b64" | base64 -d 2>/dev/null)"
    [ -n "$_old_path" ] && old_by_path["$_old_path"]="$_record"
done < <(printf '%s' "$old_db" | jq -r '.[] | [.id, (.path | @base64), (tostring | @base64)] | @tsv' 2>/dev/null)

for f in "${files[@]}"; do
    [ -f "$f" ] || continue

    name="$(basename "$f")"
    name_noext="${name%.*}"
    id="$(lw_file_hash "$f")"
    thumb="$LW_THUMB_DIR/${id}.png"
    mtime="$(stat -c%Y "$f" 2>/dev/null || echo 0)"

    existing="${old_by_id[$id]:-}"
    migrated_from_path=false
    # During the ID migration, match by path as a fallback so existing
    # favorites/tags survive the first content-hash refresh.
    if [ -z "$existing" ]; then
        existing="${old_by_path[$f]:-}"
        [ -n "$existing" ] && migrated_from_path=true
    fi
    existing_mtime="0"
    [ -n "$existing" ] && existing_mtime="$(echo "$existing" | jq -r '.mtime // 0' 2>/dev/null)"

    if [ -n "$existing" ] && [ "$migrated_from_path" != "true" ] && [ "$existing_mtime" = "$mtime" ]; then
        [ ! -s "$thumb" ] && "$SCRIPT_DIR/thumbnail.sh" "$f" "$thumb" >/dev/null 2>&1
        echo "$existing" >> "$tmp_file"
        continue
    fi

    [ ! -s "$thumb" ] && "$SCRIPT_DIR/thumbnail.sh" "$f" "$thumb" >/dev/null 2>&1
    meta="$("$SCRIPT_DIR/metadata.sh" "$f")"
    favorite="$(echo "$existing" | jq -r '.favorite // false' 2>/dev/null)"
    [ "$favorite" != "true" ] && favorite="false"
    # Carry over user-owned tags so a rescan never overwrites them.
    carry_over="$(echo "$existing" | jq -c '{ tags: (.tags // []) }' 2>/dev/null)"
    [ -z "$carry_over" ] && carry_over='{"tags":[]}'

    jq -n \
        --arg id "$id" \
        --arg name "$name_noext" \
        --arg path "$f" \
        --arg thumb "$thumb" \
        --argjson mtime "$mtime" \
        --argjson meta "$meta" \
        --argjson favorite "$favorite" \
        --argjson carry_over "$carry_over" \
        '{
            id: $id,
            name: $name,
            path: $path,
            thumb: $thumb,
            mtime: $mtime,
            favorite: $favorite
        } + $carry_over + $meta' >> "$tmp_file"
done

# Atomic + crash-safe write: the temp file lives in the SAME directory as
# LW_DB_FILE (so the rename below is guaranteed to stay on one filesystem)
# and is fsync'd before the rename (lw_atomic_commit), so any reader
# (Quickshell's FileView, watching this file for changes) always sees
# either the complete old content or the complete new content -- never a
# truncated/empty file mid-write, and never a renamed-but-not-yet-durable
# file if the machine loses power right after. Writing directly into
# LW_DB_FILE with `>` would truncate it to 0 bytes before jq's output is
# flushed, and a watcher firing in that exact window would read
# invalid/empty JSON.
final_tmp="$(lw_atomic_tmp_for "$LW_DB_FILE")"
jq -s '.' "$tmp_file" > "$final_tmp"

# Nothing actually changed (a no-op refresh -- e.g. Refresh mashed
# repeatedly, or the watcher firing on an event that didn't alter the
# tracked video set) -> skip the write entirely. Saves the I/O, and just
# as importantly avoids firing WallpaperService's FileView watchChanges
# for a file whose content is identical, which would otherwise make the
# UI redo a reload for nothing on every spammed refresh.
if cmp -s "$final_tmp" "$LW_DB_FILE" 2>/dev/null; then
    rm -f "$final_tmp"
else
    lw_atomic_commit "$final_tmp" "$LW_DB_FILE"
fi
cat "$LW_DB_FILE"
