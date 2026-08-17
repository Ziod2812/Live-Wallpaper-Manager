pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

/*
 * SmartPlaybackService.qml
 * ---------------------------
 * "Smart Playback" -- the decision layer only. This file owns none of
 * the actual playback machinery: it watches for five trigger conditions
 * (fullscreen app, on battery, monitor asleep, screen locked, gaming)
 * and calls into EXISTING services to react --
 * PlaybackService.smartStop/StartWallpaperOnMonitor() and
 * smartStop/StartAllWallpapers() for a LOCAL wallpaper -- a genuine
 * mpvpaper termination + relaunch, NOT a pause (see PlaybackService's
 * own "SMART PLAYBACK" section) -- PlaybackService.pauseStream()/
 * resumeStream() (already existed, reused verbatim -- streaming has its
 * own mpv-IPC pause primitive, which already drives CPU/GPU to ~0
 * without losing the connection, so it is intentionally left as-is)
 * for Streaming mode, PowerService for battery state,
 * MultiMonitorService for the monitor list, NotifyService for the
 * optional toast. No new playback engine, no new mpvpaper handling --
 * this file is pure orchestration on top of what already exists.
 *
 * Two background sources feed it, both started/stopped in lockstep with
 * `enabled` (and, for the poll, with whichever of its three options are
 * actually turned on) so Smart Playback OFF costs exactly nothing --
 * "Ignore all Smart Playback logic... No CPU overhead":
 *
 *   - watcherProc (scripts/smart_playback_watch.sh): a long-running,
 *     EVENT-DRIVEN process blocking on Hyprland's own IPC socket --
 *     drives pauseOnFullscreen. ~0 CPU while nothing on screen is
 *     changing; restarted automatically if it ever exits, same pattern
 *     WatcherService.qml already uses for watch_wallpaper_dir.sh.
 *   - pollTimer + pollProc (scripts/smart_playback_poll.sh): a light,
 *     infrequent (3s) status check for the three conditions Hyprland has
 *     no event for (screen lock, monitor DPMS, GameMode) -- same
 *     "infrequent poll for something slow-changing" precedent already
 *     set by PowerService's own 45s battery poll.
 *
 * Multi-monitor scope ("all" vs "focused") only actually differentiates
 * the two per-output conditions (fullscreen, monitor sleep) -- battery/
 * lock/gaming are whole-system states with no meaningful "which
 * monitor" question, so those always pause every monitor regardless of
 * scope, matching how a locked session or a dead battery affects every
 * output equally.
 *
 * Settings are read directly off SettingsService.settings with a
 * guarded fallback (same pattern PlaybackService's streamLoop/
 * streamMuted/streamQuality and Components/MusicDockPanel.qml's every
 * reader already use) rather than added to SettingsService's
 * DEFAULT_SETTINGS -- settings.sh already accepts arbitrary keys, so no
 * schema change was needed anywhere for this feature, and upgrades with
 * no settings.json entry yet still get sane defaults.
 */
QtObject {
    id: service

    // ── Settings ──────────────────────────────────────────────────────────
    readonly property bool enabled: SettingsService.settings.smart_playback_enabled === true

    readonly property bool pauseOnFullscreen:   SettingsService.settings.smart_playback_pause_fullscreen !== false
    readonly property bool pauseOnBattery:      SettingsService.settings.smart_playback_pause_battery === true
    readonly property bool pauseOnMonitorSleep: SettingsService.settings.smart_playback_pause_monitor_sleep !== false
    readonly property bool pauseOnScreenLock:   SettingsService.settings.smart_playback_pause_screen_lock !== false
    readonly property bool pauseWhileGaming:    SettingsService.settings.smart_playback_pause_gaming === true
    readonly property bool notificationsOn:     SettingsService.settings.smart_playback_notifications !== false

    // "all" (pause every monitor together) | "focused" (only the
    // monitor(s) actually triggering fullscreen/sleep)
    readonly property string scope: {
        const v = SettingsService.settings.smart_playback_scope;
        return v === "focused" ? "focused" : "all";
    }

    function setEnabled(v) { SettingsService.set("smart_playback_enabled", !!v); }
    function setScope(v) { SettingsService.set("smart_playback_scope", v); }
    function setOption(key, value) { SettingsService.set(key, !!value); }

    // ── Live detected state ──────────────────────────────────────────────
    property var fullscreenMonitors: ({}) // {monitorName: bool}, from watcherProc
    property var sleepingMonitors: ({})   // {monitorName: bool}, from pollProc
    property bool screenLocked: false     // from pollProc
    property bool gamingActive: false     // from pollProc

    // What's actually shown in the panel / notifications right now.
    property bool paused: false
    property string pauseReason: "" // "fullscreen application" | "on battery" | "screen locked" | "gaming" | "monitor asleep" | ""

    function _anyTrue(obj) {
        for (const k in obj) { if (obj[k]) return true; }
        return false;
    }

    // ================== FULLSCREEN WATCHER (event-driven) ==================
    function _wantFullscreenWatcher() {
        return service.enabled && service.pauseOnFullscreen;
    }

    property Process watcherProc: Process {
        id: watcherProc
        command: ["bash", Paths.script("smart_playback_watch.sh")]
        stdout: SplitParser {
            onRead: (line) => {
                if (line === "MISSING_DEPENDENCY") return; // non-Hyprland/no-python3 -- this one option just stays inert
                try {
                    const parsed = JSON.parse(line);
                    if (parsed && typeof parsed === "object") {
                        service.fullscreenMonitors = parsed;
                        service._evaluate();
                    }
                } catch (e) { /* malformed line -- the next one still lands */ }
            }
        }
        onExited: (code, status) => {
            if (service._wantFullscreenWatcher()) service.watcherRestartTimer.restart();
        }
    }
    property Timer watcherRestartTimer: Timer {
        id: watcherRestartTimer
        interval: 2000
        onTriggered: { if (service._wantFullscreenWatcher()) watcherProc.running = true; }
    }

    // ================== LOCK / SLEEP / GAMING (light poll) ==================
    function _wantPoll() {
        return service.enabled && (service.pauseOnMonitorSleep || service.pauseOnScreenLock || service.pauseWhileGaming);
    }

    property Process pollProc: Process {
        id: pollProc
        command: ["bash", Paths.script("smart_playback_poll.sh")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    service.screenLocked = !!parsed.locked;
                    service.gamingActive = !!parsed.gaming;
                    const sleeping = {};
                    (parsed.sleeping || []).forEach(name => { sleeping[name] = true; });
                    service.sleepingMonitors = sleeping;
                } catch (e) { /* transient parse hiccup -- the next poll corrects it */ }
                service._evaluate();
            }
        }
    }
    property Timer pollTimer: Timer {
        id: pollTimer
        interval: 3000
        repeat: true
        triggeredOnStart: true
        onTriggered: { if (!pollProc.running) pollProc.running = true; }
    }

    // ================== START/STOP alongside `enabled`/options ==================
    function _syncBackgroundWork() {
        if (service._wantFullscreenWatcher()) {
            if (!watcherProc.running) watcherProc.running = true;
        } else {
            watcherRestartTimer.stop();
            if (watcherProc.running) watcherProc.running = false;
            service.fullscreenMonitors = ({});
        }

        if (service._wantPoll()) {
            pollTimer.running = true;
        } else {
            pollTimer.running = false;
            if (pollProc.running) pollProc.running = false;
            service.screenLocked = false;
            service.gamingActive = false;
            service.sleepingMonitors = ({});
        }

        if (!service.enabled) {
            service._resumeEverything();
        }
        service._evaluate();
    }

    Component.onCompleted: _syncBackgroundWork()

    property Connections _settingsConn: Connections {
        target: SettingsService
        function onSettingsChanged() { service._syncBackgroundWork(); }
    }
    property Connections _powerConn: Connections {
        target: PowerService
        function onOnBatteryChanged() { service._evaluate(); }
    }
    property Connections _playbackConn: Connections {
        target: PlaybackService
        function onPlayModeChanged() { service._evaluate(); }
        function onRunningChanged() { service._evaluate(); }
        function onSelectedMonitorChanged() { service._evaluate(); }
        function onStreamStatusChanged() { service._evaluate(); }
    }
    property Connections _monitorConn: Connections {
        target: MultiMonitorService
        function onMonitorsChanged() { service._evaluate(); }
    }

    // ================== DECISION LOGIC ==================
    function _resumeEverything() {
        if (PlaybackService.playMode === "wallpapers") {
            PlaybackService.smartStartAllWallpapers();
        } else if (PlaybackService.playMode === "streaming" && PlaybackService.streamActive && PlaybackService.streamPaused) {
            PlaybackService.resumeStream();
        }
        if (service.paused) {
            service.paused = false;
            service.pauseReason = "";
        }
    }

    function _globalReason() {
        if (service.pauseOnScreenLock && service.screenLocked) return "screen locked";
        if (service.pauseWhileGaming && service.gamingActive) return "gaming";
        if (service.pauseOnBattery && PowerService.onBattery) return "on battery";
        return "";
    }

    function _evaluate() {
        if (!service.enabled) return; // _syncBackgroundWork already resumed everything

        const mode = PlaybackService.playMode;

        // Streaming: single global mpvpaper instance, no per-monitor
        // targeting to speak of -- reuse the EXISTING stream pause/
        // resume primitives verbatim, no new IPC path invented here.
        if (mode === "streaming") {
            const globalReason = service._globalReason();
            const fsReason = (service.pauseOnFullscreen && service._anyTrue(service.fullscreenMonitors)) ? "fullscreen application" : "";
            const slReason = (service.pauseOnMonitorSleep && service._anyTrue(service.sleepingMonitors)) ? "monitor asleep" : "";
            const reason = globalReason || fsReason || slReason;

            if (reason && PlaybackService.streamActive && !PlaybackService.streamPaused) {
                PlaybackService.pauseStream();
                service._announce(true, reason);
            } else if (!reason && PlaybackService.streamActive && PlaybackService.streamPaused && service.paused) {
                // Only auto-resume a pause Smart Playback itself caused --
                // never override a pause the user set with their own
                // pause button (guarded by `service.paused`).
                PlaybackService.resumeStream();
                service._announce(false, "");
            }
            return;
        }

        if (mode !== "wallpapers") return; // Web mode: no pause primitive exists for it (kiosk browser / mpv-web have no safe freeze here) -- left running, by design

        // Nothing to do only when there is truly nothing playing AND
        // Smart Playback itself has nothing stopped to restore. Unlike
        // the old SIGSTOP design (where a frozen process still reported
        // "running"), a genuinely killed mpvpaper makes
        // PlaybackService.running go false -- so this guard must also
        // let evaluation continue while `service.paused` is true, or a
        // fullscreen-exit could never be noticed and the wallpaper would
        // stay stopped forever.
        if (!PlaybackService.running && !service.paused) return;

        const globalReason = service._globalReason();
        if (globalReason) {
            PlaybackService.smartStopAllWallpapers();
            service._announce(true, globalReason);
            return;
        }

        const monNames = MultiMonitorService.monitors.map(m => m.name);

        if (monNames.length === 0) {
            // Single-monitor / monitor list not populated yet -- fall
            // back to whatever PlaybackService itself is targeting.
            const single = PlaybackService.selectedMonitor;
            const fs = service.pauseOnFullscreen && service._anyTrue(service.fullscreenMonitors);
            const sl = service.pauseOnMonitorSleep && service._anyTrue(service.sleepingMonitors);
            if (fs || sl) {
                PlaybackService.smartStopWallpaperOnMonitor(single);
                service._announce(true, fs ? "fullscreen application" : "monitor asleep");
            } else if (service.paused) {
                PlaybackService.smartStartWallpaperOnMonitor(single);
                service._announce(false, "");
            }
            return;
        }

        const triggered = monNames.filter(n =>
            (service.pauseOnFullscreen && service.fullscreenMonitors[n]) ||
            (service.pauseOnMonitorSleep && service.sleepingMonitors[n])
        );

        if (triggered.length === 0) {
            if (service.paused) {
                PlaybackService.smartStartAllWallpapers();
                service._announce(false, "");
            }
            return;
        }

        if (service.scope === "focused") {
            for (const n of monNames) {
                if (triggered.indexOf(n) !== -1) PlaybackService.smartStopWallpaperOnMonitor(n);
                else PlaybackService.smartStartWallpaperOnMonitor(n);
            }
        } else {
            PlaybackService.smartStopAllWallpapers();
        }
        const anyFs = triggered.some(n => service.fullscreenMonitors[n]);
        service._announce(true, anyFs ? "fullscreen application" : "monitor asleep");
    }

    function _announce(nowPaused, reason) {
        if (service.paused === nowPaused && service.pauseReason === reason) return; // no actual change -- don't spam
        service.paused = nowPaused;
        service.pauseReason = reason;
        if (!service.notificationsOn) return;
        // Wallpapers mode is a genuine stop/restore (mpvpaper fully
        // terminated then relaunched); streaming mode is a real mpv-IPC
        // pause/resume (connection kept alive) -- word the toast to
        // match what actually happened in each mode.
        const isFullStop = PlaybackService.playMode === "wallpapers";
        if (nowPaused) {
            NotifyService.info((isFullStop ? "⏸ Wallpaper stopped" : "⏸ Wallpaper paused") + (reason ? " (" + reason + ")" : ""));
        } else {
            NotifyService.info(isFullStop ? "▶ Wallpaper restored" : "▶ Wallpaper resumed");
        }
    }
}
