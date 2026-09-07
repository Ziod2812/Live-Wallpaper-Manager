#!/usr/bin/env bash
#
# launch_debian_wayland_safe.sh
# ------------------------------
# Kept as a standalone diagnostic/manual-launch helper (see
# docs/DEBIAN_WAYLAND_STARTUP.md). Despite the filename this is not
# Debian-specific: the same WAYLAND_DISPLAY gaps (missing entirely for an
# icon/menu launch, or leaking QT_QPA_PLATFORM=xcb into a real Wayland
# session) happen on Arch, Fedora and Ubuntu too, so this uses the same
# lw_ensure_wayland_env() recovery as launch_quickshell.sh and open_app.sh.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/utils.sh"
lw_ensure_wayland_env

exec quickshell -c livewallpaper "$@"
