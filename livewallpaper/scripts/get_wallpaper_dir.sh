#!/usr/bin/env bash
#
# get_wallpaper_dir.sh
# -------------------------------------------------------
# Prints the wallpaper directory CURRENTLY IN USE (with "~" expanded,
# resolved via env var -> settings.json -> default — see utils.sh for
# the exact priority). Kept as its own tiny script so the QML
# WallpaperService doesn't have to re-implement the settings.json lookup.
# -------------------------------------------------------
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

echo "$LW_WALLPAPER_DIR"
