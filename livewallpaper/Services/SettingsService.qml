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
        gif_wallpaper_directory: "~/Pictures/GIF Wallpaper",
        gif_favorites: "[]",
        gif_large_thumbnails: false,
        playlist_enabled: false,
        playlist_interval_minutes: 30,
        playlist_mode: "sequential",
        playlist_custom_paths: "[]",
        playlist_custom_collection: "",
        gif_playlist_enabled: false,
        gif_playlist_interval_minutes: 30,
        gif_playlist_mode: "sequential",
        battery_resolution: "720p",
        battery_fps: "30",
        music_dock_draggable: true,
        music_dock_free_position: false,
        music_dock_pos_x: -1,
        music_dock_pos_y: -1,
        location_lat: "",
        location_lng: "",
        schedule_enabled: false,
        schedule_rules: "[]",
        weather_enabled: false,
        weather_rules: "{}",
         weather_poll_minutes: 20,
         smart_selection_enabled: false,
         smart_accent_enabled: false,
         active_accent_color: "#353446",
         // Background blur default: 0.15 = the LOWEST stored value = the
         // slider's 0% / maximum-blur end, so the app boots FULLY
         // frosted: every derived surface (panelBg/cardBg/cardHoverBg/
         // segmentTrackBg) sits at alpha 1.0 -- completely concealing the
         // animated wallpaper -- and the real blur is at its maximum
         // (Theme.blurRadius 64px / frosted_glass.sh compositor size 12).
         // This stored value drives BOTH the artistic translucency (via
         // micaAlpha(), which ramps EVERY surface to fully opaque as the
         // value drops toward the maximum-blur end) and the blur radius
         // itself: Theme.blurRadius maps the stored value inversely, so
         // the lowest stored value 0.15 gets the MAXIMUM blur radius (see
         // Config/Theme.qml's uiBgOpacity / blurRadius / micaAlpha + the
         // inverted slider in Pages/SettingsPage.qml).
         // Keep in sync with Theme.qml's uiBgOpacity fallback and
         // scripts/settings.sh's DEFAULT_SETTINGS.
         ui_bg_opacity: 0.15,
        transition_enabled: false,
        transition_type: "fade",
        transition_duration: 1.0,
        tray_enabled: true,
        notifications_enabled: true
    })

    // True once settings.json has actually been read from disk at least
    // once. Until then, `settings` still holds the hardcoded defaults
    // above (e.g. transition_enabled: true), which do not necessarily
    // match the user's real saved value. Consumers that take a
    // side-effecting action based on a setting at startup (spawning/
    // killing a helper process, for instance) should gate on this
    // instead of acting on the possibly-stale default -- see AwwwService.
    property bool loaded: false

    readonly property string wallpaperDirectory: settings.wallpaper_directory || ""
    readonly property string gifWallpaperDirectory: settings.gif_wallpaper_directory || ""
    readonly property bool autostart: settings.autostart !== false

    readonly property bool autoRefresh: settings.auto_refresh !== false
    readonly property bool playlistEnabled: settings.playlist_enabled === true
    readonly property int playlistIntervalMinutes: settings.playlist_interval_minutes || 30
    readonly property string playlistMode: settings.playlist_mode || "sequential"
    // The Playlist page's "Custom" mode now picks from one saved
    // Collection (see CollectionService) instead of a manually built
    // wallpaper/GIF list -- this just holds which collection name is
    // selected. (playlist_custom_paths above is kept in the settings
    // schema for backward compatibility with existing settings.json
    // files, but is no longer read anywhere.)
    readonly property string playlistCustomCollection: settings.playlist_custom_collection || ""
    readonly property string batteryResolution: settings.battery_resolution || "720p"
    readonly property string batteryFps: settings.battery_fps || "30"
    readonly property string performanceMode: settings.performance || "balanced"

    readonly property bool adaptiveFpsEnabled: settings.adaptive_fps_enabled === true
    readonly property int adaptiveFpsMin: Number(settings.adaptive_fps_min || 24)
    readonly property int adaptiveFpsMax: Number(settings.adaptive_fps_max || 60)
    readonly property int adaptiveGpuLow: Number(settings.adaptive_gpu_low || 30)
    readonly property int adaptiveGpuHigh: Number(settings.adaptive_gpu_high || 75)
    readonly property bool thermalProtectionEnabled: settings.thermal_protection_enabled !== false
    readonly property real thermalWarningC: Number(settings.thermal_warning_c || 75)
    readonly property real thermalCriticalC: Number(settings.thermal_critical_c || 85)
    readonly property int thermalWarningFps: Number(settings.thermal_warning_fps || 30)
    readonly property bool batteryProfilesEnabled: settings.battery_profiles_enabled !== false
    readonly property int lowBatteryThreshold: Number(settings.low_battery_threshold || 20)
    readonly property int lowBatteryFps: Number(settings.low_battery_fps || 20)
    readonly property bool transitionEnabled: settings.transition_enabled === true
    readonly property string transitionType: settings.transition_type || "fade"
    readonly property real transitionDuration: {
        const d = Number(settings.transition_duration);
        return isFinite(d) && d >= 0.15 && d <= 3.0 ? d : 1.0;
    }

    // ── Collections / Schedule / Weather / Transitions ──────────────────
    readonly property string locationLat: settings.location_lat || ""
    readonly property string locationLng: settings.location_lng || ""
    readonly property bool hasLocation: locationLat !== "" && locationLng !== ""
    readonly property bool scheduleEnabled: settings.schedule_enabled === true
    readonly property var scheduleRules: {
        try {
            const parsed = JSON.parse(settings.schedule_rules || "[]");
            return Array.isArray(parsed) ? parsed : [];
        } catch (e) { return []; }
    }
    readonly property bool weatherEnabled: settings.weather_enabled === true
    readonly property var weatherRules: {
        try {
            const parsed = JSON.parse(settings.weather_rules || "{}");
            return (parsed && typeof parsed === "object") ? parsed : {};
        } catch (e) { return {}; }
    }
    readonly property int weatherPollMinutes: Number(settings.weather_poll_minutes || 20)

    // schedule_rules/weather_rules are stored as JSON-encoded STRINGS
    // (same convention as gif_favorites elsewhere in this
    // file) so a single settings.sh `set` call can write the whole
    // structure atomically. Callers pass a JS array/object; this
    // stringifies it before handing off to set().
    function setScheduleRules(rulesArray) {
        service.set("schedule_rules", JSON.stringify(rulesArray));
    }

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
        // A multi-key write (see setMultiple() below) is queued as
        // { keys: {...} } instead of { key, value } -- route it to
        // settings.sh's `mset`, which applies the whole patch as one
        // atomic file replace instead of one `set` per key.
        if (next.keys) {
            setProc.command = ["bash", Paths.script("settings.sh"), "mset", JSON.stringify(next.keys)];
        } else {
            setProc.command = ["bash", Paths.script("settings.sh"), "set", next.key, next.value];
        }
        setProc.running = true;
    }

    // True if a queued write (single-key `{key,value}` or multi-key
    // `{keys:{...}}`, see setMultiple() below) touches any key in
    // `keys` -- shared by set()'s and setMultiple()'s "a newer write
    // supersedes any not-yet-sent older write for the same key(s)"
    // dedupe, so a stale queued write can never land after and clobber
    // a newer one, regardless of which of the two write shapes either
    // side is.
    function _writeTouches(item, keys) {
        if (item.key) return keys.indexOf(item.key) !== -1;
        if (item.keys) return Object.keys(item.keys).some(k => keys.indexOf(k) !== -1);
        return false;
    }

    // set(key, value) — optimistically update the local model, then queue the
    // latest value for that key. Older queued slider values are discarded.
    function set(key, value) {
        const next = Object.assign({}, settings);
        next[key] = value;

        // Mutual exclusive: Wallpaper Playlist <-> GIF Playlist
        if (key === "playlist_enabled" && value === true)
            next.gif_playlist_enabled = false;
        else if (key === "gif_playlist_enabled" && value === true)
            next.playlist_enabled = false;

        settings = next;

        const queued = pendingWrites.filter(item => !service._writeTouches(item, [key]));
        queued.push({ key: key, value: String(value) });

        if (key === "playlist_enabled" && value === true)
            queued.push({ key: "gif_playlist_enabled", value: "false" });
        else if (key === "gif_playlist_enabled" && value === true)
            queued.push({ key: "playlist_enabled", value: "false" });

        pendingWrites = queued;
        _runNextSettingWrite();
    }

    // setMultiple(pairs) — same optimistic-update-then-queue contract as
    // set() above, but for several keys that must land on disk TOGETHER
    // as one atomic write (routed to settings.sh's `mset`, see
    // _runNextSettingWrite() above). Needed anywhere a feature saves more
    // than one related key at once: writing them via N separate set()
    // calls persists N separate files, and this FileView's
    // watchChanges reload() (which re-parses settings.json on ANY
    // external change, including our own writes) can fire in the gap
    // between those N writes and hand the rest of the app a PARTIALLY
    // applied state for a moment. Music Dock's free-position drag save
    // is the motivating case: saving free_position/pos_x/pos_y as three
    // plain set() calls could reload with free_position already true but
    // pos_x/pos_y still the pre-drag values, which re-seeds the drag
    // margins from stale coordinates and visibly snaps the dock back to
    // where it was before the drag.
    function setMultiple(pairs) {
        const next = Object.assign({}, settings, pairs);
        settings = next;

        const touched = Object.keys(pairs);
        const queued = pendingWrites.filter(item => !service._writeTouches(item, touched));
        queued.push({ keys: pairs });
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
                service.loaded = true;
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
