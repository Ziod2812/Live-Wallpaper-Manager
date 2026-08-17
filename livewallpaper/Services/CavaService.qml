pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../Config"

/*
 * CavaService.qml
 * ----------------------
 * Owns the real audio-visualizer pipeline for Music Dock:
 *
 *   PipeWire -> cava -> FIFO -> CavaService.qml -> MusicDock.qml
 *
 * cava (scripts/start_cava.sh) captures real audio via PipeWire's
 * pulse-compatible server and writes raw binary bar levels (one byte
 * 0-255 per bar) into a FIFO. scripts/_cava_reader.py is kept running as
 * a long-lived Process (same pattern as WatcherService's inotifywait
 * watcher) that blocks on that FIFO and prints one JSON array per frame
 * -- read here via SplitParser, i.e. asynchronous and event-driven, no
 * polling and no busy loop on the QML side either.
 *
 * enabled() / disable() are the two entry points Panels/MusicDockOverlay
 * calls from its own lifecycle (see that file's header) -- this service
 * never starts itself.
 *
 * Never crashes or blocks the dock if cava isn't installed: start()
 * degrades to available=false and a one-time notice, leaving `bars`
 * empty so MusicDock.qml simply hides the visualizer strip.
 *
 * ── Visualizer color system ──────────────────────────────────────────
 * `visualizerColor` is the single value MusicDock.qml's bar delegate
 * binds its `color` to. It never touches cava, the FIFO, or the reader
 * process -- purely a QML color computed from `colorMode` ("manual" |
 * "random" | "rainbow") plus whichever of manualColor/randomColor/
 * rainbowHue is active, so switching modes or nudging the rainbow speed
 * only ever repaints Rectangle.color bindings (no restart(), no process
 * relaunch). Living here rather than in MusicDockPanel.qml/MusicDock.qml
 * means every MusicDock instance (one per monitor, see
 * Panels/MusicDockOverlay.qml) reads the same singleton state -- multi-
 * monitor setups stay in sync for free, including the rainbow phase,
 * since there is exactly one rainbowTimer driving one rainbowHue no
 * matter how many docks are on screen.
 */
QtObject {
    id: service

    // ── Visualizer render style (PHASE 3) ──────────────────────────────
    // "bars" (the original Repeater-of-Rectangles look) or "waveform" (a
    // smooth Canvas polyline) -- both read the exact same `bars` frame
    // data above, so there is only ever one cava pipeline regardless of
    // which style is selected. See MusicDock.qml for the actual
    // rendering branch.
    readonly property string visualizerStyle: {
        const s = SettingsService.settings.music_dock_visualizer_style;
        return s === "waveform" ? "waveform" : "bars";
    }
    // Only meaningful when visualizerStyle === "waveform" -- a taller,
    // glow-layered variant that reads as "detached" from the dock's
    // body rather than a second window (see MusicDock.qml's header for
    // why this isn't a second overlay surface).
    readonly property bool floatingWaveform: SettingsService.settings.music_dock_floating_waveform === true

    property bool available: true   // false once start_cava.sh reports cava is missing
    property bool running: false    // true once real frames are flowing
    property var bars: []           // current frame: array of ints 0-255, length === barCount

    property int barCount: {
        const n = parseInt(SettingsService.settings.music_dock_bar_count, 10);
        // Accept any sane positive integer rather than an enumerated
        // whitelist -- MusicDockPanel.barCountOptions is the source of
        // truth for which values the UI offers; this just guards against
        // a missing/corrupt/non-numeric setting.
        return (Number.isInteger(n) && n > 0 && n <= 1024) ? n : 48;
    }
    readonly property int framerate: 60
    property int sensitivity: {
        const s = parseInt(SettingsService.settings.music_dock_sensitivity, 10);
        return (s >= 10 && s <= 300) ? s : 100;
    }

    // ── Visualizer color system (see header) ──────────────────────────
    // Exactly one mode is active at a time; MusicDock.qml only ever
    // reads `visualizerColor` below.
    readonly property string colorMode: {
        const m = SettingsService.settings.music_dock_color_mode;
        return (m === "random" || m === "rainbow") ? m : "manual";
    }

    // Mode 1 -- Manual. Same setting/picker MusicDockPanel.qml already
    // had (music_dock_accent) -- completely untouched, just re-exposed
    // here so visualizerColor has one place to branch from.
    readonly property color manualColor: {
        const c = SettingsService.settings.music_dock_accent;
        return (typeof c === "string" && c.length > 0) ? c : Theme.mauve;
    }

    // Mode 2 -- Random. The generated color is persisted (survives
    // restart) and stays in effect until generateRandomColor() is
    // called again, by the button or by one of the two optional
    // auto-randomize triggers below.
    readonly property color randomColor: {
        const c = SettingsService.settings.music_dock_random_color;
        return (typeof c === "string" && c.length > 0) ? c : manualColor;
    }
    readonly property bool randomizeOnWallpaperChange: SettingsService.settings.music_dock_random_on_wallpaper_change === true
    readonly property bool randomizeOnRestart: SettingsService.settings.music_dock_random_on_restart === true

    function generateRandomColor() {
        const r = Math.floor(Math.random() * 256);
        const g = Math.floor(Math.random() * 256);
        const b = Math.floor(Math.random() * 256);
        const hex = "#" + [r, g, b].map(v => v.toString(16).padStart(2, "0")).join("");
        SettingsService.set("music_dock_random_color", hex);
    }

    // Mode 3 -- Rainbow. Cycle duration is one of a fixed set of
    // presets (matches the segmented-button UI, same pattern as
    // barCountOptions); speed is a free 0.1x-5x multiplier.
    readonly property int rainbowCycleSeconds: {
        const allowed = [5, 10, 20, 30, 60];
        const v = parseInt(SettingsService.settings.music_dock_rainbow_cycle_seconds, 10);
        return allowed.includes(v) ? v : 20;
    }
    readonly property real rainbowSpeed: {
        const v = Number(SettingsService.settings.music_dock_rainbow_speed);
        return (v >= 0.1 && v <= 5.0) ? v : 1.0;
    }
    // 0..1 phase around the hue wheel, advanced by rainbowTimer below.
    // Not persisted -- restarting mid-cycle just resumes at hue 0,
    // which is inaudible/invisible as a "jump" since it's still a
    // single continuous color, not a discontinuity in an ongoing sweep.
    property real rainbowHue: 0

    // Constant saturation/value (brightness) -- only hue moves, so the
    // sweep never flashes or dims, matching the "constant brightness /
    // constant saturation" requirement.
    readonly property real rainbowSaturation: 0.85
    readonly property real rainbowValue: 1.0

    // The single color MusicDock.qml's bar delegate binds to.
    readonly property color visualizerColor: {
        if (colorMode === "random") return randomColor;
        if (colorMode === "rainbow") return Qt.hsva(rainbowHue, rainbowSaturation, rainbowValue, 1.0);
        return manualColor;
    }

    // ── Peaclock + Cava Dock: independent visualizer color system ─────────
    // Same three-mode (manual/random/rainbow) shape as the Music Dock color
    // system directly above, but reads its own "pcdock_cava_*" settings and
    // exposes its own computed color -- tuning either dock's visualizer
    // color NEVER affects the other's, and neither dock's setting is read
    // by the other. Both branches still read the exact same `bars` frame
    // data from the one shared cava pipeline (see this file's header);
    // only the *color* differs per dock. Rainbow mode intentionally shares
    // the single rainbowHue/rainbowTimer below rather than a second timer
    // -- a second, independently-phased sweep would just be visual noise,
    // not a meaningful feature, so both docks see the same continuously
    // advancing hue whenever either (or both) is in rainbow mode.
    readonly property string pcColorMode: {
        const m = SettingsService.settings.pcdock_cava_color_mode;
        return (m === "random" || m === "rainbow") ? m : "manual";
    }
    readonly property color pcManualColor: {
        const c = SettingsService.settings.pcdock_cava_accent;
        return (typeof c === "string" && c.length > 0) ? c : Theme.mauve;
    }
    readonly property color pcRandomColor: {
        const c = SettingsService.settings.pcdock_cava_random_color;
        return (typeof c === "string" && c.length > 0) ? c : pcManualColor;
    }
    function pcGenerateRandomColor() {
        const r = Math.floor(Math.random() * 256);
        const g = Math.floor(Math.random() * 256);
        const b = Math.floor(Math.random() * 256);
        const hex = "#" + [r, g, b].map(v => v.toString(16).padStart(2, "0")).join("");
        SettingsService.set("pcdock_cava_random_color", hex);
    }
    // The single color PeaclockCavaDock.qml's bar delegate binds to.
    readonly property color pcVisualizerColor: {
        if (pcColorMode === "random") return pcRandomColor;
        if (pcColorMode === "rainbow") return Qt.hsva(rainbowHue, rainbowSaturation, rainbowValue, 1.0);
        return pcManualColor;
    }

    // ── Peaclock + Cava Dock: dedicated Waveform Color ─────────────────
    // A second, independent color slot scoped ONLY to the "waveform"
    // render style (Components/PeaclockCavaVisualizer.qml's Canvas).
    // Picking/generating a waveform color here never writes
    // pcdock_cava_accent/pcdock_cava_random_color above, so the "bars"
    // render style -- and every other element (clock, date, LIVE label,
    // border, card, background, text, which all read pcdock_accent/Theme,
    // never these keys) -- stays completely unaffected. Reuses the SAME
    // mode switch (pcColorMode) and, in Rainbow mode, the SAME shared
    // rainbowHue/rainbowTimer -- still only one rainbow sweep in the app;
    // this just reads it into its own color output instead of adding a
    // second timer.
    readonly property color pcWaveformManualColor: {
        const c = SettingsService.settings.pcdock_cava_waveform_color;
        // Falls back to the dock's current effective color so the
        // waveform looks identical to today until the user explicitly
        // picks a dedicated waveform color ("Default: Current waveform
        // color" per spec).
        return (typeof c === "string" && c.length > 0) ? c : pcManualColor;
    }
    readonly property color pcWaveformRandomColor: {
        const c = SettingsService.settings.pcdock_cava_waveform_random_color;
        return (typeof c === "string" && c.length > 0) ? c : pcWaveformManualColor;
    }
    function pcGenerateWaveformRandomColor() {
        const r = Math.floor(Math.random() * 256);
        const g = Math.floor(Math.random() * 256);
        const b = Math.floor(Math.random() * 256);
        const hex = "#" + [r, g, b].map(v => v.toString(16).padStart(2, "0")).join("");
        SettingsService.set("pcdock_cava_waveform_random_color", hex);
    }
    // The single color Components/PeaclockCavaVisualizer.qml's waveform
    // Canvas binds to. The bars Repeater keeps reading pcVisualizerColor
    // above, completely untouched -- this only ever repaints the
    // waveform trace.
    readonly property color pcWaveformColor: {
        if (pcColorMode === "random") return pcWaveformRandomColor;
        if (pcColorMode === "rainbow") return Qt.hsva(rainbowHue, rainbowSaturation, rainbowValue, 1.0);
        return pcWaveformManualColor;
    }

    // ── Peaclock + Cava Dock: Random mode auto-randomize triggers ──────
    // Own "pcdock_cava_random_on_*" keys -- independent of Music Dock's
    // "music_dock_random_on_*" equivalents above, same shape/behavior:
    // optionally roll a fresh pcRandomColor on every wallpaper change
    // and/or once per app session on restart. Wired below alongside the
    // existing Music Dock triggers (_maybeRandomizeOnRestart /
    // _wallpaperChangeConn) so both docks' Random modes are handled by
    // the same one-shot/one-listener machinery instead of a second copy.
    readonly property bool pcRandomizeOnWallpaperChange: SettingsService.settings.pcdock_cava_random_on_wallpaper_change === true
    readonly property bool pcRandomizeOnRestart: SettingsService.settings.pcdock_cava_random_on_restart === true

    // ── Peaclock + Cava Dock: visualizer render style (Noctalia-style
    // renderer integration) ────────────────────────────────────────────
    // Own "pcdock_cava_visualizer_style" key -- completely independent of
    // Music Dock's "music_dock_visualizer_style" above. Both styles below
    // read the exact same `bars` frame data from the one shared cava
    // pipeline; only the PeaclockCavaDock.qml rendering branch differs.
    // "bars"     -- compact rounded-cap spectrum bars (Noctalia
    //               audio_visualizer look), bottom-anchored in the
    //               existing CAVA strip.
    // "waveform" -- smooth mirrored oscilloscope line (Noctalia
    //               fancy_audio_visualizer "wave" mode), filled area
    //               centered in the existing CAVA strip.
    // "line"     -- thin stroked zigzag trace (ECG/pulse-monitor look),
    //               unfilled, alternating above/below the strip's center
    //               baseline -- see Components/PeaclockCavaVisualizer.
    //               qml's lineCanvas for the render.
    // No second Cava process, no new color mode, no Accent color -- see
    // Components/PeaclockCavaVisualizer.qml.
    readonly property string pcVisualizerStyle: {
        const s = SettingsService.settings.pcdock_cava_visualizer_style;
        return (s === "waveform" || s === "line") ? s : "bars";
    }

    // ── Peaclock + Cava Dock: waveform sensitivity ─────────────────────
    // A pure client-side amplitude multiplier for Components/
    // PeaclockCavaVisualizer.qml's bars/waveform rendering -- it never
    // touches cava, cava.conf, or start_cava.sh's own `sensitivity` arg
    // (that's a *capture-gain* setting baked into the running cava
    // process, shared with Music Dock -- changing it would restart cava
    // and would also affect Music Dock's bars, which this must never do).
    // This is a separate, purely visual scale applied only when painting
    // this dock's own strip, on top of the exact same real `bars` frame
    // data everything else reads. 128 is the default so the strip looks
    // identical to before this setting existed unless the user changes
    // it; own "pcdock_cava_sensitivity" key, independent of Music Dock.
    readonly property int pcSensitivity: {
        const allowed = [32, 64, 128, 256];
        const v = parseInt(SettingsService.settings.pcdock_cava_sensitivity, 10);
        return allowed.includes(v) ? v : 128;
    }
    // Gain applied to the normalized (0..1) level before the smooth
    // saturation response curve in PeaclockCavaVisualizer.qml (see that
    // file's header) -- 10.0x at the 128 default (the ~10x stronger/more
    // reactive waveform requested), scaling proportionally with the
    // picked value: 32->2.5x, 64->5x, 128->10x, 256->20x. The old
    // "1.0x at default" baseline is now folded into this constant rather
    // than left at 1x, since a hard-clamped linear 10x alone would pin
    // to max on almost any real music -- the response curve downstream
    // is what keeps that from clipping constantly while still hitting
    // visibly stronger, clearly-differentiated peaks on kicks/beats.
    readonly property real pcSensitivityGain: (pcSensitivity / 128.0) * 10.0

    // ── Peaclock + Cava Dock: visualizer horizontal position ───────────
    // Layout setting consumed by Panels/PeaclockCavaDockOverlay.qml,
    // where it repins the ENTIRE dock overlay window (clock, date, LIVE
    // indicator, Cava strip, now-playing text, card background/border --
    // the whole PanelWindow) left/center/right on its target monitor,
    // exactly mirroring how "pcdock_position" below repins it top/
    // bottom/center. It never touches CavaService.bars, the cava
    // process/config, or how Components/PeaclockCavaVisualizer.qml turns
    // a frame into pixels -- same data, same rendering math, the whole
    // card is simply moved as one unit. Own "pcdock_cava_hposition" key,
    // independent of Music Dock (which has no equivalent control).
    //
    // Fixed: this used to only shift the Cava content *inside* the strip
    // (Components/PeaclockCavaDock.qml's cavaStrip), leaving the dock
    // window itself pinned to the screen's right edge -- so "Left" never
    // actually moved the clock/date/card, only the waveform inside it.
    // cavaStrip no longer reads this value; the whole card now moves.
    //
    // "right" is the default (not "center") specifically so an install
    // that has never touched this setting keeps the exact original
    // bottom-right dock placement -- see this file's header on
    // "Placement: bottom-right corner" in PeaclockCavaDockOverlay.qml.
    readonly property string pcVisualizerHPosition: {
        const p = SettingsService.settings.pcdock_cava_hposition;
        return (p === "left" || p === "center") ? p : "right";
    }

    // 60fps, timer-based (not a NumberAnimation loop) so the step size
    // is always frame-interval / cycle-length regardless of how long
    // the timer's been running -- changing rainbowCycleSeconds or
    // rainbowSpeed mid-sweep just changes the rate going forward, it
    // never re-bases or snaps the current hue. Runs whenever EITHER
    // dock's color mode is "rainbow" (see pcColorMode above), so idle
    // CPU cost is still zero unless at least one dock actually needs it.
    property Timer rainbowTimer: Timer {
        interval: 16 // ~60fps
        repeat: true
        running: service.colorMode === "rainbow" || service.pcColorMode === "rainbow"
        onTriggered: {
            const cycleMs = service.rainbowCycleSeconds * 1000;
            const step = (interval / cycleMs) * service.rainbowSpeed;
            service.rainbowHue = (service.rainbowHue + step) % 1.0;
        }
    }

    // Fires once per app session: if the user landed in Random mode
    // with "randomize every app restart" on, roll a fresh color as
    // soon as settings.json has actually loaded (colorMode reads the
    // property-var default of "manual" until then, so this only fires
    // after the real value -- if it's "random" -- comes in).
    property bool _restartRandomizeDone: false
    property bool _pcRestartRandomizeDone: false
    function _maybeRandomizeOnRestart() {
        if (!_restartRandomizeDone && colorMode === "random" && randomizeOnRestart) {
            _restartRandomizeDone = true;
            generateRandomColor();
        }
        if (!_pcRestartRandomizeDone && pcColorMode === "random" && pcRandomizeOnRestart) {
            _pcRestartRandomizeDone = true;
            pcGenerateRandomColor();
            pcGenerateWaveformRandomColor();
        }
    }
    Component.onCompleted: _maybeRandomizeOnRestart()
    property Connections _settingsLoadedConn: Connections {
        target: SettingsService.settingsView
        function onLoaded() { service._maybeRandomizeOnRestart(); }
    }

    // Optional auto-randomize on every wallpaper change, driven off
    // PlaybackService's own currentPath (set exactly once per applied
    // wallpaper by apply()/next()/previous()/random() -- see that
    // service). Skips the empty startup value so this doesn't double up
    // with the restart trigger above on a completely fresh session.
    property Connections _wallpaperChangeConn: Connections {
        target: PlaybackService
        function onCurrentPathChanged() {
            if (!PlaybackService.currentPath) return;
            if (service.colorMode === "random" && service.randomizeOnWallpaperChange) {
                service.generateRandomColor();
            }
            if (service.pcColorMode === "random" && service.pcRandomizeOnWallpaperChange) {
                service.pcGenerateRandomColor();
                service.pcGenerateWaveformRandomColor();
            }
        }
    }

    // Set by _startProcess()/_stopProcess() -- tracks whether the pipeline
    // currently WANTS to be running, so an unexpected reader/cava exit can
    // distinguish "the user turned this off" (do nothing) from "it crashed
    // while still wanted" (retry once, short backoff).
    property bool _wantRunning: false

    // ── Multi-consumer reference counting ────────────────────────────────
    // Both Panels/MusicDockOverlay.qml and Panels/PeaclockCavaDockOverlay.qml
    // call start()/stop() on this one shared singleton from their own,
    // independent _syncBackends() -- and the two docks are independently
    // enable-able (Pages/VisualizerPage.qml's preset switcher no longer
    // forces them to be mutually exclusive), so both can legitimately want
    // Cava running AT THE SAME TIME.
    //
    // Each caller identifies itself with a stable consumer id ("musicdock",
    // "peaclock") when it starts/stops. `_consumers` is the set of ids that
    // currently want Cava running. The real pipeline only ever stops once
    // that set is empty -- so one dock turning its Cava off while the other
    // still wants it leaves the shared cava/reader process running
    // untouched. Calling stop() with no id (app exit, see
    // ApplicationService.qml) is an unconditional full stop regardless of
    // who else asked for Cava.
    property var _consumers: ({})
    readonly property bool _hasConsumers: Object.keys(service._consumers).length > 0

    // ── Start/stop process serialization ─────────────────────────────────
    // stop() and start() each hand off to an ASYNC shell script
    // (stop_cava.sh / start_cava.sh) that manages the real cava process and
    // its FIFO -- stop_cava.sh kills the pid and `pkill -x cava`s and
    // removes the FIFO; start_cava.sh recreates the FIFO and launches a new
    // cava. Dispatching both scripts concurrently is a real race: start_
    // cava.sh's fresh cava can be killed by stop_cava.sh's `pkill -x cava`,
    // or its brand-new FIFO can be `rm -f`'d by stop_cava.sh's cleanup --
    // either way a consumer ends up with a dead/never-started cava
    // pipeline while looking "enabled".
    //
    // Fix: never let starterProc and stopperProc run at the same time.
    // _startProcess()/_stopProcess() below defer to the *other* process's
    // onExited when one is already in flight, instead of dispatching
    // immediately -- so a stop()-then-start() pair (regardless of which
    // consumer called which, or how quickly) always fully tears down
    // before it launches, and a start()-then-stop() pair always finishes
    // launching before it tears down. Neither script is ever invoked twice
    // concurrently, so there is still exactly one cava process/FIFO no
    // matter how many consumers reference this singleton.
    property bool _startPending: false // start requested while stopperProc was tearing down
    property bool _stopPending: false  // stop requested while starterProc was launching

    // Public entry point -- registers `consumerId` as wanting Cava running
    // (if given) and ensures the pipeline is actually up. Idempotent: a
    // consumer that's already registered, or a pipeline that's already
    // running/launching, is a no-op.
    function start(consumerId) {
        if (consumerId !== undefined) service._consumers[consumerId] = true;
        service._startProcess();
    }

    // Public entry point -- releases `consumerId`'s claim on Cava (if
    // given). The pipeline only actually tears down once no consumer still
    // needs it. Called with no argument, it's an unconditional stop (used
    // by ApplicationService.exit()) that clears every consumer.
    function stop(consumerId) {
        if (consumerId !== undefined) {
            service._consumers = Object.assign({}, service._consumers);
            delete service._consumers[consumerId];
            if (service._hasConsumers) return; // another consumer still needs Cava running
        } else {
            service._consumers = {};
        }
        service._stopProcess();
    }

    // Actual process-level start. Shared by start() above and restart()
    // below -- deliberately never touches `_consumers`: reconfiguring an
    // already-running pipeline (restart(), or the crash-retry path in
    // readerProc.onExited) is not a change of *intent*, so it must never
    // look like some other consumer released Cava.
    function _startProcess() {
        _wantRunning = true;
        // Cancel any teardown that was queued to fire once the current
        // launch finishes (see _stopProcess()) -- we now want to stay
        // running, so starterProc.onExited below must not tear us back
        // down again.
        _stopPending = false;
        if (!available) return; // already known missing this session -- don't spam launches
        if (stopperProc.running) {
            // A teardown (possibly kicked off by a *different* consumer,
            // e.g. the dock being turned off) is still tearing down the
            // FIFO/process. Launching now would race it. Defer --
            // stopperProc.onExited re-checks _startPending once the
            // teardown has actually finished and calls us again.
            _startPending = true;
            return;
        }
        _startPending = false;
        if (starterProc.running || readerProc.running) return;
        starterProc.command = ["bash", Paths.script("start_cava.sh"),
            Paths.cavaFifoFile, Paths.cavaConfFile,
            String(barCount), String(framerate), String(sensitivity)];
        starterProc.running = true;
    }

    // Actual process-level stop. Shared by stop() above (once every
    // consumer has released Cava) and restart() below. See _startProcess()
    // for why this never touches `_consumers`.
    function _stopProcess() {
        _wantRunning = false;
        _startPending = false;
        _restartTimer.stop();
        if (readerProc.running) readerProc.running = false;
        running = false;
        bars = [];
        if (starterProc.running) {
            // A launch is still in flight (possibly kicked off by a
            // *different* consumer). Tearing down now would race it --
            // defer to starterProc.onExited, which re-checks _stopPending
            // once the launch has actually finished.
            _stopPending = true;
            return;
        }
        _stopPending = false;
        if (stopperProc.running) return; // teardown already dispatched/in flight
        stopperProc.command = ["bash", Paths.script("stop_cava.sh"), Paths.cavaFifoFile];
        stopperProc.running = true;
    }

    // Called by MusicDockPanel when bar count/sensitivity settings change
    // while the dock is already running -- cava's own bar count is fixed
    // at launch (it's a config value), so a live change needs a clean
    // stop+relaunch, same "teardown then redispatch" pattern PlaybackService
    // uses for streaming quality/loop/mute changes. This never registers or
    // releases a consumer -- it's a reconfigure, not an enable/disable, so
    // it must not stop Cava for a *different* consumer that's still using
    // it (e.g. Peaclock + Cava dock) while Music Dock's bar count changes.
    function restart() {
        if (!_wantRunning) return;
        _stopProcess();
        _wantRunning = true; // _stopProcess() above clears this; restore the intent
        _restartTimer.restart();
    }

    property Timer _restartTimer: Timer {
        interval: 300
        onTriggered: if (service._wantRunning) service._startProcess()
    }

    property Process starterProc: Process {
        id: starterProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "MISSING_DEPENDENCY") {
                    service.available = false;
                    service.running = false;
                    // Music Dock runs independently of the main panel
                    // (see MusicDockOverlay.qml), so this can fire while
                    // the panel -- and therefore Toast.qml -- isn't even
                    // visible; mirror to a desktop notification too.
                    NotifyService.info("Music Dock's visualizer needs 'cava' installed (PipeWire audio capture) -- the dock still works without it.");
                    NotifyService.desktop("Music Dock: install 'cava' to enable the audio visualizer.", false);
                }
            }
        }
        onExited: (code, status) => {
            if (code === 0 && service.available && service._wantRunning) {
                readerProc.command = ["python3", Paths.script("_cava_reader.py"),
                    Paths.cavaFifoFile, String(service.barCount)];
                readerProc.running = true;
            }
            // The launch this process represented has now fully finished
            // one way or another -- if a stop was queued while we were
            // launching (from this or another consumer), it's safe to tear
            // down for real now.
            if (service._stopPending) {
                service._stopPending = false;
                service._stopProcess();
            }
        }
    }

    property Process readerProc: Process {
        id: readerProc
        stdout: SplitParser {
            onRead: (line) => {
                if (!line) return;
                try {
                    const frame = JSON.parse(line);
                    if (Array.isArray(frame)) {
                        service.bars = frame;
                        service.running = true;
                    }
                } catch (e) {
                    // malformed frame -- drop it, next one will self-correct
                }
            }
        }
        onExited: (code, status) => {
            service.running = false;
            // cava/reader died while the dock still wants visualization
            // (crash, PipeWire hiccup, audio device change) -- retry once
            // after a short delay rather than leaving the strip dead for
            // the rest of the session.
            if (service._wantRunning && service.available) {
                service._restartTimer.restart();
            }
        }
    }

    property Process stopperProc: Process {
        id: stopperProc
        onExited: (code, status) => {
            // The teardown this process represented has now fully finished
            // -- if a start was queued while we were tearing down (from
            // this or another consumer), it's safe to launch for real now.
            if (service._startPending) {
                service._startPending = false;
                service._startProcess();
            }
        }
    }
}
