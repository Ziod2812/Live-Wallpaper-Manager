import QtQuick
import Quickshell
import Quickshell.Wayland
import "../Config"
import "../Services"
import "../Components"

/*
 * PeaclockCavaDockOverlay.qml
 * -------------------------------
 * Standalone desktop overlay for the NEW, independent Peaclock + Cava
 * Dock -- same "own PanelWindow, own layer-shell surface" shape as
 * Panels/MusicDockOverlay.qml (which this pattern is deliberately
 * modeled on), but a wholly separate window/instance/settings namespace.
 * This is NOT the Music Dock, and Panels/MusicDockOverlay.qml is
 * completely untouched by this file's existence.
 *
 * INDEPENDENCE:
 *   - Visibility is gated purely by "pcdock_enabled" (+ its own
 *     auto-hide setting) -- never by music_dock_enabled, and never by
 *     LiveWallpaperPanel.visible.
 *   - Enabling/disabling this dock has zero effect on Music Dock, and
 *     vice versa -- the two overlays, their PanelWindows, and their
 *     settings keys ("pcdock_*" here vs "music_dock_*" there) never
 *     intersect.
 *   - Cava itself is still the ONE shared CavaService singleton/process
 *     pipeline (see CavaService.qml) -- reused, not duplicated, exactly
 *     per the preset's "reuse the existing Cava implementation"
 *     requirement. This overlay calls CavaService.start("peaclock")/
 *     stop("peaclock") from its own _syncBackends() below, registering
 *     under its own consumer id alongside Panels/MusicDockOverlay.qml's
 *     identical call under "musicdock" (see CavaService.qml's
 *     "Multi-consumer reference counting" header). CavaService only
 *     actually stops the shared cava/reader process once BOTH consumer
 *     ids have released it, so having both docks enabled at once never
 *     spawns a second cava/reader process pair, AND turning Cava off on
 *     one dock never stops it out from under the other dock that still
 *     wants it running.
 *
 * Owns its own lifecycle end-to-end:
 *   Enable  -> start cava (CavaService.start, if this dock's own Cava
 *              toggle is on) -> start the MPRIS listener (shared
 *              read-only singleton, same as Music Dock) -> this window
 *              becomes visible.
 *   Disable -> this window hides -> stop cava (subject to the shared-
 *              pipeline note above).
 * ApplicationService.exit() already stops CavaService/MprisService
 * globally (Services/ApplicationService.qml, unmodified), so this dock's
 * own processes are still cleanly torn down when the whole app closes,
 * exactly like Music Dock's.
 *
 * Placement: bottom-right corner by default, matching the compact
 * "Peaclock + Cava" reference layout -- anchored bottom + right, unlike
 * Music Dock's bottom + zero-left/right centering. Both the vertical
 * ("pcdock_position") and horizontal ("pcdock_cava_hposition") settings
 * are independently adjustable at runtime; either one repins this same
 * PanelWindow (and therefore the whole dock -- clock, date, LIVE
 * indicator, Cava strip, now-playing text, card background/border) to a
 * different edge/center of the target monitor -- see "Placement
 * (Visualizer Position + Visualizer horizontal position)" below.
 *
 * Layer choice: Bottom, same reasoning as Panels/MusicDockOverlay.qml
 * -- a passive, always-on overlay, not a summoned control surface.
 */
PanelWindow {
    id: overlay

    // ── Settings (guarded fallback, see PeaclockCavaDockPanel.qml's
    // header) -- own "pcdock_*" namespace throughout. ───────────────────
    readonly property bool enabled: SettingsService.settings.pcdock_enabled === true
    readonly property bool autoHide: SettingsService.settings.pcdock_autohide === true
    readonly property bool clickThrough: SettingsService.settings.pcdock_click_through === true
    readonly property int cfgWidth: {
        const v = parseInt(SettingsService.settings.pcdock_width, 10);
        return (v >= 220 && v <= 520) ? v : 300;
    }
    readonly property int cfgHeight: {
        const v = parseInt(SettingsService.settings.pcdock_height, 10);
        return (v >= 200 && v <= 520) ? v : 300;
    }
    readonly property string targetMonitorName: {
        const m = SettingsService.settings.pcdock_monitor;
        return (m && m !== "auto") ? m : MultiMonitorService.focusedMonitorName;
    }

    // ── Visualizer position (see PeaclockCavaDockPanel.qml's "Visualizer
    // position" row) -- "bottom" keeps the original bottom placement,
    // "top"/"center" repin the very same overlay via the layer-shell
    // anchors below. Same window, same PeaclockCavaDock instance, same
    // CavaService singleton the whole time -- only the vertical anchor
    // edge changes, never the content or the audio pipeline.
    readonly property string positionVal: {
        const p = SettingsService.settings.pcdock_position;
        return (p === "top" || p === "center") ? p : "bottom";
    }

    // ── Visualizer horizontal position (FIXED -- see CavaService.qml's
    // "pcVisualizerHPosition" header) -- moves the ENTIRE dock overlay
    // (clock + date + LIVE indicator + Cava strip + now-playing text +
    // card background/border, i.e. this whole PanelWindow) left/center/
    // right on the target monitor, exactly mirroring how positionVal
    // above repins it top/bottom/center. Previously this setting only
    // narrowed/shifted the Cava content *inside* PeaclockCavaDock.qml's
    // strip while the dock window itself stayed pinned to the right
    // edge -- see Components/PeaclockCavaDock.qml's cavaStrip, which no
    // longer reads this value. "right" is the default so an untouched
    // install keeps looking exactly like the original bottom-right dock.
    readonly property string hPositionVal: CavaService.pcVisualizerHPosition

    // "Multi-monitor aware": bind to a specific ShellScreen when the
    // setting names one (or the currently focused monitor for "auto");
    // falls back to the compositor's default screen when no match is
    // found yet -- same pattern as MusicDockOverlay.qml.
    screen: {
        for (const s of Quickshell.screens) {
            if (s.name === overlay.targetMonitorName) return s;
        }
        return null;
    }

    implicitWidth: overlay.cfgWidth
    implicitHeight: overlay.cfgHeight
    color: "transparent"
    focusable: !overlay.clickThrough
    exclusiveZone: 0 // floats over the desktop, never reserves space

    // Only ever visible while THIS dock is turned on -- independent of
    // Music Dock's own enabled state and of LiveWallpaperPanel.visible.
    // Auto-hide-when-idle additionally hides it whenever no MPRIS player
    // is currently active (same convention as Music Dock).
    visible: overlay.enabled && (!overlay.autoHide || MprisService.active)

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "livewallpaper-peaclockcavadock"

    // ── Placement (Visualizer Position + Visualizer horizontal
    // position) ──────────────────────────────────────────────────────
    // Same "fade out -> swap anchor/margin binding while invisible ->
    // fade back in" technique Panels/MusicDockOverlay.qml uses for its
    // own Visualizer position setting -- see that file's header for why
    // (wlr-layer-shell anchors are a compositor-owned edge, not a
    // tweenable QML x/y). Vertical and horizontal anchors are independent
    // of each other, so every Top/Center/Bottom x Left/Center/Right
    // combination is reachable:
    //
    //   Vertical (pcdock_position):
    //     bottom (default, unchanged): anchors.bottom + margins.bottom: 20
    //     top:                         anchors.top + margins.top: 20
    //     center:                      no vertical anchor at all
    //
    //   Horizontal (pcdock_cava_hposition -- FIXED, see CavaService.qml's
    //   "pcVisualizerHPosition" header; this used to only move the
    //   waveform inside the strip instead of the window):
    //     right (default, unchanged): anchors.right + margins.right: 20
    //     left:                       anchors.left + margins.left: 20
    //     center:                     no horizontal anchor at all
    //
    // "No anchor at all" on an axis is the same zero-anchor trick
    // MusicDockOverlay.qml uses -- the compositor centers on whichever
    // axis has no anchor.
    property string _appliedPosition: positionVal
    property string _appliedHPosition: hPositionVal
    anchors.top: overlay._appliedPosition === "top"
    anchors.bottom: overlay._appliedPosition === "bottom"
    anchors.left: overlay._appliedHPosition === "left"
    anchors.right: overlay._appliedHPosition === "right"
    margins.top: overlay._appliedPosition === "top" ? 20 : 0
    margins.bottom: overlay._appliedPosition === "bottom" ? 20 : 0
    margins.left: overlay._appliedHPosition === "left" ? 20 : 0
    margins.right: overlay._appliedHPosition === "right" ? 20 : 0

    // Empty Region = accepts no pointer input at all, i.e. every click
    // passes straight through to whatever is beneath the dock. Only
    // applied when this dock's own Click-through setting is on.
    mask: overlay.clickThrough ? clickThroughMask : null
    Region { id: clickThroughMask }

    Item {
        id: dockContent
        anchors.fill: parent
        opacity: 1

        PeaclockCavaDock {
            anchors.fill: parent
        }
    }

    // Fade out -> swap the anchor/margin binding while fully transparent
    // -> fade back in. 100ms + 100ms = 200ms total, same timing as
    // MusicDockOverlay.qml's identical crossfade. Only ever touches
    // `dockContent.opacity` -- CavaService, MprisService, and the overlay
    // window itself never restart, and there is still exactly one
    // PeaclockCavaDock/CavaService instance the whole time. Both the
    // vertical and horizontal position settings share this one animation
    // (and can change together, e.g. "Left" + "Top" applied at once) so
    // toggling either -- or both -- never restarts Cava/MPRIS/the window.
    onPositionValChanged: repositionAnim.restart()
    onHPositionValChanged: repositionAnim.restart()
    SequentialAnimation {
        id: repositionAnim
        NumberAnimation {
            target: dockContent; property: "opacity"
            to: 0; duration: 100; easing.type: Easing.OutQuad
        }
        ScriptAction {
            script: {
                overlay._appliedPosition = overlay.positionVal;
                overlay._appliedHPosition = overlay.hPositionVal;
            }
        }
        NumberAnimation {
            target: dockContent; property: "opacity"
            to: 1; duration: 100; easing.type: Easing.InQuad
        }
    }

    // ── Lifecycle ─────────────────────────────────────────────────────
    // Mirrors Panels/MusicDockOverlay.qml's own _syncBackends() exactly
    // (same shape, same two shared singletons) -- this is a second,
    // independent caller of the same reuse pattern, not shared state.
    // See this file's header for the one shared-pipeline limitation that
    // reuse implies for MprisService/CavaService when both docks are
    // enabled simultaneously.
    function _syncBackends() {
        if (overlay.enabled) {
            MprisService.start();
            if (SettingsService.settings.pcdock_cava_enabled !== false) {
                CavaService.start("peaclock");
            } else {
                CavaService.stop("peaclock");
            }
        } else {
            MprisService.stop();
            CavaService.stop("peaclock");
        }
    }

    Component.onCompleted: _syncBackends()

    Connections {
        target: SettingsService
        function onSettingsChanged() { overlay._syncBackends(); }
    }
}
