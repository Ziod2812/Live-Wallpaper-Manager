import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Services"

/*
 * WallpapersModeContent.qml
 * ---------------------------
 * The "🖼 Wallpapers" mode body -- this is exactly the pre-existing
 * local-wallpaper management UI (search + filter tabs, the grid,
 * current/action bars), lifted verbatim out of LiveWallpaperPanel.qml so
 * it can live side-by-side with the new Streaming/Web mode views inside
 * ModeContentArea. No behavior, bindings, or child components changed --
 * same WallpaperService/PlaybackService wiring as before.
 *
 * PHASE 2: MonitorSelector moved out to its own page (Pages/MonitorPage.qml)
 * per the "Monitor settings" requirement -- this file no longer includes it.
 *
 * PHASE 3: added the Tags filter row, a Large-thumbnails toggle, and the
 * Preview dialog (see TagFilterBar.qml / WallpaperGrid.qml's largeThumbs /
 * WallpaperPreviewDialog.qml) -- Search/Favorites/Recent were already
 * implemented (SearchBar, FilterTabs, HistoryService) and are untouched.
 *
 * Root changed from ColumnLayout to a plain Item wrapping a ColumnLayout
 * (PHASE 3) so WallpaperPreviewDialog -- which needs anchors.fill, not
 * Layout attached properties -- can sit as a proper overlay sibling
 * instead of conflicting with the layout engine.
 */
Item {
    id: root

    property bool zenMode: false
    // Persisted so the choice survives reopening the app -- same generic
    // SettingsService.set() pattern every other UI preference here uses.
    property bool largeThumbs: SettingsService.settings.wallpaper_large_thumbnails === true

    implicitHeight: content.implicitHeight

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: Theme.spacingLg

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingLg
            visible: !root.zenMode
            opacity: root.zenMode ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Theme.durationNormal } }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingMd

                SearchBar {
                    id: searchBar
                    Layout.fillWidth: true
                }

                IconButton {
                    text: root.largeThumbs ? "▦ Large" : "▤ Compact"
                    fontSize: Theme.fontSizeSm
                    active: root.largeThumbs
                    onClicked: {
                        root.largeThumbs = !root.largeThumbs;
                        SettingsService.set("wallpaper_large_thumbnails", root.largeThumbs);
                    }
                }
            }

            FilterTabs {}

            TagFilterBar { Layout.fillWidth: true }
        }

        WallpaperGrid {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            zenMode: root.zenMode
            largeThumbs: root.largeThumbs
            onPreviewRequested: wp => {
                previewDialog.wp = wp;
                previewDialog.open = true;
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingLg
            visible: !root.zenMode
            opacity: root.zenMode ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Theme.durationNormal } }

            CurrentBar { Layout.fillWidth: true }
            ActionBar {
                Layout.fillWidth: true
            }
        }
    }

    // PHASE 3 -- Preview dialog, a sibling of `content` (not a Layout
    // child) so its anchors.fill doesn't conflict with ColumnLayout.
    WallpaperPreviewDialog {
        id: previewDialog
        anchors.fill: parent
    }

    // Re-exposed so LiveWallpaperPanel's focusTimer (searchBar.focusInput())
    // keeps working unchanged after the extraction.
    function focusSearch() {
        searchBar.focusInput();
    }
}
