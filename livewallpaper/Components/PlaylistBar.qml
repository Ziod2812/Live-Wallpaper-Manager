import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Services"

Rectangle {
    id: root
    radius: Theme.radiusLg
    color: Theme.cardBg
    border.width: 1
    border.color: Theme.panelBorder
    implicitHeight: content.implicitHeight + Theme.spacingLg * 2

    signal closeRequested()

    readonly property var intervalPresets: [5, 15, 30, 60, 120]
    readonly property var modes: [
        { value: "sequential", label: "Sequential" },
        { value: "random", label: "Random" },
        { value: "favorites", label: "★ Favorites" }
    ]

    readonly property string countdownLabel: {
        const totalSec = Math.floor(PlaylistService.msRemaining / 1000);
        const m = Math.floor(totalSec / 60);
        const s = totalSec % 60;
        return m + ":" + (s < 10 ? "0" + s : s);
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Theme.spacingLg
        spacing: Theme.spacingMd

        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: "Playlist"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMd
                font.bold: true
            }
            Text {
                visible: PlaylistService.enabled
                text: "next in " + root.countdownLabel
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
            }
            IconButton {
                text: PlaylistService.enabled ? "On" : "Off"
                active: PlaylistService.enabled
                accentColor: Theme.success
                fontSize: Theme.fontSizeSm
                onClicked: PlaylistService.setEnabled(!PlaylistService.enabled)
            }
            IconButton {
                text: "✕"
                onClicked: root.closeRequested()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            Text {
                text: "Every:"
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
            }
            Repeater {
                model: root.intervalPresets
                delegate: IconButton {
                    text: modelData >= 60 ? (modelData / 60) + "h" : modelData + "m"
                    fontSize: Theme.fontSizeSm
                    active: PlaylistService.intervalMinutes === modelData
                    onClicked: PlaylistService.setIntervalMinutes(modelData)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            Text {
                text: "Mode:"
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
            }
            Repeater {
                model: root.modes
                delegate: IconButton {
                    text: modelData.label
                    fontSize: Theme.fontSizeSm
                    active: PlaylistService.mode === modelData.value
                    onClicked: PlaylistService.setMode(modelData.value)
                }
            }
            Item { Layout.fillWidth: true }
            IconButton {
                text: "Advance now"
                fontSize: Theme.fontSizeSm
                enabled: PlaylistService.enabled
                opacity: PlaylistService.enabled ? 1.0 : 0.4
                onClicked: PlaylistService.advanceNow()
            }
        }
    }
}
