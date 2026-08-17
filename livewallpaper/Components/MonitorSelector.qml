import QtQuick
import "../Config"
import "../Services"

Row {
    id: root
    spacing: Theme.spacingSm
    visible: MultiMonitorService.multiMonitor
    height: visible ? implicitHeight : 0

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "Monitor:"
        color: Theme.subtext0
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
    }

    IconButton {
        text: "Auto"
        fontSize: Theme.fontSizeSm
        active: PlaybackService.selectedMonitor === "auto"
        onClicked: PlaybackService.selectedMonitor = "auto"
    }

    Repeater {
        model: MultiMonitorService.monitors
        delegate: IconButton {
            text: modelData.name + (modelData.focused ? " ●" : "")
            fontSize: Theme.fontSizeSm
            active: PlaybackService.selectedMonitor === modelData.name
            onClicked: PlaybackService.selectedMonitor = modelData.name
        }
    }
}
