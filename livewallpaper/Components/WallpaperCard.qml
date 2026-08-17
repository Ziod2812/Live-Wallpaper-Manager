import QtQuick
import "../Config"
import "../Services"

/*
 * WallpaperCard.qml
 * --------------------
 * One tile in the grid. Clicking the thumbnail or the Apply button plays
 * that wallpaper at the currently selected resolution/fps. The star
 * toggles favorite state. The meta row shows the *source* video's native
 * fps/resolution/duration (from ffprobe, read-only/informational) — not
 * to be confused with the playback resolution/fps selector, which caps
 * what's rendered.
 */
Item {
    id: root

    property var wp
    readonly property bool isCurrent: PlaybackService.currentPath === wp.path

    // PHASE 3 -- large-thumbnail toggle (see WallpaperGrid.qml/
    // WallpapersModeContent.qml). Scales the thumbnail + card footprint
    // up; metadata/name/buttons keep the same layout, just wider.
    property bool large: false
    readonly property int thumbW: large ? 288 : 190
    readonly property int thumbH: large ? 168 : 110
    readonly property bool hasTags: Array.isArray(wp.tags) && wp.tags.length > 0

    signal previewRequested(var wp)

    implicitWidth: thumbW
    // thumb + name/favorite/apply row (34) + metadata row (16) + tags
    // row (22, only when present) + spacing between each visible row.
    implicitHeight: thumbH + 34 + 16 + (hasTags ? 22 : 0) + Theme.spacingSm * (hasTags ? 3 : 2)

    Column {
        anchors.fill: parent
        spacing: Theme.spacingSm

        // -------------------- THUMBNAIL --------------------
        Rectangle {
            id: thumbFrame
            width: root.thumbW
            height: root.thumbH
            radius: Theme.radiusMd
            color: Theme.surface0
            border.width: root.isCurrent ? 2 : 0
            border.color: Theme.accent
            clip: true

            scale: thumbMouse.pressed ? 0.97 : (thumbMouse.containsMouse ? 1.02 : 1.0)
            Behavior on scale {
                NumberAnimation { duration: Theme.durationFast; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
            }
            Behavior on border.width {
                NumberAnimation { duration: Theme.durationFast }
            }

            Image {
                id: thumb
                anchors.fill: parent
                source: wp.thumb ? "file://" + wp.thumb : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                opacity: status === Image.Ready ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: Theme.durationNormal } }
            }

            // Placeholder while the thumbnail loads or is missing
            Rectangle {
                anchors.fill: parent
                visible: thumb.status !== Image.Ready
                color: Theme.surface0
                Text {
                    anchors.centerIn: parent
                    text: "󰈰"
                    font.family: Theme.fontFamily
                    font.pixelSize: 28
                    color: Theme.overlay0
                }
            }

            // Now-playing pulse indicator
            Rectangle {
                visible: root.isCurrent
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 6
                width: 10
                height: 10
                radius: 5
                color: Theme.accent
                SequentialAnimation on opacity {
                    running: root.isCurrent
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                }
            }

            // PHASE 3 -- Preview button, only visible on hover so it
            // doesn't compete with the click-to-apply thumbnail. Opens
            // WallpaperPreviewDialog (owned by the page, not this card --
            // see WallpapersModeContent.qml) via previewRequested.
            IconButton {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 6
                visible: thumbMouse.containsMouse
                text: "🔍"
                fontSize: Theme.fontSizeSm
                implicitWidth: 28
                implicitHeight: 28
                onClicked: root.previewRequested(root.wp)
            }

            MouseArea {
                id: thumbMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: PlaybackService.apply(wp.path)
            }
        }

        // -------------------- NAME + FAVORITE + APPLY --------------------
        Row {
            width: root.thumbW
            spacing: Theme.spacingSm

            IconButton {
                text: wp.favorite ? "★" : "☆"
                active: wp.favorite === true
                accentColor: Theme.yellow
                width: 32
                implicitWidth: 32
                fontSize: Theme.fontSizeLg
                onClicked: WallpaperService.toggleFavorite(wp.path)
            }

            Text {
                width: root.thumbW - 32 - 60 - Theme.spacingSm * 2
                text: wp.name
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }

            IconButton {
                text: "Apply"
                fontSize: Theme.fontSizeSm
                onClicked: PlaybackService.apply(wp.path)
            }
        }

        // -------------------- METADATA ROW --------------------
        Row {
            width: root.thumbW
            spacing: Theme.spacingSm

            Text {
                text: (wp.fps || 0) + "fps"
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }
            Text {
                text: wp.resolution || ""
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }
            Text {
                text: wp.duration || ""
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }
        }

        // -------------------- TAGS (PHASE 3) --------------------
        Flow {
            width: root.thumbW
            spacing: 4
            visible: Array.isArray(wp.tags) && wp.tags.length > 0

            Repeater {
                model: Array.isArray(wp.tags) ? wp.tags.slice(0, root.large ? 6 : 3) : []
                delegate: Rectangle {
                    radius: Theme.radiusSm
                    color: Theme.surface0
                    height: 16
                    width: tagLabel.implicitWidth + 10
                    Text {
                        id: tagLabel
                        anchors.centerIn: parent
                        text: modelData
                        color: Theme.subtext0
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                    }
                }
            }
        }
    }
}
