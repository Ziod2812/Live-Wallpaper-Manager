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
    property string title: "Playlist"

    // Which backing service this bar controls. Defaults to (and today,
    // only ever used with) PlaylistService -- kept as a property rather
    // than hardcoded since the bar itself is generic over any service
    // exposing this same enabled/intervalMinutes/mode/msRemaining shape.
    property QtObject service: PlaylistService

    readonly property var intervalPresets: [5, 15, 30, 60, 120]
    readonly property var modes: [
        { value: "sequential", label: "Sequential" },
        { value: "random", label: "Random" },
        { value: "favorites", label: "★ Favorites" },
        { value: "custom", label: "Custom" }
    ]

    readonly property string countdownLabel: {
        const totalSec = Math.floor(root.service.msRemaining / 1000);
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
                text: root.title
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMd
                font.bold: true
            }
            Text {
                visible: root.service.enabled
                text: "next in " + root.countdownLabel
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
            }
            IconButton {
                text: root.service.enabled ? "On" : "Off"
                active: root.service.enabled
                accentColor: Theme.success
                fontSize: Theme.fontSizeSm
                onClicked: root.service.setEnabled(!root.service.enabled)
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
                    active: root.service.intervalMinutes === modelData
                    onClicked: root.service.setIntervalMinutes(modelData)
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
                    active: root.service.mode === modelData.value
                    onClicked: root.service.setMode(modelData.value)
                }
            }
            Item { Layout.fillWidth: true }
            IconButton {
                text: "Advance now"
                fontSize: Theme.fontSizeSm
                enabled: root.service.enabled
                opacity: root.service.enabled ? 1.0 : 0.4
                onClicked: root.service.advanceNow()
            }
        }

        // "Custom" mode's source: one saved Collection (see
        // CollectionService / the collection manager further down the
        // Playlist page) that this mode randomly picks from. Only shown
        // once Custom is the active mode.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            visible: root.service.mode === "custom"

            Text {
                text: "Custom playlist source:"
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
            }

            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(collList.implicitHeight, 200)
                contentWidth: width
                contentHeight: collList.implicitHeight
                clip: true

                Column {
                    id: collList
                    width: parent.width
                    spacing: Theme.spacingXs

                    Repeater {
                        model: CollectionService.names
                        delegate: Rectangle {
                            width: collList.width
                            height: rowLayout.implicitHeight + Theme.spacingSm
                            radius: Theme.radiusMd
                            color: root.service.customCollection === modelData ? Theme.segmentActiveBg : "transparent"

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.service.setCustomCollection(modelData)
                            }

                            RowLayout {
                                id: rowLayout
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: Theme.spacingSm
                                anchors.rightMargin: Theme.spacingSm
                                spacing: Theme.spacingSm

                                Rectangle {
                                    width: 10; height: 10; radius: 5
                                    color: (CollectionService.collections[modelData] && CollectionService.collections[modelData].color) || Theme.accent
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                    elide: Text.ElideRight
                                }

                                Text {
                                    text: CollectionService.pathCount(modelData) + " wallpapers"
                                    color: Theme.subtext0
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                }
                            }
                        }
                    }

                    Text {
                        visible: CollectionService.names.length === 0
                        text: "No collections yet -- create one below to use here."
                        color: Theme.subtext0
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                    }
                }
            }

            Text {
                text: root.service.customCollection.length > 0
                    ? "Using \u201c" + root.service.customCollection + "\u201d (" + CollectionService.pathCount(root.service.customCollection) + " wallpapers)"
                    : "No collection selected -- falls back to plain random."
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
            }
        }
    }
}
