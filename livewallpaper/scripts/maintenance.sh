#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"
case "${1:-cleanup}" in
  cleanup)
    lw_ensure_dirs
    find "$LW_THUMB_DIR" -type f -name '*.png' -mtime +"${2:-30}" -delete 2>/dev/null
    find "$LW_CACHE_DIR" -type f -name '.tmp.*' -delete 2>/dev/null
    echo "Old thumbnails and temporary cache files removed."
    ;;
  *) echo "Usage: maintenance.sh cleanup [days]" >&2; exit 2 ;;
esac