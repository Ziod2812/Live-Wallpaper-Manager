#!/usr/bin/env bash
#
# recent.sh [limit]
# -------------------------------------------------------
# Prints a JSON array of the most recently APPLIED wallpapers (newest
# first), backing the "Recent" filter tab.
#
# Sourced from history.json (written by lw_add_history() every time
# apply_wallpaper.sh succeeds), joined with wallpapers.json for full
# name/thumb/resolution/fps fields, same shape as a normal wallpaper card.
#
# [limit] defaults to 5.
# -------------------------------------------------------
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

LIMIT="${1:-5}"

lw_recent_wallpapers "$LIMIT"
