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

    // ── Drag-anywhere (freeform position) ──────────────────────────────
    // Dragging the dock (see `dockDragArea` below, on the whole widget --
    // album art, "Nothing playing" text, blank background, all of it,
    // not just one control) abandons the Bottom/Center/Top preset system
    // entirely and pins this PanelWindow to the top-left corner instead,
    // using margins.left/margins.top as plain pixel x/y -- the only way
    // to get a freely-positioned surface out of wlr-layer-shell, whose
    // anchors are compositor-owned edges, not a QML x/y we can set
    // directly. `draggable` just gates whether dockDragArea reacts at
    // all; `freePosition` is what's actually been dragged-and-saved.
    readonly property bool draggable: SettingsService.settings.music_dock_draggable !== false
    readonly property bool freePosition: SettingsService.settings.music_dock_free_position === true
    // Multiplier applied to every dx/dy in dockDragArea._applyLatest()
    // below -- 1.0 (100%, the setting's default) is the original 1:1
    // feel, lower tracks more slowly/precisely, higher covers more
    // ground per flick. Guarded fallback (same convention as every
    // other music_dock_* read in this file): only a sane 25-400% is
    // trusted, matching MusicDockPanel.qml's "Drag sensitivity" slider
    // range so a value the slider could never actually produce can't
    // reach the drag math either.
    readonly property real dragSensitivity: {
        const v = parseInt(SettingsService.settings.music_dock_drag_sensitivity, 10);
        return ((v >= 25 && v <= 400) ? v : 100) / 100;
    }
    readonly property real savedX: {
        const v = Number(SettingsService.settings.music_dock_pos_x);
        return (v >= 0) ? v : -1;
    }
    readonly property real savedY: {
        const v = Number(SettingsService.settings.music_dock_pos_y);
        return (v >= 0) ? v : -1;
    }

    // Live pixel position while free/dragging -- plain (non-bound)
    // properties, same reasoning as MusicDock.qml's old cava `_applyPos`
    // pattern: dockDragArea mutates these directly every mouse move, so
    // nothing here is ever a declarative `x: <expr>` binding that a
    // manual assignment could silently break.
    property real dragMarginLeft: 40
    property real dragMarginTop: 40
    property bool _dragging: false

    // Drag tick interval, derived from this monitor's actual refresh
    // rate instead of a hardcoded 60Hz assumption -- matters on
    // multi-monitor setups where the dock's target monitor isn't
    // necessarily the same refresh rate as whichever screen the user
    // happens to be looking at, and re-derives automatically if the
    // dock's target monitor changes at runtime (unplug/replug, user
    // switches "music_dock_monitor", focus moves for "auto") since
    // this is a plain reactive binding on overlay.screen, not a value
    // computed once at startup.
    //
    // Deliberately defensive end-to-end, because "refreshRate" is
    // reported by whatever compositor/driver combination the user
    // happens to be running, and this needs to degrade safely on
    // hardware/software this wasn't tested against rather than ever
    // hand the Timer a broken interval:
    //   - property may not exist at all on some ShellScreen builds
    //     (`in` check, not just a falsy check, so 0 is treated as
    //     "reported, but not usable" rather than "absent")
    //   - value may be 0, negative, NaN, or Infinity (bad EDID, a
    //     virtual/headless output, a compositor bug)
    //   - value may be absurdly high/low (misreporting drivers exist)
    //     so the derived interval is clamped to 8-33ms (125Hz down to
    //     30Hz) -- comfortably covers real panels from 30Hz e-ink-ish
    //     external monitors up through 120/144/240Hz gaming panels
    //     without ever going fast enough to flood the compositor or
    //     slow enough to feel laggy
    // Falls back to the original flat 16ms/~60Hz tick whenever any of
    // the above trips.
    readonly property int dragTickInterval: {
        const s = overlay.screen;
        const r = (s && ("refreshRate" in s)) ? Number(s.refreshRate) : NaN;
        if (!isFinite(r) || r <= 0) return 16;
        return Math.min(33, Math.max(8, Math.round(1000 / r)));
    }

    // Seeds dragMarginLeft/Top from wherever the dock effectively is
    // right now -- the saved free position if one exists, otherwise a
    // best-effort approximation of the CURRENT preset's spot (so the
    // very first drag never jumps) -- clamped to stay fully on-screen.
    function _seedDragMargins() {
        const sw = overlay.screen ? overlay.screen.width : (dragMarginLeft + implicitWidth);
        const sh = overlay.screen ? overlay.screen.height : (dragMarginTop + implicitHeight);
        const maxX = Math.max(0, sw - implicitWidth);
        const maxY = Math.max(0, sh - implicitHeight);
        let x, y;
        if (overlay.savedX >= 0 && overlay.savedY >= 0) {
            x = overlay.savedX;
            y = overlay.savedY;
        } else {
            x = Math.round(maxX / 2); // presets are always horizontally centered
            if (overlay._appliedPosition === "top") y = 12;
            else if (overlay._appliedPosition === "center") y = Math.round(maxY / 2);
            else y = maxY - 20; // bottom
        }
        dragMarginLeft = Math.max(0, Math.min(x, maxX));
        dragMarginTop = Math.max(0, Math.min(y, maxY));
    }
    onSavedXChanged: if (overlay.freePosition) overlay._seedDragMargins()
    onSavedYChanged: if (overlay.freePosition) overlay._seedDragMargins()

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

    // ── Placement (Visualizer Position + Drag-anywhere) ──────────────────
    // wlr-layer-shell anchors are a compositor-owned edge, not a QML x/y
    // we can tween -- so the anchor/margin flip below is instant, and
    // instead applied on the invisible midpoint of a fade-out/fade-in
    // crossfade of the content (`repositionAnim` below), which is what
    // actually reads as a smooth transition for the PRESET case.
    // Anchoring neither top nor bottom (the "center" case) is the same
    // zero-anchor trick already used for horizontal centering -- the
    // compositor centers on whichever axis has no anchor, so no anchors
    // at all centers both.
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
    // free/dragging: anchors.left + anchors.top instead, with
    // margins.left/margins.top driven by dragMarginLeft/dragMarginTop --
    // this is layer-shell's only route to an arbitrary pixel position,
    // and it deliberately overrides every preset anchor above while
    // active (`_dragging` during the drag itself, `freePosition` once
    // it's been released-and-saved).
    //
    // `_appliedPosition` starts equal to positionVal (a live binding) but
    // that binding is deliberately overwritten by the ScriptAction below
    // the first time positionVal changes -- from then on it only updates
    // at the fade's midpoint, which is what actually staggers the anchor
    // swap behind the fade-out instead of firing on the same frame as it.
    property string _appliedPosition: positionVal
    readonly property bool _free: overlay.freePosition || overlay._dragging
    anchors.left: overlay._free
    anchors.top: overlay._free || overlay._appliedPosition === "top"
    anchors.bottom: !overlay._free && overlay._appliedPosition === "bottom"
    margins.left: overlay._free ? overlay.dragMarginLeft : 0
    margins.top: overlay._free
        ? overlay.dragMarginTop
        : (overlay._appliedPosition === "top" ? 12 : 0)
    margins.bottom: (!overlay._free && overlay._appliedPosition === "bottom") ? 20 : 0

    // Short interpolation for preset<->free transitions (Reset position /
    // double-click / picking Bottom-Center-Top while already free) so
    // those discrete jumps glide instead of snapping.
    //
    // Deliberately DISABLED while `_dragging` is true (enabled: false
    // below). dragTicker already throttles margin writes to the target
    // monitor's own refresh rate (~60/s on a typical 60Hz panel), which
    // is a discrete target update every 16ms -- shorter than this
    // animation's own 60ms duration. Left enabled during a drag, every
    // new tick's target arrives before the previous 60ms ease finishes,
    // so the animation queue never catches up and the surface's ACTUAL
    // on-screen position permanently trails the `dragMarginLeft/Top`
    // value dockDragArea is computing against. That's exactly the kind
    // of "our math assumes the window is where we told it to be, but it
    // isn't yet" mismatch _applyLatest()'s pendingDx/Dy accumulator (see
    // above) is built to avoid -- except this one happens one layer
    // further down, in the animated geometry itself, where JS can't see
    // it.
    // Net effect if left on: the dock visibly lags/undershoots the
    // cursor throughout a drag, worse the faster or longer you drag,
    // and still off by however much animation was left in flight the
    // moment you release. Snapping instantly during the drag (no
    // Behavior) and only easing for the discrete preset-switch case
    // removes that second source of drift entirely.
    Behavior on margins.left {
        enabled: !overlay._dragging
        NumberAnimation { duration: 60; easing.type: Easing.OutQuad }
    }
    Behavior on margins.top {
        enabled: !overlay._dragging
        NumberAnimation { duration: 60; easing.type: Easing.OutQuad }
    }

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

        // ── Whole-dock drag surface ──────────────────────────────────────
        // Deliberately the FIRST child here, i.e. lowest input priority
        // among siblings -- MusicDock (added below, effectively "on top")
        // and everything nested inside it (play/prev/next buttons,
        // progress bar, cava) still claim clicks over their own bounds
        // exactly as before; this MouseArea only ever sees clicks that
        // fall through blank background -- album art frame, the
        // title/artist labels, empty space around the controls -- which
        // in practice is "grab anywhere on the dock" like the person
        // asked, without stealing input from anything actually
        // clickable. QML doesn't occlude input by paint z-order, only by
        // which item actually has a handler at that point, so this works
        // even though MusicDock visually paints over it.
        MouseArea {
            id: dockDragArea
            anchors.fill: parent
            enabled: overlay.draggable
            hoverEnabled: overlay.draggable
            cursorShape: overlay.draggable ? Qt.SizeAllCursor : Qt.ArrowCursor
            preventStealing: true

            // lastGlobalX/lastGlobalY: SCREEN (global) mouse reading at
            // the most recent onPositionChanged event, via
            // mapToGlobal(mouseX, mouseY) -- NOT the raw local
            // mouseX/mouseY. This is the key fix: mouseX/mouseY are
            // local to this MouseArea, so they shift the instant this
            // window's own geometry changes -- and Qt is known to
            // synthesize a follow-up position-changed event right after
            // a window moves under a stationary cursor (to keep
            // hover/highlight state correct), not just from real
            // hardware input. Reading local coordinates can't tell that
            // apart from a genuine drag, so every self-triggered event
            // was getting summed into pendingDx/Dy as if the user had
            // moved the mouse -- and since the size of that induced
            // read equals whatever we just moved the window by, it
            // scales with dragSensitivity, so it got worse (overshoot,
            // shake while the hand is still, and eventually outrunning
            // the cursor entirely) the higher sensitivity was pushed.
            // mapToGlobal cancels this: it adds this item's OWN current
            // screen offset back to the local coordinate, so a pure
            // "window moved, cursor didn't" event maps to the SAME
            // global point before and after -- only genuine cursor
            // movement produces a nonzero global delta, regardless of
            // whether/when the compositor has actually committed our
            // last margin write.
            property real lastGlobalX: 0
            property real lastGlobalY: 0
            property bool _moved: false

            // Raw cursor movement accumulated since the last applied
            // tick, built ONLY from back-to-back real onPositionChanged
            // events, each measured in the global frame above (see
            // lastGlobalX/Y's header for why local coordinates aren't
            // safe here). dragTicker below still throttles how often
            // this accumulated sum is turned into a margin write (raw
            // pointer-move events can arrive far faster than the
            // compositor can redraw/ack a reconfigure; applying one on
            // every single event queues up a backlog that plays out as
            // visible stutter/catch-up instead of a smooth follow).
            // (The margins.left/top Behavior further down is explicitly
            // OFF while dragging -- see its own comment -- so it never
            // adds a second, competing source of lag on top of this.)
            property real pendingDx: 0
            property real pendingDy: 0

            onPressed: {
                overlay._seedDragMargins();
                overlay._dragging = true;
                _moved = false;
                const g = dockDragArea.mapToGlobal(mouseX, mouseY);
                lastGlobalX = g.x;
                lastGlobalY = g.y;
                pendingDx = 0;
                pendingDy = 0;
            }

            onPositionChanged: {
                if (!pressed) return;
                const g = dockDragArea.mapToGlobal(mouseX, mouseY);
                pendingDx += g.x - lastGlobalX;
                pendingDy += g.y - lastGlobalY;
                lastGlobalX = g.x;
                lastGlobalY = g.y;
            }

            // Applies everything accumulated in pendingDx/Dy since the
            // last tick, then zeroes the accumulator outright -- not to
            // any computed "expected new position", just to 0, since
            // pendingDx/Dy is already a pure delta (see lastGlobalX/Y's
            // header above), not an absolute reading that needs
            // re-anchoring.
            function _applyLatest() {
                const dx = pendingDx;
                const dy = pendingDy;
                if (dx !== 0 || dy !== 0) _moved = true;
                // Sensitivity scales how far the dock moves per pixel of
                // cursor travel (overlay.dragSensitivity's header above)
                // -- applied here, after the _moved check above (which
                // must stay tied to actual cursor movement, not the
                // scaled distance).
                const sdx = dx * overlay.dragSensitivity;
                const sdy = dy * overlay.dragSensitivity;
                const sw = overlay.screen ? overlay.screen.width : (overlay.dragMarginLeft + overlay.implicitWidth);
                const sh = overlay.screen ? overlay.screen.height : (overlay.dragMarginTop + overlay.implicitHeight);
                const maxX = Math.max(0, sw - overlay.implicitWidth);
                const maxY = Math.max(0, sh - overlay.implicitHeight);
                overlay.dragMarginLeft = Math.max(0, Math.min(overlay.dragMarginLeft + sdx, maxX));
                overlay.dragMarginTop = Math.max(0, Math.min(overlay.dragMarginTop + sdy, maxY));
                pendingDx = 0;
                pendingDy = 0;
            }

            Timer {
                id: dragTicker
                interval: overlay.dragTickInterval // self-tunes to this
                                                    // monitor's refresh rate
                                                    // -- see pendingDx/Dy's
                                                    // header above, and
                                                    // dragTickInterval's
                                                    // own header for the
                                                    // fallback rule
                repeat: true
                running: dockDragArea.pressed
                onTriggered: dockDragArea._applyLatest()
            }

            onReleased: {
                _applyLatest(); // flush the very last position -- dragTicker
                                 // won't fire again once `pressed` goes false
                overlay._dragging = false;
                // Plain click, no actual movement -- don't silently flip
                // the dock from an adaptive preset into a fixed pixel
                // position just because someone tapped the background.
                if (!_moved) return;
                // One atomic write for all three keys (SettingsService.
                // setMultiple(), not three separate .set() calls) --
                // three separate writes here used to let the settings
                // FileView's watchChanges reload catch free_position
                // already true while pos_x/pos_y were still the pre-drag
                // values, which re-seeded the drag margins from stale
                // coordinates and visibly snapped the dock back to its
                // old spot right after release. See setMultiple()'s
                // header in Services/SettingsService.qml for the full
                // story.
                SettingsService.setMultiple({
                    music_dock_free_position: true,
                    music_dock_pos_x: Math.round(overlay.dragMarginLeft),
                    music_dock_pos_y: Math.round(overlay.dragMarginTop)
                });
            }

            // Quick escape hatch -- double-click anywhere on the dock
            // snaps it back to the last-selected preset (Bottom/Center/
            // Top) without hunting for a settings toggle.
            onDoubleClicked: {
                SettingsService.set("music_dock_free_position", "false");
            }
        }

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

    Component.onCompleted: {
        overlay._seedDragMargins();
        overlay._syncBackends();
    }

    Connections {
        target: SettingsService
        function onSettingsChanged() { overlay._syncBackends(); }
    }
}
