#!/usr/bin/env bash
#
# utils.sh
# ---------
# Shared function library for all Live Wallpaper Manager scripts.
# Every other script MUST source this file first:
#
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/utils.sh"
#
# This is a straight port of the original Eww-era utils.sh. The bash/jq/
# ffmpeg/mpvpaper logic is unchanged; only the eww-specific "push to UI"
# calls have been removed, since the Quickshell frontend now watches the
# JSON files directly (FileView + watchChanges) instead of being poked by
# the scripts. Quickshell picks up every write these scripts make to
# wallpapers.json / history.json / settings.json / current automatically.

# ---------------------------------------------------------------------------
# CANONICAL PATHS (single source of truth for the whole project)
# ---------------------------------------------------------------------------
LW_CACHE_DIR="${LW_CACHE_DIR:-$HOME/.cache/livewallpaper}"
LW_THUMB_DIR="$LW_CACHE_DIR/thumbs"
LW_DATA_DIR="${LW_DATA_DIR:-$HOME/.config/quickshell/livewallpaper/data}"

LW_DB_FILE="$LW_DATA_DIR/wallpapers.json"
LW_SETTINGS_FILE="$LW_DATA_DIR/settings.json"
LW_HISTORY_FILE="$LW_DATA_DIR/history.json"
LW_HISTORY_FILE_LEGACY="$LW_CACHE_DIR/history.json" # pre-migration location

LW_CURRENT_FILE="$LW_CACHE_DIR/current"
LW_LAST_FILE="$LW_CACHE_DIR/last"
LW_RESOLUTION_FILE="$LW_CACHE_DIR/resolution"
LW_FPS_FILE="$LW_CACHE_DIR/fps"
LW_LOG_DIR="$LW_CACHE_DIR/logs"
LW_LOG_FILE="$LW_LOG_DIR/wallpaper.log"
LW_WATCHER_LOG_FILE="$LW_LOG_DIR/watcher.log"
LW_ERROR_LOG_FILE="$LW_LOG_DIR/error.log"
LW_STATE_DIR="$LW_CACHE_DIR/state"

# ---------------------------------------------------------------------------
# MULTI-MONITOR STATE
# ---------------------------------------------------------------------------
# Every monitor gets its own state directory under $LW_STATE_DIR/<name>/
# (current/last/resolution/fps/pid), so each output can play a different
# wallpaper independently, be stopped/started independently, and survive
# Quickshell restarts independently. The legacy top-level files above
# (LW_CURRENT_FILE etc, with no monitor in the path) are kept as-is and
# used as the "no monitor specified" / single-monitor fallback, so
# existing single-monitor setups and old callers keep working unchanged.
#
# lw_sanitize_monitor_name <name> -> filesystem-safe version (monitor names
# like "eDP-1"/"DP-2" are already safe, but this guards against exotic
# names with slashes/spaces from ever escaping $LW_STATE_DIR).
lw_sanitize_monitor_name() {
    echo "$1" | tr -c 'A-Za-z0-9_.-' '_'
}

# lw_monitor_state_dir <monitor> -> directory for that monitor's state
# (created on demand). Pass "" or "auto" for the legacy global (no
# specific monitor) state directory.
lw_monitor_state_dir() {
    local monitor="$1"
    if [ -z "$monitor" ] || [ "$monitor" = "auto" ]; then
        echo "$LW_CACHE_DIR" # legacy top-level files live directly here
        return
    fi
    local safe
    safe="$(lw_sanitize_monitor_name "$monitor")"
    local dir="$LW_STATE_DIR/$safe"
    mkdir -p "$dir"
    echo "$dir"
}

# lw_monitor_state_file <monitor> <kind>
# <kind> is one of: current, last, resolution, fps, pid, apply_status,
# worker_pid (worker_pid added alongside the apply-worker cancellation
# helpers below -- same per-monitor directory, no schema change).
lw_monitor_state_file() {
    local monitor="$1" kind="$2"
    local dir
    dir="$(lw_monitor_state_dir "$monitor")"
    echo "$dir/$kind"
}

# ---------------------------------------------------------------------------
# CRASH-SAFE ATOMIC WRITES -- shared primitive for every script that
# persists JSON (settings.json, wallpapers.json, history.json, apply
# status, ...) or other small state files. Guarantees, in order:
#
#   1. Content is written to a hidden temp file in the SAME DIRECTORY as
#      the target (never $TMPDIR/tmp) so the final rename is guaranteed to
#      land on the same filesystem. A cross-filesystem "mv" is NOT atomic
#      (it silently falls back to copy+unlink), which reopens exactly the
#      "reader sees a half-written file" window an atomic write exists to
#      close.
#   2. The temp file's data is fsync'd to disk BEFORE the rename, so a
#      crash/power loss immediately after the rename can never leave the
#      target pointing at a file whose bytes never actually reached disk
#      (a bare `mv` only guarantees ordering, not durability).
#   3. The rename itself is a single atomic filesystem operation -- every
#      reader (including Quickshell's FileView watchChanges) only ever
#      observes the fully-old or fully-new file, never a partial one.
#   4. The directory is fsync'd AFTER the rename, so the rename's
#      directory-entry update also survives a crash, not just the file's
#      data.
# ---------------------------------------------------------------------------

# lw_fsync_path <path>
# Best-effort durability flush for <path> (file or directory). Uses
# coreutils' `sync -f` (syncs only the filesystem containing <path>,
# available on modern Arch/util-linux coreutils) when present, falling
# back to a full `sync` otherwise. Never fails the caller's save over
# this -- the atomic rename (guarantee #3 above) already prevents
# corruption on its own; this only closes the "data not durable yet" gap
# for true power-loss safety.
lw_fsync_path() {
    local path="$1"
    [ -e "$path" ] || return 0
    if sync -f "$path" 2>/dev/null; then
        return 0
    fi
    sync 2>/dev/null
    return 0
}

# lw_atomic_tmp_for <target_file> -> prints the path of a fresh, empty,
# hidden temp file created in the SAME DIRECTORY as <target_file>
# (creating that directory first if needed). Same-directory placement is
# what makes the later rename onto <target_file> atomic.
lw_atomic_tmp_for() {
    local target="$1" dir
    dir="$(dirname "$target")"
    mkdir -p "$dir" || return 1
    mktemp "$dir/.$(basename "$target").XXXXXX"
}

# lw_atomic_commit <tmp_file> <target_file>
# Fsyncs <tmp_file>, atomically renames it onto <target_file>, then
# fsyncs the directory so the rename itself is durable too. On any
# failure the half-finished temp file is removed and <target_file> is
# left completely untouched -- callers never see a corrupt/truncated
# config as a result of this call.
lw_atomic_commit() {
    local tmp="$1" target="$2"
    if [ ! -f "$tmp" ]; then
        return 1
    fi
    lw_fsync_path "$tmp"
    if ! mv -f "$tmp" "$target"; then
        rm -f "$tmp"
        return 1
    fi
    lw_fsync_path "$target"
    return 0
}

# lw_write_text_atomic <file> <value>
# Write a small state value without exposing a truncated file to readers,
# and fsync before/after the rename so the write survives a crash or
# power loss, not just a clean process exit.
lw_write_text_atomic() {
    local file="$1" value="$2" tmp
    tmp="$(lw_atomic_tmp_for "$file")" || return 1
    if ! printf '%s\n' "$value" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    lw_atomic_commit "$tmp" "$file"
}

# lw_list_active_monitors -> newline-separated list of monitor names that
# have ever had a wallpaper applied to them (i.e. have a state directory),
# used by stop-all/status tooling and the multi-monitor UI.
lw_list_active_monitors() {
    [ -d "$LW_STATE_DIR" ] || return 0
    find "$LW_STATE_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null
}

# ---------------------------------------------------------------------------
# lw_cleanup_orphan_monitor_state
# Removes state directories for monitors that are no longer connected
# (unplugged, renamed by the compositor, etc) -- prevents
# ~/.cache/livewallpaper/state/ from accumulating dead entries forever.
# Safety: only removes a monitor's state if BOTH (a) it's not in the
# currently-connected monitor list, AND (b) its recorded pid (if any) is
# already dead -- never touches a monitor that's still legitimately
# connected, and never kills a still-running wallpaper just because
# detection hiccuped once.
# ---------------------------------------------------------------------------
lw_cleanup_orphan_monitor_state() {
    [ -d "$LW_STATE_DIR" ] || return 0
    command -v hyprctl >/dev/null 2>&1 || return 0

    local connected
    connected="$(hyprctl monitors -j 2>/dev/null | jq -r '.[].name' 2>/dev/null)"
    [ -z "$connected" ] && return 0 # couldn't determine -- don't guess, do nothing

    local dir name pid
    for dir in "$LW_STATE_DIR"/*/; do
        [ -d "$dir" ] || continue
        name="$(basename "$dir")"

        grep -qxF "$name" <<< "$connected" && continue # still connected, skip

        pid=""
        [ -s "$dir/pid" ] && pid="$(cat "$dir/pid" 2>/dev/null)"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            continue # still alive somehow -- leave it alone, don't kill blindly
        fi

        rm -rf "$dir"
        lw_log_info "lw_cleanup_orphan_monitor_state: removed stale state for disconnected monitor '$name'"
    done
}

LW_DEFAULT_WALLPAPER_DIR="$HOME/Pictures/Live Wallpaper"

# Wallpaper directory: read from settings.json ("wallpaper_directory") so it
# can be changed from the UI without rebuilding anything. Priority order:
#   1. LW_WALLPAPER_DIR env var (manual override, e.g. for testing)
#   2. "wallpaper_directory" in settings.json (changed by the user)
#   3. LW_DEFAULT_WALLPAPER_DIR
# jq stores the raw string, it does not expand "~" the way a shell does,
# so it's expanded by hand below.
if [ -n "${LW_WALLPAPER_DIR:-}" ]; then
    : # already overridden via env var, keep as-is
elif [ -s "$LW_SETTINGS_FILE" ] && command -v jq >/dev/null 2>&1; then
    LW_WALLPAPER_DIR="$(jq -r '.wallpaper_directory // empty' "$LW_SETTINGS_FILE" 2>/dev/null)"
fi
LW_WALLPAPER_DIR="${LW_WALLPAPER_DIR:-$LW_DEFAULT_WALLPAPER_DIR}"
case "$LW_WALLPAPER_DIR" in
    "~"|"~/"*) LW_WALLPAPER_DIR="${HOME}${LW_WALLPAPER_DIR#\~}" ;;
esac

# ---------------------------------------------------------------------------
# lw_write_apply_status <status_file> <state> <video> <message>
# <state> is one of: pending | success | error
# Used by apply_wallpaper.sh / _apply_worker.sh to report async progress to
# the QML side (which watches this file via FileView instead of blocking
# on the launching script).
# ---------------------------------------------------------------------------
lw_write_apply_status() {
    local status_file="$1" state="$2" video="$3" message="$4"
    local tmp
    tmp="$(lw_atomic_tmp_for "$status_file")" || return 1
    if ! jq -n \
        --arg state "$state" \
        --arg video "$video" \
        --arg message "$message" \
        --argjson ts "$(date +%s)" \
        '{state: $state, video: $video, message: $message, timestamp: $ts}' > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    lw_atomic_commit "$tmp" "$status_file"
}

lw_ensure_dirs() {
    mkdir -p "$LW_WALLPAPER_DIR" "$LW_THUMB_DIR" "$LW_DATA_DIR" "$LW_LOG_DIR"

    # One-time migration: history.json used to live under the disposable
    # cache dir, which meant "Clear Cache" silently wiped wallpaper
    # history too. It's user data, not throwaway cache, so it now lives
    # in $LW_DATA_DIR instead -- move it over the first time this runs
    # after upgrading, if the old file is still there and hasn't already
    # been migrated.
    if [ -s "$LW_HISTORY_FILE_LEGACY" ] && [ ! -s "$LW_HISTORY_FILE" ]; then
        mv "$LW_HISTORY_FILE_LEGACY" "$LW_HISTORY_FILE" 2>/dev/null
        lw_log_info "lw_ensure_dirs: migrated history.json from cache/ to data/ (Clear Cache no longer erases wallpaper history)"
    fi

    lw_json_validate_or_reset "$LW_DB_FILE" "[]"
    lw_json_validate_or_reset "$LW_HISTORY_FILE" "[]"
    # settings.json is NOT validated here -- it needs the full default
    # schema (theme/resolution/fps/hwdec/...), not a bare "{}". See
    # settings.sh, which validates it against DEFAULT_SETTINGS instead.
}

# ---------------------------------------------------------------------------
# lw_set_wallpaper_dir <new_path>
# Change the wallpaper directory: validate, create if missing, persist to
# settings.json. Does NOT refresh the database itself — the caller (e.g.
# change_directory.sh) is responsible for calling wallpaper_list.sh after.
# Prints "OK" on success, or an error message (+ exit 1) if the path is
# invalid (empty, or an existing file rather than a directory).
# ---------------------------------------------------------------------------
lw_set_wallpaper_dir() {
    local new_dir="$1"

    if [ -z "$new_dir" ]; then
        echo "Path must not be empty." >&2
        return 1
    fi

    case "$new_dir" in
        "~"|"~/"*) new_dir="${HOME}${new_dir#\~}" ;;
    esac

    if [ -e "$new_dir" ] && [ ! -d "$new_dir" ]; then
        echo "Path exists but is not a directory: $new_dir" >&2
        return 1
    fi

    # Serialize directory changes with settings.sh writes. The refresh is
    # performed by change_directory.sh after this function returns, so this
    # lock only covers the settings mutation itself.
    if ! lw_lock_or_skip "settings_db" 5; then
        echo "Settings are busy; please try again." >&2
        return 1
    fi

    mkdir -p "$new_dir" 2>/dev/null || {
        echo "Could not create directory (check write permission): $new_dir" >&2
        return 1
    }

    lw_json_init_if_missing "$LW_SETTINGS_FILE" '{}'
    local tmp
    tmp="$(lw_atomic_tmp_for "$LW_SETTINGS_FILE")" || {
        echo "Could not create a temp file for the settings write." >&2
        return 1
    }
    if ! jq --arg d "$new_dir" '.wallpaper_directory = $d' "$LW_SETTINGS_FILE" > "$tmp"; then
        rm -f "$tmp"
        echo "Failed to update settings.json" >&2
        return 1
    fi
    lw_atomic_commit "$tmp" "$LW_SETTINGS_FILE"

    lw_log_info "Wallpaper directory changed -> $new_dir"
    echo "OK"
}

# ---------------------------------------------------------------------------
# LOG — unified logging, easier to debug than every script echoing on its own.
# Usage: lw_log "info" "Applied wallpaper X"
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# LOG — unified, centralized logging.
#   logs/wallpaper.log -- everything (info + warn + error), the general log
#   logs/error.log     -- errors ONLY, for quick triage without scrolling
#   logs/watcher.log   -- dedicated to watch_wallpaper_dir.sh (via
#                          lw_log_watcher), since its output is chatty and
#                          usually only interesting when debugging
#                          auto-refresh specifically
#
# Every existing call site keeps working unchanged -- only WHERE these
# write changed (single livewallpaper.log -> logs/ directory), not their
# names or signatures.
# ---------------------------------------------------------------------------
lw_log() {
    local level="$1"; shift
    local msg="$*"
    mkdir -p "$LW_LOG_DIR"
    local line
    line="$(printf '[%s] [%s] %s' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$msg")"
    echo "$line" >> "$LW_LOG_FILE"
    [ "$level" = "ERROR" ] && echo "$line" >> "$LW_ERROR_LOG_FILE"
}

lw_log_info()  { lw_log "INFO"  "$*"; }
lw_log_warn()  { lw_log "WARN"  "$*"; }
lw_log_error() { lw_log "ERROR" "$*"; echo "$*" >&2; }

# lw_log_watcher <message> -- used only by watch_wallpaper_dir.sh, in
# addition to (not instead of) the general log above.
lw_log_watcher() {
    mkdir -p "$LW_LOG_DIR"
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LW_WATCHER_LOG_FILE"
    lw_log_info "$*"
}

# ---------------------------------------------------------------------------
# MONITOR — detect the focused monitor via hyprctl, fallback $MONITOR/eDP-1.
# ---------------------------------------------------------------------------
lw_detect_monitor() {
    local monitor="${MONITOR:-eDP-1}"
    if command -v hyprctl >/dev/null 2>&1; then
        local detected
        detected="$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused==true) | .name' 2>/dev/null)"
        [ -n "$detected" ] && monitor="$detected"
    fi
    echo "$monitor"
}

# ---------------------------------------------------------------------------
# MPVPAPER — kill safely, wait for confirmed death before returning control
# to the caller (avoids layer-shell surface contention that forced a
# double-click on Apply in earlier versions).
# ---------------------------------------------------------------------------
lw_kill_mpvpaper() {
    if ! pgrep -x mpvpaper >/dev/null 2>&1; then
        return 0
    fi

    pkill -x mpvpaper 2>/dev/null
    pkill -f "mpvpaper" 2>/dev/null

    local i
    for i in $(seq 1 20); do
        pgrep -x mpvpaper >/dev/null 2>&1 || break
        sleep 0.1
    done

    if pgrep -x mpvpaper >/dev/null 2>&1; then
        pkill -9 -x mpvpaper 2>/dev/null
        pkill -9 -f "mpvpaper" 2>/dev/null
        sleep 0.5
    fi

    # Give the compositor a moment to clean up the old layer-shell surface
    sleep 0.35
}

# ---------------------------------------------------------------------------
# lw_kill_pid_wait <pid>
# Send SIGTERM, then POLL (never a fixed sleep) until the pid is actually
# confirmed gone; escalate to SIGKILL and poll again if it ignores TERM.
# Shared by lw_kill_mpvpaper_for_monitor below (both its tracked-pid stop
# and its untracked-straggler sweep) so there is exactly one "stop a
# process and wait for its real exit" implementation instead of two
# near-duplicate copies drifting apart over time. No-op if the pid is
# already dead or empty.
# ---------------------------------------------------------------------------
lw_kill_pid_wait() {
    local pid="$1"
    [ -n "$pid" ] || return 0
    kill -0 "$pid" 2>/dev/null || return 0 # already dead

    kill "$pid" 2>/dev/null
    local i
    for i in $(seq 1 20); do
        kill -0 "$pid" 2>/dev/null || return 0
        sleep 0.1
    done

    kill -9 "$pid" 2>/dev/null
    for i in $(seq 1 10); do
        kill -0 "$pid" 2>/dev/null || return 0
        sleep 0.1
    done
}

# ---------------------------------------------------------------------------
# lw_kill_mpvpaper_for_monitor <monitor> [target_wallpaper]
# Multi-monitor-aware kill: stops ONLY the mpvpaper instance previously
# recorded as playing on <monitor> (via its state dir's "pid" file),
# leaving wallpapers on every other monitor untouched. A no-op if that
# monitor never had a recorded PID AND no untracked straggler is found
# below, rather than falling back to killing everything, which would
# defeat the point.
#
# [target_wallpaper] is optional, purely for the forensic log below --
# callers that know what video they were about to switch to (or start)
# may pass it so the log line captures BOTH sides of the switch.
#
# FORENSIC LOGGING: every call prints a full, impossible-to-miss block to
# both the log file AND stderr (so it shows up live in a terminal run,
# not just after the fact) before touching any process. This is
# intentionally loud -- meant to be grepped for "MPV KILL DETECTED"
# after a real A->B repro to get the exact call stack that triggered it.
# ---------------------------------------------------------------------------
lw_kill_mpvpaper_for_monitor() {
    local monitor="$1"
    local target_wallpaper="${2:-}"
    local pid_file
    pid_file="$(lw_monitor_state_file "$monitor" "pid")"

    local pid="" ppid="" current_wallpaper=""
    if [ -s "$pid_file" ]; then
        pid="$(cat "$pid_file" 2>/dev/null)"
        [ -n "$pid" ] && ppid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    fi
    local cur_file
    cur_file="$(lw_monitor_state_file "$monitor" "current")"
    [ -s "$cur_file" ] && current_wallpaper="$(cat "$cur_file" 2>/dev/null)"

    # Full call stack, not just the immediate caller -- walk every frame
    # bash has (FUNCNAME[0] is this function itself, so start at 1).
    local stack="" i frame
    for ((i = 1; i < ${#FUNCNAME[@]}; i++)); do
        frame="${FUNCNAME[$i]:-?}() @ ${BASH_SOURCE[$i]:-?}:${BASH_LINENO[$((i - 1))]:-?}"
        stack="${stack}  [$i] ${frame}"$'\n'
    done

    local forensic_block
    forensic_block="$(cat <<EOF
===== MPV KILL DETECTED =====
TIMESTAMP:         $(date '+%Y-%m-%d %H:%M:%S.%N')
PID:                ${pid:-<none tracked>}
PPID:               ${ppid:-<n/a>}
MONITOR:            ${monitor:-<default/legacy>}
CURRENT WALLPAPER:  ${current_wallpaper:-<unknown>}
TARGET WALLPAPER:   ${target_wallpaper:-<not provided by caller>}
CALLER:             ${FUNCNAME[1]:-?}() @ ${BASH_SOURCE[1]:-?}:${BASH_LINENO[0]:-?}
BASH_SOURCE[0]:     ${BASH_SOURCE[0]:-?}
FUNCNAME:           ${FUNCNAME[*]:-?}
BASH_LINENO:        ${BASH_LINENO[*]:-?}
FULL CALL STACK:
${stack}=============================
EOF
)"
    # Both the log file (for later grep) and stderr (visible live if run
    # from a terminal, e.g. `bash apply_wallpaper.sh ... 2>&1 | tee ...`).
    lw_log_info "$forensic_block"
    printf '%s\n' "$forensic_block" >&2

    if [ -n "$pid" ]; then
        rm -f "$pid_file"
        lw_kill_pid_wait "$pid"
    fi

    # ── Defense-in-depth: untracked-straggler sweep ─────────────────────
    # A superseding request can cancel an in-flight apply/stream/web
    # worker (see lw_cancel_inflight_apply_worker) at almost any point in
    # its lifecycle -- including the brief window after it has already
    # spawned mpvpaper via setsid (a deliberately separate session, so it
    # survives the worker script that launched it -- see
    # lw_launch_mpvpaper) but before that worker finished writing the new
    # pid to pid_file. Such a process would be invisible to the
    # tracked-pid stop above and could otherwise linger as a second,
    # untracked mpvpaper on this monitor. Sweep for any mpvpaper whose
    # argv names this exact monitor -- an exact, whole-argv-token match
    # (never a substring, so "DP-1" can never accidentally match "DP-11")
    # -- and stop those too. Skipped for the legacy "no specific monitor"
    # slot (monitor "" or "auto"), which lw_kill_mpvpaper's blanket sweep
    # already covers at its call sites.
    if [ -n "$monitor" ] && [ "$monitor" != "auto" ]; then
        local stray_pid
        for stray_pid in $(pgrep -x mpvpaper 2>/dev/null); do
            if cat "/proc/$stray_pid/cmdline" 2>/dev/null | tr '\0' '\n' | grep -qx -- "$monitor"; then
                lw_log_warn "MPV KILL: untracked straggler pid=$stray_pid matched monitor='$monitor' argv -- stopping it too (caller=[${FUNCNAME[1]:-?}() @ ${BASH_SOURCE[1]:-?}])"
                lw_kill_pid_wait "$stray_pid"
            fi
        done
    fi

    # Give the compositor a moment to clean up the old layer-shell surface
    sleep 0.35
}

# ---------------------------------------------------------------------------
# lw_log_mpv_start <monitor> <pid> <video> <caller_desc>
# Companion forensic log to the kill block above -- fired from
# lw_launch_mpvpaper right after it confirms a new mpvpaper pid came up.
# Captures start time (from /proc, not just "now") so a real repro can
# compare it against the previous instance's start time and prove
# whether it's really a NEW process or the same one misread as new.
# ---------------------------------------------------------------------------
lw_log_mpv_start() {
    local monitor="$1" pid="$2" video="$3" caller_desc="$4"
    local ppid="" starttime=""
    ppid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    if [ -r "/proc/$pid/stat" ]; then
        starttime="$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null)"
    fi
    local block
    block="$(cat <<EOF
===== MPV START =====
TIMESTAMP:   $(date '+%Y-%m-%d %H:%M:%S.%N')
PID:         $pid
PPID:        ${ppid:-<n/a>}
START_TICKS: ${starttime:-<n/a>} (jiffies since boot, from /proc/$pid/stat field 22 -- compare across switches to prove same-vs-new process)
MONITOR:     ${monitor:-<default/legacy>}
VIDEO:       $video
CALLER:      $caller_desc
======================
EOF
)"
    lw_log_info "$block"
    printf '%s\n' "$block" >&2
}


# ---------------------------------------------------------------------------
# lw_cancel_inflight_apply_worker <monitor>
# Cancels a still-running _apply_worker.sh previously dispatched for
# <monitor> (if any). apply_wallpaper.sh dispatches a background worker and
# returns immediately (see its header comment) -- without this, spamming
# Apply/Next/Previous/Random/Stop on the same monitor could leave two or
# more workers alive at once, each independently calling
# lw_kill_mpvpaper_for_monitor + lw_launch_mpvpaper_retry, which raced to
# kill/launch mpvpaper out of order (flicker, wasted GPU/CPU spinning up
# videos nobody will see, and an apply_status write-race between workers).
# Called by apply_wallpaper.sh (before dispatching a new worker) and
# stop_wallpaper.sh (before killing mpvpaper), so only ever ONE worker is
# ever in flight per monitor.
#
# Only ever touches the worker's own pid (a background bash script) --
# NEVER mpvpaper itself, which is a separately-detached process (see
# lw_launch_mpvpaper's own `setsid mpvpaper ...` -- a second, independent
# session) specifically so it keeps playing even after the worker script
# that launched it exits. lw_kill_mpvpaper_for_monitor remains the only
# thing that ever stops mpvpaper.
#
# Bounded wait (~0.5s max) before giving up and forcefully killing it --
# never blocks the caller anywhere near as long as a full
# lw_kill_mpvpaper wait would.
# ---------------------------------------------------------------------------
lw_cancel_inflight_apply_worker() {
    local monitor="$1"
    local pid_file
    pid_file="$(lw_monitor_state_file "$monitor" "worker_pid")"

    [ -s "$pid_file" ] || return 0
    local pid
    pid="$(cat "$pid_file" 2>/dev/null)"
    rm -f "$pid_file"

    [ -n "$pid" ] || return 0
    kill -0 "$pid" 2>/dev/null || return 0 # already finished on its own

    lw_log_info "lw_cancel_inflight_apply_worker: canceling in-flight apply worker process group (pid $pid) on monitor '$monitor' -- a newer request superseded it"
    # apply_wallpaper.sh starts the worker with setsid. Kill the whole worker
    # process group, not only the bash parent: shell substitutions and helper
    # processes may otherwise keep inherited flock descriptors open after the
    # parent is gone, leaving apply_monitor_<monitor> locked for the next
    # wallpaper selection.
    kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null
    local i
    for i in $(seq 1 10); do
        if ! kill -0 -- "-$pid" 2>/dev/null && ! kill -0 "$pid" 2>/dev/null; then
            break
        fi
        sleep 0.05
    done
    kill -9 -- "-$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null
    # Give the group a short bounded window to disappear so inherited
    # descriptors from a helper cannot race the next Apply.
    for i in $(seq 1 10); do
        if ! kill -0 -- "-$pid" 2>/dev/null && ! kill -0 "$pid" 2>/dev/null; then
            break
        fi
        sleep 0.05
    done
}

# ---------------------------------------------------------------------------
# LOCKING -- prevents overlapping runs of scripts that must never race each
# other: a full directory scan started twice at once (spam-clicking
# Refresh, or the auto-watcher firing mid manual-refresh), or concurrent
# can pile up. Backed by flock(1)
# against a per-<name> lock file under $LW_CACHE_DIR/locks -- works across
# separate process invocations (not just background jobs of one shell),
# and always releases automatically when the holding process exits or is
# killed, so there is no stale-lock cleanup to worry about (unlike a
# hand-rolled pidfile lock).
# ---------------------------------------------------------------------------
LW_LOCK_DIR="$LW_CACHE_DIR/locks"

# lw_lock_file <name> -> path of that lock's file (parent dir created on
# demand).
lw_lock_file() {
    mkdir -p "$LW_LOCK_DIR" 2>/dev/null
    local safe_name
    safe_name="$(lw_sanitize_monitor_name "$1")"
    echo "$LW_LOCK_DIR/$safe_name.lock"
}

# lw_try_lock <name> [wait_seconds]
# Attempts to acquire the named lock, waiting up to [wait_seconds] (default
# 0 = fail immediately if already held) for it to free up. On success, the
# lock is held for the rest of THIS PROCESS's lifetime (released
# automatically on exit, including a crash/kill -9) and this returns 0. On
# failure it returns 1 -- does NOT exit, so callers decide what "couldn't
# get the lock" means for them.
lw_try_lock() {
    local name="$1" wait_seconds="${2:-0}"
    local lockfile fd_var
    lockfile="$(lw_lock_file "$name")"
    # Dynamic fd-variable name (via eval) so more than one named lock can
    # be held at once by the same script without one `exec {fd}>...`
    # clobbering another's fd.
    fd_var="LW_LOCK_FD_${name//[^A-Za-z0-9_]/_}"
    eval "exec {$fd_var}>\"\$lockfile\"" 2>/dev/null || return 1
    if eval "flock -w \"\$wait_seconds\" \"\$$fd_var\""; then
        return 0
    fi
    # A failed flock leaves the just-opened descriptor in this process.
    # Close it before the next retry so rapid Apply handoffs cannot
    # accumulate descriptors while waiting for the old worker to exit.
    local failed_fd="${!fd_var:-}"
    if [[ "$failed_fd" =~ ^[0-9]+$ ]]; then
        eval "exec ${failed_fd}>&-" 2>/dev/null || true
    fi
    unset "$fd_var"
    return 1
}

# lw_unlock <name>
# Release a lock before this process exits. Most locks are intentionally held
# until process exit, but the control-fence lock is only needed while claiming
# a per-monitor lock.
lw_unlock() {
    local name="$1" fd_var fd
    fd_var="LW_LOCK_FD_${name//[^A-Za-z0-9_]/_}"
    fd="${!fd_var:-}"
    if [[ "$fd" =~ ^[0-9]+$ ]]; then
        eval "exec ${fd}>&-" 2>/dev/null || true
    fi
    unset "$fd_var"
}

# Claim a monitor control lock without holding the global Stop-All fence for
# the duration of the operation. The fence prevents Stop-All from starting
# while this lock is being claimed; after the per-monitor lock is acquired,
# independent monitors can proceed concurrently.
lw_lock_control_monitor() {
    local monitor="$1" wait_seconds="${2:-5}"
    local monitor_lock="apply_monitor_${monitor:-auto}"
    if ! lw_try_lock "apply_all" "$wait_seconds"; then
        return 1
    fi
    if ! lw_try_lock "$monitor_lock" "$wait_seconds"; then
        lw_unlock "apply_all"
        return 1
    fi
    lw_unlock "apply_all"
}
# lw_lock_or_skip <name> [wait_seconds]
# Convenience wrapper for the common "if I can't get this lock quickly,
# just get out of the way" case. Logs + returns 1 if the lock couldn't be
# acquired within [wait_seconds] (default 0); returns 0 on success. Callers
# that need to exit 0 quietly on failure.
# never leave wallpapers.json touched -- or even attempted -- when it
# can't run) still do that themselves; this only handles the locking part.
lw_lock_or_skip() {
    local name="$1" wait_seconds="${2:-0}"
    if lw_try_lock "$name" "$wait_seconds"; then
        return 0
    fi
    lw_log_info "lw_lock_or_skip: '$name' is already locked by another instance -- skipping this run"
    return 1
}

# ---------------------------------------------------------------------------
# lw_resolution_to_height <resolution> -> prints just the target height in
# pixels (e.g. "1080"), or empty for "original"/unmatched. Shared by
# lw_resolution_to_scale (mpv scale filter).
# ---------------------------------------------------------------------------
lw_resolution_to_height() {
    case "$1" in
        480p)  echo "480" ;;
        720p)  echo "720" ;;
        1080p) echo "1080" ;;
        2k|2K)  echo "1440" ;;
        4k|4K) echo "2160" ;;
        *) echo "" ;;
    esac
}

# ---------------------------------------------------------------------------
# lw_resolution_to_scale <resolution> -> prints the "scale=-2:H" filter
# fragment (WITHOUT the "vf=" prefix), or empty if "original"/unmatched.
# No prefix because it still needs to be merged with the fps filter into a
# single "vf=" string (see lw_launch_mpvpaper) — mpv only accepts one "vf="
# flag per run; a second one OVERWRITES the first rather than stacking.
# ---------------------------------------------------------------------------
lw_resolution_to_scale() {
    local height
    height="$(lw_resolution_to_height "$1")"
    [ -n "$height" ] && echo "scale=-2:$height" || echo ""
}

# ---------------------------------------------------------------------------
# lw_fps_to_filter <fps> -> prints the "fps=N" filter fragment used to CAP
# the playback frame rate (mpv interpolates/drops frames to match), or
# empty for "original"/unmatched (keep the video's native fps, no filter).
#
# Note: this is the PLAYBACK fps (can be forced lower to save battery/CPU),
# distinct from the video's native fps shown on each card (read via
# ffprobe, informational only, not adjustable).
# ---------------------------------------------------------------------------
lw_fps_to_filter() {
    case "$1" in
        24) echo "fps=24" ;;
        30) echo "fps=30" ;;
        60) echo "fps=60" ;;
        *)  echo "" ;;
    esac
}

# ---------------------------------------------------------------------------
# lw_launch_mpvpaper <video> <monitor> <resolution> <fps> [extra_mpv_opts]
# Launch mpvpaper via hyprctl dispatch exec (so Hyprland parents the
# process), falling back to setsid. Prints "true"/"false" depending on
# whether it came up (polls pgrep for up to 1.5s).
# ---------------------------------------------------------------------------
lw_launch_mpvpaper() {
    local video="$1" monitor="$2" resolution="$3" fps="${4:-original}" extra="${5:-}"
    local scale_part fps_part vf_combined mpv_opts

    scale_part="$(lw_resolution_to_scale "$resolution")"
    fps_part="$(lw_fps_to_filter "$fps")"

    vf_combined=""
    if [ -n "$scale_part" ] && [ -n "$fps_part" ]; then
        vf_combined="vf=${scale_part},${fps_part}"
    elif [ -n "$scale_part" ]; then
        vf_combined="vf=${scale_part}"
    elif [ -n "$fps_part" ]; then
        vf_combined="vf=${fps_part}"
    fi

    # Hardware decoding was previously hard-disabled (hwdec=no), which is
    # the safest setting across GPU drivers but forces the CPU to decode
    # every frame in software -- for 4K/60fps videos this is the single
    # biggest source of playback lag/dropped frames. "auto-safe" asks mpv
    # to negotiate hardware decoding only through codec/driver
    # combinations known not to crash, falling back to software
    # automatically if unavailable -- noticeably smoother on most systems
    # while keeping the same crash-safety guarantee "no" was chosen for.
    #
    # Configurable via settings.json's "hwdec" key if it ever causes
    # trouble on a particular GPU:
    #   scripts/settings.sh set hwdec no          # back to the old safe default
    #   scripts/settings.sh set hwdec auto-safe   # default (recommended)
    #   scripts/settings.sh set hwdec auto        # more aggressive, may be less stable
    local hwdec="auto-safe"
    if [ -s "$LW_SETTINGS_FILE" ] && command -v jq >/dev/null 2>&1; then
        local configured_hwdec
        configured_hwdec="$(jq -r '.hwdec // empty' "$LW_SETTINGS_FILE" 2>/dev/null)"
        [ -n "$configured_hwdec" ] && hwdec="$configured_hwdec"
    fi
    # NOTE: earlier revisions of this function force-disabled hwdec
    # whenever a resolution/fps filter (vf=scale/fps) was in play, on the
    # theory that hw-decoded frames + software-only vf filters don't mix
    # well. That was never confirmed against a real mpvpaper.log, and in
    # practice it just forced 4K source videos through *software* decode
    # at every non-native resolution/fps setting -- which is what drove a
    # weak CPU to 96C/80% load. hwdec + vf=scale is a normal, well-
    # supported combination in mpv, so that override has been removed.
    # If a specific resolution/fps combo genuinely fails, the fix belongs
    # in mpv's actual reported error (now captured in mpvpaper.log with a
    # "Command:" header), not in blanket-disabling hwdec.

    # GPU render profile: mpv's built-in "fast" profile swaps the default
    # high-quality scalers (spline36/ewa_lanczos, sigmoid upscaling, etc.)
    # for cheap bilinear ones and disables dithering/interpolation. Those
    # high-quality filters are meant for something you actively watch and
    # pause on -- for an always-on, looping background video sitting behind
    # every window, they're wasted GPU shader work running 24/7. This is
    # the biggest single lever for reducing sustained GPU usage/heat/power
    # on weaker iGPUs, on top of the hwdec change above.
    #
    # Configurable via settings.json's "gpu_profile" key:
    #   scripts/settings.sh set gpu_profile fast      # default (recommended, lowest GPU load)
    #   scripts/settings.sh set gpu_profile default    # mpv's normal quality/perf balance
    #   scripts/settings.sh set gpu_profile quality     # mpv's "gpu-hq" profile, highest quality/GPU cost
    local gpu_profile="fast"
    if [ -s "$LW_SETTINGS_FILE" ] && command -v jq >/dev/null 2>&1; then
        local configured_profile
        configured_profile="$(jq -r '.gpu_profile // empty' "$LW_SETTINGS_FILE" 2>/dev/null)"
        [ -n "$configured_profile" ] && gpu_profile="$configured_profile"
    fi

    mpv_opts="loop no-audio hwdec=$hwdec"
    case "$gpu_profile" in
        fast)    mpv_opts="$mpv_opts profile=fast" ;;
        quality) mpv_opts="$mpv_opts profile=gpu-hq" ;;
        *)       : ;; # "default"/unrecognized -- leave mpv's own defaults alone
    esac
    [ -n "$vf_combined" ] && mpv_opts="$mpv_opts $vf_combined"
    [ -n "$extra" ] && mpv_opts="$mpv_opts $extra"

    # ── IPC socket (single-persistent-mpv reuse) ─────────────────────────
    # Exposes mpv's JSON IPC protocol on this monitor's socket, exactly
    # like _stream_worker.sh already does for Streaming mode -- but here
    # it backs lw_mpv_try_reuse (below), which lets a later wallpaper
    # change on this monitor swap the file in place instead of killing
    # and relaunching mpvpaper. Purely additive: nothing about the launch
    # itself changes, and an old mpv build without IPC support simply
    # leaves reuse inert (lw_mpv_try_reuse degrades to "false", i.e. the
    # normal kill+relaunch path, exactly like today).
    local mpv_ipc_sock
    mpv_ipc_sock="$(lw_monitor_state_file "$monitor" "mpv_ipc")"
    rm -f "$mpv_ipc_sock" 2>/dev/null
    mpv_opts="$mpv_opts input-ipc-server=$mpv_ipc_sock"

    # ------------------------------------------------------------------
    # GPU SWITCHING (wallpaper-only) -- which physical GPU mpvpaper
    # renders on. This is env-vars-for-this-one-process ONLY (DRI_PRIME /
    # NVIDIA PRIME render-offload) -- it never changes system PRIME, udev,
    # Xorg/Hyprland config, or any other process's GPU. See gpu_manager.sh
    # for the full explanation and resolution logic.
    #
    # Configurable via settings.json's "gpu_mode" key (written by
    # GPUManagerService.qml's selector, GPU Manager > GPU dropdown):
    #   auto | intel | amd | nvidia | power-saving | high-performance
    # "auto" (default) -- no override, byte-for-byte the same launch as
    # before this feature existed.
    #
    # gpu_manager.sh is the single source of truth for resolving a mode to
    # an actual GPU. If it can't resolve one (removed hardware, missing
    # driver, unknown mode, ...) it prints nothing and exits non-zero --
    # that is treated as "no override" here, same as "auto". This function
    # NEVER fails a launch over a GPU-selection problem; GPUManagerService
    # is responsible for detecting an unavailable selection ahead of time,
    # resetting it to Auto, and notifying the user.
    # ------------------------------------------------------------------
    local gpu_mode="auto"
    if [ -s "$LW_SETTINGS_FILE" ] && command -v jq >/dev/null 2>&1; then
        gpu_mode="$(jq -r '.gpu_mode // "auto"' "$LW_SETTINGS_FILE" 2>/dev/null)"
    fi
    if [ -z "$gpu_mode" ] || [ "$gpu_mode" = "null" ]; then
        gpu_mode="auto"
    fi
    local gpu_env_assignments="" gpu_env_line
    local -a gpu_env_array=()
    if [ "$gpu_mode" != "auto" ] && [ -n "${SCRIPT_DIR:-}" ] && [ -x "$SCRIPT_DIR/gpu_manager.sh" ]; then
        gpu_env_assignments="$("$SCRIPT_DIR/gpu_manager.sh" env "$gpu_mode" 2>>"$LW_ERROR_LOG_FILE")"
        if [ -n "$gpu_env_assignments" ]; then
            while IFS= read -r gpu_env_line; do
                [ -n "$gpu_env_line" ] && gpu_env_array+=("$gpu_env_line")
            done <<< "$gpu_env_assignments"
        fi
    fi

    # mpvpaper's own output (its real crash/error reason: bad codec,
    # monitor not found, no free GPU surface, etc.) used to be thrown away
    # to /dev/null, which meant the only thing anyone ever saw was our own
    # generic "exited immediately" message. Captured here instead so
    # apply_wallpaper.sh can surface the actual reason.
    local mpv_log="$LW_CACHE_DIR/mpvpaper.log"
    mkdir -p "$LW_CACHE_DIR"
    {
        printf '=== %s ===\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        if [ "${#gpu_env_array[@]}" -gt 0 ]; then
            printf 'GPU mode: %s (%s)\n' "$gpu_mode" "${gpu_env_array[*]}"
        fi
        printf 'Command: mpvpaper -f -o %q %q %q\n' "$mpv_opts" "$monitor" "$video"
    } > "$mpv_log"

    # Snapshot PIDs before launching so that, once mpvpaper comes up, we can
    # tell exactly WHICH pid is the one we just started -- essential for
    # multi-monitor, where several mpvpaper processes run concurrently and
    # "pgrep -x mpvpaper" alone can't distinguish between them.
    local before_pids
    before_pids="$(pgrep -x mpvpaper 2>/dev/null)"

    local launched_via_hyprctl=false
    local method_file="$LW_CACHE_DIR/launch_method"
    local known_method=""
    [ -s "$method_file" ] && known_method="$(cat "$method_file")"

    # Only attempt hyprctl if we don't already know it fails on this
    # system. Once we've determined "direct" works and "hyprctl" doesn't,
    # every subsequent Apply/Next/Previous/Random skips straight to the
    # direct launch instead of wasting ~1.5s probing hyprctl again first
    # -- this was the main source of the "delay before it plays" feeling.
    # Delete ~/.cache/livewallpaper/launch_method (or run cache.sh clear)
    # to make it re-probe, e.g. after a Hyprland upgrade.
    if [ "$known_method" != "direct" ] && command -v hyprctl >/dev/null 2>&1 && [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
        # `hyprctl dispatch exec "<string>"` behavior around quoting/redirection
        # varies across Hyprland versions -- some tokenize the string
        # themselves instead of handing it to a real shell, which silently
        # swallowed our "> logfile 2>&1" redirect (mpvpaper still launched,
        # but its output went nowhere, hence "No output captured").
        #
        # Sidestepping that entirely: write a tiny, real bash script to disk
        # and tell Hyprland to exec THAT (a single path, zero quoting
        # ambiguity). The script itself is interpreted by bash via its
        # shebang, so its own quotes/redirects are guaranteed to work
        # exactly like any other bash script.
        local launcher="$LW_CACHE_DIR/launch_mpvpaper.sh"
        {
            printf '#!/usr/bin/env bash\n'
            printf 'exec'
            if [ "${#gpu_env_array[@]}" -gt 0 ]; then
                printf ' env'
                local le
                for le in "${gpu_env_array[@]}"; do
                    printf ' %q' "$le"
                done
            fi
            printf ' mpvpaper -f -o %q %q %q >> %q 2>&1\n' \
                "$mpv_opts" "$monitor" "$video" "$mpv_log"
        } > "$launcher"
        chmod +x "$launcher"

        hyprctl dispatch exec "$launcher" >/dev/null 2>&1
        launched_via_hyprctl=true

        # Give the IPC-dispatched launch a short window; if mpvpaper still
        # isn't running by then (some Hyprland versions/configs don't
        # dispatch `exec` reliably for arbitrary scripts), fall through to
        # a direct launch below instead of waiting out the full timeout
        # for nothing.
        local j
        for j in $(seq 1 15); do
            pgrep -x mpvpaper >/dev/null 2>&1 && break
            sleep 0.1
        done
    fi

    # "Did THIS launch come up" now means "is there a mpvpaper pid that
    # wasn't in before_pids", not just "does any mpvpaper exist" -- with
    # multi-monitor, other monitors' mpvpaper instances are already
    # running and must not be mistaken for this one.
    lw_new_mpvpaper_pid() {
        comm -13 <(printf '%s\n' "$before_pids" | sort -u) \
                 <(pgrep -x mpvpaper 2>/dev/null | sort -u) 2>/dev/null | head -1
    }

    if [ -n "$(lw_new_mpvpaper_pid)" ]; then
        [ "$launched_via_hyprctl" = "true" ] && echo "hyprctl" > "$method_file"
    else
        if [ "$launched_via_hyprctl" = "true" ]; then
            lw_log_warn "lw_launch_mpvpaper: hyprctl dispatch exec did not bring mpvpaper up, falling back to a direct launch (remembering this for next time)"
        fi
        if [ "${#gpu_env_array[@]}" -gt 0 ]; then
            setsid env "${gpu_env_array[@]}" mpvpaper -f -o "$mpv_opts" "$monitor" "$video" \
                >> "$mpv_log" 2>&1 < /dev/null &
        else
            setsid mpvpaper -f -o "$mpv_opts" "$monitor" "$video" \
                >> "$mpv_log" 2>&1 < /dev/null &
        fi
        disown
        echo "direct" > "$method_file"
    fi

    local i new_pid=""
    # mpvpaper needs real time to connect to the compositor, create an
    # EGL/OpenGL context, and parse the demuxer -- for large/high-fps
    # videos (4K60, etc.) this routinely takes several seconds on first
    # launch. The old 1.5s window was too short: it would conclude
    # "failed" and kill a wallpaper that was still mid-startup, then retry
    # and kill it again, never actually giving it a chance to finish.
    for i in $(seq 1 80); do
        new_pid="$(lw_new_mpvpaper_pid)"
        if [ -n "$new_pid" ]; then
            lw_write_text_atomic "$(lw_monitor_state_file "$monitor" "pid")" "$new_pid"
            # Record what this mpv instance was actually launched with, so
            # a later lw_mpv_try_reuse call can tell whether the settings
            # that can ONLY take effect at process start (hwdec, GPU
            # render profile, which physical GPU it's running on) still
            # match before trusting IPC reuse over a full relaunch.
            lw_mpv_write_launch_sig "$monitor" "mode=wallpaper"
            lw_log_mpv_start "$monitor" "$new_pid" "$video" "${FUNCNAME[1]:-?}() @ ${BASH_SOURCE[1]:-?}"
            echo true
            return
        fi
        sleep 0.1
    done
    echo false
}

# ---------------------------------------------------------------------------
# lw_launch_mpvpaper_retry <video> <monitor> <resolution> <fps> [max_attempts]
# Calls lw_launch_mpvpaper with automatic retry (increasing backoff) so the
# user doesn't have to click Apply a second time. Prints "true"/"false".
# ---------------------------------------------------------------------------
lw_launch_mpvpaper_retry() {
    local video="$1" monitor="$2" resolution="$3" fps="${4:-original}" max_attempts="${5:-3}"
    local attempt result
    for attempt in $(seq 1 "$max_attempts"); do
        result="$(lw_launch_mpvpaper "$video" "$monitor" "$resolution" "$fps")"
        if [ "$result" = "true" ]; then
            echo true
            return
        fi
        # Clean up only what THIS attempt may have half-started on THIS
        # monitor (via its recorded pid, if lw_launch_mpvpaper got that
        # far) -- never a blanket pkill, which would also kill wallpapers
        # already happily running on other monitors.
        lw_kill_mpvpaper_for_monitor "$monitor" "$video"
        sleep "$attempt"
    done
    echo false
}

# ---------------------------------------------------------------------------
# lw_mpv_write_launch_sig <monitor> <mode_sig>
# Records what an mpv instance was launched with: the settings that can
# only take effect at process start (hwdec / GPU render profile / which
# physical GPU) plus <mode_sig> -- an opaque string the CALLER builds,
# capturing whatever else was baked into that specific launch (e.g.
# "mode=wallpaper", or "mode=stream loop=yes mute=no quality=auto").
# Shared by lw_launch_mpvpaper, _stream_worker.sh, and _web_worker.sh so
# the three call sites can't drift out of sync.
#
# NOTE: lw_mpv_try_reuse no longer gates reuse on this matching -- a
# wallpaper/stream/web switch is never turned into a kill+relaunch just
# because these process-start-only settings differ from what's tracked
# here. This is now purely a DIAGNOSTIC record (surfaced in
# lw_mpv_try_reuse's log lines) of what the currently-alive process was
# actually started with, kept for troubleshooting -- not a decision input.
# ---------------------------------------------------------------------------
lw_mpv_write_launch_sig() {
    local monitor="$1" mode_sig="$2"
    local hwdec="auto-safe" gpu_profile="fast" gpu_mode="auto" gpu_env_assignments=""
    if [ -s "$LW_SETTINGS_FILE" ] && command -v jq >/dev/null 2>&1; then
        local v
        v="$(jq -r '.hwdec // empty' "$LW_SETTINGS_FILE" 2>/dev/null)"; [ -n "$v" ] && hwdec="$v"
        v="$(jq -r '.gpu_profile // empty' "$LW_SETTINGS_FILE" 2>/dev/null)"; [ -n "$v" ] && gpu_profile="$v"
        v="$(jq -r '.gpu_mode // "auto"' "$LW_SETTINGS_FILE" 2>/dev/null)"; [ -n "$v" ] && [ "$v" != "null" ] && gpu_mode="$v"
    fi
    if [ "$gpu_mode" != "auto" ] && [ -n "${SCRIPT_DIR:-}" ] && [ -x "$SCRIPT_DIR/gpu_manager.sh" ]; then
        gpu_env_assignments="$("$SCRIPT_DIR/gpu_manager.sh" env "$gpu_mode" 2>>"$LW_ERROR_LOG_FILE")"
    fi
    lw_write_text_atomic "$(lw_monitor_state_file "$monitor" "launch_sig")" \
        "hwdec=$hwdec profile=$gpu_profile gpu_mode=$gpu_mode gpu_env=${gpu_env_assignments// /,} $mode_sig"
}

# ---------------------------------------------------------------------------
# lw_mpv_try_reuse <video> <monitor> <resolution> <fps> [mode_sig]
# Changes the wallpaper on <monitor> by sending the already-running mpv
# instance a "loadfile" + updated video filter over its IPC socket (see
# the "IPC socket" block in lw_launch_mpvpaper above). Prints "true"/
# "false".
#
# ARCHITECTURE: as long as the tracked mpv PID is alive, this function
# NEVER gives its caller a reason to kill it. The only thing that ever
# makes it print "false" is the tracked mpv genuinely not being there to
# reuse in the first place (nothing tracked yet, or the tracked pid has
# actually exited) -- that is the ONLY case in which a caller (e.g.
# _apply_worker.sh) may go on to launch a fresh mpv. Every other kind of
# trouble (missing/stale socket, unanswered ping, a rejected/slow IPC
# command) is retried in place against the SAME live process; if all
# retries are exhausted the pid is still left completely alone and this
# still prints "false" -- callers must treat that as "could not update
# the wallpaper this time", never as "kill and relaunch", for as long as
# `kill -0 "$pid"` keeps succeeding. See lw_mpv_try_reuse's callers
# (_apply_worker.sh, _stream_worker.sh, _web_worker.sh) for how they
# honor this.
#
# What used to be here: an extra check that the CURRENTLY RUNNING
# instance's launch-time settings (hwdec / GPU render profile / which
# physical GPU / <mode_sig>, see lw_mpv_write_launch_sig) still matched
# what this call would need, falling back to a full relaunch on any
# mismatch. That is deliberately no longer a reuse blocker: a wallpaper
# FILE switch (Next/Previous/Random/manual/auto-rotation/playlist/preset)
# must never be turned into a kill+relaunch just because those
# process-start-only settings differ -- the file changes via IPC either
# way, on the SAME pid. (One direct consequence: a hwdec/GPU-profile/GPU-
# mode change made via Settings while a wallpaper is already playing only
# fully takes effect the next time mpv is actually restarted for another
# reason -- explicit Stop, app exit, or a genuine crash -- not silently
# mid-play. That's an accepted trade-off of never killing a live mpv for
# a normal switch.)
#
# <mode_sig> is still recorded at launch time (lw_mpv_write_launch_sig)
# purely for diagnostics/logging -- it no longer gates whether reuse is
# attempted.
# ---------------------------------------------------------------------------
lw_mpv_try_reuse() {
    local video="$1" monitor="$2" resolution="$3" fps="${4:-original}"
    local mode_sig="${5:-mode=wallpaper}"
    local py="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}/_mpv_ipc.py"
    local caller_desc="${FUNCNAME[1]:-?}() @ ${BASH_SOURCE[1]:-?}"

    command -v python3 >/dev/null 2>&1 || {
        lw_log_warn "MPV IPC LOAD: monitor='$monitor' SKIP reason=no-python3 caller=[$caller_desc]"
        echo false; return
    }
    [ -x "$py" ] || [ -f "$py" ] || {
        lw_log_warn "MPV IPC LOAD: monitor='$monitor' SKIP reason=mpv-ipc-helper-missing caller=[$caller_desc]"
        echo false; return
    }

    # 1) The ONLY gate that may return "false" and let the caller launch a
    # fresh mpv: is there even a tracked mpv for this monitor, and is it
    # actually alive? Everything past this point retries against THIS
    # exact pid and never disqualifies it for any other reason.
    local pid_file pid
    pid_file="$(lw_monitor_state_file "$monitor" "pid")"
    if [ ! -s "$pid_file" ]; then
        lw_log_info "MPV IPC LOAD: monitor='$monitor' -> false reason=no-tracked-pid caller=[$caller_desc] (nothing to reuse -- launch is the correct fallback)"
        echo false; return
    fi
    pid="$(cat "$pid_file" 2>/dev/null)"
    if ! { [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; }; then
        lw_log_info "MPV IPC LOAD: monitor='$monitor' pid=$pid -> false reason=pid-not-alive caller=[$caller_desc] (process already gone -- launch is the correct fallback)"
        echo false; return
    fi

    # Build the vf filter lw_launch_mpvpaper would use for this
    # resolution/fps, once, outside the retry loop below.
    local scale_part fps_part vf_combined
    scale_part="$(lw_resolution_to_scale "$resolution")"
    fps_part="$(lw_fps_to_filter "$fps")"
    if [ -n "$scale_part" ] && [ -n "$fps_part" ]; then
        vf_combined="${scale_part},${fps_part}"
    elif [ -n "$scale_part" ]; then
        vf_combined="$scale_part"
    elif [ -n "$fps_part" ]; then
        vf_combined="$fps_part"
    else
        vf_combined=""
    fi

    local sock
    sock="$(lw_monitor_state_file "$monitor" "mpv_ipc")"

    # WALLPAPER-SWITCH FIX -- requested pre-switch trace: PID, socket,
    # current wallpaper, target wallpaper, logged once before any retry
    # is attempted, so a real repro can be lined up against the
    # per-attempt lines below.
    local current_file target_desc
    current_file="$(lw_monitor_state_file "$monitor" "current")"
    target_desc="pid=$pid sock='$sock' current='$([ -s "$current_file" ] && cat "$current_file" 2>/dev/null)' target='$video'"
    lw_log_info "MPV IPC LOAD: monitor='$monitor' $target_desc caller=[$caller_desc] -- starting switch"

    # 2) Reconnect/retry loop against the SAME live pid. A missing/stale
    # socket file, an unanswered ping, or a loadfile that isn't acked in
    # time are all treated as TRANSIENT (mpv briefly busy tearing down the
    # old file's decoder, compositor hiccup, a socket that hasn't been
    # (re)created yet, ...) rather than as "give up and kill it" -- retried
    # in place a bounded number of times before this finally reports
    # "false" (pid still left completely alone either way).
    local attempt max_attempts=6 retry_delay=0.3
    for attempt in $(seq 1 "$max_attempts"); do
        # The pid could have exited mid-retry (crash between attempts) --
        # re-check every pass so a dead process is reported honestly
        # instead of retrying against nothing.
        if ! kill -0 "$pid" 2>/dev/null; then
            lw_log_info "MPV IPC LOAD: monitor='$monitor' pid=$pid -> false reason=pid-died-during-retry attempt=$attempt caller=[$caller_desc] (launch is the correct fallback)"
            echo false; return
        fi

        if [ ! -S "$sock" ]; then
            lw_log_info "MPV IPC LOAD: monitor='$monitor' pid=$pid -> retry reason=no-ipc-socket attempt=$attempt/$max_attempts sock='$sock' caller=[$caller_desc]"
            sleep "$retry_delay"
            continue
        fi

        if ! python3 "$py" "$sock" ping >/dev/null 2>&1; then
            lw_log_info "MPV IPC LOAD: monitor='$monitor' pid=$pid -> retry reason=ipc-ping-failed attempt=$attempt/$max_attempts sock='$sock' caller=[$caller_desc]"
            sleep "$retry_delay"
            continue
        fi

        # WALLPAPER-SWITCH FIX -- do not trust a bare "the command was
        # accepted" any more. _mpv_ipc.py's apply-wallpaper now reads
        # mpv's "path" property back after loadfile and only exits 0
        # when that readback actually equals the requested video
        # (path_verified) -- see handle_apply_wallpaper() there for
        # why (loadfile can be acked as "success" by mpv's IPC layer
        # while the file mpvpaper is actually displaying never changes,
        # e.g. if mpvpaper's own render loop doesn't pick up the
        # reconfigure). Capture the JSON regardless of exit status so
        # a real failure can be told apart (in the logs) from a
        # transient one: "acked but not verified" vs "not acked at
        # all" are different problems and worth distinguishing when
        # troubleshooting on real hardware.
        local ipc_result path_verified loadfile_acked reported_path vf_applied
        ipc_result="$(python3 "$py" "$sock" apply-wallpaper "$video" "$vf_combined" 2>/dev/null)"
        path_verified="$(printf '%s' "$ipc_result" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("path_verified"))
except Exception:
    print("unknown")' 2>/dev/null)"
        if [ "$path_verified" = "True" ]; then
            loadfile_acked="$(printf '%s' "$ipc_result" | python3 -c 'import json,sys
print(json.load(sys.stdin).get("loadfile_acked"))' 2>/dev/null)"
            reported_path="$(printf '%s' "$ipc_result" | python3 -c 'import json,sys
print(json.load(sys.stdin).get("reported_path"))' 2>/dev/null)"
            vf_applied="$(printf '%s' "$ipc_result" | python3 -c 'import json,sys
print(json.load(sys.stdin).get("vf_applied"))' 2>/dev/null)"
            lw_log_info "MPV IPC LOAD: monitor='$monitor' pid=$pid -> true video='$video' vf='$vf_combined' loadfile_acked=$loadfile_acked path_verified=true reported_path='$reported_path' vf_applied=$vf_applied attempt=$attempt/$max_attempts caller=[$caller_desc] (same PID reused, no kill/relaunch)"
            echo true
            return
        fi

        lw_log_info "MPV IPC LOAD: monitor='$monitor' pid=$pid -> retry reason=loadfile-acked-but-not-verified path_verified=$path_verified attempt=$attempt/$max_attempts video='$video' raw='$ipc_result' caller=[$caller_desc]"
        sleep "$retry_delay"
    done

    lw_log_warn "MPV IPC LOAD: monitor='$monitor' pid=$pid -> false reason=ipc-retries-exhausted attempts=$max_attempts video='$video' caller=[$caller_desc] (pid still alive -- left untouched, NOT killed; caller must not relaunch while this pid is alive)"
    echo false
}

# ===========================================================================
# PERSISTENT-MPV CONTRACT (wallpaper mode)
# ===========================================================================
# Three deliberately separate entry points for the normal local-wallpaper
# path. This is a structural guarantee, not just a behavioral one: a normal
# A->B/B->C wallpaper switch can ONLY ever call lw_switch_wallpaper_via_ipc,
# which has no kill/pkill/terminate anywhere in its body or anything it
# calls. The only function in this whole file that is allowed to terminate
# mpvpaper is lw_stop_persistent_mpv (== lw_kill_mpvpaper_for_monitor) --
# and it is called from exactly two places: stop_wallpaper.sh (explicit
# user Stop) and lw_start_persistent_mpv's own dead-process cleanup below
# (which only ever touches a PID it has already confirmed is not alive).
# ===========================================================================

# ---------------------------------------------------------------------------
# lw_switch_wallpaper_via_ipc <video> <monitor> <resolution> <fps> [mode_sig]
# THE only function a normal wallpaper change (Next/Previous/Random/manual/
# auto-rotation/playlist/preset) may call. Sends loadfile over IPC to
# whatever mpv is already tracked as alive for <monitor>. Prints
# "true"/"false" -- "false" means "could not update this time", never
# "go kill it". Contains no kill/pkill/terminate call, directly or
# transitively (thin wrapper over lw_mpv_try_reuse, which is already held
# to that same guarantee -- see its own header comment above).
# ---------------------------------------------------------------------------
lw_switch_wallpaper_via_ipc() {
    lw_mpv_try_reuse "$@"
}

# ---------------------------------------------------------------------------
# lw_start_persistent_mpv <video> <monitor> <resolution> <fps>
# Starts MPV ONLY when no live player exists for <monitor>. Callers must
# already have established this (via kill -0 on the tracked pid, or
# lw_switch_wallpaper_via_ipc having reported "false" with the pid
# confirmed dead) before calling this -- it is not itself a decision
# point about whether to kill anything live.
#
# Defensive check: if this is ever called while a tracked pid is still
# genuinely alive (a caller bug), it refuses to touch that live process
# and reports the situation instead of killing it -- consistent with
# "if MPV is still alive, it must remain alive" applying everywhere, not
# just in the paths that are supposed to check first.
# ---------------------------------------------------------------------------
lw_start_persistent_mpv() {
    local video="$1" monitor="$2" resolution="$3" fps="${4:-original}"
    local pid_file pid
    pid_file="$(lw_monitor_state_file "$monitor" "pid")"
    if [ -s "$pid_file" ]; then
        pid="$(cat "$pid_file" 2>/dev/null)"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            lw_log_warn "lw_start_persistent_mpv: called with pid=$pid still ALIVE on monitor='$monitor' -- this is a caller bug (should have used lw_switch_wallpaper_via_ipc). Refusing to touch the live process; NOT starting a second one, NOT killing it."
            echo false
            return
        fi
    fi
    # Confirmed: nothing live to preserve. Clear any stale tracking entry
    # for this monitor (a dead pid, or a straggler process from a prior
    # failed launch attempt -- see lw_kill_mpvpaper_for_monitor's own
    # comment) before starting the one real player.
    lw_kill_mpvpaper_for_monitor "$monitor" "$video"
    lw_launch_mpvpaper_retry "$video" "$monitor" "$resolution" "$fps" 3
}

# ---------------------------------------------------------------------------
# lw_stop_persistent_mpv <monitor>
# The ONLY normal-path function allowed to terminate mpvpaper. Callers:
# stop_wallpaper.sh (explicit user Stop / app shutdown) only. Never call
# this from a wallpaper-switch code path.
# ---------------------------------------------------------------------------
lw_stop_persistent_mpv() {
    lw_kill_mpvpaper_for_monitor "$@"
}

# ---------------------------------------------------------------------------
# JSON HELPERS
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# lw_json_init_if_missing <file> <empty_value: "[]" or "{}">
lw_json_init_if_missing() {
    local file="$1" empty="${2:-[]}"
    if [ ! -s "$file" ]; then
        mkdir -p "$(dirname "$file")"
        echo "$empty" > "$file"
    fi
}

# ---------------------------------------------------------------------------
# lw_json_validate_or_reset <file> <default_value>
# Validates that <file> contains parseable JSON via jq. If it's missing,
# empty, or corrupt, it's replaced with <default_value> (a backup of the
# corrupt content is kept alongside as "<file>.corrupt" for inspection,
# rather than silently discarding it). Never lets a broken JSON file crash
# a script that reads it downstream -- called at the start of any script
# that reads wallpapers.json/settings.json/history.json.
# ---------------------------------------------------------------------------
lw_json_validate_or_reset() {
    local file="$1" default_value="$2"

    if [ ! -s "$file" ]; then
        mkdir -p "$(dirname "$file")"
        echo "$default_value" > "$file"
        return 0
    fi

    if ! jq empty "$file" >/dev/null 2>&1; then
        lw_log_error "lw_json_validate_or_reset: $file is corrupt/invalid JSON -- restoring default (corrupt copy saved as $file.corrupt)"
        cp "$file" "$file.corrupt" 2>/dev/null
        echo "$default_value" > "$file"
        return 1
    fi

    return 0
}

# lw_file_hash <path> -> content-derived SHA-256 ID used as a stable
# wallpaper/thumbnail name. Content identity means a rename does not lose
# the record, while replacing a file at the same path gets a new ID.
lw_file_hash() {
    sha256sum "$1" | cut -d' ' -f1
}

# ---------------------------------------------------------------------------
# HISTORY — record the wallpaper that was just applied, used for next/
# previous and "Recently Used". Capped at the 50 most recent records.
# ---------------------------------------------------------------------------
lw_add_history() {
    local video="$1"
    # Applies on different monitors can complete together. Serialize the
    # read/merge/replace cycle so one recent entry cannot overwrite another.
    lw_lock_or_skip "wallpaper_history" 10 || return 1
    lw_json_init_if_missing "$LW_HISTORY_FILE" "[]"
    local tmp
    tmp="$(lw_atomic_tmp_for "$LW_HISTORY_FILE")" || return 1
    # Note: deliberately NOT using unique_by(.path) here — jq's unique_by
    # SORTS the result by that field (alphabetically by path), which would
    # destroy the "most recent first" order that "Recently Used" needs.
    # Instead: group by path, keep the record with the newest timestamp per
    # path, then sort by timestamp descending.
    if jq --arg path "$video" --arg ts "$(date +%s)" '
        ([{path: $path, timestamp: ($ts | tonumber)}] + .)
        | group_by(.path)
        | map(max_by(.timestamp))
        | sort_by(-.timestamp)
        | .[0:50]
    ' "$LW_HISTORY_FILE" > "$tmp" 2>/dev/null; then
        lw_atomic_commit "$tmp" "$LW_HISTORY_FILE"
    else
        rm -f "$tmp"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# lw_recent_wallpapers <limit>
# Prints a JSON array of the <limit> most recently applied wallpapers
# (joined against the database for name/thumb/metadata), newest first.
# Wallpapers deleted from disk (no longer in the database) are silently
# skipped instead of showing a broken card.
# ---------------------------------------------------------------------------
lw_recent_wallpapers() {
    local limit="${1:-5}"
    lw_json_init_if_missing "$LW_HISTORY_FILE" "[]"
    lw_json_init_if_missing "$LW_DB_FILE" "[]"

    jq -n \
        --argjson history "$(cat "$LW_HISTORY_FILE")" \
        --argjson db "$(cat "$LW_DB_FILE")" \
        --argjson limit "$limit" '
        ($db | map({(.path): .}) | add) as $by_path |
        [$history[] | select($by_path[.path] != null) | ($by_path[.path] + {last_used: .timestamp})]
        | .[0:$limit]
    '
}

# ---------------------------------------------------------------------------
# NAVIGATION — next/previous/random share logic: take the path list in
# database order, find the current video's position, return the
# next/previous/random path. Prints empty if the database is empty or has
# only one video.
#
# lw_neighbor_wallpaper <direction> [monitor]
# [monitor] given -> reference THAT monitor's current/last wallpaper as
# the starting point (multi-monitor: each output steps through the
# library independently). [monitor] omitted -> legacy global
# current/last, i.e. original single-monitor behavior.
# ---------------------------------------------------------------------------
lw_neighbor_wallpaper() {
    local direction="$1"  # "next" | "previous" | "random"
    local monitor="${2:-}"
    lw_json_init_if_missing "$LW_DB_FILE" "[]"

    local current_file="$LW_CURRENT_FILE" last_file="$LW_LAST_FILE"
    if [ -n "$monitor" ]; then
        current_file="$(lw_monitor_state_file "$monitor" "current")"
        last_file="$(lw_monitor_state_file "$monitor" "last")"
        # Fall back to legacy global if this monitor has no history yet
        [ ! -s "$current_file" ] && [ ! -s "$last_file" ] && [ -s "$LW_LAST_FILE" ] && last_file="$LW_LAST_FILE"
    fi

    local current=""
    [ -s "$current_file" ] && current="$(cat "$current_file")"
    [ -z "$current" ] && [ -s "$last_file" ] && current="$(cat "$last_file")"

    case "$direction" in
        random)
            local rest_count rand_idx
            rest_count="$(jq -r --arg cur "$current" '[.[] | select(.path != $cur)] | length' "$LW_DB_FILE")"
            if [ "$rest_count" -eq 0 ] 2>/dev/null; then
                jq -r '.[0].path // empty' "$LW_DB_FILE"
            else
                rand_idx=$(( RANDOM % rest_count ))
                jq -r --arg cur "$current" --argjson idx "$rand_idx" '
                    [.[] | select(.path != $cur)][$idx].path
                ' "$LW_DB_FILE"
            fi
            ;;
        next|previous)
            jq -r --arg cur "$current" --arg dir "$direction" '
                map(.path) as $paths |
                ($paths | length) as $n |
                if $n == 0 then empty
                else
                    (($paths | index($cur)) // -1) as $idx |
                    (if $idx == -1 then 0
                     elif $dir == "next" then ($idx + 1) % $n
                     else ($idx - 1 + $n) % $n
                     end) as $target |
                    $paths[$target]
                end
            ' "$LW_DB_FILE"
            ;;
    esac
}
