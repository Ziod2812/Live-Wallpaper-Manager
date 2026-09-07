pragma Singleton
import QtQuick

/*
 * Navigation.qml
 * ----------------
 * Phase 1: static list of the Manager app's pages, plus the currently
 * selected page id. This is the single source of truth for navigation --
 * Sidebar renders `items`, ManagerWindow's page Loader resolves
 * `currentItem.source`, and Toolbar/StatusBar read `currentItem.label`.
 * Nothing here talks to any existing Service; it is purely UI navigation
 * state local to the new desktop-app skeleton.
 *
 * PHASE 2: promoted to a singleton (see Manager/qmldir) so any page can
 * call `Navigation.navigate(id)` directly.
 *
 * UI SIMPLIFICATION: the standalone "Music" page has been removed --
 * VisualizerPage now hosts both the Cava/visualizer controls and the
 * Music Dock settings (MusicDockPanel.qml) in one page, since Music Dock
 * is inherently the visualizer's playback surface and having two pages
 * for the same settings was redundant. No functionality was dropped,
 * only the extra page entry -- see Pages/VisualizerPage.qml.
 *
 * The standalone "Collections" page was folded into PlaylistPage.qml the
 * same way -- Collections exists mainly to feed Playlist's "Custom" mode
 * a saved pool of wallpapers, so managing collections now lives right
 * next to that picker instead of on its own nav entry. Filing a
 * wallpaper into a collection from its "+" button (AddToCollectionDialog)
 * is unaffected -- that flow never went through this page.
 *
 * The standalone "Schedule" page was removed the same way: its
 * Time-of-day rules editor moved into PlaylistPage.qml too. Schedule's
 * other two sections (Location, Weather-based wallpaper) were dropped
 * rather than moved -- there is no location-editing or weather-rule UI
 * anywhere in the app anymore, though the underlying settings/services
 * are untouched, so a previously-set location keeps working for
 * "sunrise"/"sunset" rule boundaries.
 *
 * `source` paths are resolved with Qt.resolvedUrl() relative to THIS
 * file (Manager/Navigation.qml), so they correctly point into the
 * sibling Pages/ directory regardless of where the app is launched from.
 */
QtObject {
    id: navigation

    readonly property var items: [
        { id: "wallpapers",  label: "Wallpapers",  icon: "🖼", source: Qt.resolvedUrl("../Pages/WallpapersPage.qml") },
        { id: "playlist",    label: "Playlist",    icon: "♫", source: Qt.resolvedUrl("../Pages/PlaylistPage.qml") },
        { id: "visualizer",  label: "Visualizer",  icon: "◐", source: Qt.resolvedUrl("../Pages/VisualizerPage.qml") },
        { id: "monitor",     label: "Monitor",     icon: "▭", source: Qt.resolvedUrl("../Pages/MonitorPage.qml") },
        { id: "performance", label: "Performance", icon: "⚡", source: Qt.resolvedUrl("../Pages/PerformancePage.qml") },
         { id: "diagnostics", label: "Diagnostics", icon: "✓", source: Qt.resolvedUrl("../Pages/DiagnosticsPage.qml") },
        { id: "settings",    label: "Settings",    icon: "⚙", source: Qt.resolvedUrl("../Pages/SettingsPage.qml") },
        { id: "about",       label: "About",       icon: "ℹ", source: Qt.resolvedUrl("../Pages/AboutPage.qml") }
    ]

    // Which page is currently selected. Defaults to the first entry
    // ("wallpapers") so the app always opens on a sensible page.
    property string currentId: items.length > 0 ? items[0].id : ""

    readonly property var currentItem: {
        for (let i = 0; i < items.length; i++) {
            if (items[i].id === currentId)
                return items[i];
        }
        return items.length > 0 ? items[0] : null;
    }

    function navigate(id) {
        for (let i = 0; i < items.length; i++) {
            if (items[i].id === id) {
                currentId = id;
                return;
            }
        }
    }
}
