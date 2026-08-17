#!/usr/bin/env bash
#
# _mpris_worker.sh
# -------------------------------------------------------------------------
# Internal helper for MprisService.qml -- not meant to be run by hand.
#
# Emits one JSON line per MPRIS state change, e.g.:
#   {"active":true,"player":"spotify","title":"Midsummer","artist":"Myuu",
#    "album":"...","artUrl":"file:///...","status":"Playing",
#    "shuffle":false,"loop":"None","duration":227.0,"position":84.2}
# or {"active":false} when no MPRIS player is available.
#
# Detects Spotify, mpv, VLC, Firefox, Chromium, or any other MPRIS-
# compliant player automatically via `playerctl -l` -- preferring
# whichever one is currently Playing, falling back to the first player
# found so paused sessions still show something.
#
# Event-driven, not a busy loop: two background `playerctl --follow`
# watchers (metadata + playback-status, across all players) write a
# trigger byte into a private FIFO whenever MPRIS reports a real change;
# the main loop blocks on that FIFO with `read -u`. A 1-second timeout is
# only armed while something is actually Playing (MPRIS has no
# position-changed signal, so this is the one genuinely time-based part,
# needed purely to keep the progress bar moving) -- while paused/stopped
# the read blocks indefinitely with zero CPU use.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh" 2>/dev/null || true

# Reap any worker (and its playerctl --follow watchers) left running from
# a previous session that never got a chance to run the `cleanup` trap
# below (Quickshell force-killed/crashed) -- same "clean up any orphaned
# instance from a previous session before starting a new one" pattern
# TrayService.qml's trayProc already uses for _tray_icon.py.
# MprisService.qml never starts a second worker while one is already
# running, so it's safe to sweep unconditionally here. Excludes our own
# pid ($$) the same way TrayService's reap does.
for _pid in $(pgrep -f "_mpris_worker.sh" 2>/dev/null); do
    [ "$_pid" != "$$" ] && kill "$_pid" 2>/dev/null
done
pkill -f "playerctl --all-players --follow" 2>/dev/null

if ! command -v playerctl >/dev/null 2>&1; then
    echo '{"error":"playerctl_missing"}'
    exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
    echo '{"error":"jq_missing"}'
    exit 1
fi

# pick_player -> name of the best MPRIS player to report on: the first
# one that's actually Playing, else just the first one playerctl knows
# about (so a paused track still shows correctly).
pick_player() {
    local p st
    while IFS= read -r p; do
        [ -z "$p" ] && continue
        st="$(playerctl -p "$p" status 2>/dev/null)"
        if [ "$st" = "Playing" ]; then
            printf '%s' "$p"
            return 0
        fi
    done < <(playerctl -l 2>/dev/null)
    playerctl -l 2>/dev/null | head -1
}

LAST_STATUS="Stopped"

emit() {
    local player title artist album art status shuffle loopst length_us position
    player="$(pick_player)"

    if [ -z "$player" ]; then
        LAST_STATUS="Stopped"
        printf '{"active":false}\n'
        return
    fi

    title="$(playerctl -p "$player" metadata title 2>/dev/null)"
    artist="$(playerctl -p "$player" metadata artist 2>/dev/null)"
    album="$(playerctl -p "$player" metadata album 2>/dev/null)"
    art="$(playerctl -p "$player" metadata mpris:artUrl 2>/dev/null)"
    status="$(playerctl -p "$player" status 2>/dev/null)"
    shuffle="$(playerctl -p "$player" shuffle 2>/dev/null)"
    loopst="$(playerctl -p "$player" loop 2>/dev/null)"
    length_us="$(playerctl -p "$player" metadata mpris:length 2>/dev/null)"
    position="$(playerctl -p "$player" position 2>/dev/null)"

    [ -z "$length_us" ] && length_us=0
    [ -z "$position" ] && position=0
    [ -z "$status" ] && status="Stopped"
    [ -z "$loopst" ] && loopst="None"

    LAST_STATUS="$status"

    jq -nc \
        --arg player "$player" \
        --arg title "$title" \
        --arg artist "$artist" \
        --arg album "$album" \
        --arg art "$art" \
        --arg status "$status" \
        --arg shuffle "$shuffle" \
        --arg loopst "$loopst" \
        --argjson length_us "${length_us:-0}" \
        --argjson position "${position:-0}" \
        '{active:true, player:$player, title:$title, artist:$artist,
          album:$album, artUrl:$art, status:$status,
          shuffle:($shuffle=="On"), loop:$loopst,
          duration:($length_us/1000000), position:$position}'
}

# ── Private trigger FIFO ──────────────────────────────────────────────
# Two follow-watchers below write into THIS fifo (not our real stdout)
# so their arbitrary trigger output never interleaves with the JSON
# lines this script itself prints -- only emit()'s output ever reaches
# stdout, one full line at a time.
TRIG_FIFO="$(mktemp -u "${TMPDIR:-/tmp}/lwm_mpris_trig.XXXXXX")"
mkfifo "$TRIG_FIFO" 2>/dev/null || { echo '{"error":"fifo_failed"}'; exit 1; }
exec 3<>"$TRIG_FIFO"
rm -f "$TRIG_FIFO"

# Wrapped in a restart loop: playerctl --follow exits immediately when no
# player exists yet (or the last one just quit) -- restarting keeps this
# watcher alive across "no players" gaps without a tight/busy loop
# (each failed attempt still costs a real playerctl startup, so it backs
# off half a second between tries).
watch_metadata() {
    while true; do
        playerctl --all-players --follow metadata --format 'm' >&3 2>/dev/null
        sleep 0.5
    done
}
watch_status() {
    while true; do
        playerctl --all-players --follow status --format 's' >&3 2>/dev/null
        sleep 0.5
    done
}

watch_metadata &
META_PID=$!
watch_status &
STAT_PID=$!

cleanup() {
    kill "$META_PID" "$STAT_PID" 2>/dev/null
    pkill -P "$META_PID" 2>/dev/null
    pkill -P "$STAT_PID" 2>/dev/null
    pkill -f "playerctl --all-players --follow" 2>/dev/null
    exec 3<&- 2>/dev/null
}
trap cleanup EXIT INT TERM

emit

while true; do
    if [ "$LAST_STATUS" = "Playing" ]; then
        read -r -t 1 -u 3 _line
    else
        read -r -u 3 _line
    fi
    # Drain any extra queued triggers so a burst of MPRIS events (e.g. a
    # track change firing several property updates at once) collapses
    # into a single emit() instead of one per line.
    while read -r -t 0.02 -u 3 _more; do :; done
    emit
done
