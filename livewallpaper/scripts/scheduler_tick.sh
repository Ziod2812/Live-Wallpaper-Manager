#!/usr/bin/env bash
#
# scheduler_tick.sh
# --------------------
# Called on a poll interval by SchedulerService.qml (Timer, default every
# 60s -- see that file). Evaluates settings.schedule_rules against the
# current local time (rule boundaries may be plain "HH:MM" or the
# literal tokens "sunrise"/"sunset", resolved via sun_times.sh) and, if
# the winning rule changed since the last tick, applies a wallpaper for
# it:
#   - source_type "collection" -> a random member via collections.sh random
#   - source_type "wallpaper"  -> that exact path
#
# Idempotent per tick: writes $LW_CACHE_DIR/schedule_state.json with the
# currently-active rule id, and only actually calls apply_wallpaper.sh
# when that id changes (or a "collection" rule is re-entered and the
# caller passed --reshuffle, e.g. from the Schedule page's "shuffle now"
# button) -- so a 60s poll doesn't relaunch mpv every minute for no
# reason.
#
# Silent no-op (exit 0) whenever schedule_enabled is false, there are no
# rules, or no rule currently matches -- this is a background poll, not
# a user action, so it must never surface an error dialog.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

lw_ensure_dirs
lw_json_init_if_missing "$LW_SETTINGS_FILE" "{}"

RESHUFFLE=0
[ "$1" = "--reshuffle" ] && RESHUFFLE=1

STATE_FILE="$LW_CACHE_DIR/schedule_state.json"

# Read schedule_enabled AND schedule_rules with a SINGLE jq call (two
# fields joined with \x1f). Both elements must be stringified explicitly:
# `join()` on a mixed array (string + JSON array) makes jq try to `+` the
# two together and hard-fails with "cannot be added", silently returning
# nothing (verified empirically) -- `tostring` on the rules element is what
# keeps the join working when schedule_rules is a real array. The old code
# forked jq up to 5x before even reaching the per-rule scan (enabled /
# rules / array-type check / rule count) -- and the zero-rule case needed
# no extra jq at all: the scan loop below simply never matches and exits
# on the same empty-match path the old explicit count check did.
IFS=$'\x1f' read -r ENABLED RULES_JSON <<< "$(jq -r \
    '[(.schedule_enabled // false | tostring), (.schedule_rules // "[]" | tostring)] | join("\u001f")' \
    "$LW_SETTINGS_FILE" 2>/dev/null)"
if [ "$ENABLED" != "true" ]; then
    exit 0
fi

[ -z "$RULES_JSON" ] && RULES_JSON="[]"
if ! jq -e 'type == "array"' <<< "$RULES_JSON" >/dev/null 2>&1; then
    lw_log_warn "scheduler_tick.sh: schedule_rules is not a JSON array, skipping"
    exit 0
fi

# Resolve sunrise/sunset once per tick (cheap, offline) so every rule
# that references them uses the same instant -- but ONLY when at least
# one rule actually references a sun token. sun_times.sh spawns a whole
# Python interpreter (plus its own settings.json jq read); paying that
# every 60s tick when the schedule is all plain HH:MM rules (the common
# case) is pure wasted work. The substring check is intentionally
# conservative: a false positive only costs one unnecessary (harmless)
# sun_times.sh call, never a skipped one.
SUNRISE="" SUNSET=""
case "$RULES_JSON" in
    *sunrise*|*sunset*)
        read -r SUNRISE SUNSET <<< "$("$SCRIPT_DIR/sun_times.sh")"
        ;;
esac

_resolve_token() {
    case "$1" in
        sunrise) echo "$SUNRISE" ;;
        sunset)  echo "$SUNSET" ;;
        *)       echo "$1" ;;
    esac
}

_hhmm_to_min() {
    # "HH:MM" -> minutes since midnight. "--:--" (unresolved sun event,
    # e.g. polar location) -> empty, caller must skip the rule.
    local v="$1"
    [ "$v" = "--:--" ] && { echo ""; return; }
    local h="${v%%:*}" m="${v##*:}"
    h=$((10#$h)); m=$((10#$m))
    echo $(( h * 60 + m ))
}

# 10# forces base-10 parsing so a leading-zero minute like "09" isn't
# misread as an (invalid) octal literal.
NOW_H=$((10#$(date +%H)))
NOW_M=$((10#$(date +%M)))
NOW_MIN=$(( NOW_H * 60 + NOW_M ))

# Pull every rule's fields with ONE jq call instead of re-invoking jq per
# rule scanned. The old loop forked jq 3x per rule just to check
# start/end (".[$i]" slice + 2 field reads), then after finding a match
# it parsed that exact same rule object a 4th/5th/6th time over again
# just to read back id/source_type/source. An 8-rule schedule could cost
# 25+ jq forks a tick; this is now exactly 1, matching the same
# single-jq-call pattern already used for the AWWW transition settings
# in utils.sh and the id-lookup table in wallpaper_list.sh.
#
# Fields are joined with \x1f (ASCII Unit Separator), not a real tab:
# bash's `read` treats tab as "IFS whitespace" and silently collapses
# consecutive delimiters, which misaligns columns the moment any rule
# has an empty start/end/source (verified empirically -- @tsv output fed
# through `IFS=$'\t' read` drops empty fields instead of preserving
# them, shifting every field after it by one). \x1f isn't IFS
# whitespace, so empty fields round-trip correctly.
MATCH_ID="" MATCH_SOURCE_TYPE="" MATCH_SOURCE=""
FOUND=0
while IFS=$'\x1f' read -r rid start_raw end_raw source_type source_value; do
    if [ -n "$start_raw" ] && [ -n "$end_raw" ]; then
        start_hhmm="$(_resolve_token "$start_raw")"
        end_hhmm="$(_resolve_token "$end_raw")"
        start_min="$(_hhmm_to_min "$start_hhmm")"
        end_min="$(_hhmm_to_min "$end_hhmm")"
        if [ -n "$start_min" ] && [ -n "$end_min" ]; then
            if [ "$start_min" -le "$end_min" ]; then
                # Same-day window, e.g. 06:00-12:00
                if [ "$NOW_MIN" -ge "$start_min" ] && [ "$NOW_MIN" -lt "$end_min" ]; then
                    FOUND=1
                fi
            else
                # Wraps past midnight, e.g. sunset-sunrise or 22:00-06:00
                if [ "$NOW_MIN" -ge "$start_min" ] || [ "$NOW_MIN" -lt "$end_min" ]; then
                    FOUND=1
                fi
            fi
        fi
    fi
    if [ "$FOUND" -eq 1 ]; then
        MATCH_ID="$rid"
        MATCH_SOURCE_TYPE="$source_type"
        MATCH_SOURCE="$source_value"
        break
    fi
done < <(jq -r '.[] | [(.id // ""), (.start // ""), (.end // ""), (.source_type // "collection"), (.source // "")] | join("\u001f")' <<< "$RULES_JSON")

if [ "$FOUND" -ne 1 ]; then
    exit 0
fi

rule_id="$MATCH_ID"
source_type="$MATCH_SOURCE_TYPE"
source_value="$MATCH_SOURCE"

[ -z "$source_value" ] && exit 0

last_id=""
[ -f "$STATE_FILE" ] && last_id="$(jq -r '.active_rule_id // empty' "$STATE_FILE" 2>/dev/null)"

if [ "$rule_id" = "$last_id" ] && [ "$RESHUFFLE" -eq 0 ]; then
    exit 0
fi

APPLY_PATH=""
if [ "$source_type" = "wallpaper" ]; then
    APPLY_PATH="$source_value"
else
    APPLY_PATH="$("$SCRIPT_DIR/collections.sh" random "$source_value" 2>>"$LW_ERROR_LOG_FILE")"
fi

if [ -z "$APPLY_PATH" ]; then
    lw_log_warn "scheduler_tick.sh: rule '$rule_id' resolved to no wallpaper (empty collection?), skipping apply"
    exit 0
fi

bash "$SCRIPT_DIR/apply_wallpaper.sh" "$APPLY_PATH" >/dev/null 2>>"$LW_ERROR_LOG_FILE"

lw_lock_or_skip "schedule_state" 3 || exit 0
tmp="$(lw_atomic_tmp_for "$STATE_FILE")" || exit 0
jq -n --arg id "$rule_id" --arg path "$APPLY_PATH" --argjson t "${EPOCHSECONDS:-$(date +%s)}" \
    '{active_rule_id: $id, applied_path: $path, applied_at: $t}' > "$tmp"
lw_atomic_commit "$tmp" "$STATE_FILE"

lw_log_info "scheduler_tick.sh: rule '$rule_id' -> $APPLY_PATH"
exit 0
