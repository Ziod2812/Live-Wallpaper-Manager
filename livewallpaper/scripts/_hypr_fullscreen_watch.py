#!/usr/bin/env python3
"""
_hypr_fullscreen_watch.py
-------------------------------------------------------
Internal helper for smart_playback_watch.sh -- not meant to be run by
hand.

Connects to Hyprland's own IPC EVENT socket (socket2 -- a plain unix
socket at $XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock)
and blocks on it. This is a real event stream, not a poll loop: the
process sits idle (recv() blocked in the kernel) using ~0 CPU for as
long as nothing on screen changes, and reacts the instant Hyprland
reports something relevant -- exactly the "prefer Hyprland events over
continuous polling" requirement for Smart Playback's fullscreen
detection.

Whenever a fullscreen-relevant event arrives, recomputes -- via two
cheap `hyprctl -j` calls, never a busy loop -- which monitors currently
have a fullscreen window as the active window of their visible
workspace, and prints ONE line of JSON to stdout, but ONLY when that
result actually changed from the last line printed, e.g.:

    {"DP-1": true, "eDP-1": false}

Services/SmartPlaybackService.qml reads this line-by-line (a
Quickshell.Io SplitParser on the launching Process's stdout) and merges
it into fullscreenMonitors -- see that file for what happens next
(fully stopping/restoring PlaybackService's wallpaper via
PlaybackService's smartStop/StartWallpaperOnMonitor primitives).
"""
import json
import os
import socket
import subprocess
import sys

RELEVANT_EVENTS = (
    "fullscreen>>",
    "activewindow>>",
    "activewindowv2>>",
    "workspace>>",
    "workspacev2>>",
    "moveworkspace>>",
    "movewindow>>",
    "monitoraddremoved>>",
    "focusedmon>>",
    "closewindow>>",
)


def socket_path():
    runtime = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    return os.path.join(runtime, "hypr", sig, ".socket2.sock")


def hyprctl_json(*args):
    try:
        out = subprocess.run(
            ["hyprctl", "-j", *args],
            capture_output=True, text=True, timeout=2,
        )
        if out.returncode != 0:
            return None
        return json.loads(out.stdout)
    except (subprocess.SubprocessError, ValueError, OSError):
        return None


def compute_fullscreen_monitors():
    """
    Returns {monitor_name: bool} -- True if that monitor's currently
    visible workspace has a fullscreen window active on it. Returns None
    (meaning "couldn't tell, keep whatever we last knew") if hyprctl
    itself didn't answer -- a transient hiccup should never be
    misreported as "nothing is fullscreen anywhere".
    """
    monitors = hyprctl_json("monitors")
    clients = hyprctl_json("clients")
    if monitors is None or clients is None:
        return None

    result = {}
    for mon in monitors:
        name = mon.get("name")
        if not name:
            continue
        ws = mon.get("activeWorkspace") or {}
        ws_id = ws.get("id")
        result[name] = False
        if ws_id is None:
            continue
        for c in clients:
            cw = (c.get("workspace") or {}).get("id")
            if cw != ws_id:
                continue
            # Hyprland has reported this as a plain bool in some
            # versions and as a fullscreen MODE int in others (0 = none,
            # 1 = maximized, 2 = fullscreen) -- treat either truthy form
            # as "this window covers the whole output", which is exactly
            # the case Smart Playback cares about (the wallpaper behind
            # it is invisible either way).
            fs = c.get("fullscreen")
            if fs is True or (isinstance(fs, int) and fs != 0):
                result[name] = True
                break
    return result


def main():
    last = None

    # Establish the initial state immediately on startup -- without
    # this, a user who turns Smart Playback on while ALREADY inside a
    # fullscreen app would keep the wallpaper running (burning GPU
    # behind the fullscreen window) until the next unrelated window
    # event happened to fire.
    initial = compute_fullscreen_monitors()
    if initial is not None:
        last = initial
        print(json.dumps(initial), flush=True)

    path = socket_path()
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(path)
    except OSError:
        # Hyprland's socket isn't reachable (not running under Hyprland,
        # or the socket isn't up yet right after login) -- nothing more
        # this process can do. Exit non-zero so the bash launcher's
        # caller (WatcherService-style restart-on-exit in
        # SmartPlaybackService.qml) can retry a little later.
        sys.exit(1)

    buf = b""
    try:
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break # Hyprland restarted / socket closed -- let the launcher reconnect
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                try:
                    text = line.decode("utf-8", "ignore")
                except UnicodeDecodeError:
                    continue
                if not any(text.startswith(ev) for ev in RELEVANT_EVENTS):
                    continue
                current = compute_fullscreen_monitors()
                if current is not None and current != last:
                    last = current
                    print(json.dumps(current), flush=True)
    finally:
        try:
            sock.close()
        except OSError:
            pass


if __name__ == "__main__":
    main()
