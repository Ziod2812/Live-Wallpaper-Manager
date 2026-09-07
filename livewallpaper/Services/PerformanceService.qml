pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

/*
 * PerformanceService.qml
 * ----------------------
 * v2.1.0 Performance Engine.
 *
 * Combines GPU utilization, GPU temperature, battery state and the user's
 * playback preference into one conservative runtime FPS decision. It never
 * rewrites the user's selected FPS. Instead it uses PlaybackService's
 * transient performanceFpsOverride and re-launches only local wallpapers.
 *
 * Precedence:
 *   1. Critical thermal protection can stop playback and later restore it.
 *   2. Adaptive FPS chooses a tier from current GPU load.
 *   3. Battery profiles cap FPS while discharging / low battery.
 *   4. Thermal warning caps FPS.
 *
 * The engine polls only while at least one feature that needs it is enabled.
 */
QtObject {
    id: service

    readonly property bool adaptiveEnabled: SettingsService.adaptiveFpsEnabled
    readonly property bool thermalEnabled: SettingsService.thermalProtectionEnabled
    readonly property bool batteryEnabled: SettingsService.batteryProfilesEnabled
    readonly property bool monitoringNeeded: adaptiveEnabled || thermalEnabled || batteryEnabled

    property int currentGpuPercent: -1
    property real currentGpuTemp: -1
    property int adaptiveTargetFps: 0
    property int effectiveTargetFps: 0
    property string stateText: "Idle"
    property string thermalState: "normal" // normal | warning | critical
    property bool thermalPaused: false
    property bool applying: false

    function _currentGpuMetric() {
        const stats = GPUManagerService.gpuStats || [];
        let maxUtil = -1;
        let maxTemp = -1;
        for (const s of stats) {
            if (s && typeof s.utilization_pct === "number")
                maxUtil = Math.max(maxUtil, s.utilization_pct);
            if (s && typeof s.temp_c === "number")
                maxTemp = Math.max(maxTemp, s.temp_c);
        }
        return { utilization: maxUtil, temperature: maxTemp };
    }

    function _clamp(value, lo, hi) {
        return Math.max(lo, Math.min(hi, value));
    }

    function _adaptiveFpsFor(util) {
        const minFps = Math.min(SettingsService.adaptiveFpsMin, SettingsService.adaptiveFpsMax);
        const maxFps = Math.max(SettingsService.adaptiveFpsMin, SettingsService.adaptiveFpsMax);
        if (util < 0) return maxFps;
        const low = _clamp(SettingsService.adaptiveGpuLow, 0, 100);
        const high = _clamp(Math.max(SettingsService.adaptiveGpuHigh, low + 1), 1, 100);
        const range = Math.max(1, high - low);
        if (util <= low) return maxFps;
        if (util >= high) return minFps;
        const ratio = (util - low) / range;
        // Hysteresis-like tiering without excessive restarts.
        const tierCount = 3;
        const tier = Math.round(ratio * tierCount);
        const step = (maxFps - minFps) / tierCount;
        return Math.round(maxFps - tier * step);
    }

    function _batteryCap() {
        if (!batteryEnabled || !PowerService.hasBattery || !PowerService.onBattery)
            return 0;
        if (PowerService.batteryPercent >= 0 &&
            PowerService.batteryPercent <= SettingsService.lowBatteryThreshold) {
            return Math.max(1, SettingsService.lowBatteryFps);
        }
        return Math.max(1, parseInt(SettingsService.batteryFps, 10) || 30);
    }

    function _effectiveTarget() {
        let target = 0;
        if (adaptiveEnabled) target = service.adaptiveTargetFps;
        const batteryCap = _batteryCap();
        if (batteryCap > 0) target = target > 0 ? Math.min(target, batteryCap) : batteryCap;
        if (service.thermalState === "warning") {
            const thermalFps = Math.max(1, SettingsService.thermalWarningFps);
            target = target > 0 ? Math.min(target, thermalFps) : thermalFps;
        }
        return target;
    }

    function _applyTarget(target, reason) {
        if (!PlaybackService.currentPath || PlaybackService.playMode !== "wallpapers") return;
        if (target <= 0) {
            PlaybackService.clearPerformanceFpsOverride(reason || "");
            return;
        }
        const numeric = Math.max(1, Math.round(target));
        if (PlaybackService.appliedFps === String(numeric)) return;
        applying = true;
        PlaybackService.reapplyWithPerformanceFps(numeric, reason || "");
        applying = false;
    }

    function _pauseForThermal() {
        if (service.thermalPaused) return;
        if (PlaybackService.playMode !== "wallpapers" ||
            !PlaybackService.currentPath ||
            !PlaybackService.running) return;
        service.thermalPaused = true;
        PlaybackService.stopAll();
        NotifyService.error("GPU temperature is critical — wallpaper playback paused for safety.");
    }

    function _resumeFromThermal() {
        if (!service.thermalPaused) return;
        service.thermalPaused = false;
        PlaybackService.start();
        NotifyService.info("GPU temperature is safe again — wallpaper playback resumed.");
    }

    function evaluate() {
        const metric = _currentGpuMetric();
        currentGpuPercent = metric.utilization;
        currentGpuTemp = metric.temperature;

        let thermal = "normal";
        if (thermalEnabled && metric.temperature >= 0) {
            if (metric.temperature >= SettingsService.thermalCriticalC) thermal = "critical";
            else if (metric.temperature >= SettingsService.thermalWarningC) thermal = "warning";
        }
        thermalState = thermal;

        if (thermal === "critical") {
            stateText = "Thermal protection";
            _pauseForThermal();
            effectiveTargetFps = 0;
            return;
        }

        if (service.thermalPaused &&
            (!thermalEnabled || metric.temperature < SettingsService.thermalCriticalC - 5)) {
            _resumeFromThermal();
        }

        adaptiveTargetFps = adaptiveEnabled ? _adaptiveFpsFor(metric.utilization) : 0;
        const target = _effectiveTarget();
        effectiveTargetFps = target;

        if (target > 0) {
            let reason = adaptiveEnabled ? "Adaptive FPS" : "Performance protection";
            if (PowerService.onBattery && batteryEnabled) {
                reason = PowerService.batteryPercent >= 0 &&
                    PowerService.batteryPercent <= SettingsService.lowBatteryThreshold
                    ? "Low battery protection"
                    : "Battery profile";
            } else if (thermal === "warning") {
                reason = "Thermal protection";
            }
            _applyTarget(target, reason);
            stateText = target + " FPS target";
        } else {
            // No runtime cap is needed. Restore the user's saved FPS if an
            // earlier controller override is still active.
            if (PlaybackService.performanceFpsOverride.length > 0 &&
                !PowerService.onBattery && thermal === "normal") {
                PlaybackService.clearPerformanceFpsOverride("Performance controller");
            }
            stateText = "User FPS";
        }
    }

    property Timer pollTimer: Timer {
        interval: 3000
        running: service.monitoringNeeded
        repeat: true
        triggeredOnStart: true
        onTriggered: service.evaluate()
    }

    onAdaptiveEnabledChanged: evaluate()
    onThermalEnabledChanged: evaluate()
    onBatteryEnabledChanged: evaluate()

    // Performance engine also owns the GPU-stats polling gate: live GPU
    // stats (gpu_manager.sh stats, 1s) are only needed while at least one
    // of this engine's three features is actually running. The old code set
    // GPUManagerService.statsActive = true unconditionally in
    // Component.onCompleted, which started a bash+jq process (plus a full
    // nvidia-smi invocation, on NVIDIA systems) every single second for the
    // ENTIRE lifetime of the shell session -- even when adaptive FPS,
    // thermal protection AND battery profiles were all OFF and the
    // Performance page had never been opened (<0.1% of that polling ever
    // got read). Now statsActive is only ever turned ON here (never off):
    // PerformancePage.qml owns the other half of the gate (true while the
    // System Resources card is visible, false when the page unloads), and
    // this service must not yank the flag out from under a visible page.
    // The one deliberate asymmetry -- we never switch statsActive back off
    // when monitoringNeeded goes false -- is what keeps the page's own
    // lifecycle fully authoritative over a shared flag.
    onMonitoringNeededChanged: {
        if (service.monitoringNeeded) {
            GPUManagerService.statsActive = true;
        }
    }

    Component.onCompleted: {
        if (service.monitoringNeeded) {
            GPUManagerService.statsActive = true;
        }
        evaluate();
    }
}
