pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

/*
 * AwwwService.qml
 * ----------------
 * Owns the AWWW daemon lifecycle for the application's transition feature.
 * The transition toggle is intentionally a real runtime switch:
 *   ON  -> ensure awww-daemon is running
 *   OFF -> stop the AWWW daemon
 *
 * This service does not decide which wallpaper backend to use. The shell
 * scripts still gate GIF/video transitions from transition_enabled. This
 * service only makes sure the daemon lifecycle follows that setting.
 */
QtObject {
    id: service

    readonly property bool enabledSetting: SettingsService.transitionEnabled
    property bool available: false

    function start() {
        if (!enabledSetting || startProc.running)
            return;
        if (stopProc.running)
            stopProc.running = false;
        startProc.running = true;
    }

    function stop() {
        // Kill the daemon explicitly so the setting is a true on/off switch,
        // including when AWWW was started outside this Quickshell process.
        if (startProc.running)
            startProc.running = false;
        if (!stopProc.running)
            stopProc.running = true;
    }

    property Process startProc: Process {
        id: startProc
        command: ["bash", "-lc",
            "if ! command -v awww-daemon >/dev/null 2>&1 && [ ! -x \"$HOME/.local/bin/awww-daemon\" ]; then exit 127; fi; " +
            "if command -v awww >/dev/null 2>&1 && awww query >/dev/null 2>&1; then exit 0; fi; " +
            "daemon=\"$(command -v awww-daemon 2>/dev/null || printf '%s' \"$HOME/.local/bin/awww-daemon\")\"; " +
            "mkdir -p \"$HOME/.cache/livewallpaper\"; " +
            "nohup \"$daemon\" >>\"$HOME/.cache/livewallpaper/awww-daemon.log\" 2>&1 </dev/null & " +
            "for i in $(seq 1 30); do sleep 0.1; if command -v awww >/dev/null 2>&1 && awww query >/dev/null 2>&1; then exit 0; fi; done; exit 1"]
        onExited: (code, status) => {
            service.available = code === 0;
        }
    }

    property Process stopProc: Process {
        id: stopProc
        command: ["bash", "-lc",
            // Best-effort graceful shutdown first (talks to the daemon over
            // its own IPC socket).
            "if command -v awww >/dev/null 2>&1; then awww kill >/dev/null 2>&1 || true; fi; " +
            // Then a normal SIGTERM by exact process name.
            "pkill -x awww-daemon >/dev/null 2>&1 || true; " +
            // Give it a brief moment to actually exit, then verify. If it's
            // still alive (hung, IPC socket mismatch, ignored SIGTERM,
            // whatever), force it -- toggling this setting off must be a
            // guaranteed kill, not a best-effort request, or the daemon is
            // left running as an orphan indistinguishable from the setting
            // never having been read at all.
            "for i in 1 2 3 4 5; do pgrep -x awww-daemon >/dev/null 2>&1 || exit 0; sleep 0.1; done; " +
            "pkill -9 -x awww-daemon >/dev/null 2>&1 || true"]
        onExited: {
            service.available = false;
        }
    }

    property Process probeProc: Process {
        id: probeProc
        command: ["bash", "-lc",
            "if command -v awww >/dev/null 2>&1 && command -v awww-daemon >/dev/null 2>&1 && awww query >/dev/null 2>&1; then echo ready; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                service.available = text.trim() === "ready";
            }
        }
    }

    // Do NOT act on enabledSetting until SettingsService.loaded is true --
    // otherwise this can fire on the hardcoded default (transition_enabled:
    // true) before settings.json has actually been read, spawning the
    // daemon on every startup even when the user's real saved setting is
    // off, and racing the corrective stop() against a daemon process that
    // hasn't finished forking yet (leaving an orphaned awww-daemon that
    // nothing else will kill until the app fully exits).
    function _syncDaemonState() {
        if (!SettingsService.loaded)
            return;
        if (enabledSetting) start();
        else stop();
    }

    onEnabledSettingChanged: _syncDaemonState()

    property Connections _settingsLoadedConn: Connections {
        target: SettingsService
        function onLoadedChanged() { service._syncDaemonState(); }
    }

    Component.onCompleted: {
        _syncDaemonState();
        probeProc.running = true;
    }
}
