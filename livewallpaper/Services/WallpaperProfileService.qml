pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

/*
 * WallpaperProfileService.qml
 * -----------------------------
 * "Per-wallpaper performance profile" (e.g. Anime 60 FPS / heavy
 * wallpaper 30 FPS / laptop battery 15 FPS). Same read/write split as
 * every other data-backed service here: reactive read via
 * FileView(watchChanges) on data/performance_profiles.json, writes
 * delegated to scripts/performance_profiles.sh.
 *
 * Storage shape (see performance_profiles.sh's own header comment):
 *   { "wallpapers": { "<path>": {fps?, resolution?}, ... },
 *     "monitors":   { "<name>": {fps?, resolution?}, ... } }
 *
 * Resolution order for a given (path, monitor) pair, per the user's
 * choice of "wallpaper-level override, monitor-level fallback":
 *   1. wallpapers[path]        (most specific -- "this exact video
 *                                should always run at N FPS")
 *   2. monitors[monitor]       (e.g. "the laptop's built-in panel
 *                                always caps at 15 FPS")
 *   3. neither set -> caller's own global selectedFps/selectedResolution
 *      (this service returns "" for a field with no override; callers
 *      already know their own fallback and should keep using it).
 *
 * SCOPE NOTE: this only covers FPS + Resolution. GPU decode mode
 * (hwdec/gpu_profile) is deliberately NOT included here -- those are
 * process-launch-time-only mpv settings, and utils.sh's
 * lw_mpv_try_reuse / "PERSISTENT-MPV CONTRACT" explicitly guarantees a
 * normal wallpaper switch (Next/Previous/Random/manual/Apply) NEVER
 * kills/relaunches the persistent mpv process -- it only ever swaps the
 * file (and now fps/resolution's vf filter) over IPC on the SAME pid.
 * A per-wallpaper hwdec/gpu_profile override could only take effect by
 * killing and relaunching mpv on switch, which would break that
 * guarantee (and the single-persistent-player-per-monitor
 * architecture generally). If per-wallpaper GPU decode mode is wanted
 * later, it needs its own explicit "restart player to apply" flow --
 * not silent per-switch kill/relaunch -- so it is left out of this
 * service for now rather than half-implemented.
 */
QtObject {
    id: service

    property var profiles: ({ wallpapers: ({}), monitors: ({}) })
    readonly property var wallpaperProfiles: profiles.wallpapers || ({})
    readonly property var monitorProfiles: profiles.monitors || ({})

    function wallpaperProfile(path) {
        if (!path) return ({});
        return wallpaperProfiles[path] || ({});
    }
    function monitorProfile(monitor) {
        if (!monitor || monitor === "auto") return ({});
        return monitorProfiles[monitor] || ({});
    }

    // hasWallpaperProfile/hasMonitorProfile -- true if that entry
    // overrides at least one field. Used by the UI to show "Custom
    // profile" state on a wallpaper card / monitor row.
    function hasWallpaperProfile(path) {
        const p = wallpaperProfile(path);
        return !!(p.fps || p.resolution);
    }
    function hasMonitorProfile(monitor) {
        const p = monitorProfile(monitor);
        return !!(p.fps || p.resolution);
    }

    // effectiveFor(path, monitor, fallbackFps, fallbackResolution)
    // Resolves the precedence described above and returns
    // { fps, resolution } ready to hand to PlaybackService.apply()/
    // _applyNavigationTarget() in place of the raw
    // selectedFps/selectedResolution.
    function effectiveFor(path, monitor, fallbackFps, fallbackResolution) {
        const wp = service.wallpaperProfile(path);
        const mp = service.monitorProfile(monitor);
        return {
            fps: wp.fps || mp.fps || fallbackFps,
            resolution: wp.resolution || mp.resolution || fallbackResolution
        };
    }

    function reload() {
        profilesView.reload();
    }

    // setWallpaperProfile/setMonitorProfile -- pass "" for a field to
    // leave it unset (inherit). Passing "" for BOTH clears the entry,
    // matching performance_profiles.sh's own set_* contract.
    function setWallpaperProfile(path, fps, resolution) {
        if (!path) return;
        _run(wallpaperWriteProc, ["bash", Paths.script("performance_profiles.sh"),
            "set_wallpaper", path, fps || "", resolution || ""]);
    }
    function clearWallpaperProfile(path) {
        if (!path) return;
        _run(wallpaperWriteProc, ["bash", Paths.script("performance_profiles.sh"),
            "clear_wallpaper", path]);
    }
    function setMonitorProfile(monitor, fps, resolution) {
        if (!monitor || monitor === "auto") return;
        _run(monitorWriteProc, ["bash", Paths.script("performance_profiles.sh"),
            "set_monitor", monitor, fps || "", resolution || ""]);
    }
    function clearMonitorProfile(monitor) {
        if (!monitor || monitor === "auto") return;
        _run(monitorWriteProc, ["bash", Paths.script("performance_profiles.sh"),
            "clear_monitor", monitor]);
    }

    // Same "queue writes, one Process at a time" contract as
    // CollectionService/SettingsService -- occasional user-driven
    // edits, not a hot loop, but rapid edits (e.g. tuning a slider)
    // must not race two settings.sh-style processes against the same
    // file.
    property var _queue: []
    function _run(proc, command) {
        service._queue.push({ proc: proc, command: command });
        service._drain();
    }
    function _drain() {
        if (service._queue.length === 0) return;
        const item = service._queue[0];
        if (item.proc.running) return;
        service._queue = service._queue.slice(1);
        item.proc.command = item.command;
        item.proc.running = true;
    }
    function _onWriteExited() {
        service.reload();
        service._drain();
    }

    property FileView profilesView: FileView {
        path: Paths.performanceProfilesFile
        watchChanges: true
        onFileChanged: service.reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                service.profiles = {
                    wallpapers: (parsed && parsed.wallpapers) || ({}),
                    monitors: (parsed && parsed.monitors) || ({})
                };
            } catch (e) {
                console.warn("WallpaperProfileService: failed to parse performance_profiles.json:", e);
            }
        }
    }

    property Process wallpaperWriteProc: Process { onExited: service._onWriteExited() }
    property Process monitorWriteProc: Process { onExited: service._onWriteExited() }
}
