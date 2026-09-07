import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Services"

/*
 * MonitorPerformanceProfilePanel.qml
 * -------------------------------------
 * Per-monitor FPS/resolution override (Services/WallpaperProfileService.qml,
 * "Per-wallpaper performance profile" -- monitor-level fallback half of
 * it). A wallpaper-level profile (WallpaperPreviewDialog.qml) always
 * wins over this; this is for things like "the laptop's built-in panel
 * always caps at 15 FPS regardless of which wallpaper is on it",
 * without having to pin every single video individually.
 *
 * Same MultiMonitorService.monitors list PerMonitorStatus.qml already
 * uses. GPU decode mode is intentionally not offered here -- see
 * WallpaperProfileService.qml's header comment.
 */
Rectangle {
    id: root
    radius: Theme.radiusLg
    color: Theme.cardBg
    border.width: 1
    border.color: Theme.panelBorder
    implicitHeight: content.implicitHeight + Theme.spacingLg * 2

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Theme.spacingLg
        spacing: Theme.spacingMd

        Text {
            text: "🖥 Per-monitor performance profile"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeLg
            font.bold: true
        }

        Text {
            visible: MultiMonitorService.count === 0
            text: "No monitors detected."
            color: Theme.subtext0
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
        }

        Repeater {
            model: MultiMonitorService.monitors

            delegate: ColumnLayout {
                id: row
                required property var modelData
                Layout.fillWidth: true
                spacing: Theme.spacingXs

                readonly property string monitorName: row.modelData.name
                readonly property var profile: WallpaperProfileService.monitorProfile(row.monitorName)

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: row.monitorName + (row.modelData.focused ? " (focused)" : "")
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        font.bold: true
                    }
                    IconButton {
                        text: "Clear"
                        fontSize: Theme.fontSizeSm
                        visible: WallpaperProfileService.hasMonitorProfile(row.monitorName)
                        onClicked: WallpaperProfileService.clearMonitorProfile(row.monitorName)
                    }
                }

                ProfileOptionRow {
                    label: "FPS"
                    currentValue: row.profile.fps || ""
                    options: [
                        { value: "", text: "Auto" },
                        { value: "15", text: "15" },
                        { value: "24", text: "24" },
                        { value: "30", text: "30" },
                        { value: "60", text: "60" }
                    ]
                    onSelected: (value) => WallpaperProfileService.setMonitorProfile(
                        row.monitorName, value, row.profile.resolution || "")
                }

                ProfileOptionRow {
                    label: "Resolution"
                    currentValue: row.profile.resolution || ""
                    options: [
                        { value: "", text: "Auto" },
                        { value: "480p", text: "480p" },
                        { value: "720p", text: "720p" },
                        { value: "1080p", text: "1080p" },
                        { value: "original", text: "Original" }
                    ]
                    onSelected: (value) => WallpaperProfileService.setMonitorProfile(
                        row.monitorName, row.profile.fps || "", value)
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spacingXs
                    height: 1
                    color: Theme.panelBorder
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: "A per-wallpaper profile (set from a wallpaper's preview) always overrides these. \"Auto\" targeting also can't resolve a monitor profile at apply time -- pick a specific monitor above (or on the Wallpapers page) for this to take effect."
            color: Theme.subtext0
            font.family: Theme.fontFamily
            font.pixelSize: 10
            wrapMode: Text.WordWrap
        }
    }
}
