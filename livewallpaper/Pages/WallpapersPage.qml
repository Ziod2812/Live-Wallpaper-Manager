import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Services"
import "../Components"

/*
 * WallpapersPage.qml
 * ---------------------
 * PHASE 2 -- "Wallpaper settings" moved here from the panel: the
 * Wallpapers/Streaming/Web mode switcher and its content (browsing,
 * search, filters, the current-mode's live view). This hosts the exact
 * same ModeSwitcher + ModeContentArea components the panel used to host
 * directly, unmodified.
 *
 * appMode / requestModeChange() (the "stop whatever's playing before
 * switching tabs" guard) was MOVED here verbatim from
 * Panels/LiveWallpaperPanel.qml -- it no longer exists on the panel.
 * Still calls the same PlaybackService.stopAll() / SettingsService.set()
 * as before; no service logic changed.
 */
Item {
    id: root

    property string appMode: {
        const m = SettingsService.settings.app_mode;
        return (m === "streaming" || m === "web") ? m : "wallpapers";
    }
    property bool modeSwitching: false

    function requestModeChange(mode) {
        if (mode === appMode || modeSwitching) return;

        // ── Clean-stop guard ─────────────────────────────────────────────
        // Stop whatever is actively playing/connecting on the CURRENT mode
        // before switching tabs -- see PlaybackService.stopAll(). An idle
        // mode switch (nothing playing, just browsing tabs) is a no-op.
        const ps = PlaybackService;
        const activelyPlaying =
            ps.running                       ||
            ps.streamStatus === "playing"    ||
            ps.streamStatus === "connecting" ||
            ps.webStatus    === "playing"    ||
            ps.webStatus    === "connecting";
        if (activelyPlaying) {
            ps.stopAll();
        }

        appMode = mode;
        SettingsService.set("app_mode", mode);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingLg

        ModeSwitcher {
            Layout.fillWidth: true
            currentMode: root.appMode
            locked: root.modeSwitching
            onModeSelected: mode => root.requestModeChange(mode)
        }

        ModeContentArea {
            id: modeContentArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentMode: root.appMode
            onAnimatingChanged: root.modeSwitching = animating
        }
    }

    // PHASE 4 -- used by ManagerWindow's Ctrl+F shortcut. ModeContentArea
    // already forwards to WallpapersModeContent.focusSearch() (Phase 2
    // extraction); this just extends that same chain one level further.
    function focusSearch() {
        modeContentArea.focusSearch();
    }
}
