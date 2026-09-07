import QtQuick
import QtQuick.Layouts
import "../Config"

/*
 * StatRow.qml
 * -----------------
 * One "Label ......... Value" line.
 * and Cache sections (7+ rows combined) don't repeat the same
 * RowLayout/Text/Text boilerplate; same font tokens/sizes DirPanel and
 * CurrentBar already use for label/value text.
 */
RowLayout {
    id: root
    Layout.fillWidth: true

    property string label: ""
    property string value: ""
    property color valueColor: Theme.text

    Text {
        Layout.fillWidth: true
        text: root.label
        color: Theme.subtext0
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
    }

    Text {
        text: root.value
        color: root.valueColor
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        font.bold: true
        elide: Text.ElideMiddle
        horizontalAlignment: Text.AlignRight
    }
}
