#!/usr/bin/env bash
#
# stop_wallpaper.sh [monitor]
# -----------------------------------------------------------------------------
# Stop synchronously with start_wallpaper.sh using an operation PID lock.
# Uses per-monitor PID state, SIGTERM -> bounded wait -> SIGKILL.
# Does not guess arbitrary PIDs.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

lw_detect_distro() {
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        printf '%s\n' "${ID:-unknown}"
    else
        printf '%s\n' "unknown"
    fi
}

LW_DISTRO="$(lw_detect_distro)"
LW_ON_NIX=false
if command -v nix-store >/dev/null 2>&1 || [ -d /nix/store ] || [ -n "${IN_NIX_SHELL:-}" ]; then
    LW_ON_NIX=true
fi

if [ "$LW_ON_NIX" = true ]; then
    export PATH="$HOME/.nix-profile/bin:$HOME/.local/state/nix/profiles/profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$PATH"
fi
export PATH="$HOME/.local/bin:$SCRIPT_DIR:$PATH"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/utils.sh"

LW_OPERATION_LOCK_DIR="$LW_CACHE_DIR/locks/wallpaper-operation.lock"
LW_OPERATION_LOCK_TIMEOUT="${LW_OPERATION_LOCK_TIMEOUT:-6}"

lw_pid_alive() {
    local pid="${1:-}"
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
    [ "$pid" -ne 1 ] || return 1
    kill -0 "$pid" 2>/dev/null
}

lw_remove_own_operation_lock() {
    local owner=""
    [ -d "$LW_OPERATION_LOCK_DIR" ] || return 0
    owner="$(cat "$LW_OPERATION_LOCK_DIR/pid" 2>/dev/null || true)"
    [ "$owner" = "$$" ] || return 0
    rm -f "$LW_OPERATION_LOCK_DIR/pid" 2>/dev/null || true
    rmdir "$LW_OPERATION_LOCK_DIR" 2>/dev/null || true
}

lw_acquire_operation_lock() {
    local owner elapsed start
    start="$(date +%s 2>/dev/null || printf '0')"

    while :; do
        if mkdir -p "$(dirname "$LW_OPERATION_LOCK_DIR")" 2>/dev/null && \
           mkdir "$LW_OPERATION_LOCK_DIR" 2>/dev/null; then
            if ! printf '%s\n' "$$" > "$LW_OPERATION_LOCK_DIR/pid"; then
                rmdir "$LW_OPERATION_LOCK_DIR" 2>/dev/null || true
                return 1
            fi
            trap lw_remove_own_operation_lock EXIT INT TERM HUP
            return 0
        fi

        owner="$(cat "$LW_OPERATION_LOCK_DIR/pid" 2>/dev/null || true)"
        if [ -n "$owner" ] && ! lw_pid_alive "$owner"; then
            rm -rf "$LW_OPERATION_LOCK_DIR" 2>/dev/null || true
            continue
        fi

        elapsed=$(( $(date +%s 2>/dev/null || printf '0') - start ))
        if [ "$elapsed" -ge "$LW_OPERATION_LOCK_TIMEOUT" ]; then
            lw_log_warn "stop_wallpaper.sh: operation lock busy (pid=${owner:-unknown})"
            return 75
        fi
        sleep 0.05
    done
}

lw_read_valid_backend_pid() {
    local pid_file="$1"
    local pid comm cmdline

    [ -s "$pid_file" ] || return 1
    pid="$(tr -cd '0-9' < "$pid_file" 2>/dev/null | head -c 12)"
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
    [ "$pid" -ne 1 ] || return 1
    lw_pid_alive "$pid" || return 1

    comm="$(ps -o comm= -p "$pid" 2>/dev/null | tr -d '[:space:]' || true)"
    cmdline="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"

    # PID reuse protection: only kill process confirmed to be a wallpaper backend.
    case "$comm $cmdline" in
        *mpvpaper*|*chromium*|*chromium-browser*|*google-chrome*|*firefox*)
            printf '%s\n' "$pid"
            return 0
            ;;
        *)
            lw_log_warn "stop_wallpaper.sh: refusing PID '$pid' because process identity is not a known wallpaper backend (comm='$comm')"
            return 1
            ;;
    esac
}

lw_stop_tracked_pid() {
    local monitor="$1"
    local pid_file pid i
    pid_file="$(lw_monitor_state_file "$monitor" "pid")"

    if pid="$(lw_read_valid_backend_pid "$pid_file" 2>/dev/null)"; then
        lw_log_info "stop_wallpaper.sh: sending SIGTERM to pid=$pid (process group) monitor='$monitor'"
        rm -f "$pid_file"
        # Process-group signal, not just the tracked pid: this backend was
        # launched with `setsid`, so it's the leader of its own process
        # group. mpvpaper has no children so this is equivalent to before
        # for that case, but a chromium/firefox kiosk browser (also tracked
        # here -- see lw_read_valid_backend_pid's case above) forks
        # zygote/GPU/renderer children into that same group that would
        # otherwise be left running after the tracked pid alone was killed.
        # Falls back to a plain single-pid signal if -pid is ever rejected.
        kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true

        # 3-second graceful wait: avoid old layer-shell surface overlapping with
        # new one. Do not sleep indefinitely even if backend is stuck.
        for i in $(seq 1 30); do
            lw_pid_alive "$pid" || break
            sleep 0.1
        done

        if lw_pid_alive "$pid"; then
            lw_log_warn "stop_wallpaper.sh: pid=$pid ignored SIGTERM; escalating to SIGKILL (process group)"
            kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
            for i in $(seq 1 10); do
                lw_pid_alive "$pid" || break
                sleep 0.1
            done
        fi
    else
        # PID stale/malformed: clear state but never read an adjacent PID.
        rm -f "$pid_file"
    fi
}

lw_stop_one_monitor() {
    local monitor="$1"
    lw_cancel_inflight_apply_worker "$monitor"
    lw_stop_tracked_pid "$monitor"
    lw_stop_persistent_mpv "$monitor"
    lw_clear_awww_output "$monitor"
    rm -f "$(lw_monitor_state_file "$monitor" "current")"
    lw_write_apply_status \
        "$(lw_monitor_state_file "$monitor" "apply_status")" \
        "success" "" "Stopped"
}

MONITOR="${1:-}"
lw_ensure_dirs

lw_acquire_operation_lock || {
    echo "Wallpaper start/stop operation is busy; retry shortly." >&2
    exit 75
}

if [ -z "$MONITOR" ]; then
    # Snapshot list before stopping so hotplug doesn't change the loop
    # mid-flight. If the list cannot be retrieved, fall back to legacy/global slot.
    monitors="$(lw_list_active_monitors 2>/dev/null || true)"
    while IFS= read -r monitor; do
        [ -n "$monitor" ] || continue
        lw_stop_one_monitor "$monitor"
    done <<< "$monitors"

    lw_stop_one_monitor ""
    lw_kill_mpvpaper
    rm -f "$LW_CURRENT_FILE"
    lw_write_apply_status \
        "$(lw_monitor_state_file "" "apply_status")" \
        "success" "" "Stopped"
    lw_log_info "stop_wallpaper.sh: stopped wallpapers on all monitors (distro=$LW_DISTRO nix=$LW_ON_NIX)"
    echo "Stopped live wallpaper."
else
    lw_stop_one_monitor "$MONITOR"
    legacy_status_file="$LW_CACHE_DIR/apply_status"
    lw_write_apply_status "$legacy_status_file" "success" "" "Stopped"
    lw_log_info "stop_wallpaper.sh: stopped wallpaper on monitor '$MONITOR' (distro=$LW_DISTRO nix=$LW_ON_NIX)"
    echo "Stopped live wallpaper on $MONITOR."
fi
