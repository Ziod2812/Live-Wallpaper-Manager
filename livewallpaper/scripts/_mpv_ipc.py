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
from urllib.parse import unquote, urlparse

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


def _local_path(value):
    """Normalize local paths and file:// URIs for reliable comparisons."""
    if not value:
        return None
    value = str(value)
    if value.startswith("file://"):
        parsed = urlparse(value)
        if parsed.scheme != "file":
            return value
        value = unquote(parsed.path)
    return value


def _paths_match(requested, reported):
    """Compare mpv's reported local media path with the requested path.

    mpv may report an absolute/resolved path or a file:// URI, so comparing
    the raw strings can false-negative after a successful load. Normalize
    both forms and then compare realpaths. Do NOT fall back to basename-only
    matching: two different wallpapers in different directories are allowed
    to share a filename, and that would incorrectly verify the old file.
    """
    requested = _local_path(requested)
    reported = _local_path(reported)
    if not reported or not requested:
        return False
    if reported == requested:
        return True
    try:
        return os.path.realpath(reported) == os.path.realpath(requested)
    except OSError:
        return False



def _get_property(sock, req_id, name):
    ok, data = _round_trip(sock, req_id, ["get_property", name])
    return ok, data


def _set_property(sock, req_id, name, value):
    ok, data = _round_trip(sock, req_id, ["set_property", name, value])
    return ok, data


def _set_vf(sock, req_id, vf_value):
    ok, data = _round_trip(sock, req_id, ["vf", "set", vf_value or ""])
    return ok, data


def _wait_for_path(sock, req_id, requested, timeout=4.0, poll_interval=0.10):
    """Wait until mpv reports that the newly requested media is active.

    `loadfile` is asynchronous: mpv can acknowledge the command before its
    `path` property has changed. Reading `path` exactly once immediately after
    the acknowledgement therefore creates a false-negative where the switch
    succeeded but the caller concludes that IPC failed and shows:
    "mpv is still running, not killed".

    Poll the property for a bounded period instead. This does not restart or
    interfere with the player; it merely waits for mpv's normal demux/load
    state to catch up with the already-acknowledged `loadfile`.
    """
    deadline = time.monotonic() + max(0.25, float(timeout))
    last_path = None
    while time.monotonic() < deadline:
        ok, reported = _get_property(sock, req_id, "path")
        req_id += 1
        if ok:
            last_path = reported
            if _paths_match(requested, reported):
                return True, reported, req_id
        time.sleep(max(0.02, float(poll_interval)))
    return False, last_path, req_id


def _resolve_transition(transition):
    # GEOMETRY-TRANSITIONS REMOVED (by request): this used to also accept
    # left/right/top/bottom/wipe/wave/grow/center/any/outer/random, all of
    # which drove mpv's video-zoom/video-pan-x/video-pan-y properties (a
    # visible scale/pan animation on the live wallpaper surface itself).
    # That geometry path has been deleted below, not just disabled -- there
    # is no code left in this file that can set video-zoom/video-pan-* to
    # anything other than 0.0. Only two transitions exist now:
    #   "fade"           -> real lavfi cross-fade (see _transition_*_load)
    #   "simple"/"none"  -> no animation at all, straight loadfile replace
    # Anything else (an old/unknown value coming from a settings.json
    # written before this change) falls back to "fade" rather than
    # erroring, since "fade" is the only remaining transition that isn't
    # a plain cut.
    if transition not in {"fade", "simple", "none"}:
        transition = "fade"
    return transition


def _transition_before_load(sock, req_id, transition, duration, base_vf):
    """Prepare the currently playing video before loadfile.

    Returns (next_req_id, mode_state) consumed by _transition_after_load.
    Only a real lavfi fade is supported; there is no zoom/pan animation of
    any kind in this build.
    """
    transition = _resolve_transition(transition)
    half = max(0.05, duration / 2.0)

    # Force video-pan-x/-y/video-zoom back to neutral unconditionally. This
    # is a one-way reset only (never set to a non-zero value anywhere in
    # this file) -- it exists purely to clean up a stuck non-zero value
    # that a pre-update process might still be holding from an older
    # version of this script, so upgrading never leaves a live wallpaper
    # visibly zoomed/panned forever.
    _set_property(sock, req_id, "video-pan-x", 0.0); req_id += 1
    _set_property(sock, req_id, "video-pan-y", 0.0); req_id += 1
    _set_property(sock, req_id, "video-zoom", 0.0); req_id += 1

    if transition == "fade":
        ok, pos = _get_property(sock, req_id, "time-pos"); req_id += 1
        try:
            pos = float(pos)
        except (TypeError, ValueError):
            pos = 0.0
        fade_out = f"lavfi=[fade=t=out:st={max(0.0, pos):.3f}:d={half:.3f}]"
        vf = ",".join(x for x in [base_vf, fade_out] if x)
        _set_vf(sock, req_id, vf); req_id += 1
        time.sleep(half)
        return req_id, {"kind": "fade", "transition": transition}

    # simple/none: no visual animation -- loadfile replace happens with no
    # preparation step at all.
    return req_id, {"kind": "direct", "transition": transition}


def _transition_after_load(sock, req_id, state, duration, base_vf):
    kind = state.get("kind")
    half = max(0.05, duration / 2.0)

    if kind == "fade":
        fade_in = f"lavfi=[fade=t=in:st=0:d={half:.3f}]"
        vf = ",".join(x for x in [base_vf, fade_in] if x)
        _set_vf(sock, req_id, vf); req_id += 1
        time.sleep(half)
        _set_vf(sock, req_id, base_vf); req_id += 1
        return req_id

    # "direct": plain cut, nothing to animate. video-pan-*/video-zoom were
    # already forced to 0.0 in _transition_before_load and nothing in this
    # file ever moves them away from 0.0 again.
    return req_id

def handle_apply_wallpaper(sock, video, vf_value, transition="fade", duration=1.0):
    """Switch the persistent mpvpaper player in-place with a real MPV-side transition.

    No desktop screenshot, no AWWW overlay, no second video player, and no
    mpvpaper restart are used. Geometry/zoom/pan transitions have been
    removed entirely (by request) -- the only transition left is "fade"
    (libavfilter inside MPV); any other value falls back to "fade". Every
    other case is a plain loadfile replace with no animation.
    """
    req_id = 1
    try:
        duration = float(duration)
    except (TypeError, ValueError):
        duration = 1.0
    duration = max(0.0, min(duration, 5.0))
    transition = _resolve_transition(transition or "fade")

    # Prove current media before touching it, so a failed load can restore it.
    old_ok, old_path = _get_property(sock, req_id, "path"); req_id += 1
    old_path = old_path if old_ok else None

    # Animate the current frame/media without leaving the MPV surface.
    try:
        req_id, state = _transition_before_load(sock, req_id, transition, duration, vf_value or "")
    except Exception:
        state = {"kind": "direct", "transition": transition}

    # Replace the file on the SAME mpv process.
    load_ok, _ = _round_trip(sock, req_id, ["loadfile", video, "replace"])
    req_id += 1
    if not load_ok:
        # Best-effort recovery: restore the previous media through the same
        # persistent MPV, never by killing/relaunching mpvpaper.
        if old_path:
            _round_trip(sock, req_id, ["loadfile", old_path, "replace"]); req_id += 1
            _set_vf(sock, req_id, vf_value or ""); req_id += 1
        print(json.dumps({"loadfile_acked": False, "path_verified": False,
                          "reported_path": old_path, "vf_applied": False,
                          "transition": transition}))
        sys.exit(1)

    # IMPORTANT: `loadfile` is asynchronous. A successful acknowledgement
    # only means mpv accepted the request; the `path` property can still show
    # the OLD file for a short time while the new demuxer is starting. A
    # single immediate get_property therefore produced the exact false error
    # seen by users: the wallpaper really changed (or was changing), but the
    # helper reported `path_verified=false`, causing the shell to show
    # "mpv is still running, not killed". Wait briefly for mpv to publish
    # the new path before deciding that the switch failed.
    verified, reported_path, req_id = _wait_for_path(sock, req_id, video, timeout=4.0)
    if not verified:
        print(json.dumps({"loadfile_acked": True, "path_verified": False,
                          "reported_path": reported_path, "vf_applied": False,
                          "transition": transition}))
        sys.exit(1)

    # Complete the in-player transition and restore the normal filter chain.
    try:
        req_id = _transition_after_load(sock, req_id, state, duration, vf_value or "")
    except Exception:
        # Do not let a cosmetic transition error turn a successful media swap
        # into a false failure. Always restore clean transform defaults.
        _set_vf(sock, req_id, vf_value or ""); req_id += 1
        _set_property(sock, req_id, "video-pan-x", 0.0); req_id += 1
        _set_property(sock, req_id, "video-pan-y", 0.0); req_id += 1
        _set_property(sock, req_id, "video-zoom", 0.0); req_id += 1

    # Final filter restore (fade/transform must never leak into the next switch).
    vf_ok, _ = _set_vf(sock, req_id, vf_value or "")

    print(json.dumps({
        "loadfile_acked": True,
        "path_verified": True,
        "reported_path": reported_path,
        "vf_applied": vf_ok,
        "transition": transition,
        "duration": duration,
    }))
    sys.exit(0)

def main():
    if len(sys.argv) < 3:
        fail()
        return

    sock_path = sys.argv[1]
    action = sys.argv[2]
    value = sys.argv[3] if len(sys.argv) > 3 else None
    value2 = sys.argv[4] if len(sys.argv) > 4 else None
    value3 = sys.argv[5] if len(sys.argv) > 5 else None
    value4 = sys.argv[6] if len(sys.argv) > 6 else None

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
    elif action == "screenshot-to-file":
        if not value:
            fail()
            return
        try:
            # mpv captures the decoded video frame, not the Wayland output.
            # This avoids including panels, docks, bars, cursors, or other
            # compositor surfaces in the live-wallpaper transition frame.
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(TIMEOUT)
            sock.connect(sock_path)
        except OSError:
            fail()
            return
        try:
            ok, data = _round_trip(sock, 9001, ["screenshot-to-file", value, "video"])
            print(json.dumps({"ok": ok, "path": value, "data": data}))
            sys.exit(0 if ok else 1)
        finally:
            try:
                sock.close()
            except OSError:
                pass
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
            handle_apply_wallpaper(sock, value, value2, value3 or "fade", value4 or "1.0")
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
