#!/usr/bin/env bash
#
# smart_playback_poll.sh
# -------------------------------------------------------
# One-shot status check for the three Smart Playback conditions Hyprland
# has no IPC event for: screen lock, monitor DPMS/sleep state, and an
# active GameMode session. Called from a light, infrequent timer (see
# Services/SmartPlaybackService.qml's pollTimer, 3s) rather than watched
# via any event source, since none of these three have one to watch for
# on a typical Hyprland setup -- same "infrequent poll for something
# slow-changing" precedent already established by Services/PowerService.qml
# (its own 45s battery-status poll). This script is only ever invoked at
# all while Smart Playback is ON and at least one of these three options
# is enabled -- see SmartPlaybackService's start/stop logic -- so Smart
# Playback OFF (or these three options all off) costs nothing.
#
# Every check below is a single cheap, already-fast system query -- not
# a loop, not a "wait for it" block -- so one invocation normally
# completes in a few milliseconds.
#
# RELIABILITY FIX: every external call below (loginctl, hyprctl, gdbus)
# is now wrapped in `timeout $LW_SP_TIMEOUT`, same fix/precedent as
# folder_picker.sh's documented "ROOT CAUSE OF THE FREEZE" (a gdbus call
# with no timeout at all). Before this fix, a single stuck D-Bus/logind
# call (e.g. right after resume-from-suspend, a wedged session bus, or a
# frozen Hyprland IPC) would block this entire script -- and since
# SmartPlaybackService.qml's pollTimer guards against overlap
# (`if (!pollProc.running) pollProc.running = true`), a hung script
# means pollProc just never finishes, and screen-lock/monitor-sleep/
# gaming detection silently freeze at their last known value for as
# long as the shell stays open. Every command here now fails fast
# instead, so a single wedged tool degrades that one signal for this
# poll cycle rather than stalling the whole feature.
#
# Prints one line of JSON:
#   {"locked": false, "gaming": false, "sleeping": ["DP-1"]}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Generous relative to the "a few milliseconds" normal case, but small
# relative to the 3s poll interval -- a command that doesn't answer
# within this is treated as unavailable for this cycle, not waited on.
LW_SP_TIMEOUT=2

# ── Screen lock ───────────────────────────────────────────────────────────
# Prefer loginctl's own LockedHint (desktop-agnostic, works with any lock
# screen that reports it correctly via logind); fall back to checking
# for the Wayland lockers Hyprland users commonly reach for if loginctl
# isn't available or the session doesn't report the hint.
locked="false"
if command -v loginctl >/dev/null 2>&1; then
    me="${USER:-$(id -un 2>/dev/null)}"
    session_id="$(timeout "$LW_SP_TIMEOUT" loginctl show-user "$me" -p Display --value 2>/dev/null)"
    if [ -z "$session_id" ]; then
        session_id="$(timeout "$LW_SP_TIMEOUT" loginctl list-sessions --no-legend 2>/dev/null | awk -v u="$me" '$3 == u {print $1; exit}')"
    fi
    if [ -n "$session_id" ]; then
        hint="$(timeout "$LW_SP_TIMEOUT" loginctl show-session "$session_id" -p LockedHint --value 2>/dev/null)"
        [ "$hint" = "yes" ] && locked="true"
    fi
fi
if [ "$locked" = "false" ]; then
    # COMPATIBILITY: widened from the original hyprlock/swaylock-only
    # check to the fuller set of Wayland lockers actually seen on
    # Hyprland setups (swaylock-effects is a separate binary name from
    # swaylock; gtklock/waylock/i3lock are common alternate choices) --
    # a single pgrep with alternation, same cost as the old two-call
    # version. loginctl's LockedHint above already covers any locker
    # that reports it correctly, so this is only the fallback path.
    if pgrep -x 'hyprlock|swaylock|swaylock-effects|gtklock|waylock|i3lock' >/dev/null 2>&1; then
        locked="true"
    fi
fi

# ── GameMode ──────────────────────────────────────────────────────────────
# Feral Interactive's GameMode is the de-facto Linux signal for "a game
# is actively running" -- Steam, Lutris, Heroic, and most native
# launchers request it automatically for the duration of a play
# session. Best-effort only: if gamemoded/gdbus aren't installed this
# just always reports false, the same graceful degrade every other
# optional tool in this project already gets (inotifywait, notify-send,
# hyprctl, ...).
gaming="false"
if pgrep -x gamemoded >/dev/null 2>&1 && command -v gdbus >/dev/null 2>&1; then
    games="$(timeout "$LW_SP_TIMEOUT" gdbus call --session \
        --dest com.feralinteractive.GameMode \
        --object-path /com/feralinteractive/GameMode \
        --method com.feralinteractive.GameMode.ListGames 2>/dev/null)"
    case "$games" in
        *"([],)"*|*"(@a(is) [],)"*|""|*"([])"*) : ;;
        *) gaming="true" ;;
    esac
fi

# ── Monitor DPMS / sleep ──────────────────────────────────────────────────
# Not every Hyprland version reports dpmsStatus in `hyprctl monitors -j`;
# on ones that don't, jq's `select(.dpmsStatus == false)` simply matches
# nothing (null never equals false), so this degrades to "nothing
# reported as sleeping" rather than guessing.
sleeping_json="[]"
if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    probed="$(timeout "$LW_SP_TIMEOUT" hyprctl monitors -j 2>/dev/null | jq -c '[.[] | select(.dpmsStatus == false) | .name]' 2>/dev/null)"
    [ -n "$probed" ] && sleeping_json="$probed"
fi

if command -v jq >/dev/null 2>&1; then
    jq -nc --argjson locked "$locked" --argjson gaming "$gaming" --argjson sleeping "$sleeping_json" \
        '{locked: $locked, gaming: $gaming, sleeping: $sleeping}' 2>/dev/null \
        || echo '{"locked":false,"gaming":false,"sleeping":[]}'
else
    # jq missing entirely -- hand-roll the tiny fixed-shape JSON object
    # rather than skip reporting lock/gaming state too.
    echo "{\"locked\":$locked,\"gaming\":$gaming,\"sleeping\":$sleeping_json}"
fi
