pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

/*
 * HistoryService.qml
 * ---------------------
 * Backs the "Recent" filter tab. history.json stores a flat, chronological
 * list of {path, timestamp} written by apply_wallpaper.sh; this service
 * joins it against WallpaperService's database to get full card data
 * (name/thumb/metadata), the same way lw_recent_wallpapers() does in bash,
 * but reactively — recomputed whenever either file changes.
 */
QtObject {
    id: service

    // Shared cap for the "Recent" tab across BOTH wallpaper (video) and
    // GIF pages -- history.json is already a single chronological log of
    // every apply regardless of type (_apply_worker.sh calls
    // lw_add_history() for GIFs and videos alike), so capping the pool
    // itself to 20 here, once, is what keeps "Recent" combined instead of
    // 20 wallpapers *plus* 20 GIFs.
    readonly property int limit: 20
    property var rawHistory: []

    // Newest-first paths within the shared 20-entry pool, regardless of
    // type. GifModeContent filters this against its own scanned .gif list
    // the same way recentWallpapers below filters it against the video
    // database -- one pool, two views into it.
    readonly property var recentPaths: rawHistory.slice(0, limit).map(e => e.path)

    readonly property var recentWallpapers: {
        const byPath = {};
        for (const wp of WallpaperService.wallpapers) byPath[wp.path] = wp;

        const out = [];
        for (const entry of rawHistory.slice(0, limit)) {
            const wp = byPath[entry.path];
            if (wp) out.push(Object.assign({}, wp, { last_used: entry.timestamp }));
        }
        return out;
    }

    function reload() {
        historyView.reload();
    }

    property FileView historyView: FileView {
        path: Paths.historyFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                service.rawHistory = JSON.parse(text());
            } catch (e) {
                console.warn("HistoryService: failed to parse history.json:", e);
            }
        }
    }
}
