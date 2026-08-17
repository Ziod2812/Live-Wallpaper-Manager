import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Components"

/*
 * PlaylistPage.qml
 * -------------------
 * Hosts the playlist scheduling controls. Custom playlist editing has been
 * intentionally removed; Playlist now controls only the built-in playback
 * modes (Sequential, Random, Favorites).
 */
Flickable {
    id: root

    anchors.fill: parent
    contentWidth: width
    contentHeight: content.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
        id: content
        width: root.width
        spacing: Theme.spacingLg

        PlaylistBar {
            Layout.fillWidth: true
            onCloseRequested: {}
        }
    }
}
