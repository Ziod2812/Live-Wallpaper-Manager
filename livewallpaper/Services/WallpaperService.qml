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
    // "all" | "favorites" | "recent" | "duplicates"
    property string filterMode: "all"
    property bool refreshing: false

    // PHASE 3 -- "" means no tag filter active. Combines with filterMode/
    // search (AND, not OR) in filteredWallpapers below.
    property string selectedTag: ""

    // PHASE 4 -- Advanced search fields (Name/Tag covered by `search`/
    // `selectedTag` above already). All AND together with everything
    // else in filteredWallpapers. Defaults ("" / 0 / false) mean "no
    // constraint", so leaving the panel untouched behaves exactly like
    // today's search.
    property string advResolution: ""      // exact match against wp.resolution, e.g. "1920x1080"
    property int advMinFps: 0              // 0 = any
    property int advMinDurationSeconds: 0  // 0 = any
    property bool advFavoriteOnly: false

    function clearAdvancedFilters() {
        advResolution = "";
        advMinFps = 0;
        advMinDurationSeconds = 0;
        advFavoriteOnly = false;
    }

    readonly property bool advFiltersActive:
        advResolution.length > 0 || advMinFps > 0 || advMinDurationSeconds > 0 || advFavoriteOnly

    // PHASE 4 -- Duplicate detection. `id` is already a full sha256 of the
    // file's content (see wallpaper_list.sh: id = lw_file_hash(f)), so two
    // records sharing the same id are byte-identical files -- true
    // duplicates, not just similar ones. Pure derived read of existing
    // data, no new script/process needed.
    readonly property var duplicateGroups: {
        const byId = {};
        for (const wp of wallpapers) {
            if (!wp.id) continue;
            (byId[wp.id] = byId[wp.id] || []).push(wp);
        }
        const groups = [];
        for (const id in byId) {
            if (byId[id].length > 1) groups.push({ id: id, items: byId[id] });
        }
        return groups;
    }

    readonly property var duplicateIdSet: {
        const set = {};
        for (const g of duplicateGroups) set[g.id] = true;
        return set;
    }

    readonly property int duplicateCount: duplicateGroups.reduce((n, g) => n + g.items.length, 0)

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

    // PHASE 4 -- every distinct resolution across the library, for the
    // advanced-search resolution picker (chip-select, same shape as
    // allTags/TagFilterBar rather than a freeform text field, so it can
    // never mismatch the actual stored "WxH" strings).
    readonly property var allResolutions: {
        const set = {};
        for (const wp of wallpapers) if (wp.resolution) set[wp.resolution] = true;
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
            // PHASE 4 -- Duplicates tab: only records that are part of a
            // same-content-hash group (see duplicateIdSet above).
            if (filterMode === "duplicates" && !(wp.id && duplicateIdSet[wp.id])) return false;
            // PHASE 3 -- tag filter (AND'd with whatever filterMode above matched)
            if (selectedTag.length > 0 && !(Array.isArray(wp.tags) && wp.tags.includes(selectedTag))) return false;
            if (q.length > 0) {
                const nameMatch = wp.name.toLowerCase().includes(q);
                const tagMatch = Array.isArray(wp.tags) && wp.tags.some(t => t.toLowerCase().includes(q));
                if (!nameMatch && !tagMatch) return false;
            }
            // PHASE 4 -- Advanced search fields (AND'd with everything above)
            if (advResolution.length > 0 && wp.resolution !== advResolution) return false;
            if (advMinFps > 0 && (wp.fps || 0) < advMinFps) return false;
            if (advMinDurationSeconds > 0 && (wp.duration_seconds || 0) < advMinDurationSeconds) return false;
            if (advFavoriteOnly && !wp.favorite) return false;
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

    // PHASE 4 -- Tags (#22 "Gắn tag cho wallpaper"). Same optimistic-local-
    // update-then-authoritative-file-watch shape as toggleFavorite above.
    function addTag(path, tag) {
        tag = (tag || "").trim();
        if (tag.length === 0) return;
        wallpapers = wallpapers.map(wp => {
            if (wp.path !== path) return wp;
            const tags = Array.isArray(wp.tags) ? wp.tags : [];
            if (tags.includes(tag)) return wp;
            return Object.assign({}, wp, { tags: tags.concat([tag]) });
        });
        tagProc.command = ["bash", Paths.script("tag.sh"), path, "add", tag];
        tagProc.running = true;
    }

    function removeTag(path, tag) {
        wallpapers = wallpapers.map(wp => {
            if (wp.path !== path || !Array.isArray(wp.tags)) return wp;
            return Object.assign({}, wp, { tags: wp.tags.filter(t => t !== tag) });
        });
        tagProc.command = ["bash", Paths.script("tag.sh"), path, "remove", tag];
        tagProc.running = true;
    }

    property FileView dbView: FileView {
        path: Paths.dbFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                service.wallpapers = JSON.parse(text());
                // One-shot, startup-only self-heal for thumbnails that
                // went missing on disk since the last full scan (cache
                // wiped by something other than Clear Cache, an
                // interrupted ffmpeg run, etc.) -- see verify_thumbs.sh.
                // Deliberately NOT a full refresh(): that re-hashes every
                // video on disk (see wallpaper_list.sh), which is fine
                // for a user-triggered Refresh but too heavy to run
                // unconditionally on every launch for a large library.
                if (!service._thumbsVerified) {
                    service._thumbsVerified = true;
                    verifyThumbsProc.running = true;
                }
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

    // Set once the startup thumbnail self-heal (see dbView.onLoaded
    // above) has fired, so later reloads (favorite toggles, applying a
    // wallpaper, etc. all rewrite wallpapers.json and re-trigger
    // onLoaded) don't redundantly re-run it every time.
    property bool _thumbsVerified: false

    property Process verifyThumbsProc: Process {
        id: verifyThumbsProc
        command: ["bash", Paths.script("verify_thumbs.sh")]
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
    property Process tagProc: Process { id: tagProc }
}
