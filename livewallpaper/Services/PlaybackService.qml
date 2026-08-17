pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

/*
 * PlaybackService.qml
 * ----------------------
 * Owns everything related to actually playing a wallpaper, multi-monitor
 * aware, and NON-BLOCKING: apply/toggle/start/next/previous/random all
 * dispatch their underlying script and return almost instantly (the
 * scripts themselves hand the slow part -- stopping the old mpvpaper,
 * launching + retrying the new one, which can legitimately take several
 * seconds for a 4K/60fps video -- off to a detached background worker).
 * Real completion is reported asynchronously through each monitor's
 * "apply_status" state file (pending -> success | error), watched here via
 * FileView rather than by blocking on the launching process's exit.
 *
 *   - selectedMonitor: which output the panel's controls target. "auto"
 *     (default) means "let the bash layer auto-detect the focused
 *     monitor", identical to the original single-monitor behavior.
 *   - selectedResolution / selectedFps: the in-memory choice from the
 *     panel's selector rows.
 *   - currentPath / currentName: what's playing on the SELECTED monitor.
 *   - running: whether mpvpaper is alive on the selected monitor (or
 *     anywhere, when "auto") -- polled every 2s.
 *   - busy: true from the moment an action is dispatched until its
 *     apply_status resolves (pending -> success/error), or until a
 *     30s safety-net timeout if a status update never arrives.
 *   - playPosition: elapsed seconds in the current loop of the wallpaper.
 *   - playDuration: duration (seconds) of the current wallpaper from the DB.
 *   - playPercent: integer 0-100 of how far through the current loop.
 *
 * Also auto-downgrades quality when settings.performance is
 * "battery-saver" and PowerService reports running on battery (and
 * restores the original quality back on AC).
 *
 * On shell startup this also replays the last-used wallpaper if
 * settings.autostart is true and nothing is currently running.
 *
 * ── Streaming & Web modes ─────────────────────────────────────────────
 * Streaming (remote URL) and Web (URL or local HTML) share this exact
 * same mpvpaper/mpv backend and the exact same dispatch/status-file
 * infrastructure above -- they are just two more "what to hand mpvpaper"
 * cases, not a second playback system. `playMode` tracks which content
 * type is currently active:
 *   "wallpapers" -> local video file via apply_wallpaper.sh (unchanged)
 *   "streaming"  -> remote URL via stream_wallpaper.sh (mpv's built-in
 *                   yt-dlp resolves YouTube/Twitch/Vimeo/etc.)
 *   "web"        -> web URL (same mpv path as streaming) or local HTML
 *                   (a kiosk-mode browser instead) via web_wallpaper.sh
 * Only ever one of applyProc/navigationProc/streamProc/webProc/stopProc
 * dispatches at a time, and only ever one mpvpaper (or kiosk browser)
 * runs per monitor -- switching mode, or dispatching a new play* call,
 * always tears down whatever the monitor was already doing first (see
 * playUrl/playWeb/stopAll below), so two backends can never collide.
 *
 * This API is fully backwards-compatible: every pre-existing
 * property/method keeps its old meaning, and the new streaming/web bits
 * are purely additive.
 */
QtObject {
    id: service

    property string selectedMonitor: "auto"
    property string selectedResolution: "1080p"
    property string selectedFps: "original"

    property string currentPath: ""
    property bool running: false
    property bool busy: false

    // ── Active play-mode tracking ────────────────────────────────────────
    // Records what kind of content is currently (or was last) playing.
    // Only ever changed by apply()/playUrl()/playWeb()/stopAll() -- never
    // by a mode-switch alone -- so the panel can show the right "now
    // playing" summary regardless of which mode tab happens to be open.
    property string playMode: "wallpapers" // "wallpapers" | "streaming" | "web"

    // ── Streaming state ────────────────────────────────────────────────
    property string streamUrl: ""       // the original URL the user entered
    property string streamTitle: ""     // resolved title from yt-dlp (may be empty)
    property string streamThumbnail: "" // thumbnail URL from yt-dlp (may be empty)
    property string streamUploader: ""  // channel/uploader name
    property bool   streamIsLive: false // true for Twitch-style live streams
    // "idle" | "connecting" | "playing" | "paused" | "buffering" | "error" | "stopping"
    //
    // "connecting" -> "playing"/"paused"/"buffering" is decided by the real
    // mpv IPC poll (see streamProgressProc below), not by the launcher
    // script's own "I spawned the process" report. apply_status's success
    // state (further down this file) still flips connecting -> playing as
    // a FALLBACK ONLY, for the case mpv IPC genuinely isn't available
    // (no python3, or an mpv build without --input-ipc-server support) --
    // whichever signal is real arrives first wins, so the UI is never
    // stuck on "Connecting" once mpv is actually up.
    property string streamStatus: "idle"

    // Loop and mute are per-stream *preferences*, not just runtime toggles:
    // restored from settings.json on load (same pattern as
    // LiveWallpaperPanel's appMode) so they survive a restart, then a
    // toggle() call below breaks the binding and takes over as plain
    // in-memory state -- identical lifecycle to appMode.
    property bool streamLoop: {
        const v = SettingsService.settings.stream_loop;
        return (v === undefined || v === null) ? true : !!v;
    }
    property bool streamMuted: {
        const v = SettingsService.settings.stream_muted;
        return (v === undefined || v === null) ? false : !!v;
    }

    // ── Quality (streaming) ──────────────────────────────────────────────
    // Ordered low->high; "auto" leaves mpv/yt-dlp's own format selection
    // untouched, the numeric entries cap it at that max height (see
    // _stream_worker.sh's --ytdl-format). Same restore-from-settings /
    // break-binding-on-toggle lifecycle as streamLoop/streamMuted above.
    readonly property var streamQualityLevels: ["auto", "360", "480", "720", "1080", "1440", "2160"]
    property string streamQuality: {
        const v = SettingsService.settings.stream_quality;
        return (v && streamQualityLevels.indexOf(v) !== -1) ? v : "auto";
    }
    readonly property int streamQualityIndex: streamQualityLevels.indexOf(streamQuality)

    // "1080" -> "1080p FHD", "auto" -> "Auto", unknown height -> "?"
    function _qualityLabel(h) {
        if (h === "auto") return "Auto";
        const n = parseInt(h, 10);
        if (!n) return "?";
        const tag = n >= 2160 ? " 4K" : n >= 1440 ? " 2K" : n >= 1080 ? " FHD" : n >= 720 ? " HD" : "";
        return n + "p" + tag;
    }
    readonly property string streamQualityLabel: _qualityLabel(streamQuality)

    // The SOURCE's own best-available height, from stream_info.sh's probe
    // -- purely informational (e.g. "Source: 1080p FHD" badge), independent
    // of whatever cap streamQuality currently applies.
    property int streamHeight: 0
    readonly property string streamHeightLabel: streamHeight > 0 ? _qualityLabel(String(streamHeight)) : ""

    // Total length of the current VOD, in seconds -- from stream_info.sh's
    // yt-dlp probe (info.duration). 0 for live streams / unknown sources.
    // This is metadata, not a guess: it's what yt-dlp itself reports for
    // the source, same trust level as streamTitle/streamThumbnail/streamHeight.
    property real streamMetaDuration: 0

    // ── Streaming playback controls (mpv IPC) ────────────────────────────
    // Real position/duration/pause/buffering read from mpv itself over the
    // --input-ipc-server socket _stream_worker.sh launches it with (see
    // stream_ipc.sh) -- NOT inferred from elapsed wall-clock time or
    // guessed from streamMetaDuration. streamControlsReady is false until
    // the very first successful IPC read confirms the socket is actually
    // talking to mpv, so the panel never shows a seek bar/pause button
    // that silently does nothing (older mpv builds, or IPC not up yet).
    // The poll runs from "connecting" onward (not just "playing") so that
    // first successful read is also what promotes streamStatus itself.
    property bool streamControlsReady: false
    property real streamPosition: 0
    property real streamDuration: 0
    property bool streamPaused: false
    property bool streamBuffering: false
    // A live stream (or one whose length mpv/yt-dlp never resolves) has no
    // meaningful seek target -- the bar is display-only in that case.
    readonly property bool streamSeekable: streamControlsReady && streamDuration > 0 && !streamIsLive

    // "Actively streaming" -- playing, paused, or buffering all mean mpv is
    // genuinely up and a stream is loaded; only these three states accept
    // pause/resume/seek calls or keep the IPC poll running. Idle/
    // connecting/error/stopping do not.
    function _isStreamActive() {
        return streamStatus === "playing" || streamStatus === "paused" || streamStatus === "buffering";
    }

    // Public read-only mirror of _isStreamActive() -- Services/SmartPlaybackService.qml
    // needs this to decide whether pauseStream()/resumeStream() apply,
    // without reaching into a function named with the "internal"
    // underscore convention this file uses elsewhere.
    readonly property bool streamActive: _isStreamActive()

    function _resetStreamControls() {
        streamControlsReady = false;
        streamPosition = 0;
        streamDuration = 0;
        streamPaused = false;
        streamBuffering = false;
        // Cancel anything queued against the OLD session's IPC socket --
        // a leftover debounced seek or queued pause/resume must never
        // fire against a stream that's since been relaunched, stopped,
        // or replaced. See _sendStreamControl/_seekDebounceTimer below.
        _pendingSeekTarget = -1;
        _seekDebounceTimer.stop();
        _streamCtrlPending = null;
        if (streamControlProc.running) streamControlProc.running = false;
    }

    // ── Stream-session generation guard ──────────────────────────────────
    // streamProc is a single, reused Process object -- every playUrl()/
    // _relaunchStream() dispatch runs through it, and superseding an
    // in-flight dispatch (new URL, quality/loop/mute change, switching
    // to Wallpapers/Web, or a plain Stop) has always meant killing
    // whatever streamProc is currently doing. A killed process's own
    // exit is asynchronous and (being terminated) almost always reports
    // a non-zero code -- so without this guard, that stale exit could
    // arrive AFTER a newer dispatch has already moved streamStatus on
    // to "connecting"/"playing", and unconditionally stomp it back to
    // "error" (streamProc.onExited used to do exactly that).
    //
    // _streamGen is bumped by every call that supersedes the current
    // streaming attempt (playUrl, _relaunchStream, and _clearStreamState
    // -- reached from apply()/_applyNavigationTarget()/stopAll()/
    // stopStream()/stopProc.onExited). _streamProcGen records which
    // generation the currently-dispatched streamProc invocation belongs
    // to. streamProc.onExited only ever treats a non-zero exit as a
    // real failure when _streamProcGen still matches the CURRENT
    // _streamGen -- a stale/superseded exit is silently ignored instead.
    property int _streamGen: 0
    property int _streamProcGen: -1

    // If streamProc is already running when a new dispatch is
    // requested, the running instance is asked to terminate and the
    // requested launch is deferred here until streamProc.onExited
    // confirms it has actually exited -- so the same Process object is
    // never asked to stop-and-restart within the same tick, and the two
    // invocations can never overlap or be misattributed to each other.
    property var _streamPendingLaunch: null

    // Single entry point for (re)dispatching streamProc -- used by both
    // playUrl() and _relaunchStream() so the defer-until-confirmed-dead
    // behavior only has to be implemented once.
    function _startStreamProc(gen, args) {
        if (streamProc.running) {
            service._streamPendingLaunch = { gen: gen, args: args };
            streamProc.running = false;
            return;
        }
        service._streamProcGen = gen;
        service._dispatch(streamProc, "stream_wallpaper.sh", args);
    }

    // ── Stream control-command queueing (pause/resume/seek) ──────────────
    // streamControlProc is likewise a single reused Process object, fired
    // by pauseStream()/resumeStream()/seekStreamTo() -- previously each
    // call overwrote `command`/`running` directly with no regard for
    // whether a previous control command was still in flight (a real
    // risk for seek in particular, since a Slider's onMoved fires
    // continuously while dragging). _sendStreamControl() now coalesces:
    // only the most recent request matters (a new seek target supersedes
    // an older queued one; pause/resume are simple toggles), so at most
    // one command is ever in flight plus one queued, and the queued one
    // fires as soon as the in-flight one exits.
    property var _streamCtrlPending: null

    function _sendStreamControl(action, value) {
        if (streamControlProc.running) {
            service._streamCtrlPending = { action: action, value: value };
            return;
        }
        const args = [_streamIpcMonitorArg(), action];
        if (value !== undefined && value !== null) args.push(String(value));
        streamControlProc.command = ["bash", Paths.script("stream_ipc.sh")].concat(args);
        streamControlProc.running = true;
    }

    // Seek specifically is debounced on top of the queueing above: a
    // Slider drag can call seekStreamTo() many times per second, and
    // there is no value in sending each intermediate position to mpv --
    // only the final target matters. The optimistic streamPosition
    // update (see seekStreamTo) still happens immediately so the UI
    // tracks the drag with no added latency; only the actual IPC seek
    // command is delayed/coalesced.
    property real _pendingSeekTarget: -1
    property Timer _seekDebounceTimer: Timer {
        interval: 120
        repeat: false
        onTriggered: {
            if (service._pendingSeekTarget < 0) return;
            const target = service._pendingSeekTarget;
            service._pendingSeekTarget = -1;
            if (service.playMode !== "streaming" || !service._isStreamActive()) return;
            service._sendStreamControl("seek", target);
        }
    }

    // ── Web state ─────────────────────────────────────────────────────
    property string webSource: ""       // URL or absolute file path
    property string webSourceType: "url" // "url" | "local"
    property string webTitle: ""        // resolved title (URL sources only)
    // "idle" | "connecting" | "playing" | "error"
    property string webStatus: "idle"

    function _domainFrom(url) {
        try {
            const m = String(url).match(/^https?:\/\/(?:www\.)?([^\/]+)/);
            return m ? m[1] : url;
        } catch (e) { return url; }
    }

    // ── Playback progress tracking ──────────────────────────────────────
    // Counts elapsed seconds within the current wallpaper loop so the UI
    // can show a progress bar even though mpvpaper has no IPC socket by
    // default. Resets to 0 whenever the current wallpaper changes or
    // playback stops.
    property real playPosition: 0

    readonly property real playDuration: {
        if (playMode !== "wallpapers") return 0; // streaming/web have no fixed loop length
        if (!currentPath) return 0;
        const wp = WallpaperService.wallpapers.find(w => w.path === currentPath);
        return (wp && wp.duration && wp.duration > 0) ? wp.duration : 0;
    }

    // Integer percent 0-100, wraps around on loop
    readonly property int playPercent: {
        if (playDuration <= 0 || !running) return 0;
        return Math.round((playPosition % playDuration) / playDuration * 100);
    }

    onCurrentPathChanged: {
        playPosition = 0;
        if (running) playProgressTimer.restart();
    }
    onRunningChanged: {
        if (running) {
            playPosition = 0;
            playProgressTimer.running = true;
        } else {
            playProgressTimer.running = false;
            playPosition = 0;
        }
    }

    property Timer playProgressTimer: Timer {
        id: playProgressTimer
        interval: 1000
        repeat: true
        running: false
        onTriggered: {
            if (!service.running) { running = false; return; }
            if (service.playDuration > 0) {
                service.playPosition = (service.playPosition + 1) % service.playDuration;
            }
        }
    }

    // Saved pre-battery-saver quality, restored when back on AC.
    property string _preBatteryResolution: ""
    property string _preBatteryFps: ""
    property bool _batterySaverActive: false

    readonly property string currentName: {
        if (playMode === "streaming" && streamUrl) {
            return streamTitle.length > 0 ? streamTitle : _domainFrom(streamUrl);
        }
        if (playMode === "web") {
            if (!webSource) return "None";
            if (webSourceType === "local") return webSource.split("/").pop();
            return webTitle.length > 0 ? webTitle : _domainFrom(webSource);
        }
        if (!currentPath) return "None";
        const base = currentPath.split("/").pop();
        return base.replace(/\.[^.]+$/, "");
    }

    function _monitorArgs() {
        return selectedMonitor && selectedMonitor !== "auto" ? [selectedMonitor] : [];
    }

    function _dispatch(proc, scriptName, extraArgs) {
        // Smart Playback safety net: any manual action (Stop/Next/
        // Previous/Random/Apply/Start) supersedes whatever Smart
        // Playback was tracking -- forget which monitors it stopped and
        // drop any not-yet-dispatched restore/stop it had queued, so it
        // can never later "restore" a wallpaper the user has since
        // changed out from under it. No thaw step is needed here (unlike
        // the old SIGSTOP/SIGCONT design) since a genuinely stopped
        // mpvpaper is just... not running -- stop_wallpaper.sh/
        // start_wallpaper.sh below handle a dead or already-running
        // process fine either way.
        if (service._anyMonitorSmartStopped() || Object.keys(service._smartStopQueue).length > 0) {
            service.smartStoppedMonitors = ({});
            service._smartStopQueue = ({});
        }
        busy = true;
        busyTimeout.restart();
        proc.command = ["bash", Paths.script(scriptName)].concat(extraArgs || []).concat(_monitorArgs());
        proc.running = true;
    }

    // Shell actions are asynchronous. Keep later clicks instead of dropping
    // them while the monitor lock is owned by the current apply worker.
    property var pendingActions: []

    function _dropQueuedApplyActions() {
        const remaining = [];
        for (let i = 0; i < service.pendingActions.length; i++) {
            const action = service.pendingActions[i];
            if (action && action.scriptName !== "apply_wallpaper.sh") {
                remaining.push(action);
            }
        }
        service.pendingActions = remaining;
    }

    function _request(proc, scriptName, extraArgs) {
        // A newly selected wallpaper supersedes an older queued selection.
        // The shell script also cancels the detached worker that is already
        // running, so the latest click is the one that should be applied.
        if (scriptName === "apply_wallpaper.sh") {
            service._dropQueuedApplyActions();
        }
        const action = {
            proc: proc,
            scriptName: scriptName,
            extraArgs: extraArgs || []
        };
        // `busy` belongs to the detached wallpaper worker and may briefly
        // outlive the short dispatcher process. Only queue when this exact
        // Process is still running; otherwise a stale busy flag must not make
        // the visible Stop/Next/Previous/Random buttons appear dead.
        if (proc.running) {
            service.pendingActions = service.pendingActions.concat([action]);
            return;
        }
        service._dispatch(proc, scriptName, extraArgs);
    }

    function _drainActions() {
        if (service.busy || service.pendingActions.length === 0) return;
        const action = service.pendingActions[0];
        service.pendingActions = service.pendingActions.slice(1);
        service._dispatch(action.proc, action.scriptName, action.extraArgs);
    }

    function apply(path) {
        if (!path || String(path).trim().length === 0) {
            NotifyService.error("The selected wallpaper has no valid file path.");
            return;
        }
        // A card selection is an explicit replacement request. Do not queue
        // behind an older card/navigation dispatcher; stop that short-lived
        // dispatcher and let apply_wallpaper.sh cancel its detached worker.
        if (applyProc.running) applyProc.running = false;
        if (navigationProc.running) navigationProc.running = false;
        service._dropQueuedApplyActions();
        // A card selection replaces whatever streaming/web session (if
        // any) was active on this monitor -- there is only ever one
        // mpvpaper per monitor, so switching content types here is the
        // same "tear down, then dispatch" rule stopAll() uses elsewhere.
        if (streamProc.running) streamProc.running = false;
        if (webProc.running) webProc.running = false;
        _clearStreamState();
        _clearWebState();
        playMode = "wallpapers";
        service._dispatch(applyProc, "apply_wallpaper.sh", [
            path,
            selectedResolution,
            selectedFps
        ]);
        NotifyService.info("Applying selected wallpaper…");
    }

    // ── GPU Switching feature (Services/GPUManagerService.qml) ──────────
    // Purely additive: does not change apply()/stop()/start() or any
    // other existing method's behavior or signature. Called only when
    // GPUManagerService's persisted GPU mode actually changes.
    //
    // The new GPU/environment takes effect for mpvpaper via
    // utils.sh's lw_launch_mpvpaper() reading settings.json directly, so
    // the only thing this needs to do is: if a local wallpaper is
    // currently playing, safely stop and relaunch it on the SAME path
    // it was already showing (steps 1-3 of the GOAL: stop safely,
    // relaunch with the new GPU env, restore the current wallpaper) --
    // exactly the existing apply() flow, same as _commitBatteryMode()
    // already does for a resolution/fps change below. Streaming/web
    // sessions and the rest of the app (SmartPlayback, playlists,
    // ...) are never touched.
    function reapplyForGpuChange() {
        if (service.playMode !== "wallpapers") return; // nothing local playing to relaunch
        if (!service.currentPath) return; // new mode simply takes effect on the next Apply/Start
        service.apply(service.currentPath);
    }

    function toggle() {
        if (service.running) {
            service.stop();
        } else {
            service.start();
        }
    }

    function start() {
        _request(startProc, "start_wallpaper.sh", []);
    }

    function stop() {
        // Stop is a user-requested override: discard queued navigation so a
        // delayed Next/Random cannot start another wallpaper after stopping.
        service.pendingActions = [];
        service.busy = false;
        service.busyTimeout.stop();
        if (stopProc.running) return;
        _dispatch(stopProc, "stop_wallpaper.sh", []);
    }

    function _navigationList() {
        return WallpaperService.wallpapers || [];
    }

    // BUGFIX (Next/Previous unreliable): apply_wallpaper.sh runs
    // asynchronously and the on-disk "current" file it eventually writes
    // only reaches `service.currentPath` once currentView's FileView
    // watcher notices the change and reloads -- there is real-world
    // latency there (inotify + a QML event-loop turn). next()/previous()
    // compute their target index from `service.currentPath` at click
    // time, and _request() QUEUES a click into pendingActions rather
    // than dropping it when navigationProc is still busy (see _request).
    // Before this fix, a second Next/Previous pressed before that
    // round-trip completed would still read the OLD on-disk currentPath,
    // compute the SAME index the first click already chose, and end up
    // re-queuing the exact same wallpaper instead of advancing further --
    // which looks exactly like "Next/Previous doesn't reliably work",
    // especially under the repeated-navigation test case.
    //
    // Fix: _applyNavigationTarget() now advances `service.currentPath`
    // optimistically, synchronously, the moment a target is chosen/
    // dispatched -- not after the shell round-trip confirms it. Every
    // subsequent next()/previous()/random() call (even ones that end up
    // queued behind a still-running navigationProc) then computes its
    // index from the wallpaper navigation is ACTUALLY headed toward, so
    // rapid repeated presses chain correctly: B -> C -> D -> E instead of
    // B -> C -> C -> C. Once apply_wallpaper.sh actually finishes and
    // currentView's FileView reloads, it reconciles currentPath against
    // the real on-disk value -- identical to what we already set in the
    // success case, so this never fights the authoritative source, it
    // only removes the stale-read race. No new wallpaper-loading
    // implementation was introduced: every navigation target still goes
    // through the exact same navigationProc -> apply_wallpaper.sh
    // centralized backend as before.
    function _applyNavigationTarget(target, debugMeta) {
        if (!target || !target.path) {
            if (debugMeta) {
                console.log("[WALLPAPER] action=" + debugMeta.action +
                    " current=" + JSON.stringify(service.currentPath) +
                    " result=no-target(list empty)");
            }
            NotifyService.error("No wallpapers available. Refresh the wallpaper list first.");
            WallpaperService.refresh();
            return;
        }
        // Navigation has its own Process so a card Apply that is still
        // dispatching cannot swallow or delay the bottom-row controls.
        // Same as apply(): navigating out of a streaming/web session
        // replaces it, it never plays alongside it.
        if (streamProc.running) streamProc.running = false;
        if (webProc.running) webProc.running = false;
        _clearStreamState();
        _clearWebState();
        playMode = "wallpapers";
        if (debugMeta) {
            console.log("[WALLPAPER] action=" + debugMeta.action +
                " current_index=" + debugMeta.currentIndex +
                " target_index=" + debugMeta.targetIndex +
                " target=" + target.path);
        }
        // See BUGFIX comment above _applyNavigationTarget: this optimistic
        // update (not the eventual FileView reload) is what makes
        // back-to-back Next/Previous/Random clicks chain correctly.
        service.currentPath = target.path;
        _request(navigationProc, "apply_wallpaper.sh", [
            target.path,
            selectedResolution,
            selectedFps
        ]);
    }

    // Resolve navigation from the reactive QML database. This keeps the
    // buttons working even when the shell script's database has not caught up
    // with the FileView yet, and still uses the same serialized apply worker.
    function next() {
        const list = _navigationList();
        if (list.length === 0) {
            console.log("[WALLPAPER] action=next result=no-wallpapers");
            WallpaperService.refresh();
            NotifyService.info("Refreshing wallpapers…");
            return;
        }
        let index = -1;
        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].path === service.currentPath) {
                index = i;
                break;
            }
        }
        const targetIndex = index < 0 ? 0 : (index + 1) % list.length;
        _applyNavigationTarget(list[targetIndex], { action: "next", currentIndex: index, targetIndex: targetIndex });
    }

    function previous() {
        const list = _navigationList();
        if (list.length === 0) {
            console.log("[WALLPAPER] action=previous result=no-wallpapers");
            WallpaperService.refresh();
            NotifyService.info("Refreshing wallpapers…");
            return;
        }
        let index = -1;
        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].path === service.currentPath) {
                index = i;
                break;
            }
        }
        const targetIndex = index < 0 ? list.length - 1 : (index - 1 + list.length) % list.length;
        _applyNavigationTarget(list[targetIndex], { action: "previous", currentIndex: index, targetIndex: targetIndex });
    }

    function random() {
        const list = _navigationList();
        if (list.length === 0) {
            console.log("[WALLPAPER] action=random result=no-wallpapers");
            WallpaperService.refresh();
            NotifyService.info("Refreshing wallpapers…");
            return;
        }
        const candidates = [];
        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].path !== service.currentPath) {
                candidates.push(list[i]);
            }
        }
        const pool = candidates.length > 0 ? candidates : list;
        const target = pool[Math.floor(Math.random() * pool.length)];
        _applyNavigationTarget(target, { action: "random", currentIndex: -1, targetIndex: -1 });
    }

    // ══════════════════════════════════════════════════════════════════
    // STREAMING MODE
    // ══════════════════════════════════════════════════════════════════

    /*
     * playUrl(url)
     * ------------
     * Play a remote streaming URL (YouTube, Twitch, Vimeo, HLS, direct
     * MP4/WebM, ...) as a live wallpaper via mpvpaper. mpv's built-in
     * yt-dlp integration resolves the stream for supported platforms;
     * direct media URLs are played as-is.
     *
     * Tears down anything else already dispatching or playing on this
     * monitor first (wallpaper apply/navigation, a previous stream, or a
     * web session) so there is never more than one mpvpaper/browser
     * instance racing for the same output. State transitions:
     *   idle -> connecting -> playing | error
     * resolved via statusView (same apply_status file wallpaper mode
     * uses -- _stream_worker.sh writes it identically).
     */
    function playUrl(url) {
        const trimmed = url ? url.trim() : "";
        if (trimmed.length === 0) {
            NotifyService.error("Invalid URL.");
            return;
        }

        // Cancel anything else already in flight so playUrl can never
        // race a queued wallpaper apply/navigation or a previous stream.
        // streamProc itself is NOT force-killed inline here anymore --
        // see _startStreamProc()/the generation guard above -- if it's
        // still running (a previous stream), the new dispatch is safely
        // deferred until that instance is confirmed to have exited.
        if (applyProc.running) applyProc.running = false;
        if (navigationProc.running) navigationProc.running = false;
        if (webProc.running) webProc.running = false;
        service._dropQueuedApplyActions();
        service.pendingActions = [];
        service.busy = false;
        service.busyTimeout.stop();

        playMode = "streaming";
        streamUrl = trimmed;
        streamTitle = "";
        streamThumbnail = "";
        streamUploader = "";
        streamIsLive = false;
        streamHeight = 0;
        streamMetaDuration = 0;
        streamStatus = "connecting";
        _resetStreamControls();
        _clearWebState();

        const gen = ++service._streamGen;
        service._startStreamProc(gen, [
            trimmed,
            streamLoop  ? "yes" : "no",
            streamMuted ? "yes" : "no",
            streamQuality
        ]);

        // Fetch metadata in the background -- non-blocking, arrives (if
        // at all) via streamInfoProc's stdout independent of whether
        // playback itself succeeds.
        streamInfoProc.command = ["bash", Paths.script("stream_info.sh"), trimmed];
        streamInfoProc.running = true;
    }

    /*
     * stopStream()
     * ------------
     * Stop an active stream. Delegates to the same stop_wallpaper.sh
     * every other mode uses (it kills whatever pid is recorded for the
     * monitor, mpvpaper or otherwise) -- streamStatus is fully reset to
     * "idle" in stopProc.onExited once the stop is confirmed.
     */
    function stopStream() {
        streamStatus = "stopping";
        service.pendingActions = [];
        service.busy = false;
        service.busyTimeout.stop();
        if (streamInfoProc.running) streamInfoProc.running = false;
        // Invalidate the current stream generation and drop any deferred
        // relaunch immediately -- a user-requested stop must never be
        // resurrected later by a queued _relaunchStream()/playUrl()
        // dispatch that was only waiting on streamProc to exit.
        service._streamGen++;
        service._streamPendingLaunch = null;
        if (stopProc.running) return;
        _dispatch(stopProc, "stop_wallpaper.sh", []);
    }

    function _clearStreamState() {
        streamUrl = "";
        streamTitle = "";
        streamThumbnail = "";
        streamUploader = "";
        streamIsLive = false;
        streamHeight = 0;
        streamMetaDuration = 0;
        streamStatus = "idle";
        _resetStreamControls();
        if (streamInfoProc.running) streamInfoProc.running = false;
        if (streamProgressProc.running) streamProgressProc.running = false;
        // Reached from apply()/_applyNavigationTarget()/stopAll()/
        // stopProc.onExited -- i.e. genuinely leaving this stream
        // session. Invalidate its generation and drop any deferred
        // relaunch so a late streamProc exit, or a relaunch that was
        // only queued behind it, can never resurrect stream state after
        // we've already moved on. See the generation guard above.
        service._streamGen++;
        service._streamPendingLaunch = null;
    }

    /*
     * toggleStreamLoop() / toggleStreamMute() / stepStreamQuality()
     * ----------------------------------------------------------------
     * mpv has no runtime IPC control wired up here (that would need an
     * --input-ipc-server socket and a socat/python dependency this
     * project doesn't otherwise require) -- so a live change works by
     * re-dispatching the same URL with the new flag, the exact same
     * teardown-then-relaunch path everything else in this file already
     * uses. It costs a ~1-2s re-buffer, but adds no new process type,
     * no new dependency, and can't leak: it's stopStream()+playUrl()
     * with one extra courtesy -- see _relaunchStream() -- of not
     * discarding the already-resolved title/thumbnail/uploader/live
     * badge, since this isn't a new source, just a flag flip. (Quality
     * DOES also re-run the streamHeight probe -- see _relaunchStream --
     * since a quality change is the one case where re-confirming what's
     * actually playing is worth the extra yt-dlp call.)
     *
     * Persisted to settings.json immediately regardless of whether a
     * stream is currently playing, so the preference applies the next
     * time the user starts one too.
     */
    function toggleStreamLoop() {
        streamLoop = !streamLoop;
        SettingsService.set("stream_loop", streamLoop);
        if (playMode === "streaming" && streamUrl &&
            (streamStatus === "connecting" || _isStreamActive())) {
            _relaunchStream();
        }
    }

    function toggleStreamMute() {
        streamMuted = !streamMuted;
        SettingsService.set("stream_muted", streamMuted);
        if (playMode === "streaming" && streamUrl &&
            (streamStatus === "connecting" || _isStreamActive())) {
            _relaunchStream();
        }
    }

    // direction: +1 to step up a tier, -1 to step down. Clamped, not
    // wrapped -- stepping past "4K" or below "Auto" is simply a no-op,
    // so a spam-clicked +/- button can never throw streamQualityIndex
    // out of streamQualityLevels' bounds.
    function stepStreamQuality(direction) {
        const idx = streamQualityLevels.indexOf(streamQuality);
        const next = idx + (direction > 0 ? 1 : -1);
        if (next < 0 || next >= streamQualityLevels.length) return;
        streamQuality = streamQualityLevels[next];
        SettingsService.set("stream_quality", streamQuality);
        if (playMode === "streaming" && streamUrl &&
            (streamStatus === "connecting" || _isStreamActive())) {
            _relaunchStream();
        }
    }

    function _relaunchStream() {
        if (applyProc.running) applyProc.running = false;
        if (navigationProc.running) navigationProc.running = false;
        if (webProc.running) webProc.running = false;
        service.pendingActions = [];
        service.busy = false;
        service.busyTimeout.stop();
        streamStatus = "connecting";
        _resetStreamControls();
        // streamProc is NOT force-killed inline anymore -- see
        // _startStreamProc()/the generation guard above -- the running
        // instance (if any) is asked to terminate and this relaunch is
        // safely deferred until it's confirmed dead.
        const gen = ++service._streamGen;
        service._startStreamProc(gen, [
            streamUrl,
            streamLoop  ? "yes" : "no",
            streamMuted ? "yes" : "no",
            streamQuality
        ]);
        // Re-probe: the actually-selected format can change with the new
        // quality cap, so the "Source: ..." badge should reflect it too.
        streamInfoProc.command = ["bash", Paths.script("stream_info.sh"), streamUrl];
        streamInfoProc.running = true;
    }

    /*
     * Streaming playback controls — pause/resume/seek + live progress.
     * ---------------------------------------------------------------
     * All of these talk to the actual mpv instance via stream_ipc.sh (see
     * that script's header) -- they do nothing to PlaybackService's own
     * dispatch/status-file machinery above, and are no-ops (safely
     * ignored) when nothing is streaming or the IPC socket isn't up yet.
     * Real state always wins: a pause/seek call doesn't optimistically
     * update streamPosition/streamPaused itself -- it just fires the
     * command and lets the next streamProgressTimer tick (at most 1s
     * away) read back what mpv actually did.
     */
    function _streamIpcMonitorArg() {
        return (selectedMonitor && selectedMonitor !== "auto") ? selectedMonitor : "";
    }

    function pauseStream() {
        if (playMode !== "streaming" || !_isStreamActive()) return;
        _sendStreamControl("pause");
    }

    function resumeStream() {
        if (playMode !== "streaming" || !_isStreamActive()) return;
        _sendStreamControl("resume");
    }

    function toggleStreamPause() {
        if (streamPaused) resumeStream(); else pauseStream();
    }

    // seconds: absolute target position, clamped to [0, streamDuration].
    // The optimistic streamPosition update happens immediately (so a
    // dragged Slider tracks with no added latency); the actual IPC seek
    // command is debounced/coalesced -- see _seekDebounceTimer above --
    // so a rapid drag sends at most one "seek" every ~120ms instead of
    // one per onMoved callback.
    function seekStreamTo(seconds) {
        if (playMode !== "streaming" || !_isStreamActive() || !streamSeekable) return;
        const target = Math.max(0, Math.min(seconds, streamDuration));
        streamPosition = target; // optimistic, corrected by the next poll
        _pendingSeekTarget = target;
        _seekDebounceTimer.restart();
    }

    function seekStreamPercent(fraction) {
        if (!streamSeekable) return;
        seekStreamTo(Math.max(0, Math.min(1, fraction)) * streamDuration);
    }

    // Short alias for seekStreamTo(seconds) -- same behavior, same
    // guards (no-op outside an active stream / seekable), just a
    // shorter name for callers like a Slider's onMoved. Purely
    // additive: seekStreamTo/seekStreamPercent above are unchanged and
    // still work exactly as before.
    function seek(seconds) {
        seekStreamTo(seconds);
    }

    property Process streamControlProc: Process {
        id: streamControlProc
        onExited: (code, status) => {
            // Whatever happened, ask for a fresh read right away instead
            // of waiting up to 1s for the regular timer tick.
            if (service.playMode === "streaming" && service._isStreamActive()) {
                service._pollStreamProgress();
            }
            // A newer pause/resume/seek arrived while this one was still
            // in flight -- send it now that the socket is free again.
            if (service._streamCtrlPending) {
                const next = service._streamCtrlPending;
                service._streamCtrlPending = null;
                service._sendStreamControl(next.action, next.value);
            }
        }
    }

    function _pollStreamProgress() {
        if (streamProgressProc.running) return; // previous poll still in flight
        streamProgressProc.command = ["bash", Paths.script("stream_ipc.sh"), _streamIpcMonitorArg(), "get-progress"];
        streamProgressProc.running = true;
    }

    property Process streamProgressProc: Process {
        id: streamProgressProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (service.playMode !== "streaming") return;
                if (!text || text.trim().length === 0) return;
                try {
                    const info = JSON.parse(text.trim());
                    // {} (empty object) means "socket not up yet" -- leave
                    // streamControlsReady false rather than flipping it on
                    // with zeroed-out values. Also don't touch streamStatus:
                    // a socket that isn't answering yet tells us nothing
                    // new, connecting/error/stopping stay exactly as they
                    // were.
                    if (Object.keys(info).length === 0) return;
                    service.streamControlsReady = true;
                    if (typeof info.position === "number") service.streamPosition = info.position;
                    // Prefer mpv's own duration once it knows it; fall back
                    // to the yt-dlp metadata probe until then (VOD only --
                    // live streams correctly report 0 from both sources).
                    service.streamDuration = (typeof info.duration === "number" && info.duration > 0)
                        ? info.duration : service.streamMetaDuration;
                    service.streamPaused = !!info.paused;
                    service.streamBuffering = !!info.buffering;

                    // THE authoritative playback-state transition: a real
                    // answer from mpv's own IPC socket -- not the launcher
                    // script's exit code, not yt-dlp metadata -- is what
                    // promotes "connecting" to "playing"/"paused"/
                    // "buffering", and what keeps status honest afterward
                    // (e.g. reflecting a user-initiated pause immediately).
                    // Only touches the "actively streaming" states; never
                    // resurrects a stream the user has already stopped, or
                    // overwrites a real error, from a stray late poll
                    // response racing against stop()/an error transition.
                    if (service.streamStatus === "connecting" || service._isStreamActive()) {
                        service.streamStatus = service.streamPaused
                            ? "paused"
                            : (service.streamBuffering ? "buffering" : "playing");
                    }
                } catch (e) {}
            }
        }
    }

    property Timer streamProgressTimer: Timer {
        interval: 1000
        repeat: true
        // Starts from "connecting" -- not just once already "playing" --
        // because the poll itself is what confirms mpv is up and
        // promotes streamStatus to playing/paused/buffering. Waiting for
        // status to already say "playing" before ever polling would mean
        // nothing could ever make that first transition happen, which is
        // exactly how the UI used to get stuck on "Connecting" whenever
        // the launcher script's own success report raced or was missed.
        running: service.playMode === "streaming"
                 && (service.streamStatus === "connecting" || service._isStreamActive())
        triggeredOnStart: true
        onTriggered: service._pollStreamProgress()
    }

    // ══════════════════════════════════════════════════════════════════
    // WEB MODE
    // ══════════════════════════════════════════════════════════════════

    /*
     * playWeb(source, type)
     * ----------------------
     * source: a URL string (type "url") or an absolute path to a local
     *         HTML file (type "local").
     *
     * URL sources take the exact same mpvpaper/mpv path as playUrl().
     * Local HTML launches a kiosk-mode browser instead (mpv cannot
     * render HTML); its pid is stored in the monitor's own "pid" state
     * file, exactly where mpvpaper's pid normally goes, so the existing
     * lw_kill_mpvpaper_for_monitor / stop_wallpaper.sh path tears it
     * down identically without needing to know it's a browser.
     */
    function playWeb(source, type) {
        const trimmed = source ? source.trim() : "";
        if (trimmed.length === 0) {
            NotifyService.error(type === "local" ? "No HTML file selected." : "Invalid URL.");
            return;
        }

        if (applyProc.running) applyProc.running = false;
        if (navigationProc.running) navigationProc.running = false;
        if (streamProc.running) streamProc.running = false;
        if (webProc.running) webProc.running = false;
        service._dropQueuedApplyActions();
        service.pendingActions = [];
        service.busy = false;
        service.busyTimeout.stop();

        playMode = "web";
        webSource = trimmed;
        webSourceType = type || "url";
        webStatus = "connecting";
        webTitle = "";
        _clearStreamState();

        service._dispatch(webProc, "web_wallpaper.sh", [trimmed, webSourceType]);

        // Title lookup only makes sense for URL sources (mpv/yt-dlp path).
        if (webSourceType === "url") {
            webInfoProc.command = ["bash", Paths.script("stream_info.sh"), trimmed];
            webInfoProc.running = true;
        }
    }

    /*
     * reloadWeb()
     * -----------
     * Re-apply the current web source from scratch (e.g. after editing
     * the page, or after Clear Cache). A thin wrapper over playWeb() so
     * it goes through the exact same teardown-then-relaunch path.
     */
    function reloadWeb() {
        if (!webSource || webSource.trim().length === 0) return;
        playWeb(webSource, webSourceType);
    }

    function stopWeb() {
        webStatus = "idle";
        service.pendingActions = [];
        service.busy = false;
        service.busyTimeout.stop();
        if (webInfoProc.running) webInfoProc.running = false;
        if (stopProc.running) return;
        _dispatch(stopProc, "stop_wallpaper.sh", []);
    }

    function _clearWebState() {
        webSource = "";
        webSourceType = "url";
        webStatus = "idle";
        webTitle = "";
        if (webInfoProc.running) webInfoProc.running = false;
    }

    // ══════════════════════════════════════════════════════════════════
    // UNIFIED STOP — safe to call from mode-switching code
    // ══════════════════════════════════════════════════════════════════

    /*
     * stopAll()
     * ---------
     * Stops whatever is currently playing or dispatching (wallpaper,
     * stream, or web), clears all three modes' state, and returns
     * PlaybackService to idle. Called by LiveWallpaperPanel whenever the
     * user switches mode tabs away from one that's actively playing, so
     * a wallpaper/stream/web session can never keep running behind a
     * different mode's tab -- the single guarantee this whole merge
     * exists to preserve: at most one mpvpaper (or kiosk browser) alive
     * per monitor, ever.
     *
     * stopAllFinished() fires once stopProc actually exits -- i.e. once
     * mpvpaper/the kiosk browser are CONFIRMED dead, not just "asked to
     * stop" (stop_wallpaper.sh blocks on its own kill-and-wait loop
     * before returning, see utils.sh's lw_kill_mpvpaper). Purely
     * additive: existing callers that never listen for it are completely
     * unaffected. Added so ApplicationService.exit() can wait for a real
     * clean stop before closing the app, instead of racing it.
     */
    signal stopAllFinished()

    function stopAll() {
        if (applyProc.running) applyProc.running = false;
        if (navigationProc.running) navigationProc.running = false;
        if (streamProc.running) streamProc.running = false;
        if (webProc.running) webProc.running = false;
        service.pendingActions = [];
        service.busy = false;
        service.busyTimeout.stop();
        if (streamInfoProc.running) streamInfoProc.running = false;
        if (webInfoProc.running) webInfoProc.running = false;

        _clearStreamState();
        _clearWebState();
        playMode = "wallpapers";

        if (stopProc.running) return;
        _dispatch(stopProc, "stop_wallpaper.sh", []);
    }

    // Called from every dispatch Process.onExited. This is just "did the
    // script manage to even START the real work" -- a non-zero exit here
    // means it failed immediately (bad args, missing video, empty
    // library, ...) with no background worker ever launched, so there is
    // no later apply_status update to wait for: clear busy now and show
    // the error. A zero exit just means "dispatched successfully" --
    // busy stays true until statusView reports the real outcome.
    function _dispatchExited(exitCode, errText) {
        if (exitCode !== 0) {
            busy = false;
            busyTimeout.stop();
            const msg = (errText && errText.trim().length > 0)
                ? errText.trim().split("\n").pop()
                : "Command failed (exit code " + exitCode + "). Check ~/.cache/livewallpaper/livewallpaper.log";
            NotifyService.error(msg);
            // Propagate an immediate dispatch failure to whichever mode
            // it belongs to, so the panel doesn't sit on "connecting..."
            // forever waiting for an apply_status update that will never
            // come (the worker never even launched).
            if (service.playMode === "streaming") service.streamStatus = "error";
            else if (service.playMode === "web") service.webStatus = "error";
            service._drainActions();
        }
    }

    // Safety net: if a background worker crashes/hangs before ever
    // writing a status update, don't leave the UI stuck showing "busy"
    // forever.
    property Timer busyTimeout: Timer {
        interval: 30000
        onTriggered: {
            if (service.busy) {
                service.busy = false;
                // A worker crashed/hung before ever writing apply_status
                // -- don't leave the streaming/web UI stuck on
                // "connecting..." forever either.
                if (service.playMode === "streaming" && service.streamStatus === "connecting") {
                    service.streamStatus = "error";
                    service._resetStreamControls();
                } else if (service.playMode === "web" && service.webStatus === "connecting") service.webStatus = "error";
                currentView.reload();
                pollRunning.running = true;
                service._drainActions();
            }
        }
    }

    function _repathForMonitor() {
        currentView.path = Paths.monitorStateFile(selectedMonitor, "current");
        currentView.reload();
        statusView.path = Paths.monitorStateFile(selectedMonitor, "apply_status");
        statusView.reload();
        pollRunning.running = true;
    }

    onSelectedMonitorChanged: _repathForMonitor()
    Component.onCompleted: _repathForMonitor()

    property FileView currentView: FileView {
        id: currentView
        path: Paths.monitorStateFile("auto", "current")
        watchChanges: true
        // The file may legitimately not exist (nothing applied yet, or
        // just Stopped) — that's not an error, just "no current wallpaper".
        onFileChanged: reload()
        onLoaded: {
            const raw = text().trim();
            // _stream_worker.sh / _web_worker.sh record their source in
            // this same "current" file, prefixed so it's distinguishable
            // at a glance in the raw state directory -- but currentPath
            // is specifically "the local file path currently playing",
            // so streaming/web sources are represented via streamUrl/
            // webSource instead and never surface here.
            if (raw.startsWith("stream:") || raw.startsWith("web:") || raw.startsWith("web-local:")) {
                service.currentPath = "";
            } else {
                service.currentPath = raw;
            }
        }
        onLoadFailed: { service.currentPath = ""; }
    }

    // The authoritative source of "did the last action actually succeed",
    // written asynchronously by the bash worker instead of being inferred
    // from a blocking process exit.
    property FileView statusView: FileView {
        id: statusView
        path: Paths.monitorStateFile("auto", "apply_status")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const status = JSON.parse(text());
                if (status.state === "pending") {
                    service.busy = true;
                } else if (status.state === "success") {
                    service.busy = false;
                    service.busyTimeout.stop();
                    service._drainActions();
                    currentView.reload();
                    pollRunning.running = true;
                    // Only a "connecting" session actually finished
                    // starting up -- a success status while stopStream/
                    // stopWeb had already moved streamStatus/webStatus to
                    // "stopping" is stop_wallpaper.sh's OWN success
                    // report, not a late launch confirmation, and must
                    // not resurrect it back to "playing". stopProc.onExited
                    // below is what settles the stopping case to idle.
                    if (service.playMode === "streaming" && service.streamStatus === "connecting") service.streamStatus = "playing";
                    else if (service.playMode === "web" && service.webStatus === "connecting") service.webStatus = "playing";
                } else if (status.state === "error") {
                    service.busy = false;
                    service.busyTimeout.stop();
                    service._drainActions();
                    if (status.message) NotifyService.error(status.message);
                    pollRunning.running = true;
                    if (service.playMode === "streaming" && service.streamStatus !== "idle") {
                        service.streamStatus = "error";
                        service._resetStreamControls();
                    } else if (service.playMode === "web" && service.webStatus !== "idle") service.webStatus = "error";
                }
            } catch (e) {
                console.warn("PlaybackService: failed to parse apply_status:", e);
            }
        }
        onLoadFailed: { /* no status yet -- nothing applied on this monitor so far, not an error */ }
    }

    property Process applyProc: Process {
        id: applyProc
        stderr: StdioCollector { id: applyErr }
        onExited: (code, status) => service._dispatchExited(code, applyErr.text)
    }
    property Process navigationProc: Process {
        id: navigationProc
        stderr: StdioCollector { id: navigationErr }
        onExited: (code, status) => {
            // Debug trace for the Next/Previous/Random dispatcher --
            // confirms whether apply_wallpaper.sh was even launched
            // successfully; the actual playing/error outcome still
            // arrives separately via statusView (apply_status file).
            console.log("[WALLPAPER] navigationProc exited code=" + code + " current=" + service.currentPath);
            if (code !== 0) {
                // _applyNavigationTarget()'s optimistic currentPath update
                // assumed this dispatch would succeed. It didn't (the
                // dispatcher itself failed to even launch
                // apply_wallpaper.sh's worker) -- resync currentPath from
                // the actual on-disk state rather than leaving it pointed
                // at a wallpaper that was never really applied.
                currentView.reload();
            }
            service._dispatchExited(code, navigationErr.text);
        }
    }
    property Process toggleProc: Process {
        id: toggleProc
        stderr: StdioCollector { id: toggleErr }
        onExited: (code, status) => service._dispatchExited(code, toggleErr.text)
    }
    property Process startProc: Process {
        id: startProc
        stderr: StdioCollector { id: startErr }
        onExited: (code, status) => service._dispatchExited(code, startErr.text)
    }
    property Process stopProc: Process {
        id: stopProc
        stderr: StdioCollector { id: stopErr }
        onExited: (code, status) => {
            // stop_wallpaper.sh does its work synchronously (unlike
            // apply/stream/web, it is not a detached worker), so by the
            // time this Process exits the kill + apply_status write are
            // already done -- settle stream/web state to idle right
            // here rather than waiting on statusView, which also means
            // this can never be confused with a late "connecting ->
            // playing" transition (see statusView.onLoaded's guard).
            if (service.playMode === "streaming") service._clearStreamState();
            else if (service.playMode === "web") service._clearWebState();
            service._dispatchExited(code, stopErr.text);
            service.stopAllFinished();
        }
    }
    property Process nextProc: Process {
        id: nextProc
        stderr: StdioCollector { id: nextErr }
        onExited: (code, status) => service._dispatchExited(code, nextErr.text)
    }
    property Process previousProc: Process {
        id: previousProc
        stderr: StdioCollector { id: previousErr }
        onExited: (code, status) => service._dispatchExited(code, previousErr.text)
    }
    property Process randomProc: Process {
        id: randomProc
        stderr: StdioCollector { id: randomErr }
        onExited: (code, status) => service._dispatchExited(code, randomErr.text)
    }

    // ── Streaming & Web dispatch processes ───────────────────────────────
    // Same shape as every process above: a short-lived dispatcher whose
    // non-zero exit means "never even got to launch the background
    // worker" (handled by _dispatchExited). A zero exit means "dispatched
    // OK" -- the real playing/error outcome arrives via statusView, same
    // as apply_wallpaper.sh.
    property Process streamProc: Process {
        id: streamProc
        stderr: StdioCollector { id: streamErr }
        onExited: (code, status) => {
            const finishedGen = service._streamProcGen;
            const pending = service._streamPendingLaunch;
            if (pending) {
                // This exit is the OLD instance we asked to terminate so
                // a newer playUrl()/_relaunchStream() could take over --
                // it's now confirmed dead, so launch the deferred
                // request. Its own exit code is irrelevant (it was
                // killed on purpose); do not touch streamStatus here.
                service._streamPendingLaunch = null;
                service._streamProcGen = pending.gen;
                service._dispatch(streamProc, "stream_wallpaper.sh", pending.args);
                return;
            }
            // No relaunch queued behind this exit: only treat a failure
            // as real if nothing has superseded this generation since it
            // was dispatched (a relaunch/new URL/mode switch/stop already
            // moved on) -- otherwise this is a stale exit and must not
            // overwrite whatever streamStatus is now current.
            if (code !== 0 && finishedGen === service._streamGen) {
                service.streamStatus = "error";
                service._dispatchExited(code, streamErr.text);
            }
        }
    }

    // Fire-and-forget metadata lookup (title/thumbnail/uploader/live/
    // height) via stream_info.sh. Deliberately has no bearing on playback
    // success -- a stream plays fine with {} metadata, this is cosmetic.
    property Process streamInfoProc: Process {
        id: streamInfoProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text || text.trim().length === 0) return;
                try {
                    const info = JSON.parse(text.trim());
                    if (service.playMode === "streaming") {
                        if (info.title)     service.streamTitle     = info.title;
                        if (info.thumbnail) service.streamThumbnail = info.thumbnail;
                        if (info.uploader)  service.streamUploader  = info.uploader;
                        service.streamIsLive = !!info.live;
                        if (info.height) service.streamHeight = parseInt(info.height, 10) || 0;
                        if (info.duration) service.streamMetaDuration = Number(info.duration) || 0;
                    }
                } catch (e) {}
            }
        }
    }

    property Process webProc: Process {
        id: webProc
        stderr: StdioCollector { id: webErr }
        onExited: (code, status) => {
            if (code !== 0) {
                service.webStatus = "error";
                service._dispatchExited(code, webErr.text);
            }
        }
    }

    property Process webInfoProc: Process {
        id: webInfoProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text || text.trim().length === 0) return;
                try {
                    const info = JSON.parse(text.trim());
                    if (service.playMode === "web" && info.title) {
                        service.webTitle = info.title;
                    }
                } catch (e) {}
            }
        }
    }

    // -------------------- RUNNING-STATE POLL --------------------
    // "auto" -> is ANY mpvpaper alive (original single-monitor semantics).
    // specific monitor -> is THAT monitor's recorded pid alive.
    property Process pollRunning: Process {
        id: pollRunning
        command: {
            if (service.selectedMonitor && service.selectedMonitor !== "auto") {
                const pidFile = Paths.monitorStateFile(service.selectedMonitor, "pid");
                return ["bash", "-c", "f=" + JSON.stringify(pidFile) + "; [ -s \"$f\" ] && kill -0 \"$(cat \"$f\")\" 2>/dev/null && echo true || echo false"];
            }
            return ["bash", "-c", "pgrep -x mpvpaper >/dev/null 2>&1 && echo true || echo false"];
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const wasRunning = service.running;
                service.running = (text.trim() === "true");
                // mpvpaper died unexpectedly (crash, killed out-of-band,
                // network drop for a stream, ...) -- reflect that in
                // whichever mode's status was claiming "playing", so the
                // panel doesn't keep showing a dead stream/web session as
                // live. Web-local (kiosk browser) isn't polled by this
                // mpvpaper-name check, so it's deliberately left alone
                // here; its own process exiting is what settles it.
                if (wasRunning && !service.running) {
                    // mpvpaper vanished while we thought it was playing --
                    // that IS a real backend failure (crash, killed
                    // out-of-band, network drop), so it must read as
                    // Error, not silently fall back to idle/nothing-
                    // playing. A user-requested stop always goes through
                    // stopStream()/stopProc.onExited instead, which
                    // already settles streamStatus to "idle" before this
                    // poll ever sees running flip -- so this branch only
                    // ever fires for the unexpected-death case.
                    if (service.playMode === "streaming" && service._isStreamActive()) {
                        service.streamStatus = "error";
                        service._resetStreamControls();
                        NotifyService.error("Stream stopped unexpectedly (mpvpaper exited).");
                    } else if (service.playMode === "web" && service.webSourceType === "url" && service.webStatus === "playing") {
                        // Match the streaming branch immediately above: mpvpaper
                        // vanishing during a web-URL session is a real backend
                        // failure, NOT a clean stop -- a user-requested stop
                        // always goes through stopWeb()/stopProc.onExited,
                        // which already settles webStatus to "idle" before
                        // this poll ever sees running flip. Setting "idle"
                        // here would silently hide the death.
                        service.webStatus = "error";
                        service._resetStreamControls();
                        NotifyService.error("Web URL stopped unexpectedly (mpvpaper exited).");
                    }
                }
            }
        }
    }

    property Timer pollTimer: Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: pollRunning.running = true
    }

    // -------------------- NATIVE AUTOSTART --------------------
    property Process autostartCheck: Process {
        id: autostartCheck
        command: ["bash", "-c", "pgrep -x mpvpaper >/dev/null 2>&1 && echo true || echo false"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "true" && SettingsService.autostart) {
                    service.start();
                }
            }
        }
    }

    property Timer autostartTimer: Timer {
        interval: 1500 // let Hyprland/monitors settle before mpvpaper attaches
        running: true
        repeat: false
        onTriggered: autostartCheck.running = true
    }

    // -------------------- SMART PLAYBACK (local wallpaper full stop/restore) --------------------
    // Smart Playback for a LOCAL wallpaper (playMode === "wallpapers") is
    // a genuine STOP, not a pause: mpvpaper is completely terminated
    // (CPU/GPU usage -> ~0) and, on restore, relaunched from scratch.
    // This deliberately reuses the exact same scripts the manual
    // Stop/Start Wallpaper buttons already use --
    // scripts/stop_wallpaper.sh (kills mpvpaper by its tracked PID,
    // falls back to a pgrep sweep, clears the per-monitor "current"
    // file) and scripts/start_wallpaper.sh (replays whatever was last
    // recorded in that monitor's "last"/"resolution"/"fps" state --
    // NOT cleared by Stop) -- so playlist position, favorites, history,
    // random state, and monitor assignment all survive untouched: they
    // live in WallpaperService/PlaylistService/HistoryService/
    // SettingsService, none of which this block ever touches, and
    // "last" is exactly what apply()/next()/previous()/random() already
    // wrote the moment that wallpaper was chosen. No second stop
    // implementation, no second launch pipeline.
    //
    // All of the actual DECISION making (which condition triggered a
    // stop, which monitor(s) it applies to, whether Smart Playback is
    // even on) lives in Services/SmartPlaybackService.qml -- this block
    // only exposes the primitives it calls into, plus tracks which
    // monitors Smart Playback itself stopped (so a later restore never
    // fires for a monitor the user already changed manually, and so a
    // rapid re-trigger is a no-op instead of a redundant dispatch).
    property var smartStoppedMonitors: ({}) // { monitorNameOrLegacySlot: true }

    function _anyMonitorSmartStopped() {
        return Object.keys(smartStoppedMonitors).length > 0;
    }

    // Single-flight, latest-wins dispatch queue keyed by monitor slot.
    // A rapid fullscreen enter/exit/enter/exit only ever leaves ONE
    // pending op per monitor (the newest one overwrites the old,
    // still-undispatched one) and never runs two stop_wallpaper.sh /
    // start_wallpaper.sh processes for the same monitor concurrently --
    // that is what guarantees "always end in the correct state, never
    // start multiple restore jobs, never leave a stale PID file" even
    // under a flapping fullscreen signal.
    property var _smartStopQueue: ({}) // { monitorKey: "stop"|"start" }

    function _queueSmartStopOp(monitorKey, op) {
        const q = Object.assign({}, service._smartStopQueue);
        q[monitorKey] = op;
        service._smartStopQueue = q;
        service._drainSmartStopQueue();
    }
    function _drainSmartStopQueue() {
        if (_smartStopProc.running) return;
        const keys = Object.keys(service._smartStopQueue);
        if (keys.length === 0) return;
        const monitorKey = keys[0];
        const op = service._smartStopQueue[monitorKey];
        const q = Object.assign({}, service._smartStopQueue);
        delete q[monitorKey];
        service._smartStopQueue = q;
        const script = op === "stop" ? "stop_wallpaper.sh" : "start_wallpaper.sh";
        _smartStopProc.command = ["bash", Paths.script(script)].concat(monitorKey ? [monitorKey] : []);
        _smartStopProc.running = true;
    }
    property Process _smartStopProc: Process {
        id: _smartStopProc
        onExited: {
            service.pollRunning.running = true; // reflect the change without waiting for the next 2s tick
            service._drainSmartStopQueue();
        }
    }

    // Per-monitor targeting (Smart Playback's "only the affected
    // monitor" multi-monitor scope).
    function smartStopWallpaperOnMonitor(monitor) {
        if (playMode !== "wallpapers") return;
        const key = (monitor && monitor !== "auto") ? monitor : "";
        if (smartStoppedMonitors[key]) return; // already stopped -- avoid a redundant dispatch
        service._queueSmartStopOp(key, "stop");
        const next = Object.assign({}, smartStoppedMonitors);
        next[key] = true;
        smartStoppedMonitors = next;
    }
    function smartStartWallpaperOnMonitor(monitor) {
        if (playMode !== "wallpapers") return;
        const key = (monitor && monitor !== "auto") ? monitor : "";
        if (!smartStoppedMonitors[key]) return;
        service._queueSmartStopOp(key, "start");
        const next = Object.assign({}, smartStoppedMonitors);
        delete next[key];
        smartStoppedMonitors = next;
    }

    // Whole-system targeting (Smart Playback's "stop all monitors"
    // scope, and every global condition -- battery/lock/gaming -- which
    // always applies everywhere regardless of scope).
    function smartStopAllWallpapers() {
        if (playMode !== "wallpapers") return;
        const monitors = MultiMonitorService.monitors;
        const keys = monitors.length > 0 ? monitors.map(m => m.name) : [""];
        // Already stopped everywhere it matters -- avoid a redundant
        // dispatch while the trigger condition persists (e.g. the 3s
        // battery/lock/gaming poll). Checked against every REQUIRED key
        // rather than "any", so a global trigger arriving after a
        // focused-scope stop already covered only some monitors still
        // catches the rest.
        if (keys.every(k => smartStoppedMonitors[k])) return;
        service._queueSmartStopOp("", "stop"); // stop_wallpaper.sh with no monitor arg stops every monitor
        const next = Object.assign({}, smartStoppedMonitors);
        for (const k of keys) next[k] = true;
        next[""] = true; // legacy single-monitor slot too
        smartStoppedMonitors = next;
    }
    function smartStartAllWallpapers() {
        if (playMode !== "wallpapers") return;
        if (!service._anyMonitorSmartStopped()) return;
        // Only restart monitors actually tracked as smart-stopped --
        // never every monitor unconditionally -- so a monitor Smart
        // Playback left running the whole time (e.g. a focused-scope
        // stop that only ever touched one output) is never relaunched
        // for no reason.
        const realKeys = Object.keys(smartStoppedMonitors).filter(k => k !== "");
        if (realKeys.length > 0) {
            for (const k of realKeys) service._queueSmartStopOp(k, "start");
        } else {
            // Only the legacy/global slot was tracked -- single-monitor
            // setup. start_wallpaper.sh with no arg auto-detects the
            // focused monitor, same legacy fallback the rest of this
            // file already relies on.
            service._queueSmartStopOp("", "start");
        }
        smartStoppedMonitors = ({});
    }

    // -------------------- PERFORMANCE MODE (battery-saver) --------------------
    // When settings.performance === "battery-saver": stepping onto battery
    // auto-downgrades to settings.battery_resolution/battery_fps; stepping
    // back onto AC restores whatever quality was selected before.
    //
    // FIX v1.1 — debounced battery transitions:
    //   The old design called apply() immediately on every onBattery change.
    //   If the power/battery driver briefly flaps (Discharging → Charging →
    //   Discharging within a few seconds — common on USB-C PD adapters and
    //   some laptops), this caused the wallpaper worker to be cancelled and
    //   relaunched on each flap, producing visible lag/stutter and the
    //   Low ↔ Balanced/Ultra cycling the user sees in the UI.
    //
    //   Solution: _applyPerformanceModeFor() now only records the desired
    //   target state and (re)starts a 4-second settle timer.  The actual
    //   resolution change + wallpaper re-apply only happen once the power
    //   state has been stable for 4 s.  Rapid flapping → a single,
    //   deferred restart rather than N restarts.

    // Tracks the most-recent desired battery-mode state.  Set immediately
    // on each onBattery change; consumed by _batterySettleTimer.
    property bool _pendingOnBattery: false

    // 4-second settle window: restarted on every power-state change.
    // Fires once the state is stable.
    property Timer _batterySettleTimer: Timer {
        id: batterySettleTimer
        interval: 4000
        repeat: false
        onTriggered: service._commitBatteryMode(service._pendingOnBattery)
    }

    // Called only by _batterySettleTimer — never directly.
    // Applies the settled battery state exactly once.
    function _commitBatteryMode(onBattery) {
        if (SettingsService.performanceMode !== "battery-saver") return;

        if (onBattery && !service._batterySaverActive) {
            service._preBatteryResolution = service.selectedResolution;
            service._preBatteryFps        = service.selectedFps;
            service.selectedResolution    = SettingsService.batteryResolution;
            service.selectedFps           = SettingsService.batteryFps;
            service._batterySaverActive   = true;
            NotifyService.info("On battery — switched to " + SettingsService.batteryResolution + "/" + SettingsService.batteryFps + "fps to save power.");
            // Resolution/fps only govern local wallpaper playback -- a
            // streaming/web session ignores selectedResolution entirely
            // (see stream/web worker scripts), so there is nothing to
            // re-apply for those modes here.
            if (service.currentPath && service.playMode === "wallpapers") service.apply(service.currentPath);

        } else if (!onBattery && service._batterySaverActive) {
            if (service._preBatteryResolution) service.selectedResolution = service._preBatteryResolution;
            if (service._preBatteryFps)        service.selectedFps        = service._preBatteryFps;
            service._batterySaverActive = false;
            NotifyService.info("On AC power — restored " + service.selectedResolution + "/" + service.selectedFps + "fps.");
            if (service.currentPath && service.playMode === "wallpapers") service.apply(service.currentPath);
        }
        // else: state already matches (no actual transition) — no-op
    }

    // Entry point — called on every onBattery change.
    // Only records the desired target and resets the settle timer.
    function _applyPerformanceModeFor(onBattery) {
        if (SettingsService.performanceMode !== "battery-saver") return;
        service._pendingOnBattery = onBattery;
        batterySettleTimer.restart();
    }

    property Connections _powerConnections: Connections {
        target: PowerService
        function onOnBatteryChanged() {
            service._applyPerformanceModeFor(PowerService.onBattery);
        }
    }
}
