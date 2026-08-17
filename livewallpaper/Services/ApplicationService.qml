pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

/*
 * ApplicationService.qml
 * -------------------------
 * Orchestrates a clean "Exit Application": stops every timer that could
 * schedule new work, stops wallpaper/streaming/web playback (reusing
 * PlaybackService.stopAll() -- no stop logic is duplicated here), stops
 * stops thumbnail generation and other worker processes, flushes any
 * pending settings
 * write, and then emits readyToClose() once it's actually safe to close
 * the app's windows.
 *
 * This service only touches Process/Timer objects and calls existing
 * service methods -- it owns no windows. LiveWallpaperPanel.qml listens
 * for readyToClose() and is responsible for closing its own windows and
 * (only when running standalone) quitting the Qt application itself.
 */
QtObject {
    id: service

    property bool exiting: false
    // PHASE 4 -- system tray "Restart". Set by restart() before it calls
    // exit() so that whichever window is responsible for actually
    // quitting the Qt application once readyToClose() fires (see
    // LiveWallpaperPanel.qml's standalone-only Connections block) knows
    // to relaunch a fresh process afterwards instead of just quitting.
    // Deliberately reuses every line of exit()'s teardown rather than
    // duplicating it -- a restart is just "exit, then relaunch".
    property bool restarting: false
    signal readyToClose()

    // Tray "Restart" menu item. Same full teardown as exit() (stopping
    // timers/workers, mpvpaper/Cava/MPRIS, flushing settings) followed by
    // spawning a brand-new `quickshell -c livewallpaper` process and only
    // then quitting this one -- see LiveWallpaperPanel.qml's
    // onReadyToClose, which is where the actual relaunch Process lives
    // (this service owns no windows/processes of its own beyond the
    // teardown steps below, matching exit()'s existing scope).
    function restart() {
        if (exiting) return;
        restarting = true;
        exit();
    }

    function exit() {
        if (exiting) return;
        exiting = true;

        // 1. Stop every timer that could otherwise fire mid-teardown and
        //    schedule new work (a poll tick re-launching a status check,
        //    a countdown advancing the playlist, a debounce timer firing
        //    a fresh apply, etc). Imperatively clearing `running` here is
        //    fine even where it's normally driven by a binding (e.g.
        //    PlaylistService's timers bound to `enabled`) -- the app is
        //    closing, so there's no future state change left to react to.
        PlaybackService.pollTimer.running = false;
        PlaybackService.autostartTimer.running = false;
        PlaybackService.busyTimeout.running = false;
        PlaybackService._batterySettleTimer.running = false;
        PlaybackService.playProgressTimer.running = false;
        PlaybackService.streamProgressTimer.running = false;
        PlaybackService._seekDebounceTimer.running = false;

        WatcherService.stop(); // stops watcherProc + its restartTimer
        WatcherService.restartTimer.running = false; // in case a restart() was mid-debounce

        PlaylistService.advanceTimer.running = false;
        PlaylistService.countdownTimer.running = false;

        PowerService.pollTimer.running = false;
        MultiMonitorService.refreshTimer.running = false;
        WallpaperService.parseRetryTimer.running = false;

        SmartPlaybackService.pollTimer.running = false;
        SmartPlaybackService.watcherRestartTimer.running = false;

        // 2. Stop worker/background processes that aren't covered by
        //    PlaybackService.stopAll() below:
        //    processes (repair/optimize/scan/sync/health/etc -- the
        //    daemon they talk to is left running, see header), thumbnail
        //    generation, and any in-flight favorite toggle or monitor
        //    list refresh.
        _stopIfRunning(WallpaperService.refreshProc); // thumbnail generation
        _stopIfRunning(WallpaperService.favoriteProc);
        _stopIfRunning(MultiMonitorService.listProc);
        _stopIfRunning(PowerService.checkProc);
        _stopIfRunning(SmartPlaybackService.watcherProc);
        _stopIfRunning(SmartPlaybackService.pollProc);

        // Music Dock's own background processes: cava (audio visualizer)
        // and the MPRIS listener. Both expose idempotent stop() methods
        // (same shape as PlaybackService.stopAll()) that tear down their
        // Process objects and clear state -- safe to call even if Music
        // Dock was never enabled this session.
        CavaService.stop();
        MprisService.stop();

        // 3. The authoritative stop: kills mpvpaper + any kiosk browser
        //    process across every monitor, cancels in-flight apply
        //    workers, clears stream/web state. Reused verbatim -- see
        //    PlaybackService.stopAll() for the actual kill logic.
        PlaybackService.stopAll();

        // 4. Wait for that stop to actually finish (mpvpaper/browser
        //    confirmed dead -- stopAll's kill script blocks until then,
        //    see stopAllFinished's doc comment) and for any pending
        //    settings write to flush, then we're done. Bounded by
        //    _waitTimer's own timeout so Exit can never hang forever.
        _waitAndFinish();
    }

    property Connections _stopAllConn: Connections {
        target: PlaybackService
        function onStopAllFinished() { service._stopConfirmed = true; }
    }
    property bool _stopConfirmed: false
    property int _waited: 0

    function _stopIfRunning(proc) {
        if (proc && proc.running) proc.running = false;
    }

    function _waitAndFinish() {
        _stopConfirmed = false;
        _waited = 0;
        _waitTimer.running = true;
    }

    // Multi-monitor stops can legitimately take several seconds (each
    // monitor's kill-and-confirm loop is sequential in stop_wallpaper.sh)
    // -- poll rather than block, capped well above the worst case so a
    // slow-but-succeeding stop is never cut short, but a genuinely wedged
    // stop can't hang the app open forever either.
    property Timer _waitTimer: Timer {
        interval: 150
        repeat: true
        onTriggered: {
            service._waited += interval;
            const settingsFlushed = SettingsService.pendingWrites.length === 0 && SettingsService.activeWrite === null;
            const timedOut = service._waited >= 15000;
            if ((service._stopConfirmed && settingsFlushed) || timedOut) {
                running = false;
                service.readyToClose();
            }
        }
    }

    // ── PHASE 4: Autostart ──────────────────────────────────────────────
    // Whether `quickshell -c livewallpaper` is registered to launch on
    // login (an XDG autostart .desktop entry -- see
    // scripts/manage_autostart.sh's own header for why that file, not
    // Hyprland's exec-once, is what this manages). Read once on startup;
    // refreshed after every enable/disable so the Settings toggle stays
    // in sync with the actual file on disk rather than just assuming its
    // own last write succeeded.
    property bool autostartEnabled: false
    property bool autostartAvailable: false // becomes true once the first status check completes

    function refreshAutostart() {
        autostartCheckProc.running = true;
    }
    function setAutostart(value) {
        autostartSetProc.command = ["bash", Paths.script("manage_autostart.sh"), value ? "enable" : "disable"];
        autostartSetProc.running = true;
    }

    property Process autostartCheckProc: Process {
        command: ["bash", Paths.script("manage_autostart.sh"), "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                service.autostartEnabled = text.trim() === "enabled";
                service.autostartAvailable = true;
            }
        }
    }
    property Process autostartSetProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                service.autostartEnabled = text.trim() === "enabled";
                service.autostartAvailable = true;
            }
        }
    }

    Component.onCompleted: refreshAutostart()
}
