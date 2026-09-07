#!/usr/bin/env bash
#
# sun_times.sh
# -------------
# Prints "SUNRISE SUNSET" (each HH:MM, local time, space-separated) for
# settings.location_lat/location_lng and today's date, using
# _sun_times.py's offline NOAA calculation. Used by scheduler_tick.sh to
# resolve "sunrise"/"sunset" rule boundaries.
#
# Prints "--:-- --:--" (and exits 0) if location isn't configured yet --
# callers treat that as "no sunrise/sunset rules can fire right now",
# not an error, since the wallpaper Schedule page still works fine for
# plain HH:MM rules without a location set.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

lw_ensure_dirs
lw_json_init_if_missing "$LW_SETTINGS_FILE" "{}"

LAT="$(jq -r '.location_lat // empty' "$LW_SETTINGS_FILE" 2>/dev/null)"
LNG="$(jq -r '.location_lng // empty' "$LW_SETTINGS_FILE" 2>/dev/null)"

if [ -z "$LAT" ] || [ -z "$LNG" ]; then
    echo "--:-- --:--"
    exit 0
fi

PYTHON_BIN="python3"
command -v python3 >/dev/null 2>&1 || PYTHON_BIN="python"

out="$("$PYTHON_BIN" "$SCRIPT_DIR/_sun_times.py" "$LAT" "$LNG" 2>>"$LW_ERROR_LOG_FILE")"
if [ -z "$out" ]; then
    echo "--:-- --:--"
    exit 0
fi

# _sun_times.py prints two lines (sunrise, sunset) -- flatten to one
# space-separated line for easy `read sunrise sunset <<< "$(...)"` use.
# (Local-time conversion inside _sun_times.py uses the SYSTEM timezone,
# not one derived from lat/lng -- correct as long as the machine's
# timezone already matches where the user actually is, which is the
# normal case for a desktop app and is not re-derived here.)
printf '%s\n' "$(echo "$out" | tr '\n' ' ' | sed 's/ $//')"
