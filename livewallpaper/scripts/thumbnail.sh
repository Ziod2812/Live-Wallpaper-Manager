#!/usr/bin/env bash
#
# thumbnail.sh <video> <output_thumb.png>
# ----------------------------------------
# Uses ffmpeg to grab one frame at the 3-second mark, resize/crop it to
# exactly 400x225 (16:9) and save it as a PNG.

VIDEO="$1"
THUMB="$2"

if [ -z "$VIDEO" ] || [ -z "$THUMB" ]; then
    echo "Usage: thumbnail.sh <video> <output_thumb.png>" >&2
    exit 1
fi

if [ ! -f "$VIDEO" ]; then
    echo "Error: video does not exist: $VIDEO" >&2
    exit 1
fi

mkdir -p "$(dirname "$THUMB")"

# -ss before -i for fast (input) seeking.
# scale+crop guarantees an exact 400x225 output regardless of source aspect.
ffmpeg -y \
    -ss 00:00:03 \
    -i "$VIDEO" \
    -frames:v 1 \
    -vf "scale=400:225:force_original_aspect_ratio=increase,crop=400:225" \
    -loglevel error \
    "$THUMB"

# If the video is shorter than 3s (seek fails -> no frame produced), retry at 0.
if [ ! -s "$THUMB" ]; then
    ffmpeg -y \
        -i "$VIDEO" \
        -frames:v 1 \
        -vf "scale=400:225:force_original_aspect_ratio=increase,crop=400:225" \
        -loglevel error \
        "$THUMB"
fi
