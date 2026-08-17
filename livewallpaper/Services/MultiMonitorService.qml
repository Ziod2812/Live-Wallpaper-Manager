pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

/*
 * MultiMonitorService.qml
 * --------------------------
 * Enumerates connected monitors (via scripts/monitor.sh list, which shells
 * out to `hyprctl monitors -j`) so the panel can offer a per-monitor
 * target selector. Refreshed on a light timer since outputs can be
 * hot-plugged, plus on demand via refresh().
 */
QtObject {
    id: service

    // [{name, width, height, focused}, ...]
    property var monitors: []
    readonly property int count: monitors.length
    readonly property bool multiMonitor: count > 1

    readonly property string focusedMonitorName: {
        for (const m of monitors) {
            if (m.focused) return m.name;
        }
        return monitors.length > 0 ? monitors[0].name : "";
    }

    function refresh() {
        listProc.running = true;
    }

    property Process listProc: Process {
        id: listProc
        command: ["bash", Paths.script("monitor.sh"), "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    if (Array.isArray(parsed)) service.monitors = parsed;
                } catch (e) {
                    console.warn("MultiMonitorService: failed to parse monitor list:", e);
                }
            }
        }
    }

    property Timer refreshTimer: Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: service.refresh()
    }
}
