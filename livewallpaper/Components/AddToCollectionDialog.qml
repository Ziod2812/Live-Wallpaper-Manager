import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Services"

/*
 * AddToCollectionDialog.qml
 * ----------------------------
 * Modal opened from WallpaperCard's "+" button (see
 * WallpapersModeContent.qml). Lists every collection with a toggle for
 * "is this wallpaper in it", plus a small inline "create new collection"
 * row. Same scrim + centered card shell as ConfirmDialog.qml.
 */
Item {
    id: root

    property bool open: false
    property var wp: null

    visible: opacity > 0
    opacity: open ? 1 : 0
    z: 1000

    Behavior on opacity {
        NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutCubic }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        MouseArea { anchors.fill: parent; onClicked: root.open = false }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(360, root.width - Theme.spacingXl * 2)
        implicitHeight: cardContent.implicitHeight + Theme.spacingLg * 2
        height: Math.min(implicitHeight, root.height - Theme.spacingXl * 2)
        radius: Theme.radiusLg
        color: Theme.panelBg
        border.width: 1
        border.color: Theme.panelBorder

        scale: root.open ? 1.0 : 0.94
        Behavior on scale {
            NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: cardContent
            anchors.fill: parent
            anchors.margins: Theme.spacingLg
            spacing: Theme.spacingMd

            Text {
                Layout.fillWidth: true
                text: "Add to collection"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeLg
                font.bold: true
            }

            Text {
                Layout.fillWidth: true
                visible: root.wp !== null
                text: root.wp ? root.wp.name : ""
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                elide: Text.ElideRight
            }

            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(list.implicitHeight, 220)
                contentWidth: width
                contentHeight: list.implicitHeight
                clip: true

                Column {
                    id: list
                    width: parent.width
                    spacing: Theme.spacingXs

                    Repeater {
                        model: CollectionService.names
                        delegate: RowLayout {
                            width: list.width
                            spacing: Theme.spacingSm

                            Rectangle {
                                width: 10; height: 10; radius: 5
                                color: (CollectionService.collections[modelData] && CollectionService.collections[modelData].color) || Theme.accent
                            }

                            Text {
                                Layout.fillWidth: true
                                text: modelData + "  ·  " + CollectionService.pathCount(modelData)
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                            }

                            ToggleSwitch {
                                checked: root.wp !== null && CollectionService.collectionsForPath(root.wp.path).indexOf(modelData) !== -1
                                onToggled: {
                                    if (root.wp) CollectionService.toggleWallpaper(modelData, root.wp.path);
                                }
                            }
                        }
                    }

                    Text {
                        visible: CollectionService.names.length === 0
                        text: "No collections yet — create one below."
                        color: Theme.subtext0
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingSm
                spacing: Theme.spacingSm

                Rectangle {
                    Layout.fillWidth: true
                    height: 34
                    radius: Theme.radiusMd
                    color: Theme.cardBg
                    border.width: newNameInput.activeFocus ? 1 : 0
                    border.color: Theme.accent

                    TextInput {
                        id: newNameInput
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingSm
                        anchors.rightMargin: Theme.spacingSm
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        clip: true
                        onAccepted: {
                            if (text.trim().length === 0) return;
                            CollectionService.create(text.trim());
                            if (root.wp) CollectionService.addWallpaper(text.trim(), root.wp.path);
                            text = "";
                        }
                    }

                    Text {
                        visible: newNameInput.text.length === 0
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingSm
                        anchors.verticalCenter: parent.verticalCenter
                        text: "New collection name…"
                        color: Theme.subtext0
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                    }
                }

                IconButton {
                    text: "Create"
                    fontSize: Theme.fontSizeSm
                    onClicked: newNameInput.accepted()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                IconButton {
                    text: "Done"
                    bold: true
                    fontSize: Theme.fontSizeSm
                    onClicked: root.open = false
                }
            }
        }
    }
}
