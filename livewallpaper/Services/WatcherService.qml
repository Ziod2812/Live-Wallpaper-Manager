pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

/*
 * WatcherService.qml
 * ---------------------
 * Keeps scripts/watch_wallpaper_dir.sh running for the lifetime of the
 * shell session, so dropping new videos into the wallpaper folder (or
 * deleting/renaming them) refreshes the library automatically -- no more
 * remembering to press Refresh.
 *
 * Restarts the watcher whenever the wallpaper directory changes (it needs
 * to be told a fresh inotifywait target), and respects the
 * "auto_refresh" setting (off -> watcher process isn't started at all).
 */
QtObject {
    id: service

    property bool running: false
    property bool dependencyMissing: false

    function start() {
        if (!SettingsService.autoRefresh) return;
        dependencyMissing = false;
        watcherProc.running = true;
    }

    function stop() {
        watcherProc.running = false;
        running = false;
    }

    function restart() {
        stop();
        restartTimer.restart();
    }

    property Timer restartTimer: Timer {
        interval: 250
        onTriggered: service.start()
    }

    property Process watcherProc: Process {
        id: watcherProc
        command: ["bash", Paths.script("watch_wallpaper_dir.sh")]
        stdout: SplitParser {
            onRead: (line) => {
                if (line === "MISSING_DEPENDENCY") {
                    service.dependencyMissing = true;
                    service.running = false;
                    NotifyService.info("Auto-refresh needs 'inotify-tools' (inotifywait) -- install it, or keep using the Refresh button.");
                } else if (line === "REFRESHED") {
                    service.running = true;
                    WallpaperService.reload();
                }
            }
        }
        onRunningChanged: {
            if (running) service.running = true;
        }
        onExited: (code, status) => {
            service.running = false;
            // Unexpected exit (not the intentional MISSING_DEPENDENCY path,
            // which already sets running=false without wanting a retry
            // loop) -- restart after a short delay so a transient failure
            // (e.g. directory momentarily unavailable) self-heals.
            if (!service.dependencyMissing && SettingsService.autoRefresh) {
                restartTimer.restart();
            }
        }
    }

    Component.onCompleted: start()

    property Connections _settingsConnections: Connections {
        target: SettingsService
        function onSettingsChanged() {
            if (SettingsService.autoRefresh && !watcherProc.running) {
                service.start();
            } else if (!SettingsService.autoRefresh && watcherProc.running) {
                service.stop();
            }
        }
    }

    // Directory changes need a fresh inotifywait target -- restart.
    property string _lastWatchedDir: ""
    property Connections _dirConnections: Connections {
        target: SettingsService
        function onWallpaperDirectoryChanged() {
            if (SettingsService.wallpaperDirectory !== service._lastWatchedDir) {
                service._lastWatchedDir = SettingsService.wallpaperDirectory;
                if (SettingsService.autoRefresh) service.restart();
            }
        }
    }
}
