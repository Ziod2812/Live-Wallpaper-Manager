import QtQuick
import QtQuick.Layouts
import "../Config"

/*
 * StatusBar.qml
 * ---------------
 * Bottom status line for the Manager app window. Phase 1: static/placeholder
 * text only (no Service wiring yet) -- `statusText` defaults to "Ready" and
 * `pageLabel` mirrors whichever page is currently active.
 */
Rectangle {
    id: statusBar

    property string statusText: "Ready"
    property string pageLabel: ""

    color: Theme.crust

    Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: 1
        color: Theme.panelBorder
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacingLg
        anchors.rightMargin: Theme.spacingLg
        spacing: Theme.spacingMd

        Text {
            text: statusBar.statusText
            color: Theme.subtext0
            font.family: Theme.fontFamilyUi
            font.pixelSize: Theme.fontSizeSm
        }

        Item { Layout.fillWidth: true }

        Text {
            text: statusBar.pageLabel
            color: Theme.overlay1
            font.family: Theme.fontFamilyUi
            font.pixelSize: Theme.fontSizeSm
        }
    }
}
