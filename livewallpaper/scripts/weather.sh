#!/usr/bin/env bash
#
# weather.sh [--force]
# ----------------------
# Prints one simplified weather condition token for
# settings.location_lat/location_lng, one of:
#   clear-day  clear-night  cloudy  fog  rain  snow  storm
#
# Backed by Open-Meteo's free "current weather" endpoint -- no API key,
# no signup (https://open-meteo.com). Result is cached to
# $LW_CACHE_DIR/weather.json for settings.weather_poll_minutes so
# weather_tick.sh's poll loop (see WeatherService.qml) doesn't hit the
# network every tick; pass --force to bypass the cache (used by the
# "Refresh now" button on the Schedule page).
#
# Prints "unknown" (exit 0, not an error) when location isn't configured,
# the network is unreachable, or the response can't be parsed --
# weather_tick.sh treats "unknown" as "leave the current wallpaper alone".

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

lw_ensure_dirs
lw_json_init_if_missing "$LW_SETTINGS_FILE" "{}"

FORCE=0
[ "$1" = "--force" ] && FORCE=1

WEATHER_CACHE_FILE="$LW_CACHE_DIR/weather.json"

LAT="$(jq -r '.location_lat // empty' "$LW_SETTINGS_FILE" 2>/dev/null)"
LNG="$(jq -r '.location_lng // empty' "$LW_SETTINGS_FILE" 2>/dev/null)"
POLL_MIN="$(jq -r '.weather_poll_minutes // 20' "$LW_SETTINGS_FILE" 2>/dev/null)"
[ -z "$POLL_MIN" ] || [ "$POLL_MIN" = "null" ] && POLL_MIN=20

if [ -z "$LAT" ] || [ -z "$LNG" ]; then
    echo "unknown"
    exit 0
fi

# ── Cache check ──────────────────────────────────────────────────────
if [ "$FORCE" -eq 0 ] && [ -f "$WEATHER_CACHE_FILE" ]; then
    cached_at="$(jq -r '.fetched_at // 0' "$WEATHER_CACHE_FILE" 2>/dev/null)"
    now_epoch="$(date +%s)"
    age_min=$(( (now_epoch - ${cached_at:-0}) / 60 ))
    if [ "$age_min" -lt "$POLL_MIN" ]; then
        cached_condition="$(jq -r '.condition // empty' "$WEATHER_CACHE_FILE" 2>/dev/null)"
        if [ -n "$cached_condition" ]; then
            echo "$cached_condition"
            exit 0
        fi
    fi
fi

# ── Fetch ────────────────────────────────────────────────────────────
url="https://api.open-meteo.com/v1/forecast?latitude=${LAT}&longitude=${LNG}&current=weather_code,is_day&timezone=auto"

response=""
if command -v curl >/dev/null 2>&1; then
    response="$(curl -fsS --max-time 8 "$url" 2>>"$LW_ERROR_LOG_FILE")"
elif command -v wget >/dev/null 2>&1; then
    response="$(wget -qO- --timeout=8 "$url" 2>>"$LW_ERROR_LOG_FILE")"
fi

if [ -z "$response" ] || ! jq empty <<< "$response" >/dev/null 2>&1; then
    lw_log_warn "weather.sh: fetch failed or invalid response for lat=$LAT lng=$LNG"
    # Serve a stale cache rather than nothing, if one exists.
    if [ -f "$WEATHER_CACHE_FILE" ]; then
        stale="$(jq -r '.condition // empty' "$WEATHER_CACHE_FILE" 2>/dev/null)"
        [ -n "$stale" ] && { echo "$stale"; exit 0; }
    fi
    echo "unknown"
    exit 0
fi

code="$(jq -r '.current.weather_code // -1' <<< "$response")"
is_day="$(jq -r '.current.is_day // 1' <<< "$response")"

# WMO Weather interpretation codes (open-meteo docs):
#   0            Clear sky
#   1-3          Mainly clear / partly cloudy / overcast
#   45,48        Fog
#   51-57        Drizzle
#   61-67        Rain
#   71-77        Snow
#   80-82        Rain showers
#   85,86        Snow showers
#   95,96,99     Thunderstorm
condition="unknown"
case "$code" in
    0)
        if [ "$is_day" = "1" ]; then condition="clear-day"; else condition="clear-night"; fi
        ;;
    1|2|3) condition="cloudy" ;;
    45|48) condition="fog" ;;
    51|53|55|56|57|61|63|65|66|67|80|81|82) condition="rain" ;;
    71|73|75|77|85|86) condition="snow" ;;
    95|96|99) condition="storm" ;;
    *) condition="cloudy" ;;
esac

lw_lock_or_skip "weather_cache" 3 || { echo "$condition"; exit 0; }
tmp="$(lw_atomic_tmp_for "$WEATHER_CACHE_FILE")" || { echo "$condition"; exit 0; }
jq -n --arg c "$condition" --argjson t "$(date +%s)" --argjson code "$code" \
    '{condition: $c, fetched_at: $t, weather_code: $code}' > "$tmp"
lw_atomic_commit "$tmp" "$WEATHER_CACHE_FILE"

lw_log_info "weather.sh: condition=$condition (code=$code, is_day=$is_day)"
echo "$condition"
