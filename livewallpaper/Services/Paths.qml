pragma Singleton
import Quickshell
import QtQuick

/*
 * Paths.qml
 * ----------
 * Single source of truth for every filesystem path this module touches,
 * mirroring utils.sh's LW_* variables 1:1 so the QML side and the bash
 * scripts never disagree about where things live.
 *
 *   scriptsDir  -> this module's scripts/ folder (resolved relative to
 *                  this file, so the module works no matter where it's
 *                  installed inside the Caelestia config tree)
 *   cacheDir    -> ~/.cache/livewallpaper
 *   dataDir     -> ~/.config/quickshell/livewallpaper/data
 */
QtObject {
    id: paths

    readonly property string home: Quickshell.env("HOME") || "/home/user"

    // Resolved relative to this file's own location (../scripts), so it
    // keeps working regardless of where this module is dropped inside a
    // Caelestia config tree (e.g. ~/.config/quickshell/modules/livewallpaper).
    readonly property string scriptsDir: {
        const url = Qt.resolvedUrl("../scripts/");
        return String(url).replace("file://", "");
    }

    readonly property string cacheDir: home + "/.cache/livewallpaper"
    readonly property string thumbDir: cacheDir + "/thumbs"
    readonly property string dataDir: home + "/.config/quickshell/livewallpaper/data"

    readonly property string dbFile: dataDir + "/wallpapers.json"
    readonly property string settingsFile: dataDir + "/settings.json"

    readonly property string currentFile: cacheDir + "/current"
    readonly property string lastFile: cacheDir + "/last"
    readonly property string resolutionFile: cacheDir + "/resolution"
    readonly property string fpsFile: cacheDir + "/fps"
    readonly property string historyFile: dataDir + "/history.json"
    readonly property string logFile: cacheDir + "/livewallpaper.log"

    readonly property string defaultWallpaperDir: home + "/Pictures/Live Wallpaper"
    readonly property string stateDir: cacheDir + "/state"

    // ── Music Dock (CavaService) ────────────────────────────────────────
    // Own subdirectory under the existing cache dir -- reuses the same
    // "everything lives under ~/.cache/livewallpaper" convention as
    // every other path above instead of inventing a new location.
    readonly property string musicDockCacheDir: cacheDir + "/musicdock"
    readonly property string cavaFifoFile: musicDockCacheDir + "/cava.fifo"
    readonly property string cavaConfFile: musicDockCacheDir + "/cava.conf"

    // PHASE 4 -- app icon (TrayService.qml passes this to the tray helper;
    // see Manager/ManagerWindow.qml's FloatingWindow.icon too). Resolved
    // the same way scriptsDir is, so it keeps working regardless of
    // install location.
    readonly property string appIcon: {
        const url = Qt.resolvedUrl("../assets/icons/app-icon.png");
        return String(url).replace("file://", "");
    }

    // TRAY-DEPENDENCIES FIX -- install.sh's Step 1c now creates a
    // project-local venv (dbus-next + Pillow, sidesteps PEP 668) at
    // "<install root>/venv", a sibling of scripts/ -- i.e. one level up
    // from this file, same base as scriptsDir/appIcon above. TrayService
    // launches this interpreter when it exists so the helper always runs
    // in the exact environment those packages were installed into,
    // never a plain system `python3` that may not have them.
    readonly property string trayVenvPython: {
        const url = Qt.resolvedUrl("../venv/bin/python3");
        return String(url).replace("file://", "");
    }

    function script(name) {
        return scriptsDir + name;
    }

    // Mirrors lw_sanitize_monitor_name in utils.sh
    function sanitizeMonitorName(name) {
        return String(name).replace(/[^A-Za-z0-9_.-]/g, "_");
    }

    // Mirrors lw_monitor_state_file <monitor> <kind> in utils.sh.
    // monitor "" or "auto" -> legacy top-level cache files (current/last/
    // resolution/fps live directly in cacheDir, no per-monitor subfolder).
    function monitorStateFile(monitor, kind) {
        if (!monitor || monitor === "auto") {
            return cacheDir + "/" + kind;
        }
        return stateDir + "/" + sanitizeMonitorName(monitor) + "/" + kind;
    }
}
