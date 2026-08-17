pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

/*
 * CacheService.qml
 * -------------------
 * Thin QML-facing wrapper around scripts/cache.sh. Owns cache size
 * status (for a "cache size" readout) and the Clear Cache action.
 *
 * clear() only ever removes regenerable cache (thumbnails + transient
 * logs -- see cache.sh's own header for the exact list). It never
 * touches settings.json, wallpapers.json (favorites live there),
 * history.json, playlists, or the wallpaper source files themselves --
 * see cache.sh for the authoritative "safe to delete" list.
 */
QtObject {
    id: service

    // Populated from `cache.sh status`. Null until the first refresh().
    property var status: null
    readonly property int thumbnailCount: (status && status.thumbnail_count) || 0
    readonly property string thumbnailSizeLabel: (status && status.thumbnail_size) || "0"

    property bool clearing: false

    function refresh() {
        if (statusProc.running) return;
        statusProc.running = true;
    }

    // Clears regenerable cache, then refreshes the wallpaper database so
    // any thumbnails that just got wiped are regenerated, refreshes the
    // cache-size readout, and shows a "Cache cleared -- Freed X MB"
    // notification. Reuses WallpaperService.refresh() / NotifyService --
    // no duplicate rescan/notification logic here.
    function clear() {
        if (clearing) return;
        clearing = true;
        clearOut.clear();
        clearErr.clear();
        clearProc.running = true;
    }

    function _formatBytes(bytes) {
        if (!bytes || bytes <= 0) return "0 MB";
        const mb = bytes / (1024 * 1024);
        if (mb < 1) return Math.max(1, Math.round(bytes / 1024)) + " KB";
        if (mb < 1024) return Math.round(mb) + " MB";
        return (mb / 1024).toFixed(1) + " GB";
    }

    property Process statusProc: Process {
        id: statusProc
        command: ["bash", Paths.script("cache.sh"), "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    service.status = JSON.parse(text);
                } catch (e) {
                    console.warn("CacheService: failed to parse cache status:", e);
                }
            }
        }
    }

    property Process clearProc: Process {
        id: clearProc
        command: ["bash", Paths.script("cache.sh"), "clear"]
        stdout: StdioCollector { id: clearOut }
        stderr: StdioCollector { id: clearErr }
        onExited: (code, status) => {
            service.clearing = false;
            if (code !== 0) {
                const msg = clearErr.text.trim();
                NotifyService.error(msg.length > 0 ? msg : "Failed to clear cache. Check ~/.cache/livewallpaper/logs/error.log");
                return;
            }
            let freedBytes = 0;
            try {
                const result = JSON.parse(clearOut.text);
                freedBytes = result.freed_bytes || 0;
            } catch (e) {
                // Non-fatal -- still report success, just without a size.
            }
            NotifyService.info("Cache cleared successfully. Freed " + service._formatBytes(freedBytes) + ".");
            // Thumbnails were just wiped -- rebuild them and refresh the
            // cache-size readout. Reuses WallpaperService.refresh(), which
            // already regenerates any thumbnail missing on disk.
            WallpaperService.refresh();
            service.refresh();
        }
    }

    Component.onCompleted: refresh()
}
