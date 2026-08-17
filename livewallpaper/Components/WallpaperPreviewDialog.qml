import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Services"

/*
 * WallpaperPreviewDialog.qml
 * -----------------------------
 * PHASE 3 -- "Preview" + "Large thumbnails" from the Wallpaper Library
 * requirement. Same scrim + centered card shape as ConfirmDialog.qml,
 * but sized for a large image + metadata instead of a Yes/No prompt.
 *
 * Deliberately shows the existing thumbnail file large (Image,
 * PreserveAspectFit) rather than actually playing the video -- doing
 * that would mean spawning a second mpv/mpvpaper instance just for a
 * preview, which the brief explicitly rules out ("No extra mpvpaper").
 *
 * Usage: set `wp` to a wallpaper object (same shape as WallpaperCard's
 * `wp`), then `open = true`.
 */
Item {
    id: root

    property bool open: false
    property var wp: null

    signal closed()

    visible: opacity > 0
    opacity: open ? 1 : 0
    z: 1000

    Behavior on opacity {
        NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutCubic }
    }

    function _close() {
        root.open = false;
        root.closed();
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.6)
        MouseArea {
            anchors.fill: parent
            onClicked: root._close()
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(640, root.width - Theme.spacingXl * 2)
        height: Math.min(560, root.height - Theme.spacingXl * 2)
        radius: Theme.radiusLg
        color: Theme.panelBg
        border.width: 1
        border.color: Theme.panelBorder

        scale: root.open ? 1.0 : 0.94
        Behavior on scale {
            NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        }

        MouseArea { anchors.fill: parent } // absorb clicks, don't fall through to scrim

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacingLg
            spacing: Theme.spacingMd
            visible: root.wp !== null

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: root.wp ? root.wp.name : ""
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeLg
                    font.bold: true
                    elide: Text.ElideRight
                }
                IconButton {
                    text: "✕"
                    accentColor: Theme.danger
                    onClicked: root._close()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radiusMd
                color: Theme.surface0
                clip: true

                Image {
                    anchors.fill: parent
                    source: (root.wp && root.wp.thumb) ? "file://" + root.wp.thumb : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                }
            }

            // -------------------- METADATA --------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingLg

                Text {
                    text: root.wp ? ((root.wp.resolution || "—") + " · " + (root.wp.fps || 0) + "fps · " + (root.wp.duration || "—")) : ""
                    color: Theme.subtext0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }
                Text {
                    text: root.wp ? (root.wp.filesize_human || "") : ""
                    color: Theme.subtext0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 4
                visible: root.wp && Array.isArray(root.wp.tags) && root.wp.tags.length > 0

                Repeater {
                    model: (root.wp && Array.isArray(root.wp.tags)) ? root.wp.tags : []
                    delegate: Rectangle {
                        radius: Theme.radiusSm
                        color: Theme.surface0
                        height: 20
                        width: tagLabel.implicitWidth + 12
                        Text {
                            id: tagLabel
                            anchors.centerIn: parent
                            text: modelData
                            color: Theme.subtext0
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSm

                IconButton {
                    text: (root.wp && root.wp.favorite) ? "★ Favorited" : "☆ Favorite"
                    active: root.wp && root.wp.favorite === true
                    accentColor: Theme.yellow
                    onClicked: if (root.wp) WallpaperService.toggleFavorite(root.wp.path)
                }

                Item { Layout.fillWidth: true }

                IconButton {
                    text: "▶ Apply"
                    bold: true
                    accentColor: Theme.success
                    onClicked: {
                        if (root.wp) PlaybackService.apply(root.wp.path);
                        root._close();
                    }
                }
            }
        }
    }
}
