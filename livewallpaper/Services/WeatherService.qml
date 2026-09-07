pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

/*
 * WeatherService.qml
 * ---------------------
 * Dynamic weather-based wallpapers. weather.sh does the actual Open-Meteo
 * fetch (free, no API key -- see that file) with its own TTL cache;
 * weather_tick.sh maps the resulting condition through
 * settings.weather_rules and applies a random wallpaper from the mapped
 * collection when the condition changes. This service just drives that
 * tick on a timer while settings.weather_enabled is on, and exposes
 * $LW_CACHE_DIR/weather_state.json, previously read for SchedulePage.qml's status display (that UI has since been removed).
 *
 * Polls every 5 minutes regardless of settings.weather_poll_minutes --
 * weather.sh's own cache is what actually rate-limits the network call
 * (poll_minutes controls THAT TTL); this timer only needs to be frequent
 * enough that a cache expiry is noticed promptly.
 */
QtObject {
    id: service

    readonly property bool enabled: SettingsService.settings.weather_enabled === true
    property string condition: "unknown"
    property string appliedCollection: ""
    property string appliedPath: ""

    function reload() {
        stateView.reload();
    }

    property FileView stateView: FileView {
        path: Paths.cacheDir + "/weather_state.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                service.condition = data.condition || "unknown";
                service.appliedCollection = data.collection || "";
                service.appliedPath = data.applied_path || "";
            } catch (e) {
                // Not created yet (weather never applied) -- fine.
            }
        }
    }

    property Process tickProc: Process {
        command: ["bash", Paths.script("weather_tick.sh")]
    }

    property Timer pollTimer: Timer {
        interval: 300000
        running: service.enabled
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!tickProc.running) tickProc.running = true
    }
}
