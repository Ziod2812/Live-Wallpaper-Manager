import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Services"

/*
 * SystemStatsPanel.qml
 * -----------------------
 * PHASE 3 -- "CPU / RAM / Processes" from the Performance page
 * requirement. Purely a display over SystemStatsService -- no polling,
 * process spawning, or state lives in this file itself.
 *
 * CPU model/core-thread-count/frequency line added below the CPU%
 * meter -- same SystemStatsService fields, no new polling here.
 *
 * ── Peaclock + Cava attribution ────────────────────────────────────
 * SystemStatsService's `processes` list is PID-based (see system_stats.
 * sh) -- it has exactly one row per real OS process, never per QML
 * feature. "cava" is a single shared process regardless of how many
 * docks are using it (see CavaService.qml's multi-consumer reference
 * counting), so it is already counted exactly once here whether Music
 * Dock, Peaclock + Cava, or both are enabled -- there is nothing to
 * deduplicate. Peaclock's clock face itself (Components/PeaclockClock.
 * qml) is plain QML rendered in-process by the same `quickshell`
 * process every other panel in this app runs in (Music Dock,
 * GPU panel, etc. included) -- it has no OS process/PID of its own, so
 * there is no separate row to add for it without fabricating one.
 * `_processLabel()` below instead makes that attribution legible: it
 * annotates the "quickshell" row with which of the always-in-process
 * features are currently contributing to it, and the "cava" row with
 * which dock(s) are currently sharing it -- both computed purely from
 * already-known settings, never invented numbers. An annotation
 * disappears the instant its feature is turned off, same as the
 * requirement asks for actual resource rows.
 */
Rectangle {
    id: root
    radius: Theme.radiusLg
    color: Theme.cardBg
    border.width: 1
    border.color: Theme.panelBorder
    implicitHeight: content.implicitHeight + Theme.spacingLg * 2

    readonly property bool musicDockCavaOn: SettingsService.settings.music_dock_enabled === true
        && SettingsService.settings.music_dock_cava_enabled !== false
    readonly property bool pcDockOn: SettingsService.settings.pcdock_enabled === true
    readonly property bool pcDockCavaOn: root.pcDockOn
        && SettingsService.settings.pcdock_cava_enabled !== false

    // Human-readable attribution suffix for a process row, or "" for rows
    // that don't need one. Never changes cpu/mem numbers -- purely a label.
    function _processLabel(name) {
        const n = String(name || "");
        if (n.indexOf("cava") !== -1) {
            const sharers = [];
            if (root.musicDockCavaOn) sharers.push("Music Dock");
            if (root.pcDockCavaOn) sharers.push("Peaclock + Cava");
            return sharers.length > 1 ? " — shared: " + sharers.join(" + ")
                 : sharers.length === 1 ? " — " + sharers[0]
                 : "";
        }
        if (n.indexOf("quickshell") !== -1) {
            const parts = [];
            if (SettingsService.settings.music_dock_enabled === true) parts.push("Music Dock");
            if (root.pcDockOn) parts.push("Peaclock + Cava");
            return parts.length > 0 ? " — incl. " + parts.join(", ") : "";
        }
        return "";
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Theme.spacingLg
        spacing: Theme.spacingMd

        Text {
            text: "⚙ System Resources"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeLg
            font.bold: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingXl

            // -------------------- CPU --------------------
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Text {
                    text: "CPU"
                    color: Theme.subtext0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }
                Text {
                    text: Math.round(SystemStatsService.cpuPercent) + "%"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXl
                    font.bold: true
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 6
                    radius: 3
                    color: Theme.surface0
                    Rectangle {
                        height: parent.height
                        radius: 3
                        width: parent.width * Math.min(1, SystemStatsService.cpuPercent / 100)
                        color: SystemStatsService.cpuPercent > 80 ? Theme.danger : Theme.accent
                        Behavior on width { NumberAnimation { duration: 400 } }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: SystemStatsService.cpuModel
                        + " · " + SystemStatsService.cpuCores + "C/" + SystemStatsService.cpuThreads + "T"
                        + " · " + Math.round(SystemStatsService.cpuFreqMhz) + " MHz"
                    color: Theme.overlay0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    elide: Text.ElideRight
                }
            }

            // -------------------- RAM --------------------
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Text {
                    text: "RAM"
                    color: Theme.subtext0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }
                Text {
                    text: SystemStatsService.memUsedMb + " / " + SystemStatsService.memTotalMb + " MB"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXl
                    font.bold: true
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 6
                    radius: 3
                    color: Theme.surface0
                    Rectangle {
                        height: parent.height
                        radius: 3
                        width: parent.width * Math.min(1, SystemStatsService.memPercent / 100)
                        color: SystemStatsService.memPercent > 85 ? Theme.danger : Theme.accent
                        Behavior on width { NumberAnimation { duration: 400 } }
                    }
                }
            }

            // -------------------- FPS (configured target, not a live meter --
            // see PerformancePage.qml's header for why) --------------------
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Text {
                    text: "Target FPS / Res"
                    color: Theme.subtext0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }
                Text {
                    text: PlaybackService.selectedFps + " · " + PlaybackService.selectedResolution
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXl
                    font.bold: true
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.panelBorder }

        // -------------------- PROCESSES --------------------
        Text {
            text: "Processes"
            color: Theme.subtext0
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
        }

        Repeater {
            model: SystemStatsService.processes
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                Text {
                    Layout.preferredWidth: 220
                    text: modelData.name + " (" + modelData.pid + ")" + root._processLabel(modelData.name)
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    elide: Text.ElideRight
                }
                Text {
                    Layout.preferredWidth: 70
                    text: modelData.cpu + "% CPU"
                    color: Theme.subtext0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }
                Text {
                    text: modelData.mem + "% MEM"
                    color: Theme.subtext0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }
            }
        }

        Text {
            visible: SystemStatsService.processes.length === 0
            text: "No Live Wallpaper Manager processes currently running (nothing playing)."
            color: Theme.overlay0
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
        }
    }
}
