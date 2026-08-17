pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

/*
 * MprisService.qml
 * ----------------------
 * Real MPRIS integration for Music Dock -- backed by `playerctl`, which
 * already talks to any MPRIS-compliant player (Spotify, mpv, VLC,
 * Firefox, Chromium, ...) over D-Bus, so this service never needs to
 * special-case a particular player.
 *
 * scripts/_mpris_worker.sh is kept running as a long-lived Process (same
 * long-lived-Process-with-SplitParser pattern CavaService/WatcherService
 * use) that emits one JSON line per real MPRIS change -- event-driven via
 * `playerctl --follow`, with a 1s position heartbeat only while something
 * is actually Playing (see that script's header for why). Read here via
 * SplitParser: asynchronous, no polling loop on the QML side.
 *
 * start()/stop() are called from Panels/MusicDockOverlay's own lifecycle,
 * matching CavaService's shape -- this service never starts itself.
 *
 * Playback commands (playPause/next/previous/toggleShuffle/cycleLoop/
 * seek) dispatch a plain `playerctl ...` call; they never optimistically
 * mutate title/status/etc themselves -- the very next state emission
 * from the worker (near-instant, since playerctl's own command already
 * changed the real MPRIS property) is what updates the UI, same
 * "real state always wins" principle PlaybackService's stream controls
 * use.
 */
QtObject {
    id: service

    property bool available: true // false once the worker reports playerctl/jq missing
    property bool running: false  // true once the worker is alive and emitting
    property bool active: false   // true when an MPRIS player was actually found

    property string playerName: ""
    property string title: ""
    property string artist: ""
    property string album: ""
    property string artUrl: ""
    property string status: "Stopped" // "Playing" | "Paused" | "Stopped"
    property bool shuffle: false
    property string loopStatus: "None" // "None" | "Track" | "Playlist"
    property real duration: 0 // seconds
    property real position: 0 // seconds

    readonly property bool isPlaying: status === "Playing"
    readonly property bool seekable: active && duration > 0

    property bool _wantRunning: false

    function start() {
        _wantRunning = true;
        if (!available) return;
        if (workerProc.running) return;
        workerProc.command = ["bash", Paths.script("_mpris_worker.sh")];
        workerProc.running = true;
    }

    function stop() {
        _wantRunning = false;
        _restartTimer.stop();
        if (workerProc.running) workerProc.running = false;
        running = false;
        active = false;
        status = "Stopped";
    }

    function _ctrl(args) {
        if (!service.active || !service.playerName) return;
        ctrlProc.command = ["playerctl", "-p", service.playerName].concat(args);
        ctrlProc.running = true;
    }

    function playPause() { _ctrl(["play-pause"]); }
    function play()      { _ctrl(["play"]); }
    function pause()     { _ctrl(["pause"]); }
    function next()      { _ctrl(["next"]); }
    function previous()  { _ctrl(["previous"]); }

    function toggleShuffle() {
        _ctrl(["shuffle", service.shuffle ? "Off" : "On"]);
    }

    function cycleLoop() {
        // MPRIS loop modes:
        // None     = repeat off
        // Track    = repeat current track (Repeat One)
        // Playlist = repeat the current playlist
        const order = ["None", "Track", "Playlist"];
        const idx = order.indexOf(service.loopStatus);
        const next = order[(idx + 1) % order.length];
        _pendingLoopRefresh = true;
        _ctrl(["loop", next]);
    }

    // seconds: absolute target position -- playerctl's `position <n>`
    // (no leading +/-) sets an absolute value, matching this signature.
    function seek(seconds) {
        if (!seekable) return;
        const target = Math.max(0, Math.min(seconds, service.duration));
        service.position = target; // optimistic, corrected by the next worker line
        _ctrl(["position", String(target)]);
    }

    property bool _pendingLoopRefresh: false

    property Process ctrlProc: Process {
        id: ctrlProc
        onExited: (code, status) => {
            if (!service._pendingLoopRefresh) return;
            service._pendingLoopRefresh = false;
            if (!service.active || !service.playerName) return;
            loopProbeProc.command = ["playerctl", "-p", service.playerName, "loop"];
            loopProbeProc.running = true;
        }
    }

    property Process loopProbeProc: Process {
        id: loopProbeProc
        stdout: SplitParser {
            onRead: (line) => {
                const value = String(line || "").trim();
                if (!value) return;
                if (value === "None" || value === "Track" || value === "Playlist") {
                    service.loopStatus = value;
                }
            }
        }
    }

    property Process workerProc: Process {
        id: workerProc
        stdout: SplitParser {
            onRead: (line) => {
                if (!line) return;
                let info;
                try {
                    info = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (info.error) {
                    service.available = false;
                    service.running = false;
                    // Same reasoning as CavaService's missing-dependency
                    // notice -- Music Dock can be running with the panel
                    // closed, so mirror to a desktop notification too.
                    NotifyService.info("Music Dock needs 'playerctl' (and 'jq') installed to show what's playing.");
                    NotifyService.desktop("Music Dock: install 'playerctl' and 'jq' to detect media players.", false);
                    return;
                }
                service.running = true;
                service.active = !!info.active;
                if (info.active) {
                    service.playerName = info.player || "";
                    service.title = info.title || "";
                    service.artist = info.artist || "";
                    service.album = info.album || "";
                    service.artUrl = info.artUrl || "";
                    service.status = info.status || "Stopped";
                    service.shuffle = !!info.shuffle;
                    service.loopStatus = info.loop || "None";
                    service.duration = Number(info.duration) || 0;
                    service.position = Number(info.position) || 0;
                } else {
                    service.playerName = "";
                    service.title = "";
                    service.artist = "";
                    service.album = "";
                    service.artUrl = "";
                    service.status = "Stopped";
                    service.duration = 0;
                    service.position = 0;
                }
            }
        }
        onExited: (code, status) => {
            service.running = false;
            service.active = false;
            // Worker crashed while still wanted (not a deliberate stop())
            // -- retry after a short delay so a transient D-Bus hiccup
            // self-heals instead of leaving the dock permanently blank.
            if (service._wantRunning && service.available) {
                service._restartTimer.restart();
            }
        }
    }

    property Timer _restartTimer: Timer {
        interval: 1000
        onTriggered: if (service._wantRunning) service.start()
    }
}
