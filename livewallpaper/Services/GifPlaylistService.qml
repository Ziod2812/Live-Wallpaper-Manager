pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

/*
 * GifPlaylistService.qml
 * ----------------------
 * GIF-library data source shared by the rest of the app: the alphabetically
 * sorted scan of the GIF wallpaper directory, plus GIF favorites
 * bookkeeping (settings.gif_favorites).
 *
 * REMOVED (own auto-advance timer + "GIF Playlist" UI bar): this used to
 * also be a second, independent PlaylistService -- its own
 * settings.gif_playlist_enabled on/off toggle, interval, and
 * sequential/random/favorites mode, advancing on its own timer. That was
 * deleted once PlaylistService.advanceNow() (and PlaybackService's
 * next()/previous()/random()) started auto-detecting MP4 vs GIF from
 * whatever is ACTUALLY playing -- the single "Playlist" bar now advances
 * GIFs when a GIF is showing and wallpapers when a wallpaper is showing,
 * so a second, separately-scheduled GIF-only playlist was redundant. See
 * PlaylistService.qml's own comment for the full fix.
 *
 * What's still here and still used elsewhere:
 *   - gifs / rescan(): the reactive GIF-folder scan. PlaybackService's
 *     next()/previous()/random() read `gifs` (via _navigationList()) to
 *     step through GIFs, the same way they read WallpaperService.wallpapers
 *     for MP4s.
 *   - favoritePaths(): settings.gif_favorites bookkeeping, also read by
 *     PlaylistService's "favorites" mode when a GIF is currently playing.
 *     "Recent" is no longer tracked here -- history.json (shared with
 *     wallpapers via HistoryService, see that file's header) is now the
 *     single source for Recent across both GIFs and wallpapers, capped
 *     at one combined pool of 20 instead of two separately-capped lists.
 *   - applyGif()/pickRandomFrom(): still available for any caller that
 *     wants to apply a GIF.
 */
QtObject {
    id: service

    // Alphabetically sorted list of absolute GIF paths. PlaybackService
    // triggers a rescan on demand (via _refreshNavigationSource) the first
    // time it finds this empty while navigating a GIF; also rescanned here
    // on startup so it's ready before that.
    property var gifs: []

    function expandedDirectory() {
        const p = String(SettingsService.gifWallpaperDirectory || "").trim();
        const home = Quickshell.env("HOME") || "";
        if (p === "~") return home;
        if (p.indexOf("~/") === 0) return home + p.substring(1);
        return p;
    }

    function rescan() {
        scanProc.command = [
            "bash", "-lc",
            'd="$1"; if [ -d "$d" ]; then find "$d" -maxdepth 1 -type f -iname "*.gif" -print0 | sort -z -f | tr "\\0" "\\n"; fi',
            "gif-playlist-scan", expandedDirectory()
        ];
        scanProc.running = true;
    }

    function favoritePaths() {
        try {
            const f = JSON.parse(SettingsService.settings.gif_favorites || "[]");
            return Array.isArray(f) ? f : [];
        } catch (e) {
            return [];
        }
    }

    function applyGif(path) {
        if (!path) return;
        PlaybackService.apply(path);
    }

    function pickRandomFrom(list) {
        if (list.length === 0) return;
        applyGif(list[Math.floor(Math.random() * list.length)]);
    }

    property Process scanProc: Process {
        id: scanProc
        stdout: StdioCollector { id: scanOut }
        stderr: StdioCollector { id: scanErr }
        onExited: (code, status) => {
            if (code !== 0) {
                service.gifs = [];
                return;
            }
            const lines = scanOut.text.split("\n");
            const found = [];
            for (let i = 0; i < lines.length; ++i) {
                const p = lines[i].trim();
                if (p.length) found.push(p);
            }
            service.gifs = found;
        }
    }

    // Rescan on startup unconditionally (previously gated behind the
    // now-removed "enabled" toggle) so `gifs` is ready for Next/Previous/
    // Random and the Playlist bar's "favorites" mode as soon as a GIF is
    // playing, without waiting on the on-demand rescan fallback in
    // PlaybackService._refreshNavigationSource().
    Component.onCompleted: rescan()
}
