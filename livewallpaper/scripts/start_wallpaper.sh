#!/usr/bin/env bash
#
# start_wallpaper.sh [monitor]
# -----------------------------------------------------------------------------
# Restart the most recent wallpaper for an output. Focuses on solving
# start/stop races with an atomic PID-operation lock outside the
# source/Nix Store.

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

# NixOS GUI launcher sometimes does not pass a full profile PATH.
if [ "$LW_ON_NIX" = true ]; then
    export PATH="$HOME/.nix-profile/bin:$HOME/.local/state/nix/profiles/profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$PATH"
fi
export PATH="$HOME/.local/bin:$SCRIPT_DIR:$PATH"

# Dynamic temp: ưu tiên XDG_RUNTIME_DIR cho runtime user data; fallback TMPDIR,
# cuối cùng /tmp. Tuyệt đối không cố ghi vào /nix/store.
lw_runtime_tmp_dir() {
    local candidate
    for candidate in "${XDG_RUNTIME_DIR:-}" "${TMPDIR:-}" "/tmp"; do
        [ -n "$candidate" ] || continue
        [ -d "$candidate" ] || continue
        [ -w "$candidate" ] || continue
        printf '%s\n' "$candidate"
        return 0
    done
    return 1
}

export LW_RUNTIME_TMP_DIR="${LW_RUNTIME_TMP_DIR:-$(lw_runtime_tmp_dir 2>/dev/null || printf '%s' '/tmp')}"

# Đọc utils sau khi PATH đã được normalize để binary lookup nhất quán trên
# Arch/Fedora/Debian/Ubuntu/NixOS.
# shellcheck disable=SC1091
source "$SCRIPT_DIR/utils.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/path_hardening.sh"

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
        # mkdir là thao tác atomic trên cùng filesystem.
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
            # Chỉ reclaim stale PID khi kill -0 xác nhận owner đã chết.
            rm -rf "$LW_OPERATION_LOCK_DIR" 2>/dev/null || true
            continue
        fi

        elapsed=$(( $(date +%s 2>/dev/null || printf '0') - start ))
        if [ "$elapsed" -ge "$LW_OPERATION_LOCK_TIMEOUT" ]; then
            lw_log_warn "start_wallpaper.sh: operation lock busy (pid=${owner:-unknown})"
            return 75
        fi
        sleep 0.05
    done
}

MONITOR="${1:-}"
[ -n "$MONITOR" ] || MONITOR="$(lw_detect_monitor)"

lw_ensure_dirs

lw_acquire_operation_lock || {
    echo "Wallpaper start/stop operation is busy; retry shortly." >&2
    exit 75
}

last_file="$(lw_monitor_state_file "$MONITOR" "last")"
resolution_file="$(lw_monitor_state_file "$MONITOR" "resolution")"
fps_file="$(lw_monitor_state_file "$MONITOR" "fps")"

if [ ! -s "$last_file" ] && [ -s "$LW_LAST_FILE" ]; then
    last_file="$LW_LAST_FILE"
    resolution_file="$LW_RESOLUTION_FILE"
    fps_file="$LW_FPS_FILE"
fi

if [ ! -s "$last_file" ]; then
    lw_log_warn "start_wallpaper.sh: no wallpaper history for monitor '$MONITOR'"
    echo "No wallpaper was previously selected. Pick one from the list first." >&2
    exit 1
fi

VIDEO="$(cat "$last_file" 2>/dev/null || true)"
RESOLUTION="1080p"
FPS="original"
[ -s "$resolution_file" ] && RESOLUTION="$(cat "$resolution_file" 2>/dev/null || printf '1080p')"
[ -s "$fps_file" ] && FPS="$(cat "$fps_file" 2>/dev/null || printf 'original')"

# Security boundary đặt trước apply_worker. realpath -e sẽ resolve symlink cuối
# cùng, kể cả khi một generation của Nix cung cấp symlink động.
if ! VIDEO="$(lw_harden_wallpaper_path "$VIDEO" 2>/dev/null)"; then
    lw_log_error "start_wallpaper.sh: rejected wallpaper path: ${VIDEO:-<empty>}"
    echo "Error: wallpaper path is outside the configured wallpaper directory." >&2
    exit 1
fi

# Distro/compositor checks chỉ fail-fast khi thiếu Wayland. Hyprland/KWin đều
# có thể chạy Wayland; script apply chịu trách nhiệm chọn backend chi tiết.
if ! lw_wayland_session_ok; then
    status_file="$(lw_monitor_state_file "$MONITOR" "apply_status")"
    lw_wayland_required_error "$status_file" "$VIDEO"
    exit 1
fi

# Quan trọng: KHÔNG exec trực tiếp trước khi release lock. Nếu release trước,
# stop_wallpaper.sh có thể chen vào đúng cửa sổ giữa start và apply_wallpaper.sh,
# khiến Stop hoàn tất rồi Start mới kịp ghi worker_pid -> race quay trở lại.
# Chạy apply như child để operation lock bao trọn cả bước dispatch worker,
# sau đó mới release lock. Worker decode/video thật sự vẫn chạy detached.

# PERFORMANCE FIX: kill any stale mpvpaper for this monitor BEFORE launching
# the new one. Without this, the old process leaks until its own stop() runs,
# burning GPU and causing a brief freeze when the new mpvpaper attaches to
# a display already occupied by the orphan.
_last="$(cat "$last_file" 2>/dev/null || true)"
if [ -n "$_last" ]; then
    _old_pid="$(cat "$(lw_monitor_state_file "$MONITOR" "pid")" 2>/dev/null || true)"
    if [ -n "$_old_pid" ] && kill -0 "$_old_pid" 2>/dev/null; then
        lw_log_info "start_wallpaper.sh: killing stale pid $_old_pid for monitor $MONITOR before start"
        kill -TERM "$_old_pid" 2>/dev/null || true
        sleep 0.2
        kill -KILL "$_old_pid" 2>/dev/null || true
    fi
fi
unset _last _old_pid

"$SCRIPT_DIR/apply_wallpaper.sh" "$VIDEO" "$RESOLUTION" "$FPS" "$MONITOR"
rc=$?
trap - EXIT INT TERM HUP
lw_remove_own_operation_lock
exit "$rc"
