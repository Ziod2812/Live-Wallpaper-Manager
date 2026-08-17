import QtQuick
import QtQuick.Layouts
import "../Config"

/*
 * SliderRow.qml
 * -----------------
 * One full settings row for a numeric slider:
 *
 *     Label                                    78%
 *     ━━━━━━━━━━━━━━━━━━━━━━●━━━━━━━━━━━━━━━━━━━━━━
 *
 * Label and the live value share a top line, and the track gets its
 * own full-width line underneath -- unlike SettingRow.qml (label
 * beside its control), which is still used for the toggle/button rows
 * that don't need a long track. Stacking these is what lets the track
 * span nearly the entire panel width instead of splitting the row with
 * a label column; the slider itself (SettingSlider.qml) is untouched
 * here, this only arranges it.
 *
 * A top-level item in MusicDockPanel.qml's content ColumnLayout, same
 * as SettingRow -- not nested inside one.
 */
ColumnLayout {
    id: root

    property string label: ""
    property alias from: slider.from
    property alias to: slider.to
    property alias stepSize: slider.stepSize
    property alias value: slider.value
    property alias pressed: slider.pressed
    property alias accentColor: slider.accentColor
    property string suffix: ""
    // Optional function(value) -> string, overrides the default
    // "Math.round(value) + suffix" display -- Opacity needs this since
    // its value is a 0..1 fraction, not the percent shown.
    property var formatValue: null

    signal moved()

    Layout.fillWidth: true
    spacing: Theme.spacingXs

    readonly property string displayText: root.formatValue
        ? root.formatValue(slider.value)
        : (Math.round(slider.value) + root.suffix)

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingSm

        Text {
            text: root.label
            color: Theme.subtext0
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            Layout.fillWidth: true
        }
        Text {
            text: root.displayText
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            font.bold: true
            horizontalAlignment: Text.AlignRight
        }
    }

    SettingSlider {
        id: slider
        inLayout: true
        Layout.fillWidth: true
        onMoved: root.moved()
    }
}
