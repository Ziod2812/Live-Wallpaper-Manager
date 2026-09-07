#!/usr/bin/env bash
#
# verify_thumbs.sh
# ------------------
# Cheap, read-only pass over the EXISTING wallpapers.json: for every
# entry whose thumb PNG is missing/empty on disk but whose source video
# still exists, regenerate just that one thumbnail.
#
# This is deliberately NOT the same thing as wallpaper_list.sh's full
# scan. wallpaper_list.sh recomputes a content-hash (sha256sum) of every
# single video on every run to detect renames/edits, which is the
# correct behavior for a manual "Refresh", but is too heavy to run
# unconditionally on every app launch for large libraries. This script
# only stats existing files (no hashing, no ffprobe) so it's safe to run
# every startup and self-heal thumbnails that went missing (cache wiped
# by something other than Clear Cache, an interrupted ffmpeg run, etc.)
# without waiting for the user to notice broken thumbnails and click
# Refresh manually.
#
# It never rewrites wallpapers.json -- ids/paths/thumb locations don't
# change, only the PNG files on disk get (re)created. Failures are
# logged (unlike wallpaper_list.sh's silent >/dev/null 2>&1 thumbnail
# calls) so a genuinely-broken source video is diagnosable instead of
# failing the same way forever with no trace.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

lw_ensure_dirs

[ -s "$LW_DB_FILE" ] || exit 0

# Only one verify pass at a time; if one's already running (rare -- would
# need two near-simultaneous launches) just skip, the other will cover it.
lw_lock_or_skip "thumb_verify" 0 || exit 0

regenerated=0
failed=0

while IFS=$'\t' read -r path thumb; do
    [ -n "$thumb" ] || continue
    [ -s "$thumb" ] && continue          # already present -- nothing to do
    [ -f "$path" ] || continue           # source video itself is gone; a
                                          # real scan (Refresh) will drop
                                          # this record, not our job here

    if "$SCRIPT_DIR/thumbnail.sh" "$path" "$thumb" >/dev/null 2>"$LW_ERROR_LOG_FILE.tmp"; then
        :
    fi

    if [ -s "$thumb" ]; then
        regenerated=$((regenerated + 1))
    else
        failed=$((failed + 1))
        lw_log_error "verify_thumbs: failed to regenerate thumbnail for '$path' -> '$thumb': $(cat "$LW_ERROR_LOG_FILE.tmp" 2>/dev/null)"
    fi
    rm -f "$LW_ERROR_LOG_FILE.tmp"
done < <(jq -r '.[] | [.path, .thumb] | @tsv' "$LW_DB_FILE" 2>/dev/null)

[ "$regenerated" -gt 0 ] && lw_log_info "verify_thumbs: regenerated $regenerated missing thumbnail(s)."
[ "$failed" -gt 0 ] && lw_log_info "verify_thumbs: $failed thumbnail(s) still missing after a regeneration attempt -- see error.log."

exit 0
