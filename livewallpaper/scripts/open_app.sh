#!/usr/bin/env bash
#
# open_app.sh
# -----------
# Single entry point used by BOTH .desktop launchers (the panel and the
# Manager app window) to "open the app, starting the shell first if it
# isn't running yet". Replaces the old inline `bash -c "... || (... &
# sleep 1; ...)"` chain that used to live directly in the .desktop
# Exec= lines.
#
# WHY THIS EXISTS (bug this fixes):
# The previous version only waited a fixed `sleep 1` between starting a
# fresh `quickshell -c livewallpaper` process and retrying the IPC
# `open` call. On a cold start the shell has to parse/evaluate the full
# QML tree (Services, data/*.json, weather, etc.) before its IpcHandler
# targets are registered -- on a loaded system, over a slow disk, or on
# first run before caches are warm, that can take noticeably longer
# than 1 second. When it did, the single retry after `sleep 1` also
# failed, nothing reported the failure, and the launcher appeared to do
# nothing -- the user then had to start `quickshell -c livewallpaper`
# by hand in a terminal and THEN click the launcher again (by which
# point the shell was already up, so it worked). This script fixes
# that by polling the IPC call repeatedly for up to ~15s instead of
# trying exactly once after a fixed delay, and by logging a clear
# error if it genuinely never comes up so the failure isn't silent.
#
# Usage:
#   open_app.sh <ipc-target> <ipc-method>
#   open_app.sh livewallpaper open           # compact panel (default)
#   open_app.sh livewallpapermanager open    # full Manager window
#
# Both IPC methods are idempotent (calling "open" again just
# re-focuses/re-shows an already-open window), so retrying is safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"
lw_ensure_dirs

IPC_TARGET="${1:-livewallpaper}"
IPC_METHOD="${2:-open}"

# Recover WAYLAND_DISPLAY from the actual compositor socket on disk when
# it's missing from this process's environment (common for an icon/menu
# launch, as opposed to a terminal -- see lw_ensure_wayland_env() in
# utils.sh for the full rationale), and force QT_QPA_PLATFORM=wayland once
# we know a real Wayland session is running. No-op if WAYLAND_DISPLAY was
# already present, or if no Wayland session can be found at all.
lw_ensure_wayland_env
lw_log_info "open_app.sh: env WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-<unset>} XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-<unset>} QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-<unset>}"

_try_ipc() {
    quickshell -c livewallpaper ipc call "$IPC_TARGET" "$IPC_METHOD" >/dev/null 2>&1
}

# Fast path: shell is already running and responsive.
if _try_ipc; then
    exit 0
fi

# Slow path: start (or single-instance-guard-join) the shell, then poll
# for its IPC target to come up instead of trying exactly once after a
# fixed sleep. -n makes this a no-op join if another instance is
# already mid-startup (e.g. the user double-clicked the launcher).
lw_log_info "open_app.sh: '$IPC_TARGET.$IPC_METHOD' not responding, starting shell"
setsid "$SCRIPT_DIR/launch_quickshell.sh" -c livewallpaper -n < /dev/null > /dev/null 2>&1 &
disown

attempt=0
max_attempts=30      # 30 * 0.5s = 15s ceiling
until _try_ipc; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge "$max_attempts" ]; then
        lw_log_error "open_app.sh: '$IPC_TARGET.$IPC_METHOD' still not responding after ${max_attempts} attempts (~15s) -- giving up. Check $LW_LOG_FILE / crashes-under-pid for a startup crash."
        exit 1
    fi
    sleep 0.5
done

lw_log_info "open_app.sh: '$IPC_TARGET.$IPC_METHOD' succeeded after ${attempt} retr$([ "$attempt" = 1 ] && echo y || echo ies)"
exit 0
