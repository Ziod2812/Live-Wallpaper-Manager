pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

/*
 * GPUManagerService.qml
 * -------------------------
 * GPU SWITCHING FEATURE -- lets the user choose which physical GPU
 * mpvpaper renders the wallpaper with. This service ONLY affects
 * mpvpaper: it never touches system PRIME, udev, Xorg/Hyprland config,
 * or the compositor. The actual env-var scoping happens entirely in
 * scripts/gpu_manager.sh + utils.sh's lw_launch_mpvpaper() -- this file
 * is just the detection/selection/validation layer for the UI, same
 * "small script + Paths.script() call, parse JSON via StdioCollector"
 * shape SystemStatsService.qml already uses.
 *
 *   - gpus / systemType / hybrid / currentRenderer / currentApi:
 *     read-only snapshot from `gpu_manager.sh detect`, refreshed once on
 *     startup (GPU topology essentially never changes while the app is
 *     running) and on-demand via refreshDetection().
 *   - selectedMode: the persisted choice (SettingsService's "gpu_mode"
 *     key) -- Auto | Intel | AMD | NVIDIA | Power Saving |
 *     High Performance.
 *   - selectorVisible: true only when 2+ GPUs are detected -- there's
 *     something to actually switch between. Components/GpuSelector.qml
 *     now always renders (Performance > GPU card requirement); it uses
 *     this same "more than one GPU" condition itself to decide whether
 *     to show a live dropdown or a disabled "<label> (Only GPU Detected)"
 *     trigger, rather than hiding the control entirely.
 *   - setMode(mode): validates the mode is actually available BEFORE
 *     persisting it; an unavailable pick is refused up front (toast +
 *     no-op) rather than ever being written to settings.json.
 *   - If a PREVIOUSLY saved mode turns out to be unavailable (hardware
 *     removed, driver missing, ...) once detection completes, it's
 *     reset back to "auto" automatically and the user is notified --
 *     this is the "never crash wallpaper playback" fallback the GOAL
 *     asks for, enforced here in addition to gpu_manager.sh's own
 *     defensive "no override on failure to resolve" behavior.
 *   - A genuine change to selectedMode (not just settings.json finishing
 *     its initial load) asks PlaybackService to relaunch mpvpaper with
 *     the new environment and restore whatever wallpaper was already
 *     playing -- see PlaybackService.reapplyForGpuChange(), which is a
 *     new, purely-additive method; nothing about PlaybackService's
 *     existing API changes.
 *
 * SYSTEM RESOURCES (GPU) -- statsActive/gpuStats/statsFor() below back the
 * Performance page's real GPU monitoring (utilization/VRAM/temp), reusing
 * this same singleton and the same Process+StdioCollector+JSON.parse shape
 * as detectProc above rather than adding a second GPU service. Polls
 * `gpu_manager.sh stats` (sysfs + at most one batched nvidia-smi call, see
 * that script's header) every 1s, but ONLY while `statsActive` is true --
 * PerformancePage.qml gates this to its own lifecycle exactly like it
 * already does for SystemStatsService.active, so this costs nothing
 * whenever the Performance page isn't open. This is entirely additive:
 * gpus/selectedMode/setMode/etc. above are unchanged.
 */
QtObject {
    id: service

    readonly property var modes: ["auto", "intel", "amd", "nvidia", "power-saving", "high-performance"]

    property var gpus: []            // [{vendor,label,render_node,pci,driver,boot_vga}, ...]
    property string systemType: "unknown"
    property bool hybrid: false
    property string currentRenderer: ""
    property string currentApi: ""
    property bool detected: false

    // Nothing to switch between with 0 or 1 GPU -- the UI selector
    // hides itself entirely in that case (GOAL requirement).
    readonly property bool selectorVisible: gpus.length > 1

    readonly property var availableVendors: {
        const s = ({});
        for (const g of gpus) s[g.vendor] = true;
        return s;
    }

    // "auto" only needs the app to be running. "power-saving"/
    // "high-performance" need at least TWO gpus -- gpu_manager.sh's own
    // _lw_gpu_pick_role() explicitly returns nothing (env exits 3, "no
    // override") for both roles when count<=1, since there's nothing to
    // switch to/from on a single-GPU box (see gpu_manager.sh's own
    // comment on _lw_gpu_pick_role). This used to read `gpus.length > 0`,
    // which made both modes look "available" with exactly one GPU even
    // though gpu_manager.sh could never actually resolve an override for
    // them -- a previously-saved power-saving/high-performance mode would
    // then silently stop doing anything (falling back to "auto" behavior
    // at the script level) without ever tripping _validateSelection()'s
    // revert-to-Auto notification below. intel/amd/nvidia need that
    // specific vendor actually detected, same as before.
    function modeAvailable(mode) {
        if (mode === "auto") return true;
        if (mode === "power-saving" || mode === "high-performance") return gpus.length > 1;
        return !!availableVendors[mode];
    }

    readonly property string selectedMode: {
        const v = SettingsService.settings.gpu_mode;
        return (v && modes.indexOf(v) !== -1) ? v : "auto";
    }

    // setMode() is the ONLY way the UI should change gpu_mode -- it
    // gates every write through the same availability check used for
    // the automatic post-detection fallback below, so an unavailable
    // mode can never reach settings.json in the first place.
    function setMode(mode) {
        if (service.modes.indexOf(mode) === -1) return;
        if (!service.modeAvailable(mode)) {
            NotifyService.error("That GPU isn't available on this system -- staying on Auto.");
            if (SettingsService.settings.gpu_mode !== "auto") SettingsService.set("gpu_mode", "auto");
            return;
        }
        SettingsService.set("gpu_mode", mode);
    }

    function refreshDetection() {
        if (detectProc.running) return;
        detectProc.running = true;
    }

    property Process detectProc: Process {
        id: detectProc
        command: ["bash", Paths.script("gpu_manager.sh"), "detect"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text);
                    service.gpus = Array.isArray(r.gpus) ? r.gpus : [];
                    service.systemType = r.system_type || "unknown";
                    service.hybrid = !!r.hybrid;
                    service.currentRenderer = r.current_renderer || "";
                    service.currentApi = r.current_api || "";
                } catch (e) {
                    console.warn("GPUManagerService: failed to parse detect output:", e);
                    service.gpus = [];
                }
                service.detected = true;
                service._validateSelection();
            }
        }
    }

    // Post-detection safety net: a mode saved from a previous session
    // (or a previous GPU configuration) that's no longer available gets
    // reverted to Auto automatically, with a notification -- never left
    // sitting in settings.json pointing at hardware that isn't there.
    function _validateSelection() {
        const mode = service.selectedMode;
        if (mode !== "auto" && !service.modeAvailable(mode)) {
            NotifyService.error("Previously selected GPU (" + mode + ") is no longer available -- reverted to Auto.");
            SettingsService.set("gpu_mode", "auto");
        }
    }

    // ── Live GPU stats (utilization / VRAM / temperature) ──────────────
    // [{pci, vendor, utilization_pct, vram_used_mb, vram_total_mb, temp_c}, ...]
    // Any field the current GPU/vendor/driver doesn't expose comes back as
    // JSON null from gpu_manager.sh -- surfaced here as `undefined`/`null`
    // unchanged (no fabricated zeros), so the UI can show "Not available"
    // instead of a misleading "0%"/"0 MB".
    property bool statsActive: false
    property var gpuStats: []

    // statsFor(pci) -> the matching gpuStats entry, or null. GpuPanel
    // joins this against `gpus` (which has vendor/label/render_node) by
    // pci id so the UI never needs its own copy of that matching logic.
    function statsFor(pci) {
        for (const s of gpuStats) {
            if (s.pci === pci) return s;
        }
        return null;
    }

    function refreshStats() {
        if (statsProc.running) return;
        statsProc.running = true;
    }

    property Timer statsTimer: Timer {
        interval: 1000
        running: service.statsActive
        repeat: true
        triggeredOnStart: true
        onTriggered: service.refreshStats()
    }

    property Process statsProc: Process {
        id: statsProc
        command: ["bash", Paths.script("gpu_manager.sh"), "stats"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text);
                    service.gpuStats = Array.isArray(r.gpus) ? r.gpus : [];
                } catch (e) {
                    console.warn("GPUManagerService: failed to parse stats output:", e);
                }
            }
        }
    }

    onStatsActiveChanged: if (statsActive) refreshStats()

    Component.onCompleted: refreshDetection()

    // Guards against firing a relaunch for the very first evaluation of
    // selectedMode (settings.json finishing its initial async load) --
    // only a REAL change after that counts as "the user/validation logic
    // actually changed the mode".
    property bool _initialized: false
    onSelectedModeChanged: {
        if (!service._initialized) {
            service._initialized = true;
            return;
        }
        PlaybackService.reapplyForGpuChange();
    }
}
