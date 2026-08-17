import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../Config"
import "../Services"

/*
 * PerMonitorStatus.qml
 * -----------------------
 * PHASE 3 -- "Per-monitor wallpaper" from the Monitor page requirement.
 *
 * MonitorSelector.qml (above this on the page) is how you CHOOSE which
 * monitor subsequent Apply/Next/Previous/Random calls target -- already
 * existing, unchanged. This component adds visibility into the result:
 * for every detected monitor, what's actually currently playing there,
 * read from that monitor's own state file
 * (Paths.monitorStateFile(name, "current")) -- the exact same file
 * PlaybackService.currentView reads for the SELECTED monitor, just
 * fanned out to all of them here. Read-only FileViews, one per monitor;
 * never writes, never touches the apply/stream/web worker scripts.
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
            text: "Per-monitor wallpaper"
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
            delegate: RowLayout {
                id: row
                required property var modelData
                Layout.fillWidth: true
                spacing: Theme.spacingSm

                property string raw: ""
                readonly property string _display: {
                    if (raw.length === 0) return "None";
                    if (raw.startsWith("stream:")) return "Stream: " + raw.slice(7);
                    if (raw.startsWith("web:") || raw.startsWith("web-local:")) return "Web source";
                    const base = raw.split("/").pop();
                    return base.replace(/\.[^.]+$/, "");
                }

                FileView {
                    id: stateFile
                    path: Paths.monitorStateFile(row.modelData.name, "current")
                    watchChanges: true
                    onFileChanged: reload()
                    onLoaded: row.raw = text().trim()
                    onLoadFailed: row.raw = "" // no state file yet -- "None", not an error
                }

                Text {
                    Layout.preferredWidth: 110
                    text: row.modelData.name + (row.modelData.focused ? " (focused)" : "")
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    font.bold: row.modelData.focused
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: row._display
                    color: Theme.subtext0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    elide: Text.ElideRight
                }
            }
        }
    }
}
