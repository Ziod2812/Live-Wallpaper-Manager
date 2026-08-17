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

    property real msRemaining: 0
    readonly property real msTotal: Math.max(1, intervalMinutes) * 60000

    function advanceNow() {
        if (!service.enabled) return;
        countdownTimer.restart();
        service.msRemaining = service.msTotal;

        if (mode === "random") {
            PlaybackService.random();
            return;
        }
        if (mode === "favorites") {
            const favorites = WallpaperService.wallpapers.filter(wp => wp.favorite);
            if (favorites.length === 0) {
                PlaybackService.random();
                return;
            }
            const pick = favorites[Math.floor(Math.random() * favorites.length)];
            PlaybackService.apply(pick.path);
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
