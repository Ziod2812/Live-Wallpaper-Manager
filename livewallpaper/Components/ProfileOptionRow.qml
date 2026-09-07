import QtQuick
import QtQuick.Layouts
import "../Config"

/*
 * ProfileOptionRow.qml
 * -----------------------
 * Same shape as PerformancePresetRow.qml (label + a row of chip
 * buttons), but for STRING-valued options with an explicit "Auto"
 * choice -- used by WallpaperProfileService's per-wallpaper/per-monitor
 * FPS+Resolution overrides, where "" means "inherit, no override"
 * rather than a real value. PerformancePresetRow itself is numeric-only
 * (Number(modelData).toFixed(0)), which doesn't fit "1080p"/"original"/
 * "" -- hence this sibling component instead of overloading that one.
 */
RowLayout {
    id: root

    property string label: ""
    property string currentValue: "" // "" == Auto/inherit
    // [{value, text}, ...] -- value "" is treated as the Auto option
    property var options: []
    property bool enabled: true

    signal selected(string value)

    Layout.fillWidth: true
    spacing: Theme.spacingSm
    opacity: enabled ? 1 : 0.45

    Text {
        Layout.preferredWidth: 90
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
                text: modelData.text
                fontSize: Theme.fontSizeSm
                active: modelData.value === root.currentValue
                mutedColor: Theme.subtext0
                accentColor: Theme.accent
                enabled: root.enabled
                onClicked: root.selected(modelData.value)
            }
        }

        Item { Layout.fillWidth: true }
    }
}
