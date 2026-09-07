#!/usr/bin/env bash
#
# weather_tick.sh [--force]
# ----------------------------
# Called on a poll interval by WeatherService.qml. Reads the current
# weather condition (weather.sh, cached per settings.weather_poll_minutes)
# and, if settings.weather_rules maps that condition to a non-empty
# collection AND the condition changed since the last tick, applies a
# random wallpaper from that collection.
#
# --force bypasses the "did the condition change" check (used by a
# manual "Apply now" button) but still goes through weather.sh's own
# cache/TTL for the network fetch itself.
#
# Silent no-op whenever weather_enabled is false, location isn't set,
# the condition is "unknown", or that condition has no rule mapped --
# same "never surface an error for a background poll" rule as
# scheduler_tick.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

lw_ensure_dirs
lw_json_init_if_missing "$LW_SETTINGS_FILE" "{}"

FORCE=0
[ "$1" = "--force" ] && FORCE=1

STATE_FILE="$LW_CACHE_DIR/weather_state.json"

# Read weather_enabled AND weather_rules with a SINGLE jq call (fields
# joined with \x1f) instead of two separate forks -- this script runs on
# every WeatherService poll. Both elements must be stringified before the
# join: `join()` cannot combine a string element with a raw JSON object
# (jq errors "cannot be added" and outputs nothing), so `.weather_rules`
# gets `tostring` here.
IFS=$'\x1f' read -r ENABLED RULES_JSON <<< "$(jq -r \
    '[(.weather_enabled // false | tostring), (.weather_rules // "{}" | tostring)] | join("\u001f")' \
    "$LW_SETTINGS_FILE" 2>/dev/null)"
if [ "$ENABLED" != "true" ]; then
    exit 0
fi

[ -z "$RULES_JSON" ] && RULES_JSON="{}"
if ! jq -e 'type == "object"' <<< "$RULES_JSON" >/dev/null 2>&1; then
    lw_log_warn "weather_tick.sh: weather_rules is not a JSON object, skipping"
    exit 0
fi

CONDITION="$(bash "$SCRIPT_DIR/weather.sh" 2>>"$LW_ERROR_LOG_FILE")"
if [ -z "$CONDITION" ] || [ "$CONDITION" = "unknown" ]; then
    exit 0
fi

COLLECTION="$(jq -r --arg c "$CONDITION" '.[$c] // empty' <<< "$RULES_JSON")"
if [ -z "$COLLECTION" ]; then
    exit 0
fi

last_condition=""
[ -f "$STATE_FILE" ] && last_condition="$(jq -r '.condition // empty' "$STATE_FILE" 2>/dev/null)"

if [ "$CONDITION" = "$last_condition" ] && [ "$FORCE" -eq 0 ]; then
    exit 0
fi

APPLY_PATH="$("$SCRIPT_DIR/collections.sh" random "$COLLECTION" 2>>"$LW_ERROR_LOG_FILE")"
if [ -z "$APPLY_PATH" ]; then
    lw_log_warn "weather_tick.sh: condition '$CONDITION' -> collection '$COLLECTION' is empty, skipping apply"
    exit 0
fi

bash "$SCRIPT_DIR/apply_wallpaper.sh" "$APPLY_PATH" >/dev/null 2>>"$LW_ERROR_LOG_FILE"

lw_lock_or_skip "weather_state" 3 || exit 0
tmp="$(lw_atomic_tmp_for "$STATE_FILE")" || exit 0
jq -n --arg c "$CONDITION" --arg coll "$COLLECTION" --arg path "$APPLY_PATH" --argjson t "${EPOCHSECONDS:-$(date +%s)}" \
    '{condition: $c, collection: $coll, applied_path: $path, applied_at: $t}' > "$tmp"
lw_atomic_commit "$tmp" "$STATE_FILE"

lw_log_info "weather_tick.sh: condition '$CONDITION' -> $COLLECTION -> $APPLY_PATH"
exit 0
