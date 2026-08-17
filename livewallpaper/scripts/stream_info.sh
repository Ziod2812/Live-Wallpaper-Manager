#!/usr/bin/env bash
#
# stream_info.sh <url>
# -------------------------------------------------------
# Fetches metadata for a streaming URL via yt-dlp and prints a single
# JSON object to stdout:
#   { "title": "...", "thumbnail": "...", "duration": 123,
#     "uploader": "...", "id": "...", "live": false, "height": 1080 }
#
# "height" is the tallest video format yt-dlp reports as available for
# this URL (0 if unknown) -- i.e. what the source itself tops out at,
# not necessarily what's currently selected to play (that's capped by
# the user's chosen quality, if any -- see PlaybackService.streamQuality).
#
# Returns {} on any failure (yt-dlp not found, unsupported URL, network
# error, timeout). Caller should treat {} as "no metadata available" and
# still allow playback (the URL may still work as a direct media URL even
# if yt-dlp cannot extract metadata from it).
#
# Timeout: 15 seconds — fast enough for interactive UI feedback.
# --no-download / --skip-download: extracts metadata only, no file write.

URL="$1"

if [ -z "$URL" ]; then
    echo "{}"
    exit 0
fi

# Diagnostic log target (defined locally if utils.sh was not sourced; harmless
# override if it was). Previously every failure path here returned '{}'
# silently with no log line, so a geo-blocked/private/broken URL looked
# identical to "no metadata" and there was no way to tell why.
LW_LOG_DIR="${LW_LOG_DIR:-$HOME/.cache/livewallpaper/logs}"
mkdir -p "$LW_LOG_DIR" 2>/dev/null

if ! command -v yt-dlp >/dev/null 2>&1; then
    echo "{}"
    exit 0
fi

# Use dump-single-json for structured output, pipe through jq to extract
# only the fields we need. Timeout 15s to avoid blocking the QML process
# for slow or unreachable URLs.
# Captured yt-dlp stderr (NOT /dev/null) so a failed extraction now writes
# the actual reason to log instead of being indistinguishable from "no metadata".
errno_file="$(mktemp)"
info="$(timeout 15 yt-dlp \
    --no-playlist \
    --skip-download \
    --dump-single-json \
    --quiet \
    "$URL" 2>"$errno_file")"
yt_dlp_rc=$?
yt_dlp_err="$(cat "$errno_file" 2>/dev/null)"
rm -f "$errno_file"

if [ "$yt_dlp_rc" -ne 0 ] || [ -z "$info" ] || ! command -v jq >/dev/null 2>&1; then
    _msg="yt-dlp failed (exit $yt_dlp_rc"
    [ -n "$yt_dlp_err" ] && _msg="$_msg: $(echo "$yt_dlp_err" | tr '\n' ' ')"
    _msg="$_msg)"
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "stream_info.sh: $URL -- $_msg" \
        >> "$LW_LOG_DIR/stream_info.log" 2>/dev/null
    echo "{}"
    exit 0
fi

# Extract a safe, minimal subset. Default to "" / 0 / false for missing keys.
# height: max of all listed video formats' heights -- more reliable than
# top-level .height, which some extractors leave unset when no explicit
# format was requested (we don't pass -f here, only metadata).
if ! jq -c '{
  title:     (.title     // ""),
  thumbnail: (.thumbnail // ""),
  duration:  (.duration  // 0),
  uploader:  (.uploader  // ""),
  id:        (.id        // ""),
  live:      (.is_live   // false),
  height:    (([.formats[]?.height // empty] | max) // .height // 0)
}' <<< "$info" 2>/dev/null; then
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" \
        "stream_info.sh: $URL -- jq extraction failed (yt-dlp output was not parseable JSON)" \
        >> "$LW_LOG_DIR/stream_info.log" 2>/dev/null
    echo "{}"
fi
