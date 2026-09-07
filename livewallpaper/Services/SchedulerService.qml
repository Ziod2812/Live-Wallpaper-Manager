pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

/*
 * SchedulerService.qml
 * -----------------------
 * Time-of-day / sunrise-sunset wallpaper scheduling. The actual rule
 * evaluation + applying lives in scripts/scheduler_tick.sh (kept in bash
 * so it can reuse collections.sh/sun_times.sh/apply_wallpaper.sh
 * directly) -- this service just ticks it on a timer while
 * settings.schedule_enabled is on, and exposes
 * $LW_CACHE_DIR/schedule_state.json (which rule is active right now, and
 * what got applied for it) so the Playlist page's Time-of-day rules section can show live status.
 *
 * 60s poll: fine-grained enough that a rule boundary is never missed by
 * more than a minute, cheap enough (one bash + jq invocation, no
 * network) to run indefinitely in the background.
 */
QtObject {
    id: service

    readonly property bool enabled: SettingsService.settings.schedule_enabled === true
    property string activeRuleId: ""
    property string appliedPath: ""

    function reload() {
        stateView.reload();
    }

    // "Shuffle now" button on the Playlist page (formerly SchedulePage.qml) -- re-picks a random
    // wallpaper from the currently active rule's collection even though
    // the rule itself hasn't changed.
    function reshuffleNow() {
        tickProc.command = ["bash", Paths.script("scheduler_tick.sh"), "--reshuffle"];
        tickProc.running = true;
    }

    property FileView stateView: FileView {
        path: Paths.cacheDir + "/schedule_state.json"
        watchChanges: true
        // The file may legitimately not exist yet (no rule has matched
        // since the daemon last started) -- not an error. printErrors:
        // false suppresses Quickshell's own "File does not exist" log
        // line the same way PlaybackService's currentView/statusView do;
        // onLoadFailed below now owns that reset instead of a JSON.parse
        // catch block that never actually ran for a missing file anyway.
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                service.activeRuleId = data.active_rule_id || "";
                service.appliedPath = data.applied_path || "";
            } catch (e) {
                console.warn("SchedulerService: failed to parse schedule_state.json:", e);
            }
        }
        onLoadFailed: {
            // No rule has ever matched yet -- reset to "nothing active"
            // instead of leaving a stale value from a previous file.
            service.activeRuleId = "";
            service.appliedPath = "";
        }
    }

    property Process tickProc: Process {
        command: ["bash", Paths.script("scheduler_tick.sh")]
    }

    property Timer pollTimer: Timer {
        interval: 120000  // was 60000 - scheduling rules don't change that frequently
        running: service.enabled
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!tickProc.running) tickProc.running = true
    }
}
