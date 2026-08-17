import QtQuick
import "../Config"
import "../Services"

/*
 * WallpaperGrid.qml
 * --------------------
 * Two-column grid of WallpaperCards. Source list depends on filterMode:
 *   - "all" / "favorites" -> WallpaperService.filteredWallpapers (search +
 *     favorite filter already applied there)
 *   - "recent"            -> HistoryService.recentWallpapers, which is
 *     ALSO run through the search box (name match) but keeps its own
 *     chronological order rather than being re-sorted, since "just
 *     switched through" order is the whole point of that tab.
 */
Item {
    id: root
    property bool zenMode: false
    // PHASE 3 -- large-thumbnail toggle, set from WallpapersModeContent.qml
    property bool largeThumbs: false

    signal previewRequested(var wp)

    readonly property var recentFiltered: {
        const q = WallpaperService.search.toLowerCase();
        if (q.length === 0) return HistoryService.recentWallpapers;
        return HistoryService.recentWallpapers.filter(wp => wp.name.toLowerCase().includes(q));
    }

    readonly property var activeModel: WallpaperService.filterMode === "recent" ? recentFiltered : WallpaperService.filteredWallpapers
    readonly property bool isEmpty: activeModel.length === 0

    implicitHeight: zenMode ? 560 : 380

    GridView {
        id: grid
        anchors.fill: parent
        cellWidth: root.largeThumbs ? 306 : 206
        cellHeight: root.largeThumbs ? 300 : 210
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.activeModel

        delegate: Item {
            width: grid.cellWidth
            height: grid.cellHeight

            WallpaperCard {
                anchors.centerIn: parent
                wp: modelData
                large: root.largeThumbs

                opacity: 0
                Component.onCompleted: opacity = 1
                Behavior on opacity { NumberAnimation { duration: Theme.durationNormal } }

                onPreviewRequested: wp => root.previewRequested(wp)
            }
        }

        add: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durationNormal }
            NumberAnimation { property: "scale"; from: 0.92; to: 1.0; duration: Theme.durationNormal; easing.type: Easing.OutBack }
        }
    }

    // Empty states
    Column {
        anchors.centerIn: parent
        visible: root.isEmpty
        spacing: Theme.spacingSm

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: WallpaperService.filterMode === "recent" ? "󰃰" : "󰸉"
            font.family: Theme.fontFamily
            font.pixelSize: 34
            color: Theme.overlay0
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: WallpaperService.filterMode === "recent"
                ? "No wallpapers switched yet — history shows up here after your first Apply."
                : (WallpaperService.count === 0
                    ? "No wallpapers found. Add videos to your wallpaper folder and hit Refresh."
                    : "No matches.")
            width: 320
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: Theme.subtext0
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
        }
    }
}
