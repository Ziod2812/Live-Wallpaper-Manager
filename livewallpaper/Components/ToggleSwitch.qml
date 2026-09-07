import QtQuick
import "../Config"

/*
 * ToggleSwitch.qml
 * -------------------
 * Small pill on/off switch used throughout MusicDockPanel.qml (Enable
 * Music Dock, Enable Cava, Auto-hide, Click-through, Blur, Glow). Kept
 * as its own file rather than an inline `component` block -- same
 * "one small reusable piece per file" convention DwtStatusBadge.qml/
 * reusable component files already used in this directory.
 */
Rectangle {
    id: root
    property bool checked: false
    signal toggled()

    width: 44
    height: 24
    radius: 12
    color: root.checked ? Theme.accent : Theme.surface1
    Behavior on color { ColorAnimation { duration: Theme.durationFast } }

    Rectangle {
        width: 18; height: 18; radius: 9
        color: Theme.text
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? parent.width - width - 3 : 3
        Behavior on x { NumberAnimation { duration: Theme.durationFast; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
