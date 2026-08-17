pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

/*
 * SystemStatsService.qml
 * -------------------------
 * PHASE 3 -- backs the Performance page's CPU/RAM/Processes readout.
 * This is a genuinely new capability (nothing in this codebase tracked
 * live resource usage before), NOT a duplicate of any existing service:
 * SmartPlaybackService
 * tracks *why* playback is paused, CacheService tracks *disk* usage --
 * none of them read live CPU/RAM.
 *
 * Shells out to scripts/system_stats.sh (read-only, no arguments, no
 * side effects beyond a tiny cpu-delta state file -- see that file's own
 * header) exactly the same "small script + Paths.script() call" pattern
 * monitor.sh/cache.sh already use. It never touches mpvpaper, cava, or
 * any playback state file -- only /proc/stat, /proc/cpuinfo, cpufreq
 * sysfs, `free`, and `ps`.
 *
 * cpuPercent is REAL, htop/btop-algorithm CPU usage (/proc/stat jiffy
 * delta between consecutive polls -- see system_stats.sh's own header
 * for exactly how), not an estimate. cpuModel/cpuCores/cpuThreads are
 * static per boot; cpuFreqMhz is read fresh every poll (current, not
 * max, frequency).
 *
 * `active` gates the poll timer -- PerformancePage.qml sets this true
 * only while it's the visible page, so this costs nothing the rest of
 * the time the app is open (matching CavaService's own "zero idle cost
 * unless something actually wants this running" philosophy). Polls
 * every 1s (previously 3s) -- system_stats.sh's per-call cost is a
 * handful of cheap file reads (no sleep, no heavy subprocess), so this
 * stays low-overhead at the faster interval.
 */
QtObject {
    id: service

    property bool active: false

    property real cpuPercent: 0
    property string cpuModel: ""
    property int cpuCores: 0
    property int cpuThreads: 0
    property real cpuFreqMhz: 0

    property real memUsedMb: 0
    property real memTotalMb: 0
    readonly property real memPercent: memTotalMb > 0 ? (memUsedMb / memTotalMb * 100) : 0

    // [{pid, name, cpu, mem}, ...] -- only mpvpaper/ffmpeg/cava/python3/
    // quickshell processes, sorted by CPU (see system_stats.sh).
    property var processes: []

    function refresh() {
        if (statsProc.running) return;
        statsProc.running = true;
    }

    property Timer pollTimer: Timer {
        interval: 1000
        running: service.active
        repeat: true
        triggeredOnStart: true
        onTriggered: service.refresh()
    }

    property Process statsProc: Process {
        id: statsProc
        command: ["bash", Paths.script("system_stats.sh")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text);
                    const cpu = r.cpu || {};
                    service.cpuPercent = Number(cpu.percent) || 0;
                    service.cpuModel = cpu.model || "Unknown";
                    service.cpuCores = Number(cpu.cores) || 0;
                    service.cpuThreads = Number(cpu.threads) || 0;
                    service.cpuFreqMhz = Number(cpu.freq_mhz) || 0;
                    service.memUsedMb = Number(r.mem_used_mb) || 0;
                    service.memTotalMb = Number(r.mem_total_mb) || 0;
                    service.processes = Array.isArray(r.processes) ? r.processes : [];
                } catch (e) {
                    console.warn("SystemStatsService: failed to parse stats:", e);
                }
            }
        }
    }

    onActiveChanged: if (active) refresh()
}
