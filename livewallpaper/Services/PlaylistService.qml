pragma Singleton
import Quickshell
import QtQuick

/*
 * PlaylistService.qml
 * ----------------------
 * When enabled (settings.playlist_enabled), automatically advances the
 * wallpaper every settings.playlist_interval_minutes, per
 * settings.playlist_mode:
 *   - "sequential" -> steps through the library in order (PlaybackService.next)
 *   - "random"     -> jumps to a random wallpaper (PlaybackService.random)
 *   - "favorites"  -> jumps to a random FAVORITE wallpaper only, falling
 *                     back to plain random if there are no favorites yet
 *   - "custom"     -> jumps to a random wallpaper/GIF from one saved
 *                     Collection (see CollectionService), picked on the
 *                     Playlist page (PlaylistBar.qml's collection
 *                     picker, right next to the Collections manager that
 *                     used to be its own page). Falls back to plain
 *                     random if no collection is selected or it's empty.
 *
 * Advances whatever PlaybackService.selectedMonitor currently targets, so
 * it respects the same "which output am I controlling" choice the rest of
 * the panel uses.
 */
QtObject {
    id: service

    readonly property bool enabled: SettingsService.playlistEnabled
    readonly property int intervalMinutes: SettingsService.playlistIntervalMinutes
    readonly property string mode: SettingsService.playlistMode
    readonly property string customCollection: SettingsService.playlistCustomCollection

    property real msRemaining: 0
    readonly property real msTotal: Math.max(1, intervalMinutes) * 60000

    // FIX (Playlist "Favorites" mode mixing MP4 and GIF): mirrors the
    // Next/Previous/Random fix in PlaybackService.qml. "sequential" and
    // "random" above already go through PlaybackService.next()/random(),
    // which now auto-detects MP4 vs GIF from whatever is ACTUALLY playing
    // (service.currentPath's extension) -- so those two modes already
    // advance within the right pool with no change needed here.
    // "favorites" was the one mode that bypassed that shared logic and
    // went straight to WallpaperService.wallpapers (MP4-only favorites),
    // so a GIF currently playing would get advanced to an MP4 favorite
    // instead of a GIF one. Fixed the same way: pick the favorites pool
    // based on the currently-playing type, reusing GifPlaylistService's
    // existing settings.gif_favorites bookkeeping for the GIF side
    // instead of duplicating it.
    function advanceNow() {
        if (!service.enabled) return;
        countdownTimer.restart();
        service.msRemaining = service.msTotal;

        if (mode === "random") {
            PlaybackService.random();
            return;
        }
        if (mode === "favorites") {
            if (PlaybackService._isGifPath(PlaybackService.currentPath)) {
                const gifFavs = GifPlaylistService.favoritePaths();
                const gifPool = GifPlaylistService.gifs.filter(p => gifFavs.indexOf(p) >= 0);
                if (gifPool.length === 0) {
                    PlaybackService.random();
                } else {
                    GifPlaylistService.pickRandomFrom(gifPool);
                }
                return;
            }
            const favorites = WallpaperService.wallpapers.filter(wp => wp.favorite);
            if (favorites.length === 0) {
                PlaybackService.random();
                return;
            }
            const pick = favorites[Math.floor(Math.random() * favorites.length)];
            PlaybackService.apply(pick.path);
            return;
        }
        if (mode === "custom") {
            // Client-side random pick, same pattern as "favorites" above --
            // CollectionService.collections is already loaded reactively,
            // no need to shell out to collections.sh for this.
            const coll = CollectionService.collections[service.customCollection];
            const pool = (coll && coll.paths) || [];
            if (pool.length === 0) {
                PlaybackService.random();
                return;
            }
            const target = pool[Math.floor(Math.random() * pool.length)];
            if (PlaybackService._isGifPath(target)) {
                GifPlaylistService.applyGif(target);
            } else {
                PlaybackService.apply(target);
            }
            return;
        }
        // "sequential" (default)
        PlaybackService.next();
    }

    function setEnabled(value) {
        SettingsService.set("playlist_enabled", value);
    }
    function setIntervalMinutes(minutes) {
        SettingsService.set("playlist_interval_minutes", minutes);
    }
    function setMode(newMode) {
        SettingsService.set("playlist_mode", newMode);
    }

    // ── Custom mode's source ─────────────────────────────────────────
    function setCustomCollection(name) {
        SettingsService.set("playlist_custom_collection", name || "");
    }

    property Timer advanceTimer: Timer {
        interval: service.msTotal
        running: service.enabled
        repeat: true
        onTriggered: service.advanceNow()
    }

    // 1s ticking countdown for an optional "next switch in mm:ss" label in
    // the UI -- purely cosmetic, doesn't drive the actual advance.
    property Timer countdownTimer: Timer {
        interval: 1000
        running: service.enabled
        repeat: true
        onTriggered: {
            service.msRemaining = Math.max(0, service.msRemaining - 1000);
        }
    }

    onEnabledChanged: {
        if (enabled) {
            msRemaining = msTotal;
            advanceTimer.interval = msTotal;
            advanceTimer.restart();
            countdownTimer.restart();
        } else {
            msRemaining = 0;
        }
    }

    onIntervalMinutesChanged: {
        msRemaining = msTotal;
        if (enabled) {
            advanceTimer.interval = msTotal;
            advanceTimer.restart();
            countdownTimer.restart();
        }
    }

    onModeChanged: {
        // A mode change should affect the next scheduled switch, not leave
        // an old timer cycle running from the previous mode.
        if (enabled) {
            advanceTimer.interval = msTotal;
            advanceTimer.restart();
            msRemaining = msTotal;
            countdownTimer.restart();
        }
    }

    Component.onCompleted: {
        advanceTimer.interval = msTotal;
        msRemaining = enabled ? msTotal : 0;
    }
}
