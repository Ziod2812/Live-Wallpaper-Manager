import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Services"

/*
 * MonitorLayoutPreview.qml
 * ----------------------------
 * PHASE 3 -- "Preview layout" from the Monitor page requirement.
 *
 * Scope note: monitor.sh (scripts/monitor.sh) only extracts
 * {name, width, height, focused} from `hyprctl monitors -j` -- not x/y
 * screen-space offsets. Since the brief says not to touch the
 * background pipeline, this stays schematic: monitors are laid out
 * left-to-right in MultiMonitorService's own order, each box sized
 * proportionally to its aspect ratio, NOT to their actual relative
 * position/offset on the desktop. Good enough to see "how many
 * monitors, what shape, which one's focused, which one wallpapers/the
 * visualizer currently target" at a glance -- not a pixel-accurate
 * arrangement diagram.
 */
Rectangle {
    id: root
    radius: Theme.radiusLg
    color: Theme.cardBg
    border.width: 1
    border.color: Theme.panelBorder
    implicitHeight: content.implicitHeight + Theme.spacingLg * 2

    readonly property real _maxW: {
        let m = 1;
        for (const mon of MultiMonitorService.monitors) m = Math.max(m, mon.width || 1);
        return m;
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Theme.spacingLg
        spacing: Theme.spacingMd

        Text {
            text: "🖥 Monitor Layout"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeLg
            font.bold: true
        }

        Text {
            visible: MultiMonitorService.count === 0
            text: "No monitors detected (hyprctl unavailable?)."
            color: Theme.subtext0
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
        }

        Row {
            Layout.fillWidth: true
            spacing: Theme.spacingMd
            visible: MultiMonitorService.count > 0

            Repeater {
                model: MultiMonitorService.monitors
                delegate: Rectangle {
                    required property var modelData
                    readonly property real scale: 160 / root._maxW
                    width: Math.max(60, (modelData.width || 0) * scale)
                    height: Math.max(40, (modelData.height || 0) * scale)
                    radius: Theme.radiusSm
                    color: Theme.surface0
                    border.width: modelData.focused ? 2 : 1
                    border.color: modelData.focused ? Theme.accent
                        : (PlaybackService.selectedMonitor === modelData.name ? Theme.success : Theme.panelBorder)

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.name
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.bold: modelData.focused
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.width + "×" + modelData.height
                            color: Theme.subtext0
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingMd
            Row {
                spacing: 4
                Rectangle { width: 8; height: 8; radius: 4; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "Focused"; color: Theme.subtext0; font.family: Theme.fontFamily; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
            }
            Row {
                spacing: 4
                Rectangle { width: 8; height: 8; radius: 4; color: Theme.success; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "Wallpaper target"; color: Theme.subtext0; font.family: Theme.fontFamily; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
            }
        }
    }
}
