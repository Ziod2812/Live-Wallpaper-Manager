pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

/*
 * CollectionService.qml
 * -----------------------
 * Wallpaper "collections" (named groups -- Anime / Nature / Cyberpunk /
 * Minimal, ...). Same read/write split as every other data-backed
 * service here: reactive read via FileView(watchChanges) on
 * data/collections.json, writes delegated to scripts/collections.sh so
 * the JSON-editing logic (and its locking/atomic-write safety) lives in
 * exactly one place.
 *
 * `collections` is a plain JS object: { name: { paths: [...], color,
 * created } }. Consumers that just need a flat list of names use
 * `names` below.
 */
QtObject {
    id: service

    property var collections: ({})
    readonly property var names: Object.keys(collections).sort((a, b) => a.localeCompare(b))

    function pathCount(name) {
        const c = collections[name];
        return c && c.paths ? c.paths.length : 0;
    }

    function collectionsForPath(path) {
        // Cheap client-side derivation -- no need to shell out for
        // something the already-loaded `collections` object answers
        // directly (for_path in collections.sh exists for scripting/
        // scheduler use, not for the UI's hot path).
        const out = [];
        for (const name of service.names) {
            const paths = collections[name] && collections[name].paths;
            if (paths && paths.indexOf(path) !== -1) out.push(name);
        }
        return out;
    }

    function reload() {
        collectionsView.reload();
    }

    function create(name, color) {
        if (!name || String(name).trim().length === 0) return;
        const args = ["bash", Paths.script("collections.sh"), "create", name];
        if (color) args.push(color);
        _run(createProc, args);
    }
    function remove(name) {
        _run(deleteProc, ["bash", Paths.script("collections.sh"), "delete", name]);
    }
    function rename(oldName, newName) {
        _run(renameProc, ["bash", Paths.script("collections.sh"), "rename", oldName, newName]);
    }
    function setColor(name, color) {
        _run(colorProc, ["bash", Paths.script("collections.sh"), "set_color", name, color]);
    }
    function addWallpaper(name, path) {
        _run(memberProc, ["bash", Paths.script("collections.sh"), "add", name, path]);
    }
    function removeWallpaper(name, path) {
        _run(memberProc, ["bash", Paths.script("collections.sh"), "remove", name, path]);
    }
    function toggleWallpaper(name, path) {
        _run(memberProc, ["bash", Paths.script("collections.sh"), "toggle", name, path]);
    }

    // Queues writes the same way SettingsService does -- these are
    // occasional user-driven edits (create/rename/add/remove), not a
    // hot loop, but reusing "don't start a second Process while one is
    // still running" keeps behavior predictable under rapid clicking
    // (e.g. ticking several wallpapers into a collection quickly).
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

    property FileView collectionsView: FileView {
        path: Paths.dataDir + "/collections.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                service.collections = JSON.parse(text());
            } catch (e) {
                console.warn("CollectionService: failed to parse collections.json:", e);
            }
        }
    }

    // Every write process reloads the file + re-drains the queue on
    // exit, success or not -- a failed create/rename shouldn't leave
    // later queued edits stuck forever.
    function _onWriteExited() {
        service.reload();
        service._drain();
    }

    property Process createProc: Process { onExited: service._onWriteExited() }
    property Process deleteProc: Process { onExited: service._onWriteExited() }
    property Process renameProc: Process { onExited: service._onWriteExited() }
    property Process colorProc: Process { onExited: service._onWriteExited() }
    property Process memberProc: Process { onExited: service._onWriteExited() }
}
