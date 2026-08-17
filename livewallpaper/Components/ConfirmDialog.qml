import QtQuick
import QtQuick.Layouts
import "../Config"

/*
 * ConfirmDialog.qml
 * -------------------
 * Generic modal confirmation overlay (scrim + centered card), used for
 * any destructive/disruptive action that shouldn't fire on a single
 * click -- currently "Exit Application" and "Clear Cache" from
 * DirPanel.qml, but written with no caller-specific logic so it is
 * reusable anywhere else a Yes/No confirmation is needed.
 *
 * Usage: set title/message/confirmText/cancelText/danger, then
 * `open = true`. Listen for accepted()/cancelled() and set
 * `open = false` in both handlers (the caller decides what "confirmed"
 * means -- this component only asks the question).
 */
Item {
    id: root

    property bool open: false
    property string title: "Are you sure?"
    property string message: ""
    property string confirmText: "Confirm"
    property string cancelText: "Cancel"
    // true -> confirm button reads as destructive (danger/red accent).
    // false -> confirm button reads as a neutral/positive action.
    property bool danger: true

    signal accepted()
    signal cancelled()

    visible: opacity > 0
    opacity: open ? 1 : 0
    z: 1000

    Behavior on opacity {
        NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutCubic }
    }

    // Scrim -- click-outside-to-cancel, and blocks all interaction with
    // whatever is behind it while a confirmation is pending.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)

        MouseArea {
            anchors.fill: parent
            onClicked: root.cancelled()
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(380, root.width - Theme.spacingXl * 2)
        implicitHeight: cardContent.implicitHeight + Theme.spacingLg * 2
        height: implicitHeight
        radius: Theme.radiusLg
        color: Theme.panelBg
        border.width: 1
        border.color: Theme.panelBorder

        scale: root.open ? 1.0 : 0.94
        Behavior on scale {
            NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        }

        // Absorb clicks on the card itself so they don't fall through to
        // the scrim's click-outside-to-cancel handler.
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: cardContent
            anchors.fill: parent
            anchors.margins: Theme.spacingLg
            spacing: Theme.spacingMd

            Text {
                Layout.fillWidth: true
                text: root.title
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeLg
                font.bold: true
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                visible: root.message.length > 0
                text: root.message
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingSm
                spacing: Theme.spacingSm

                Item { Layout.fillWidth: true }

                IconButton {
                    text: root.cancelText
                    fontSize: Theme.fontSizeSm
                    onClicked: root.cancelled()
                }

                IconButton {
                    text: root.confirmText
                    fontSize: Theme.fontSizeSm
                    bold: true
                    danger: root.danger
                    accentColor: root.danger ? Theme.danger : Theme.success
                    onClicked: root.accepted()
                }
            }
        }
    }
}
