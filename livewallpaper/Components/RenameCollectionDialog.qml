import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Services"

/*
 * RenameCollectionDialog.qml
 * -----------------------------
 * Tiny modal: rename a collection. Opened from Pages/PlaylistPage.qml (formerly the standalone CollectionsPage.qml).
 */
Item {
    id: root

    property bool open: false
    property string targetName: ""

    onOpenChanged: if (open) nameInput.text = targetName

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
        anchors.centerIn: parent
        width: Math.min(340, root.width - Theme.spacingXl * 2)
        implicitHeight: col.implicitHeight + Theme.spacingLg * 2
        height: implicitHeight
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
            id: col
            anchors.fill: parent
            anchors.margins: Theme.spacingLg
            spacing: Theme.spacingMd

            Text {
                text: "Rename collection"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeLg
                font.bold: true
            }

            Rectangle {
                Layout.fillWidth: true
                height: 38
                radius: Theme.radiusMd
                color: Theme.cardBg
                border.width: nameInput.activeFocus ? 1 : 0
                border.color: Theme.accent

                TextInput {
                    id: nameInput
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingMd
                    anchors.rightMargin: Theme.spacingMd
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMd
                    clip: true
                    onAccepted: {
                        if (text.trim().length > 0 && text.trim() !== root.targetName) {
                            CollectionService.rename(root.targetName, text.trim());
                        }
                        root.open = false;
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSm
                Item { Layout.fillWidth: true }
                IconButton {
                    text: "Cancel"
                    fontSize: Theme.fontSizeSm
                    onClicked: root.open = false
                }
                IconButton {
                    text: "Save"
                    bold: true
                    fontSize: Theme.fontSizeSm
                    onClicked: nameInput.accepted()
                }
            }
        }
    }
}
