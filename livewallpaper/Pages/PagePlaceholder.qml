import QtQuick
import QtQuick.Layouts
import "../Config"

/*
 * PagePlaceholder.qml
 * ---------------------
 * Shared placeholder body for every Manager page in Phase 1. Each page
 * file (WallpapersPage.qml, PlaylistPage.qml, ...) just instantiates
 * this with its own title/icon/description -- no existing logic is
 * moved into these pages yet, per the Phase 1 spec.
 */
Item {
    id: root

    property string pageTitle: "Page"
    property string icon: "•"
    property string description: "This page is a placeholder. Content will be added in a later phase."

    ColumnLayout {
        anchors.centerIn: parent
        spacing: Theme.spacingMd

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.icon
            font.pixelSize: 40
            color: Theme.accent
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.pageTitle
            font.family: Theme.fontFamilyUi
            font.pixelSize: Theme.fontSizeXl
            font.bold: true
            color: Theme.text
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 360
            text: root.description
            font.family: Theme.fontFamilyUi
            font.pixelSize: Theme.fontSizeMd
            color: Theme.subtext0
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
