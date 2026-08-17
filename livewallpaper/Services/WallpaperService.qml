pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

/*
 * WallpaperService.qml
 * ----------------------
 * Owns the wallpaper database (wallpapers.json) plus the UI-facing search
 * text and filter mode. wallpapers.json is watched via FileView, so any
 * write to it by wallpaper_list.sh / favorite.sh / refresh.sh is reflected
 * here automatically without polling and without those scripts needing to
 * know a UI exists at all.
 */
QtObject {
    id: service

    // Full, unfiltered database (array of wallpaper metadata plus
    // user-owned favorites and tags).
    property var wallpapers: []

    property string search: ""
    // "all" | "favorites" | "recent"
    property string filterMode: "all"
    property bool refreshing: false

    // PHASE 3 -- "" means no tag filter active. Combines with filterMode/
    // search (AND, not OR) in filteredWallpapers below.
    property string selectedTag: ""

    // PHASE 3 -- every distinct tag across the library, alphabetized, for
    // TagFilterBar.qml. Pure derived read of the existing wp.tags field
    // (already written by the backend -- see the `wallpapers` comment
    // above) -- no new data source.
    readonly property var allTags: {
        const set = {};
        for (const wp of wallpapers) {
            if (!Array.isArray(wp.tags)) continue;
            for (const t of wp.tags) if (t) set[t] = true;
        }
        return Object.keys(set).sort();
    }

    readonly property int count: wallpapers.length

    // Filtered + search-matched list used by the grid for "all"/"favorites".
    // The "recent" tab is served by HistoryService
    // instead, since it has its own chronological ordering that must not be
    // re-sorted.
    readonly property var filteredWallpapers: {
        const q = search.toLowerCase();
        return wallpapers.filter(wp => {
            if (filterMode === "favorites" && !wp.favorite) return false;
            // PHASE 3 -- tag filter (AND'd with whatever filterMode above matched)
            if (selectedTag.length > 0 && !(Array.isArray(wp.tags) && wp.tags.includes(selectedTag))) return false;
            if (q.length > 0) {
                const nameMatch = wp.name.toLowerCase().includes(q);
                const tagMatch = Array.isArray(wp.tags) && wp.tags.some(t => t.toLowerCase().includes(q));
                if (!nameMatch && !tagMatch) return false;
            }
            return true;
        });
    }

    function reload() {
        dbView.reload();
    }

    function refresh() {
        refreshing = true;
        refreshProc.running = true;
    }

    function toggleFavorite(path) {
        // Optimistic local flip so the star responds instantly; the
        // authoritative state comes back a moment later via the file watch.
        wallpapers = wallpapers.map(wp =>
            wp.path === path ? Object.assign({}, wp, { favorite: !wp.favorite }) : wp
        );
        favoriteProc.command = ["bash", Paths.script("favorite.sh"), path, "toggle"];
        favoriteProc.running = true;
    }

    property FileView dbView: FileView {
        path: Paths.dbFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                service.wallpapers = JSON.parse(text());
            } catch (e) {
                // Should be rare now that wallpaper_list.sh writes
                // atomically (temp file + rename), but if some other
                // process/edit is caught mid-write, self-heal instead of
                // getting stuck on stale data.
                console.warn("WallpaperService: failed to parse wallpapers.json, retrying shortly:", e);
                parseRetryTimer.restart();
            }
        }
        onLoadFailed: (error) => {
            // Database not created yet (first run) — trigger a scan.
            service.refresh();
        }
    }

    property Timer parseRetryTimer: Timer {
        interval: 300
        onTriggered: dbView.reload()
    }

    property Process refreshProc: Process {
        id: refreshProc
        command: ["bash", Paths.script("refresh.sh")]
        onExited: (code, status) => {
            service.refreshing = false;
            dbView.reload();
        }
    }

    property Process favoriteProc: Process { id: favoriteProc }
}
