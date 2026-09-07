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
 * PERFORMANCE FIX: enforces a hard cap on in-memory cache entries
 * (maxEntries) and max age (maxEntryAgeMs). cleanup() evicts the
 * oldest/stale entries when the cap is exceeded, preventing unbounded
 * RAM growth over long sessions.
 */
QtObject {
    id: service

    // ── Configurable cap (default 200 entries / ~200 MB total) ──
    readonly property int maxEntries: 200
    readonly property int maxEntryAgeMs: 30 * 60 * 1000   // 30 min

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
        clearProc.running = true;
    }

    function _formatBytes(bytes) {
        if (!bytes || bytes <= 0) return "0 MB";
        const mb = bytes / (1024 * 1024);
        if (mb < 1) return Math.max(1, Math.round(bytes / 1024)) + " KB";
        if (mb < 1024) return Math.round(mb) + " MB";
        return (mb / 1024).toFixed(1) + " GB";
    }

    // ── In-memory cache with hard cap + age-based eviction ──
    property var _entries: ({})
    property int _entryCount: 0
    property real _totalSizeBytes: 0

    function _cleanup() {
        const now = Date.now();
        const keys = Object.keys(_entries);
        if (keys.length === 0) return;

        // Evict oldest entries when over cap
        if (keys.length > service.maxEntries) {
            const sorted = keys
                .map(k => ({ key: k, age: now - (_entries[k]._ts || 0) }))
                .sort((a, b) => b.age - a.age);
            const excess = sorted.length - service.maxEntries;
            for (let i = 0; i < excess; i++) {
                const item = _entries[sorted[i].key];
                service._totalSizeBytes -= (item && item._size) || 0;
                delete _entries[sorted[i].key];
            }
            service._entryCount = Object.keys(_entries).length;
        }

        // Evict stale entries older than maxEntryAgeMs
        const staleKeys = [];
        for (const k in _entries) {
            if ((now - (_entries[k]._ts || 0)) > service.maxEntryAgeMs) {
                staleKeys.push(k);
            }
        }
        for (let i = 0; i < staleKeys.length; i++) {
            const item = _entries[staleKeys[i]];
            service._totalSizeBytes -= (item && item._size) || 0;
            delete _entries[staleKeys[i]];
        }
        if (staleKeys.length > 0)
            service._entryCount = Object.keys(_entries).length;
    }

    function cacheGet(path) {
        const e = _entries[path];
        if (!e) return null;
        if ((Date.now() - (e._ts || 0)) > service.maxEntryAgeMs) {
            service._totalSizeBytes -= (e._size) || 0;
            delete _entries[path];
            service._entryCount = Object.keys(_entries).length;
            return null;
        }
        return e;
    }

    function cacheSet(path, data, sizeBytes) {
        // Evict if over cap before inserting
        if (_entryCount >= maxEntries) {
            _cleanup();
        }
        _entries[path] = { data: data, _size: sizeBytes || 0, _ts: Date.now() };
        _entryCount = Object.keys(_entries).length;
        _totalSizeBytes += (sizeBytes || 0);
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
