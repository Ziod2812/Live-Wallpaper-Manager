#!/usr/bin/env bash
#
# launch_quickshell.sh
# ---------------------
# Thin, self-contained wrapper around the `quickshell` binary. Every place
# that starts a *new* quickshell process (desktop entries, XDG autostart,
# Hyprland exec-once/hl.on, the tray "reopen" fallback, restart_app.sh,
# update.sh) execs THIS script instead of calling `quickshell` directly, so
# the fix below only has to live in one place.
#
# WHY THIS EXISTS:
# Some setups (a line in fish's config.fish, a PAM/environment.d file, a
# terminal emulator profile, etc.) export QT_QPA_PLATFORM=xcb -- or leave
# it unset in a context where Qt's own auto-detection guesses wrong -- even
# inside a real Wayland session. Separately, a process started by an app
# launcher's icon (as opposed to a terminal) does not always inherit
# WAYLAND_DISPLAY at all, depending on how the desktop environment spawns
# .desktop Exec= commands -- see lw_ensure_wayland_env() in utils.sh, which
# recovers it from the actual compositor socket on disk when that happens,
# rather than trusting the environment to have propagated it correctly.
# Either gap means Quickshell's Wayland-native surfaces (wlroots
# layer-shell, session-lock) cannot initialize, and the process either
# segfaults natively during QML finalization a few seconds after launch
# (crashes-under-pid/*, "crashed within 10 seconds of launching") or, if
# WAYLAND_DISPLAY was missing outright, fails to start at all with no
# visible output. This is an environment misconfiguration, not a bug in
# this app's QML/scripts -- but since it's an easy trap to fall into and
# hard to self-diagnose, we defend against both cases here rather than
# requiring every user to track them down by hand.
#
# Policy: whenever we're actually inside a real Wayland session --
# WAYLAND_DISPLAY is set, OR a live wayland-N socket can be found on disk
# even if the environment didn't propagate it -- ALWAYS force
# QT_QPA_PLATFORM=wayland for this app's own quickshell process,
# regardless of whatever value it currently has (unset, "xcb",
# "wayland;xcb", or anything else). This app has no supported X11/xcb
# code path, so there is no case where a real Wayland session should
# launch it under anything but the wayland backend. This is identical
# across Arch, Fedora, Debian and Ubuntu (and any other distro) -- the
# decision is based purely on the live session, never on distro
# detection.
# If no Wayland session can be found at all (a genuine X11-only session,
# or a TTY with no session at all), QT_QPA_PLATFORM is left completely
# untouched.
#
# set -uo pipefail (not -e) to match the convention every other script
# that sources utils.sh uses in this project -- utils.sh's top level runs
# a fair amount of setup code that isn't written to be safe under -e.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/utils.sh"
lw_ensure_wayland_env

exec quickshell "$@"
