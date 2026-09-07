import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Services"

ColumnLayout {
    id: root
    spacing: Theme.spacingXs

    // ── Name row ──────────────────────────────────────────────────────────
    Row {
        spacing: Theme.spacingSm
        Layout.fillWidth: true

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "●"
            color: PlaybackService.running ? Theme.success : Theme.overlay0
            font.pixelSize: 10

            SequentialAnimation on opacity {
                running: PlaybackService.running
                loops: Animation.Infinite
                NumberAnimation { to: 0.4; duration: 900; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Current:"
            color: Theme.subtext0
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: PlaybackService.currentName
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            font.bold: true
            elide: Text.ElideRight
            width: 580
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: PlaybackService.running && PlaybackService.playDuration > 0
            text: PlaybackService.playPercent + "%"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            font.bold: true
        }
    }

    // ── Playback progress bar ─────────────────────────────────────────────
    Item {
        Layout.fillWidth: true
        height: 5
        visible: PlaybackService.running && PlaybackService.playDuration > 0

        // Track (background)
        Rectangle {
            anchors.fill: parent
            radius: 2
            color: Theme.surface0
        }

        // Filled portion
        Rectangle {
            id: progressFill
            width: Math.max(radius * 2,
                            parent.width * Math.min(PlaybackService.playPercent / 100.0, 1.0))
            height: parent.height
            radius: 2
            color: Theme.accent
            clip: true

            Behavior on width {
                NumberAnimation { duration: 800; easing.type: Easing.OutCubic }
            }

            // Subtle shimmer while playing
            Rectangle {
                id: shimmer
                visible: PlaybackService.running
                width: parent.width * 0.3
                height: parent.height
                radius: parent.radius
                x: -width
                color: "transparent"

                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.22) }
                    GradientStop { position: 1.0; color: "transparent" }
                }

                SequentialAnimation on x {
                    running: PlaybackService.running
                    loops: Animation.Infinite
                    NumberAnimation {
                        from: -shimmer.width
                        to:   progressFill.width
                        duration: 1600
                        easing.type: Easing.InOutSine
                    }
                    PauseAnimation { duration: 800 }
                }
            }
        }
    }
}
