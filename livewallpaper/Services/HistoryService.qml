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

    readonly property int limit: 5
    property var rawHistory: []

    readonly property var recentWallpapers: {
        const byPath = {};
        for (const wp of WallpaperService.wallpapers) byPath[wp.path] = wp;

        const out = [];
        for (const entry of rawHistory) {
            const wp = byPath[entry.path];
            if (wp) out.push(Object.assign({}, wp, { last_used: entry.timestamp }));
            if (out.length >= limit) break;
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
