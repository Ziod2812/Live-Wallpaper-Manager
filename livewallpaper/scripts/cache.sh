#!/usr/bin/env bash
#
# cache.sh <status|clear|clear-thumbs>
# ---------------------------------------
# Cache management for Live Wallpaper Manager.
#
#   status        Prints JSON: thumbnail cache size, thumbnail count,
#                 database size, current cache paths.
#   clear         Clears ONLY regenerable cache -- see CLEAR_TARGETS
#                 below. Prints JSON: {"freed_bytes": N}.
#   clear-thumbs  Clears only the thumbnail cache (regenerated on next
#                 refresh).
#
# clear's "safe to delete" list is deliberately narrow and explicit:
#   - $LW_THUMB_DIR             thumbnail/preview/artwork cache (*.png)
#   - mpvpaper*.log, web_browser.log   transient per-launch mpv/browser
#                               stdout, fully rewritten on next play
#   - stray ".tmp.*" files      leftovers from an interrupted
#                               lw_write_text_atomic (crash mid-write)
#
# NEVER touched by clear, on purpose:
#   - $LW_DB_FILE (wallpapers.json)  -- favorites & metadata live here
#   - $LW_SETTINGS_FILE, $LW_HISTORY_FILE
#   - current/last/resolution/fps    -- needed by "Start Wallpaper" replay
#   - $LW_STATE_DIR (per-monitor state) -- holds the PID/IPC socket of
#     whatever is ACTIVELY PLAYING right now; wiping it mid-playback
#     would desync the UI from a still-running mpvpaper/browser
#   - $LW_LOG_DIR (wallpaper.log/error.log/watcher.log) --
#     persistent logs, not marked temporary
#   - the wallpaper video files themselves (never lived under cache)
#
# clear also does NOT stop playback -- clearing cache is not the same
# action as stopping/exiting, and a wallpaper currently on screen should
# keep playing uninterrupted.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

ACTION="${1:-status}"

# lw_path_size_bytes <path> -> total size in bytes, 0 if missing/unreadable.
lw_path_size_bytes() {
    local p="$1"
    [ -e "$p" ] || { echo 0; return; }
    du -sb "$p" 2>/dev/null | cut -f1 || echo 0
}

case "$ACTION" in
    status)
        lw_ensure_dirs
        thumb_count="$(find "$LW_THUMB_DIR" -name '*.png' 2>/dev/null | wc -l)"
        thumb_size="$(du -sh "$LW_THUMB_DIR" 2>/dev/null | cut -f1)"
        db_count="0"
        [ -s "$LW_DB_FILE" ] && db_count="$(jq 'length' "$LW_DB_FILE" 2>/dev/null || echo 0)"
        jq -n \
            --arg thumb_count "$thumb_count" \
            --arg thumb_size "${thumb_size:-0}" \
            --arg db_count "$db_count" \
            --arg cache_dir "$LW_CACHE_DIR" \
            --arg data_dir "$LW_DATA_DIR" \
            --arg log_dir "$LW_LOG_DIR" \
            '{
                thumbnail_count: ($thumb_count | tonumber),
                thumbnail_size: $thumb_size,
                database_entries: ($db_count | tonumber),
                cache_dir: $cache_dir,
                data_dir: $data_dir,
                log_dir: $log_dir
            }'
        ;;
    clear)
        lw_ensure_dirs

        CLEAR_TARGETS=(
            "$LW_THUMB_DIR"
            "$LW_CACHE_DIR/mpvpaper.log"
            "$LW_CACHE_DIR/mpvpaper_web.log"
            "$LW_CACHE_DIR/web_browser.log"
        )

        freed_bytes=0
        for target in "${CLEAR_TARGETS[@]}"; do
            sz="$(lw_path_size_bytes "$target")"
            freed_bytes=$(( freed_bytes + ${sz:-0} ))
        done
        # Stray atomic-write temp files anywhere under the cache dir
        # (lw_write_text_atomic leftovers from a crash mid-write) --
        # genuinely temporary, safe to sweep regardless of location.
        while IFS= read -r -d '' f; do
            sz="$(stat -c%s "$f" 2>/dev/null || echo 0)"
            freed_bytes=$(( freed_bytes + ${sz:-0} ))
        done < <(find "$LW_CACHE_DIR" -name '.tmp.*' -type f -print0 2>/dev/null)

        rm -rf "$LW_THUMB_DIR"
        mkdir -p "$LW_THUMB_DIR"
        rm -f "$LW_CACHE_DIR/mpvpaper.log" "$LW_CACHE_DIR/mpvpaper_web.log" \
              "$LW_CACHE_DIR/web_browser.log"
        find "$LW_CACHE_DIR" -name '.tmp.*' -type f -delete 2>/dev/null

        lw_log_info "Cleared cache (freed ${freed_bytes} bytes): thumbnails + transient mpv/browser logs + stray temp files. Settings, wallpaper database (incl. favorites), history, playlists, current playback state, and persistent logs were preserved."
        jq -n --argjson freed "$freed_bytes" '{freed_bytes: $freed}'
        ;;
    clear-thumbs)
        rm -rf "$LW_THUMB_DIR"
        mkdir -p "$LW_THUMB_DIR"
        lw_log_info "Cleared thumbnail cache (will regenerate on next refresh)."
        echo "Cleared thumbnail cache."
        ;;
    *)
        echo "Usage: cache.sh <status|clear|clear-thumbs>" >&2
        exit 1
        ;;
esac
