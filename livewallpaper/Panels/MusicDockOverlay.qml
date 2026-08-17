import QtQuick
import Quickshell
import Quickshell.Wayland
import "../Config"
import "../Services"
import "../Components"

/*
 * MusicDockOverlay.qml
 * ------------------------
 * Standalone desktop overlay for Music Dock -- same "own PanelWindow,
 * own layer-shell surface" shape as Panels/TriggerDock.qml, NOT a child
 * of LiveWallpaperPanel. This is what makes it survive the main panel
 * being closed: this window's `visible` only depends on the
 * "music_dock_enabled" setting (+ auto-hide), never on
 * LiveWallpaperPanel.visible.
 *
 * Owns the Music Dock lifecycle end-to-end:
 *   Enable  -> start cava (CavaService.start)
 *           -> start the MPRIS listener (MprisService.start)
 *           -> this window becomes visible (the "overlay" itself)
 *   Disable -> this window hides
 *           -> stop MPRIS listener, stop cava
 * ApplicationService.exit() already tears down PlaybackService's
 * mpvpaper/browser session; CavaService.stop()/MprisService.stop() are
 * called directly from that same exit() sequence (Services/
 * ApplicationService.qml) so Music Dock's own background processes are
 * cleanly terminated too when the whole app closes.
 *
 * Placement: anchored to the BOTTOM only (no left/right anchor), which
 * -- same convention LiveWallpaperPanel relies on for full centering
 * with zero anchors -- makes the compositor center the surface
 * horizontally while pinning it to the bottom edge, matching the design
 * reference exactly.
 *
 * NOTE: the "Peaclock + Cava" preset lives in its own, fully independent
 * overlay -- see Panels/PeaclockCavaDockOverlay.qml -- not as a layout
 * option here. This file's content, settings keys, and lifecycle are
 * exactly what they were before that feature existed.
 *
 * Layer choice: Bottom (not Top, unlike TriggerDock/LiveWallpaperPanel
 * which are interactive controls the user explicitly summons and which
 * should always be reachable). Music Dock is a passive, always-on
 * overlay -- wlr-layer-shell's Bottom layer sits above the Background
 * layer mpvpaper itself normally runs on, but below normal
 * floating/tiled windows, matching "above wallpaper, below normal
 * windows" from the spec.
 */
PanelWindow {
    id: overlay

    // ── Settings (guarded fallback, see MusicDockPanel.qml's header) ─────
    readonly property bool enabled: SettingsService.settings.music_dock_enabled === true
    readonly property bool autoHide: SettingsService.settings.music_dock_autohide === true
    readonly property bool clickThrough: SettingsService.settings.music_dock_click_through === true
    readonly property int cfgWidth: {
        const v = parseInt(SettingsService.settings.music_dock_width, 10);
        return (v >= 360 && v <= 1400) ? v : 640;
    }
    readonly property int cfgHeight: {
        const v = parseInt(SettingsService.settings.music_dock_height, 10);
        return (v >= 64 && v <= 200) ? v : 88;
    }

    readonly property string targetMonitorName: {
        const m = SettingsService.settings.music_dock_monitor;
        return (m && m !== "auto") ? m : MultiMonitorService.focusedMonitorName;
    }

    // ── Visualizer position (see MusicDockPanel.qml's "Visualizer
    // position" row) -- "bottom" keeps the exact original placement,
    // "top"/"center" repin the very same overlay via layer-shell
    // anchors below. Same window, same MusicDock instance, same
    // CavaService singleton the whole time -- only the anchor edge
    // changes, never the content or the audio pipeline.
    readonly property string positionVal: {
        const p = SettingsService.settings.music_dock_position;
        return (p === "top" || p === "center") ? p : "bottom";
    }

    // "Multi-monitor aware": bind to a specific ShellScreen when the
    // setting names one (or the currently focused monitor for "auto");
    // falls back to the compositor's default screen when no match is
    // found yet (e.g. monitor list hasn't loaded on first run).
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

    // Only ever visible while the feature is turned on -- deliberately
    // independent of LiveWallpaperPanel.visible, which is what makes
    // Music Dock "remain visible even after the Live Wallpaper Manager
    // panel is closed". Auto-hide-when-idle additionally hides it
    // whenever no MPRIS player is currently active.
    visible: overlay.enabled && (!overlay.autoHide || MprisService.active)

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "livewallpaper-musicdock"

    // ── Placement (Visualizer Position) ──────────────────────────────
    // wlr-layer-shell anchors are a compositor-owned edge, not a QML x/y
    // we can tween -- so the anchor/margin flip below is instant, and
    // instead applied on the invisible midpoint of a fade-out/fade-in
    // crossfade of the content (`repositionAnim` below), which is what
    // actually reads as a smooth transition. Anchoring neither top nor
    // bottom (the "center" case) is the same zero-anchor trick already
    // used for horizontal centering -- the compositor centers on
    // whichever axis has no anchor, so no anchors at all centers both.
    //
    //   bottom (default, unchanged): anchors.bottom + margins.bottom: 20
    //   top:                         anchors.top + margins.top: 12
    //                                 (matches TriggerDock.qml's own
    //                                 top-floating margin convention --
    //                                 this overlay keeps exclusiveZone:
    //                                 0 like every other floating panel
    //                                 here, so it never reserves space
    //                                 from/collides with a real bar's
    //                                 exclusive zone, it just floats
    //                                 clear of the very top edge)
    //   center:                      no vertical anchor at all
    //
    // `_appliedPosition` starts equal to positionVal (a live binding) but
    // that binding is deliberately overwritten by the ScriptAction below
    // the first time positionVal changes -- from then on it only updates
    // at the fade's midpoint, which is what actually staggers the anchor
    // swap behind the fade-out instead of firing on the same frame as it.
    property string _appliedPosition: positionVal
    anchors.top: overlay._appliedPosition === "top"
    anchors.bottom: overlay._appliedPosition === "bottom"
    margins.top: overlay._appliedPosition === "top" ? 12 : 0
    margins.bottom: overlay._appliedPosition === "bottom" ? 20 : 0

    // Empty Region = accepts no pointer input at all, i.e. every click
    // passes straight through to whatever is beneath the dock. Only
    // applied when the Click-through setting is on; null (the default)
    // means the whole surface accepts input normally, same as every
    // other PanelWindow in this module.
    mask: overlay.clickThrough ? clickThroughMask : null
    Region { id: clickThroughMask }

    Item {
        id: musicDockContent
        anchors.fill: parent
        opacity: 1

        MusicDock {
            anchors.fill: parent
        }
    }

    // Fade out -> swap the anchor/margin binding while fully transparent
    // -> fade back in. 100ms + 100ms = 200ms total, inside the requested
    // 150-250ms window. This only ever touches `musicDockContent.opacity`
    // -- CavaService, MprisService, and the overlay window itself never
    // restart, and there is still exactly one MusicDock/CavaService
    // instance the whole time.
    onPositionValChanged: repositionAnim.restart()
    SequentialAnimation {
        id: repositionAnim
        NumberAnimation {
            target: musicDockContent; property: "opacity"
            to: 0; duration: 100; easing.type: Easing.OutQuad
        }
        ScriptAction { script: overlay._appliedPosition = overlay.positionVal }
        NumberAnimation {
            target: musicDockContent; property: "opacity"
            to: 1; duration: 100; easing.type: Easing.InQuad
        }
    }

    // ── Lifecycle ─────────────────────────────────────────────────────
    // Registers/releases this dock's claim on the shared CavaService under
    // the "musicdock" consumer id -- see CavaService.qml's "Multi-consumer
    // reference counting" header. Peaclock + Cava Dock (Panels/
    // PeaclockCavaDockOverlay.qml) does the identical thing under its own
    // "peaclock" id, so both docks can have Cava on at once and turning
    // this one off never stops Cava out from under the other.
    function _syncBackends() {
        if (overlay.enabled) {
            MprisService.start();
            if (SettingsService.settings.music_dock_cava_enabled !== false) {
                CavaService.start("musicdock");
            } else {
                CavaService.stop("musicdock");
            }
        } else {
            MprisService.stop();
            CavaService.stop("musicdock");
        }
    }

    Component.onCompleted: _syncBackends()

    Connections {
        target: SettingsService
        function onSettingsChanged() { overlay._syncBackends(); }
    }
}
