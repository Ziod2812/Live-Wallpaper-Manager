pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

/*
 * SettingsService.qml
 * ---------------------
 * Reactive view of settings.json. Reads happen via FileView with
 * watchChanges so any external edit (or a rewrite by settings.sh) is
 * picked up immediately. Writes are delegated to settings.sh so the
 * value-type coercion logic (bool/number/string) stays defined in one
 * place instead of being duplicated in QML and bash.
 */
QtObject {
    id: service

    property var settings: ({
        theme: "catppuccin-mocha",
        opacity: 0.72,
        blur: true,
        radius: 20,
        resolution: "1080p",
        fps: "original",
        hwdec: "auto-safe",
        gpu_profile: "fast",
        gpu_mode: "auto",
        language: "en",
        monitor: "auto",
        performance: "balanced",
        autostart: true,
        auto_refresh: true,
        wallpaper_directory: "~/Pictures/Live Wallpaper",
        playlist_enabled: false,
        playlist_interval_minutes: 30,
        playlist_mode: "sequential",
        battery_resolution: "720p",
        battery_fps: "30"
    })

    readonly property string wallpaperDirectory: settings.wallpaper_directory || ""
    readonly property bool autostart: settings.autostart !== false
    readonly property bool autoRefresh: settings.auto_refresh !== false
    readonly property bool playlistEnabled: settings.playlist_enabled === true
    readonly property int playlistIntervalMinutes: settings.playlist_interval_minutes || 30
    readonly property string playlistMode: settings.playlist_mode || "sequential"
    readonly property string batteryResolution: settings.battery_resolution || "720p"
    readonly property string batteryFps: settings.battery_fps || "30"
    readonly property string performanceMode: settings.performance || "balanced"

    function reload() {
        settingsView.reload();
    }

    // Writes are coalesced per key and serialized. A single Process cannot
    // safely accept a new command while it is still running; without this
    // queue, rapidly moving a slider could leave the optimistic UI value
    // different from settings.json.
    property var pendingWrites: []
    property var activeWrite: null

    function _runNextSettingWrite() {
        if (setProc.running || pendingWrites.length === 0) return;
        const next = pendingWrites[0];
        pendingWrites = pendingWrites.slice(1);
        activeWrite = next;
        setProc.command = ["bash", Paths.script("settings.sh"), "set", next.key, next.value];
        setProc.running = true;
    }

    // set(key, value) — optimistically update the local model, then queue the
    // latest value for that key. Older queued slider values are discarded.
    function set(key, value) {
        const next = Object.assign({}, settings);
        next[key] = value;
        settings = next;

        const queued = pendingWrites.filter(item => item.key !== key);
        queued.push({ key: key, value: String(value) });
        pendingWrites = queued;
        _runNextSettingWrite();
    }

    function changeWallpaperDirectory(path) {
        changeDirProc.command = ["bash", Paths.script("change_directory.sh"), path];
        changeDirProc.running = true;
    }

    property FileView settingsView: FileView {
        path: Paths.settingsFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                service.settings = JSON.parse(text());
            } catch (e) {
                console.warn("SettingsService: failed to parse settings.json:", e);
            }
        }
    }

    property Process setProc: Process {
        id: setProc
        onExited: (code, status) => {
            activeWrite = null;
            if (code !== 0) {
                // The optimistic value was not persisted; reload the
                // authoritative file before processing the next write.
                settingsView.reload();
            }
            _runNextSettingWrite();
        }
    }
    property Process changeDirProc: Process {
        id: changeDirProc
        onExited: (code, status) => {
            if (code === 0) settingsView.reload();
        }
    }
}
