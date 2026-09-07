#!/usr/bin/env bash
#
# metadata.sh <video_path>
# --------------------------
# Uses ffprobe to extract metadata for a single video, printed as a JSON
# object:
#   { "duration": "00:32", "duration_seconds": 32, "fps": 60,
#     "codec": "h264", "resolution": "1920x1080", "width": 1920,
#     "height": 1080, "filesize": 104857600, "filesize_human": "100M" }
#
# If ffprobe fails (corrupt file, not a video, ...) this still prints
# valid JSON with empty/0 fields instead of crashing the caller.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

VIDEO="$1"

if [ -z "$VIDEO" ] || [ ! -f "$VIDEO" ]; then
    echo '{"duration":"00:00","duration_seconds":0,"fps":0,"codec":"","resolution":"","width":0,"height":0,"filesize":0,"filesize_human":""}'
    exit 0
fi

probe_json="$(ffprobe -v error \
    -select_streams v:0 \
    -show_entries stream=width,height,r_frame_rate,codec_name \
    -show_entries format=duration,size \
    -of json "$VIDEO" 2>/dev/null)"

if [ -z "$probe_json" ]; then
    lw_log_warn "metadata.sh: ffprobe failed for $VIDEO"
    echo '{"duration":"00:00","duration_seconds":0,"fps":0,"codec":"","resolution":"","width":0,"height":0,"filesize":0,"filesize_human":""}'
    exit 0
fi

filesize="$(stat -c%s "$VIDEO" 2>/dev/null || echo 0)"
filesize_human="$(numfmt --to=iec --suffix=B "$filesize" 2>/dev/null || echo "${filesize}B")"

echo "$probe_json" | jq -c --argjson filesize "$filesize" --arg filesize_human "$filesize_human" '
    (.streams[0] // {}) as $s |
    (.format // {}) as $f |
    ($s.r_frame_rate // "0/1") as $rate_str |
    ($rate_str | split("/") | map(tonumber)) as $rate_parts |
    (if $rate_parts[1] > 0 then ($rate_parts[0] / $rate_parts[1]) else 0 end) as $fps |
    (($f.duration // "0") | tonumber? // 0) as $dur_sec |
    {
        duration: (
            (($dur_sec / 60) | floor | tostring) + ":" +
            (($dur_sec % 60 | floor | tostring) | if length < 2 then "0" + . else . end)
        ),
        duration_seconds: ($dur_sec | floor),
        fps: ($fps | floor),
        codec: ($s.codec_name // ""),
        resolution: (
            if $s.width and $s.height then "\($s.width)x\($s.height)" else "" end
        ),
        width: ($s.width // 0),
        height: ($s.height // 0),
        filesize: $filesize,
        filesize_human: $filesize_human
    }
' 2>/dev/null || echo '{"duration":"00:00","duration_seconds":0,"fps":0,"codec":"","resolution":"","width":0,"height":0,"filesize":0,"filesize_human":""}'
