pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

/*
 * TrayService.qml
 * ------------------
 * PHASE 4 -- "System tray" requirement.
 *
 * Starts/stops scripts/_tray_icon.py, a small separate long-lived helper
 * process (see that file's own header for why a tray icon can't just be
 * a QML type here -- Quickshell only reads OTHER apps' tray icons, it
 * has no API to publish one of its own). Every tray menu click just
 * shells out to the same `quickshell ipc call` commands everything else
 * already uses -- this service owns process lifecycle only, nothing
 * else.
 *
 * Gated by settings.tray_enabled (default true) -- toggled from
 * SettingsPage.qml. `available` goes false if the helper exits
 * immediately (missing dbus-next/Pillow), so the Settings toggle can
 * show "not installed" instead of silently doing nothing, same idea as
 * CavaService.available.
 *
 * TRAY-NOT-APPEARING FIX: _tray_icon.py used to shell out to `pystray`,
 * whose Linux SNI (StatusNotifierItem) support depends on a *system*
 * AppIndicator3/AyatanaAppIndicator3 GObject-introspection package. If
 * that's missing (common -- it's not pip-installable), pystray falls
 * back to a backend that doesn't speak the protocol Wayland tray hosts
 * (waybar's `tray` module, etc.) actually implement, so the icon never
 * shows up even though this Process is running fine. The helper now
 * registers a real StatusNotifierItem directly over session D-Bus via
 * `dbus-next` (pure Python, no GI dependency) -- see that file's own
 * header. Nothing here changed: same Process lifecycle, same command
 * shape, same `available` contract.
 */
QtObject {
    id: service

    readonly property bool enabledSetting: SettingsService.settings.tray_enabled !== false // default true
    property bool available: true // flips false if the helper exits within 2s of starting (missing deps)

    function setEnabled(value) {
        SettingsService.set("tray_enabled", value);
    }

    property Process trayProc: Process {
        id: trayProc
        // Kills any orphaned instance from a previous Quickshell session
        // first (e.g. the shell was reloaded/force-killed rather than
        // exited via ApplicationService.exit()) so reloading Quickshell
        // can never end up with two tray icons -- see "No duplicated
        // processes" in the Phase 4 checklist.
        // TRAY-DEPENDENCIES FIX: install.sh's Step 1c installs
        // dbus-next/Pillow into a project-local venv rather than the
        // system/user Python (PEP 668 makes `pip install --user` fail
        // outright on many current distros). Launch that venv's own
        // interpreter (Paths.trayVenvPython) when install.sh actually
        // created it, so the helper runs in the exact environment those
        // packages were installed into -- falling back to plain
        // `python3` only if it wasn't (e.g. `python3 -m venv`
        // unavailable on this system, see install.sh's warning in that
        // case). Never installs into the venv and then runs system
        // python3, or vice versa.
        command: ["bash", "-c",
            "for pid in $(pgrep -f _tray_icon.py 2>/dev/null); do " +
            "[ \"$pid\" != \"$$\" ] && kill \"$pid\" 2>/dev/null; done; " +
            "PY=" + Paths.trayVenvPython + "; " +
            "[ -x \"$PY\" ] || PY=python3; " +
            "exec \"$PY\" " + Paths.script("_tray_icon.py") + " " + Paths.appIcon]
        onExited: (code, status) => {
            if (startupGuard.running) {
                // Exited almost immediately after we asked it to start --
                // treat as "dependency missing", not a crash to restart.
                service.available = false;
            }
        }
    }

    // Gives the helper 2s to get past its dbus-next/Pillow import check
    // and initial D-Bus registration before we conclude it's actually
    // unavailable rather than just slow to start.
    property Timer startupGuard: Timer {
        interval: 2000
        repeat: false
    }

    function start() {
        if (trayProc.running) return;
        service.available = true;
        startupGuard.restart();
        trayProc.running = true;
    }
    function stop() {
        if (trayProc.running) trayProc.running = false;
    }

    onEnabledSettingChanged: {
        if (enabledSetting) start(); else stop();
    }

    // Matches LiveWallpaperPanel.qml / ManagerWindow.qml's own Connections
    // blocks -- stop the tray helper once ApplicationService confirms
    // playback has actually stopped, same "Exit Application" flow.
    property Connections _exitConnection: Connections {
        target: ApplicationService
        function onReadyToClose() {
            service.stop();
        }
    }

    Component.onCompleted: {
        if (enabledSetting) start();
    }
}
