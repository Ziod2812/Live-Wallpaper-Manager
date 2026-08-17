#!/usr/bin/env python3
"""
_mpv_ipc.py <socket_path> <action> [value] [value2]
-------------------------------------------
Internal helper for stream_ipc.sh / lw_mpv_try_reuse (utils.sh) — not
meant to be run by hand.

Talks to mpv's JSON IPC protocol (https://mpv.io/manual/master/#json-ipc)
over the unix socket mpvpaper was launched with (--input-ipc-server, added
in _stream_worker.sh / lw_launch_mpvpaper). Used for:
  - Streaming mode's playback controls (position/duration/pause/buffering
    + pause/resume/seek) — never required for playback itself, so any
    failure here just means the controls are unavailable, not that the
    stream is broken.
  - Wallpapers mode's single-persistent-mpv reuse (lw_mpv_try_reuse):
    "ping" (liveness check) and "apply-wallpaper" (swap the currently
    loaded file + video filter in place, without restarting mpv/mpvpaper)
    — see lw_mpv_try_reuse's comment in utils.sh for why this exists.

Always prints exactly one line of JSON to stdout and exits 0 on anything
it could make sense of; exits 1 with "{}" if the socket is missing/stale
or mpv didn't answer in time, so the caller can treat "no answer" and
"nothing to report" identically without parsing stderr.
"""
import json
import os
import socket
import sys
import time

TIMEOUT = 1.0


def fail():
    print("{}")
    sys.exit(1)


def _round_trip(sock, req_id, command, timeout=TIMEOUT):
    """Send ONE command and block for ITS OWN reply (matched by
    request_id), instead of pipelining several commands back-to-back on
    the same connection. Returns (ok, data) where ok is whether mpv
    replied "success" for this exact request_id before the deadline.

    WALLPAPER-SWITCH FIX: apply-wallpaper used to fire loadfile and vf
    as two requests written to the socket one after another with no
    wait in between, then read replies for both in a single shared
    receive loop. Piggybacking a second command onto the same
    connection before the first has been acknowledged is exactly the
    pattern that has caused mpv's IPC layer to misbehave on rapid
    back-to-back commands in the past (see mpv issues #3422 and #7225
    -- a stop/loadfile pair sent in quick succession on one connection
    dropping the second command, and repeated unacknowledged pipelining
    eventually leaving the socket unresponsive to further loadfile
    calls). Doing one full request/reply round trip per command removes
    that ambiguity entirely: nothing new is sent until mpv has actually
    answered the last thing.
    """
    payload = json.dumps({"command": command, "request_id": req_id}) + "\n"
    sock.sendall(payload.encode("utf-8"))

    buf = b""
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            sock.settimeout(max(0.05, deadline - time.time()))
            chunk = sock.recv(4096)
        except socket.timeout:
            break
        if not chunk:
            break
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except ValueError:
                continue
            if obj.get("request_id") == req_id:
                return obj.get("error") == "success", obj.get("data")
    return False, None


def _paths_match(requested, reported):
    """mpv may echo back an absolute/resolved form of the path it was
    given (symlinks resolved, relative -> absolute, etc.), so a strict
    string == would false-negative on a perfectly successful switch.
    Compare by realpath first; fall back to comparing the trailing
    path/filename if realpath can't be resolved (e.g. path doesn't
    exist from this process's cwd for some reason)."""
    if not reported:
        return False
    if reported == requested:
        return True
    try:
        if os.path.realpath(reported) == os.path.realpath(requested):
            return True
    except OSError:
        pass
    return os.path.basename(reported) == os.path.basename(requested)


def handle_apply_wallpaper(sock, video, vf_value):
    """WALLPAPER-SWITCH FIX -- do not report success merely because
    mpv's IPC layer acknowledged the loadfile *command*; that only
    means the command was accepted/well-formed, not that the new
    media is actually the one now loaded and playing. Verify by
    reading back the "path" property after loadfile acks, and only
    then report the switch as real. vf (the resolution/fps scale
    filter) stays best-effort on top, exactly as before -- it is a
    secondary quality-of-life detail, never the pass/fail signal.
    """
    req_id = 1

    ok, _ = _round_trip(sock, req_id, ["loadfile", video, "replace"])
    req_id += 1
    if not ok:
        print(json.dumps({"loadfile_acked": False, "path_verified": False,
                           "reported_path": None, "vf_applied": False}))
        sys.exit(1)
        return

    # loadfile was acked -- now prove the media actually changed by
    # reading the property back, per the "do not fake success" contract.
    path_ok, reported_path = _round_trip(sock, req_id, ["get_property", "path"])
    req_id += 1
    verified = path_ok and _paths_match(video, reported_path)

    # Best-effort filter update -- failure here is logged but never
    # turns an already-verified switch back into a failure.
    vf_ok, _ = _round_trip(sock, req_id, ["vf", "set", vf_value or ""])

    print(json.dumps({
        "loadfile_acked": True,
        "path_verified": verified,
        "reported_path": reported_path,
        "vf_applied": vf_ok,
    }))
    sys.exit(0 if verified else 1)


def main():
    if len(sys.argv) < 3:
        fail()
        return

    sock_path = sys.argv[1]
    action = sys.argv[2]
    value = sys.argv[3] if len(sys.argv) > 3 else None
    value2 = sys.argv[4] if len(sys.argv) > 4 else None

    if action == "get-progress":
        requests = [
            ("position", ["get_property", "time-pos"]),
            ("duration", ["get_property", "duration"]),
            ("paused", ["get_property", "pause"]),
            ("buffering", ["get_property", "paused-for-cache"]),
        ]
    elif action == "pause":
        requests = [("_", ["set_property", "pause", True])]
    elif action == "resume":
        requests = [("_", ["set_property", "pause", False])]
    elif action == "toggle-pause":
        requests = [("_", ["cycle", "pause"])]
    elif action == "seek":
        try:
            target = float(value)
        except (TypeError, ValueError):
            fail()
            return
        requests = [("_", ["seek", target, "absolute"])]
    elif action == "ping":
        # Liveness check only -- used by lw_mpv_try_reuse to confirm the
        # mpv process tracked by this monitor's pid file is actually the
        # one answering on the socket (not a stale socket left behind by
        # a process that already died) before trusting it enough to reuse.
        requests = [("pid", ["get_property", "pid"])]
    elif action == "apply-wallpaper":
        # Swap the currently-playing wallpaper in place: same mpv/mpvpaper
        # process, same layer-shell surface, just a new file + (optional)
        # video filter -- this is the whole point of reuse, avoiding the
        # kill+relaunch flicker/GPU-spinup cost of a fresh mpvpaper.
        # value = new video path (required)
        # value2 = vf filter chain string, e.g. "scale=-2:1080,fps=30", or
        #          "" to clear any previously-set filter (i.e. "original").
        #
        # Handled via its own verified round-trip path (see
        # handle_apply_wallpaper above) rather than the generic
        # fire-and-forget batch below -- this is the one action whose
        # caller (lw_mpv_try_reuse) treats its result as a real pass/
        # fail signal for whether the wallpaper actually changed.
        if not value:
            fail()
            return
        try:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(TIMEOUT)
            sock.connect(sock_path)
        except OSError:
            fail()
            return
        try:
            handle_apply_wallpaper(sock, value, value2)
        finally:
            try:
                sock.close()
            except OSError:
                pass
        return
    else:
        fail()
        return

    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(TIMEOUT)
        sock.connect(sock_path)
    except OSError:
        fail()
        return

    pending = {}
    results = {}
    req_id = 1
    try:
        for name, cmd in requests:
            rid = req_id
            req_id += 1
            pending[rid] = name
            payload = json.dumps({"command": cmd, "request_id": rid}) + "\n"
            sock.sendall(payload.encode("utf-8"))

        buf = b""
        deadline = time.time() + TIMEOUT
        while pending and time.time() < deadline:
            try:
                chunk = sock.recv(4096)
            except socket.timeout:
                break
            if not chunk:
                break
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except ValueError:
                    continue
                rid = obj.get("request_id")
                if rid is not None and rid in pending:
                    name = pending.pop(rid)
                    if obj.get("error") == "success":
                        results[name] = obj.get("data")
    finally:
        try:
            sock.close()
        except OSError:
            pass

    if action == "get-progress":
        out = {
            "position": results.get("position") or 0,
            "duration": results.get("duration") or 0,
            "paused": bool(results.get("paused")),
            "buffering": bool(results.get("buffering")),
        }
        print(json.dumps(out))
        sys.exit(0)

    if action == "ping":
        # Only a REAL success reply (mpv answered "pid" with a value)
        # counts as alive -- an empty results dict (timeout / no reply)
        # must fail loudly here (exit 1), unlike the fire-and-forget
        # controls below, because lw_mpv_try_reuse's whole safety
        # guarantee depends on never trusting a socket that didn't
        # actually answer.
        if "pid" in results:
            print(json.dumps({"pid": results["pid"]}))
            sys.exit(0)
        fail()
        return

    # "apply-wallpaper" never reaches this generic batch path -- it
    # returns from within its own dispatch branch above (see
    # handle_apply_wallpaper) because its result needs a verified
    # get_property round trip, not just an acknowledged command.

    # Fire-and-forget control actions: {} on success is enough, the panel
    # re-polls get-progress right after to pick up the real new state.
    print("{}")
    sys.exit(0)


if __name__ == "__main__":
    main()
