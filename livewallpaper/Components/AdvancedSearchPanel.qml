import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Services"

/*
 * AdvancedSearchPanel.qml
 * --------------------------
 * PHASE 4 -- #23 "Search nâng cao" (advanced search). Name/Tag are
 * already covered by SearchBar + TagFilterBar; this adds Resolution/
 * FPS/Duration/Favorite as additional AND'd filters. The data/state source
 * is injected through `filterProvider`, which keeps this panel reusable
 * across Wallpapers and GIF mode without cross-mode state leakage.
 *
 * Same shape as TagFilterBar: one property per field drives the filter.
 * GIF mode supplies its own provider and Wallpapers can still use the
 * default WallpaperService provider if the panel is reused elsewhere.
 */
Rectangle {
    id: root

    // Defaults to the standard wallpaper provider. GIF mode injects its own
    // provider, so this panel never reaches across modes for state.
    property var filterProvider: WallpaperService
    // GIF mode has no user-filterable FPS/duration semantics.
    property bool supportsMotionFilters: true

    radius: Theme.radiusMd
    color: Theme.cardBg
    implicitHeight: col.implicitHeight + Theme.spacingMd * 2

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: Theme.spacingMd
        spacing: Theme.spacingSm

        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: "Advanced search"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                font.bold: true
            }
            IconButton {
                text: "Clear"
                fontSize: Theme.fontSizeSm
                visible: root.filterProvider.advFiltersActive
                onClicked: root.filterProvider.clearAdvancedFilters()
            }
        }

        // -------------------- Resolution --------------------
        Flow {
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            visible: root.filterProvider.allResolutions.length > 0

            IconButton {
                text: "Any resolution"
                fontSize: Theme.fontSizeSm
                active: root.filterProvider.advResolution === ""
                onClicked: root.filterProvider.advResolution = ""
            }
            Repeater {
                model: root.filterProvider.allResolutions
                delegate: IconButton {
                    text: modelData
                    fontSize: Theme.fontSizeSm
                    active: root.filterProvider.advResolution === modelData
                    onClicked: root.filterProvider.advResolution =
                        (root.filterProvider.advResolution === modelData) ? "" : modelData
                }
            }
        }

        // -------------------- Min FPS / Min duration / Favorite --------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingLg

            RowLayout {
                spacing: Theme.spacingSm
                enabled: root.supportsMotionFilters
                opacity: root.supportsMotionFilters ? 1.0 : 0.5
                Text {
                    text: "Min FPS"
                    color: Theme.subtext0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }
                Rectangle {
                    width: 56
                    height: 28
                    radius: Theme.radiusSm
                    color: Theme.surface0
                    TextInput {
                        anchors.fill: parent
                        anchors.margins: 6
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        selectByMouse: true
                        validator: IntValidator { bottom: 0; top: 1000 }
                        text: root.filterProvider.advMinFps > 0 ? String(root.filterProvider.advMinFps) : ""
                        onEditingFinished: root.filterProvider.advMinFps = text.length > 0 ? parseInt(text) : 0
                    }
                }
            }

            RowLayout {
                spacing: Theme.spacingSm
                enabled: root.supportsMotionFilters
                opacity: root.supportsMotionFilters ? 1.0 : 0.5
                Text {
                    text: "Min duration (s)"
                    color: Theme.subtext0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }
                Rectangle {
                    width: 56
                    height: 28
                    radius: Theme.radiusSm
                    color: Theme.surface0
                    TextInput {
                        anchors.fill: parent
                        anchors.margins: 6
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        selectByMouse: true
                        validator: IntValidator { bottom: 0; top: 999999 }
                        text: root.filterProvider.advMinDurationSeconds > 0 ? String(root.filterProvider.advMinDurationSeconds) : ""
                        onEditingFinished: root.filterProvider.advMinDurationSeconds = text.length > 0 ? parseInt(text) : 0
                    }
                }
            }

            IconButton {
                text: root.filterProvider.advFavoriteOnly ? "★ Favorites only" : "☆ Favorites only"
                fontSize: Theme.fontSizeSm
                active: root.filterProvider.advFavoriteOnly
                accentColor: Theme.yellow
                onClicked: root.filterProvider.advFavoriteOnly = !root.filterProvider.advFavoriteOnly
            }

            Item { Layout.fillWidth: true }
        }
    }
}
