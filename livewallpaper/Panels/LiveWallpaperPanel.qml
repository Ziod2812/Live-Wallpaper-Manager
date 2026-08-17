import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../Config"
import "../Services"
import "../Components"

/*
 * LiveWallpaperPanel.qml
 * -------------------------
 * PHASE 2 -- Move Configuration UI: this panel is now a compact,
 * always-quick control surface only. Every configuration page
 * (Wallpaper/Streaming/Web browsing + mode switching, Playlist, Music
 * Dock + Visualizer and Smart Playback performance tuning, per-
 * monitor target selection, and the wallpaper-directory/cache/exit
 * "General" settings) has moved into the Manager app (see
 * Manager/ManagerWindow.qml + Pages/) and is NOT duplicated here.
 *
 * What's left, matching the Phase 2 spec exactly:
 *   Play / Pause / Next / Previous / Random  -> PlaybackControls.qml
 *   Current wallpaper                        -> CurrentBar.qml
 *   Current song                             -> CurrentSongBar.qml
 *   Open Manager                              -> MiniTitleBar.qml's button
 *
 * Every one of those reuses the exact same PlaybackService/MprisService
 * singletons the removed pages/panel used before -- no service was
 * touched, rewritten, or duplicated to make this simplification.
 *
 * appMode / requestModeChange() (the Wallpapers/Streaming/Web mode
 * switch + its "stop whatever's playing before switching tabs" guard)
 * MOVED to Pages/WallpapersPage.qml verbatim -- it's not needed here
 * since this panel no longer hosts ModeSwitcher/ModeContentArea at all.
 */
PanelWindow {
    id: panel

    implicitWidth: 820
    implicitHeight: 280
    color: "transparent"
    visible: false
    focusable: true
    exclusiveZone: 0

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.namespace: "livewallpaper"

    // No anchors -> the compositor centers a layer-shell surface with no
    // edge anchored, matching the old `:anchor "center"` geometry.

    // Whether this panel owns the whole Quickshell process it's running
    // in. When true, "Exit Application" (now on the Manager app's
    // Settings page) also quits the Qt application after closing this
    // panel's own windows -- appropriate for the dedicated
    // `quickshell -c livewallpaper` entry point (see shell.qml, which
    // sets this explicitly). Defaults to false so that embedding this
    // panel inside a larger shell (see CAELESTIA_INTEGRATION.md) never
    // accidentally terminates windows/modules this app doesn't own.
    property bool standalone: false

    // Read-only mirror of shell.qml's `triggerDockVisible` (the single
    // shared source of truth for whether TriggerDock/"LW" is showing),
    // fed in live at the shell.qml call site below. Exists only so
    // MiniTitleBar's ▼ button can paint its current on/off state -- see
    // MiniTitleBar.qml's own `triggerDockActive`. This panel never writes
    // to it itself; toggleTriggerDockRequested() below is how it asks
    // shell.qml to flip the real flag.
    property bool triggerDockVisible: false

    signal openManagerRequested()
    // ▼ button (MiniTitleBar) asking shell.qml to flip TriggerDock's
    // visibility. Deliberately just a relay -- this panel has no
    // reference to TriggerDock or to shell.qml's shared flag, so it
    // can't and doesn't touch either directly (same pattern as
    // openManagerRequested() above, which relays to managerWindow the
    // same way).
    signal toggleTriggerDockRequested()

    function open() {
        visible = true;
    }
    function close() {
        visible = false;
    }
    function toggle() {
        visible = !visible;
    }
    // NOTE: TriggerDock's shown/hidden state used to be derived here as
    // the exact inverse of this panel's own `visible` (`visible:
    // !liveWallpaperPanel.visible` in shell.qml) -- i.e. the dock only
    // ever appeared once the panel was hidden, and the ▼ button hid the
    // panel to "show" it. That coupled two conceptually independent
    // things (this panel's own visibility, and whether the corner "LW"
    // shortcut is showing) through one flag, which is exactly why ▼
    // could only ever fire once: hiding the panel also hid the button
    // that was supposed to let you toggle again. TriggerDock's visibility
    // is now its own, single, independently-owned piece of state --
    // shell.qml's `triggerDockVisible` -- toggled purely by ▼ via
    // toggleTriggerDockRequested() above, and never derived from or tied
    // to `panel.visible` in any direction.

    // Exposes: quickshell -c <config> ipc call livewallpaper toggle|open|close
    // This is what the .desktop entry and any Hyprland keybind use instead
    // of the old `eww open --toggle wallpaper-manager`.
    IpcHandler {
        target: "livewallpaper"

        function toggle(): void { panel.toggle(); }
        function open(): void { panel.open(); }
        function close(): void { panel.close(); }
        function isOpen(): bool { return panel.visible; }

        // PHASE 4 -- exposed for the system tray helper (scripts/_tray_icon.py)
        // and any external keybind/script that wants playback control
        // without needing the panel open. Same PlaybackService/
        // ApplicationService calls PlaybackControls.qml's buttons and
        // DirPanel's Exit button already make -- no new logic.
        function togglePlayback(): void { PlaybackService.toggle(); }
        function next(): void { PlaybackService.next(); }
        function previous(): void { PlaybackService.previous(); }
        function random(): void { PlaybackService.random(); }
        function exitApplication(): void { ApplicationService.exit(); }
        // PHASE 4 -- system tray "Restart". See ApplicationService.restart()
        // for the teardown.
        //
        // BUGFIX (Restart closes the app but it doesn't come back): start
        // the relaunch watchdog (scripts/restart_app.sh) NOW, in parallel
        // with the teardown below, instead of waiting for readyToClose() to
        // fire and launching the new instance directly from inside this
        // process right before Qt.quit(). That old approach raced this
        // process's own shutdown -- Qt.quit() only schedules the event loop
        // to stop, so a replacement launched immediately afterward could
        // still find the old instance's single-instance IPC lock held and
        // fail to actually take over. restart_app.sh runs as a child of
        // THIS process (reads our pid via $PPID) and polls /proc until we
        // have genuinely exited before it launches the replacement,
        // removing that race.
        //
        // RELIABILITY FIX (restart "sometimes" doesn't come back):
        // restart_app.sh needs to stay alive for the ENTIRE
        // wait-for-old-pid-to-exit + launch-and-verify sequence -- which
        // spans the exact window in which this Quickshell process is
        // tearing itself down and calling Qt.quit(). It used to be started
        // as a plain `Process { command: [...] }` (see relaunchProc,
        // removed). Quickshell's own docs are explicit that a Process
        // started that way "will be killed when quickshell dies" --
        // exactly the moment restart_app.sh most needs to survive. That
        // race is timing-dependent: if teardown happened to finish before
        // restart_app.sh reached its `setsid quickshell -c livewallpaper &`
        // line, Quickshell going down took the watchdog with it and the new
        // instance was never launched -- "restart closes the app but it
        // doesn't reliably come back", exactly as reported. The fix:
        // never use a plain Process for anything that must outlive this
        // instance -- use Quickshell.execDetached() (== the C++-level
        // Process.startDetached(), which Quickshell's docs call out
        // specifically to "prevent the process from being killed by
        // Quickshell if Quickshell is killed") instead. execDetached()
        // still spawns restart_app.sh as a normal OS child of this process
        // (so $PPID inside the script is still captured correctly, read
        // once at the top of the script before we start tearing down), but
        // Quickshell no longer owns or kills it, so it keeps running
        // through and past this process's own exit no matter how the two
        // are timed.
        function restartApplication(): void {
            // System Tray owns the detached restart watchdog. The panel only
            // performs the normal teardown; the tray helper waits for this
            // process to exit before launching the replacement.
            ApplicationService.restart();
        }
    }

    onVisibleChanged: {
        if (visible) reopenAnim.restart();
    }

    // Fired once ApplicationService.exit() has confirmed playback is
    // actually stopped and settings are flushed (see ApplicationService
    // for what "ready" means). Closing windows here rather than
    // immediately on the Exit button click is what prevents mpvpaper/the
    // kiosk browser from being left running behind a closed panel.
    // (Manager/ManagerWindow.qml has its own matching Connections block
    // to close itself too -- see that file.)
    Connections {
        target: ApplicationService
        function onReadyToClose() {
            panel.close();       // hides this PanelWindow only --
                                  // TriggerDock's visibility is
                                  // independent now and is untouched by
                                  // this (see shell.qml's
                                  // triggerDockVisible)
            if (panel.standalone) {
                // PHASE 4 -- system tray "Restart". If this readyToClose()
                // was triggered by a restart (ApplicationService.
                // restarting), restart_app.sh was already started (via
                // Quickshell.execDetached(), immune to this process's own
                // teardown -- see restartApplication()'s comment) back in
                // the IpcHandler's restartApplication() above -- it's
                // independently polling /proc for this process's pid to
                // disappear, so nothing more to do here beyond quitting.
                // See that function's comment for why the watchdog is
                // started early instead of here.
                Qt.quit();
            }
        }
    }

    // See restartApplication() above and scripts/restart_app.sh's own
    // header for the full picture. Launched via Quickshell.execDetached()
    // (not a Process {} item -- see restartApplication()'s comment for
    // why) immediately when Restart is requested, so it can begin waiting
    // for this process's actual exit as early as possible. Fire-and-forget
    // from this process's point of view -- its own exit code/output
    // doesn't matter since this Qt process has already quit by the time
    // restart_app.sh finishes; the outcome is written to livewallpaper.log
    // instead (see the script) so a failed restart is still diagnosable.

    Component.onCompleted: depCheckProc.running = true

    Process {
        id: depCheckProc
        command: ["bash", "-c",
            "for b in mpvpaper ffmpeg ffprobe jq hyprctl inotifywait notify-send; do command -v \"$b\" >/dev/null 2>&1 || echo \"$b\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const missing = text.trim().split("\n").filter(l => l.length > 0);
                // hyprctl/inotifywait/notify-send degrade gracefully (already
                // handled elsewhere: watcher self-disables, monitor detection
                // falls back to $MONITOR/eDP-1, notify-send calls are just
                // skipped) -- only call out the ones that actually break core
                // playback if missing, so this doesn't cry wolf on setups
                // that simply don't use Hyprland-specific tooling.
                const critical = missing.filter(b => ["mpvpaper", "ffmpeg", "ffprobe", "jq"].includes(b));
                const optional = missing.filter(b => !critical.includes(b));
                if (critical.length > 0) {
                    NotifyService.error("Missing required tools: " + critical.join(", ") + " — install them for Live Wallpaper Manager to work.");
                } else if (optional.length > 0) {
                    NotifyService.info("Optional tools not found: " + optional.join(", ") + " — some features (auto-refresh, monitor detection, or notifications) will be limited.");
                }
            }
        }
    }

    // -------------------- MICA/ACRYLIC SURFACE --------------------
    Rectangle {
        id: surface
        anchors.fill: parent
        radius: Theme.radiusXl
        color: Theme.panelBg
        border.width: 1
        border.color: Theme.panelBorder

        // Entrance animation played every time the panel is shown again,
        // consistent with Caelestia's panel-open motion (fast, slightly
        // overshooting scale-up + fade).
        scale: 0.96
        opacity: 0
        Component.onCompleted: { scale = 1.0; opacity = 1.0; }

        SequentialAnimation {
            id: reopenAnim
            ParallelAnimation {
                NumberAnimation { target: surface; property: "scale"; from: 0.97; to: 1.0; duration: Theme.durationNormal; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                NumberAnimation { target: surface; property: "opacity"; from: 0.0; to: 1.0; duration: Theme.durationNormal }
            }
        }

        Behavior on radius { NumberAnimation { duration: Theme.durationFast } }

        // Drop shadow substitute (Quickshell/QtQuick has no native
        // DropShadow without Qt5Compat.GraphicalEffects; a soft duplicated
        // rect behind gives a comparable Mica elevation look without the
        // extra module dependency).
        Rectangle {
            anchors.fill: parent
            anchors.margins: -6
            z: -1
            radius: parent.radius + 6
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.35)
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacingXl
            spacing: Theme.spacingLg

            MiniTitleBar {
                Layout.fillWidth: true
                onCloseRequested: panel.close()
                // Live read-only feed for the ▼ button's toggle-switch
                // look -- see `triggerDockVisible`'s comment above.
                triggerDockActive: panel.triggerDockVisible
                // ▼ button: purely relays "flip TriggerDock" up to
                // shell.qml. This panel is intentionally left open the
                // whole time -- see `toggleTriggerDockRequested` above --
                // so MiniTitleBar (and this ▼ button) never disappears
                // and can be clicked again and again: Show, Hide, Show,
                // Hide, forever, with the panel, the Manager window, and
                // playback all untouched by every click.
                onToggleTriggerDockRequested: panel.toggleTriggerDockRequested()
                onOpenManagerRequested: panel.openManagerRequested()
            }

            Toast {
                Layout.fillWidth: true
            }

            CurrentBar {
                Layout.fillWidth: true
            }

            CurrentSongBar {
                Layout.fillWidth: true
            }

            Item { Layout.fillHeight: true }

            PlaybackControls {
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }

    // PHASE 4 -- keyboard shortcuts. Only active while the panel actually
    // has keyboard focus (WlrKeyboardFocus.OnDemand above), so these never
    // steal keystrokes meant for whatever else is focused on the desktop.
    Shortcut { sequence: "Space";  onActivated: PlaybackService.toggle() }
    Shortcut { sequence: "Left";   onActivated: PlaybackService.previous() }
    Shortcut { sequence: "Right";  onActivated: PlaybackService.next() }
    Shortcut { sequence: "R";      onActivated: PlaybackService.random() }
    Shortcut { sequence: "Escape"; onActivated: panel.close() }
}
