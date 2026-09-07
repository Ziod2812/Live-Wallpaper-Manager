import QtQuick
import QtQuick.Layouts
import "../Config"

/*
 * SettingRow.qml
 * -----------------
 * "Label on the left, control(s) on the right" row used for every entry
 * in MusicDockPanel.qml. Own file, same reasoning as ToggleSwitch.qml.
 */
RowLayout {
    id: root
    property string label: ""
    default property alias content: slot.children

    Layout.fillWidth: true
    // A little more breathing room between the label and its control
    // than the row-to-row spacing below needs (MusicDockPanel.qml sets
    // that on the parent ColumnLayout) -- this is purely the horizontal
    // gap within a single row.
    spacing: Theme.spacingMd

    Text {
        text: root.label
        color: Theme.subtext0
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        // Narrower than before (was 150) now that value numbers live in
        // their own compact label next to each slider instead of being
        // baked into this text (e.g. "Animation speed" instead of
        // "Animation speed (600ms)") -- that's what actually frees up
        // the width the sliders needed. Word-wrap rather than overflow
        // so the handful of longer toggle labels ("Blur (layered
        // translucency)") wrap to a second line instead of spilling
        // into the control next to them.
        Layout.preferredWidth: 128
        Layout.alignment: Qt.AlignVCenter
        wrapMode: Text.WordWrap
    }
    Item {
        id: slot
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        implicitHeight: childrenRect.height
    }
}
