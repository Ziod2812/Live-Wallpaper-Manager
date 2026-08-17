pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

/*
 * PowerService.qml
 * -------------------
 * Polls AC/battery state (via /sys/class/power_supply) so PlaybackService
 * can automatically step down resolution/fps when settings.performance is
 * "battery-saver" and the laptop is unplugged, and restore the original
 * quality when plugged back in.
 *
 * Polling (not inotify) because power_supply "status" changes are rare
 * and cheap to check -- a plain 15s timer is simpler and more portable
 * across systems than wiring up udev/upower events for something this
 * infrequent.
 */
QtObject {
    id: service

    property bool onBattery: false
    property bool hasBattery: false

    property Process checkProc: Process {
        id: checkProc
        command: ["bash", "-c",
            "for f in /sys/class/power_supply/BAT*/status; do " +
            "  [ -f \"$f\" ] || continue; " +
            "  echo has_battery; cat \"$f\"; " +
            "done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").filter(l => l.length > 0);
                service.hasBattery = lines.includes("has_battery");
                service.onBattery = lines.some(l => l.toLowerCase() === "discharging");
            }
        }
    }

    property Timer pollTimer: Timer {
        interval: 45000   // 45 s — battery state is slow-changing; 30 s was too aggressive
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!checkProc.running) checkProc.running = true   // guard against overlap
    }
}
