import QtQuick
import "../Config"
import "../Services"

/*
 * Toast.qml
 * -----------
 * Inline error/info banner. Unlike a floating overlay, this reserves its
 * own height in the layout while visible (0 while hidden) so it pushes
 * the rest of the panel down instead of overlapping the search bar or
 * anything else below it. Long messages (e.g. a full mpvpaper error line)
 * wrap instead of overflowing the panel width.
 */
Item {
    id: root
    property string message: ""
    property bool isError: false
    property bool shown: false

    implicitHeight: shown ? bubble.implicitHeight : 0
    clip: true

    Behavior on implicitHeight {
        NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutCubic }
    }

    Rectangle {
        id: bubble
        width: parent.width
        implicitHeight: label.implicitHeight + Theme.spacingMd * 2
        y: root.shown ? 0 : -implicitHeight
        radius: Theme.radiusMd
        color: root.isError ? Qt.rgba(0.9529, 0.5451, 0.6588, 0.92) : Qt.rgba(0.6510, 0.8902, 0.6314, 0.92)

        Behavior on y { NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutCubic } }

        Text {
            id: label
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Theme.spacingMd
            text: root.message
            color: Theme.crust
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            font.bold: true
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }
    }

    Timer {
        id: hideTimer
        interval: 4200
        onTriggered: root.shown = false
    }

    Connections {
        target: NotifyService
        function onToast(message, isError) {
            root.message = message;
            root.isError = isError;
            root.shown = true;
            hideTimer.restart();
        }
    }
}
