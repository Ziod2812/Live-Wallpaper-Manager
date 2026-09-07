pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

/*
 * MultiMonitorService.qml
 * -----------------------
 * Hotplug-safe monitor topology service.
 *
 * Quan Hyprland/KWin đang commit output topology, command list có thể trả
 * JSON rỗng hoặc lỗi parse trong vài mili-giây. Service này tuyệt đối không
 * thay snapshot hợp lệ bằng dữ liệu lỗi, đồng thời không tạo Process chồng.
 *
 * `topologyGeneration` tăng mỗi khi topology thực sự đổi. Các service khác
 * có thể dựa vào `monitorsChanged`/generation để re-evaluate surface mà không
 * cần kill persistent MPV IPC.
 */
QtObject {
    id: service

    property var monitors: []
    readonly property int count: monitors.length
    readonly property bool multiMonitor: count > 1
    readonly property bool refreshing: listProc.running
    readonly property int topologyGeneration: 0

    property bool _refreshPending: false
    property int _debounceInterval: 120
    property string _lastValidJson: "[]"

    signal topologyReconciled(var added, var removed, var current)

    readonly property string focusedMonitorName: {
        for (const monitor of monitors) {
            if (monitor && monitor.focused === true) {
                return monitor.name || "";
            }
        }
        return monitors.length > 0 ? (monitors[0].name || "") : "";
    }

    function _sanitizeList(raw) {
        if (!Array.isArray(raw)) {
            return null;
        }

        const output = [];
        const seen = Object.create(null);

        for (const item of raw) {
            if (!item || typeof item.name !== "string" || !item.name.length) {
                continue;
            }
            if (seen[item.name]) {
                continue;
            }
            seen[item.name] = true;

            output.push({
                name: item.name,
                width: Number(item.width) || 0,
                height: Number(item.height) || 0,
                focused: item.focused === true
            });
        }

        return output;
    }

    function _names(list) {
        return list.map(function(item) { return item.name; });
    }

    function _reconcile(next) {
        const old = service.monitors || [];
        const oldNames = _names(old);
        const newNames = _names(next);

        const added = newNames.filter(function(name) {
            return oldNames.indexOf(name) < 0;
        });
        const removed = oldNames.filter(function(name) {
            return newNames.indexOf(name) < 0;
        });

        const json = JSON.stringify(next);
        if (json === service._lastValidJson) {
            return;
        }

        service._lastValidJson = json;
        service.monitors = next;
        service.topologyGeneration += 1;

        // Chỉ phát signal sau khi property đã commit, để listener nhìn thấy
        // state nhất quán. Không tự stop/restart MPV ở đây; PlaybackService /
        // SmartPlaybackService sẽ tự re-evaluate dựa trên monitorsChanged.
        service.topologyReconciled(added, removed, next);
    }

    function refresh(force) {
        if (listProc.running) {
            // Hotplug burst -> một lần query đang chạy + cờ pending. Không stop
            // Process hiện tại vì stop stdout giữa chừng có thể tạo JSON cụt.
            service._refreshPending = true;
            if (force) {
                service._debounceInterval = 0;
            }
            return;
        }

        service._refreshPending = false;
        listProc.running = true;
    }

    property Process listProc: Process {
        id: listProc

        command: ["bash", Paths.script("monitor.sh"), "list"]

        stdout: StdioCollector {
            onStreamFinished: {
                const sanitized = service._sanitizeList(
                    (function() {
                        try {
                            return JSON.parse(text);
                        } catch (error) {
                            console.warn(
                                "MultiMonitorService: monitor JSON parse failed; keeping last valid topology"
                            );
                            return null;
                        }
                    })()
                );

                if (sanitized !== null) {
                    service._reconcile(sanitized);
                }

                if (service._refreshPending) {
                    service._refreshPending = false;
                    service.refreshDebounce.interval = service._debounceInterval;
                    service._debounceInterval = 120;
                    service.refreshDebounce.restart();
                }
            }
        }

        onRunningChanged: {
            if (!running && service._refreshPending) {
                service._refreshPending = false;
                service.refreshDebounce.interval = 120;
                service.refreshDebounce.restart();
            }
        }
    }

    property Timer refreshDebounce: Timer {
        interval: 120
        repeat: false
        onTriggered: service.refresh(false)
    }

    property Timer refreshTimer: Timer {
        // Hotplug detection không cần fork mỗi 1s. 5s giữ CPU/process overhead
        // thấp nhưng refresh() vẫn có thể được gọi ngay khi UI cần.
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: service.refresh(false)
    }

    Component.onCompleted: service.refresh(true)
}
