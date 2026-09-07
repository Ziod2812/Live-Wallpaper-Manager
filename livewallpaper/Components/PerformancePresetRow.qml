import QtQuick
import QtQuick.Layouts
import "../Config"

RowLayout {
    id: root

    property string label: ""
    property string suffix: ""
    property real currentValue: 0
    property var options: []
    property bool enabled: true

    signal selected(real value)

    Layout.fillWidth: true
    spacing: Theme.spacingSm
    opacity: enabled ? 1 : 0.45

    Text {
        Layout.preferredWidth: 150
        text: root.label
        color: Theme.subtext0
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        verticalAlignment: Text.AlignVCenter
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingXs

        Repeater {
            model: root.options

            delegate: IconButton {
                required property var modelData

                Layout.alignment: Qt.AlignVCenter
                text: Number(modelData).toFixed(0) + root.suffix
                fontSize: Theme.fontSizeSm
                active: Number(modelData) === Number(root.currentValue)
                mutedColor: Theme.subtext0
                accentColor: Theme.accent
                enabled: root.enabled
                onClicked: root.selected(Number(modelData))
            }
        }

        Item { Layout.fillWidth: true }
    }
}
