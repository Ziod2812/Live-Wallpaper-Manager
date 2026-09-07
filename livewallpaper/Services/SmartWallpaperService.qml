pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

QtObject {
    id: service
    readonly property bool enabled: SettingsService.settings.smart_selection_enabled === true
    property Process selectProc: Process {
        id: selectProc
        command: ["bash", Paths.script("smart_select.sh")]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = String(text || "").trim();
                if (path.length > 0) {
                    applyProc.command = ["bash", Paths.script("apply_wallpaper.sh"), path];
                    applyProc.running = true;
                }
            }
        }
    }
    property Process applyProc: Process { id: applyProc }
    function selectNow() { if (!selectProc.running) selectProc.running = true; }
    property Timer selectionTimer: Timer {
        interval: 1800000
        running: service.enabled
        repeat: true
        onTriggered: service.selectNow()
    }
}