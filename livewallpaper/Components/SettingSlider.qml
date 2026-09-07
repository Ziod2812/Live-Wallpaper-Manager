import "../Config"
import QtQuick
import QtQuick.Controls.Basic as QQCB
import QtQuick.Layouts
import "SliderWheel.js" as SliderWheel

/*
 * SettingSlider.qml
 * --------------------
 * THE single reusable restyled QQCB.Slider for this project -- every
 * slider in the app (all of MusicDockPanel.qml's numeric settings:
 * opacity, width/height, radius, album art size, bar width/spacing,
 * sensitivity, animation speed -- plus the MusicDock.qml/
 * StreamingPanel.qml progress ("seek") sliders) instances this one
 * component. No slider anywhere else hand-rolls its own
 * background/handle/wheel-hookup; that logic lives here exactly once.
 *
 * YouTube-seek-bar proportions: a thin (3px) dim track at rest with an
 * always-visible accent fill, a thumb that stays hidden until hover or
 * drag, and everything (track thickness, thumb size/opacity, fill
 * width) animating over the same short, YouTube-ish duration. This
 * replaces the earlier "always-visible big thumb + glow" look --
 * lightweight/thin is the point now, not a large grab target sitting
 * on screen at all times. The hit area under the visible track is
 * still generous (barHeight), so dragging/clicking stays easy even
 * though the track itself reads as thin. There is exactly one visible
 * handle shape (the thumb itself, with its own border for a touch of
 * depth) -- no separate shadow/ghost layer sitting behind it.
 *
 *   - barHeight     total control height (and thus the hit-area
 *                    height). Defaults to 28 -- enough room for the
 *                    hover/drag thumb plus its shadow without the row
 *                    itself looking like a chunky control at rest.
 *   - trackHeight   visible track thickness at rest (idle). Defaults
 *                    to 3px; grows a touch on hover (+1.5) and a touch
 *                    more while dragging (+2), matching a seek bar's
 *                    "thin until you touch it" feel.
 *   - thumbSize     thumb diameter at rest. Defaults to 11px (idle);
 *                    grows to thumbSize+3 on hover and thumbSize+4
 *                    while dragging. The thumb itself is invisible at
 *                    rest (opacity 0) and fades in on hover/drag.
 *   - accentColor   fill + thumb color. Defaults to Theme.accent;
 *                   MusicDock.qml passes its own user-configurable
 *                   accent through here instead of duplicating the
 *                   whole handle to swap one color.
 *   - inLayout     true when this slider sits directly inside a real
 *                   Layout (RowLayout/ColumnLayout), which manages
 *                   width itself -- anchors would conflict with that
 *                   and print a QML warning, so anchors are skipped and
 *                   Layout.fillWidth does the job instead. False (the
 *                   default) keeps the anchors-based fill this needs
 *                   when it's dropped into SettingRow's content slot,
 *                   which is a plain Item, not a Layout, so
 *                   Layout.fillWidth alone has no effect there.
 *
 * Track length: this always fills 100% of whatever width its container
 * gives it (anchors or Layout.fillWidth, per inLayout above) -- already
 * the maximum the surrounding layout allows in every current caller.
 * MusicDockPanel.qml's rows (Components/SliderRow.qml) stack the label
 * above the track instead of beside it specifically so this gets the
 * row's full width rather than sharing it with a label column.
 *
 * Also wheel-adjustable (see SliderWheel.js, shared across every
 * instance of this component so the wheel math lives in exactly one
 * place too): plain wheel = 1 step, Shift+wheel = 10 steps, Ctrl+wheel
 * = 0.1 step, all clamped to from/to and snapped to stepSize.
 *
 * Keyboard: QQCB.Slider already binds Left/Right/Up/Down to
 * decrease()/increase() once it has focus (clicking it focuses it) --
 * nothing extra needed here for that.
 *
 * INPUT EVENT STEALING HARDENING (cross-distro: Arch/Fedora/Debian/
 * Ubuntu/NixOS -- X11 and Wayland):
 * Every page that scrolls (PlaylistPage.qml and SettingsPage.qml root
 * Flickables, MusicDockPanel.qml's internal body Flickable, ...) nests
 * this slider inside a scrollable. Qt's Flickable runs a competing
 * drag gesture: when you press-and-drag on the slider, the enclosing
 * flickable can steal the grab on its first vertical move and scroll
 * the page instead of moving the slider. The fix is the Dynamic
 * Parent Flickable Lock: a recursive `findScrollParent()` walks up the
 * whole ancestor chain and returns the nearest scrollable. On press
 * it snapshots and disables `interactive`; on release it restores it.
 * A Component.onDestruction guard handles teardown mid-drag.
 * propagateComposedEvents: true on the wheel MouseArea keeps wheel/clicks
 * flowing to QtQuick normally on X11 and Wayland. (The HoverHandler omits
 * it because HoverHandler.propagateComposedEvents only exists from Qt 6.2;
 * this project builds on Qt 5.15.)
 */
QQCB.Slider {
    // Invisible hit area spanning the full row width (barHeight tall)
    // so clicking/dragging anywhere near the track -- not just
    // exactly on the thin visible bar -- moves the slider, and so
    // hovering anywhere in the row (not just over the thin track)
    // reveals the thumb.
    // Mouse-wheel support (see SliderWheel.js for the step math). Plain
    // MouseArea with acceptedButtons: Qt.NoButton so it only ever
    // intercepts wheel events -- click/drag presses fall straight
    // through to the Slider's own built-in press/drag handling
    // underneath, untouched.

    id: root

    property string valueText: value.toFixed(0)
    property bool inLayout: false
    property int barHeight: 28
    property real trackHeight: 3
    property real thumbSize: 11
    property color accentColor: Theme.accent
    readonly property bool thumbVisible: root.pressed || thumbHover.hovered
    // Track: thin (3px) at rest, a touch thicker on hover, thicker
    // still while actively dragging -- a seek bar you can see the
    // shape of without it ever feeling heavy.
    readonly property real currentTrackHeight: root.pressed ? root.trackHeight + 2 : (thumbHover.hovered ? root.trackHeight + 1.5 : root.trackHeight)
    // Thumb: invisible at rest, small once it appears, slightly larger
    // again while dragging -- matches the 10-12 / 13-15 / 14-16px idle
    // / hover / drag ranges.
    readonly property real currentThumbSize: root.pressed ? root.thumbSize + 4 : (thumbHover.hovered ? root.thumbSize + 3 : root.thumbSize)
    // ------------------------------------------------------------------
    // DYNAMIC PARENT FLICKABLE LOCK (Input Event Stealing fix)
    // ------------------------------------------------------------------
    // Nearest scrollable ancestor cache. Resolved lazily on first press
    // and kept while pressed. Abstracts the layer where stealing
    // originates so the same logic works whether the slider sits in a
    // plain Flickable (PlaylistPage/SettingsPage), a ListView/GridView,
    // or inside a ScrollView whose `.flickable` holds the actual
    // scrollable -- on every supported distro and windowing system.
    property Item lockedScrollParent: null
    // Original `interactive` value, restored on release so we never
    // permanently alter the page's behaviour.
    property bool lockedScrollInteractive: false
    // True while we hold the lock; guards idempotency so nested press /
    // release storms (e.g. a panel rebuilding mid-drag) never double-set
    // or leave the scrollable stuck.
    property bool scrollLockHeld: false

    // Recursive parent traversal helper. From `from` it climbs the
    // object tree until it finds a scrollable ancestor. A node counts
    // as scrollable (duck-typed, no fragile cross-module `instanceof`)
    // when it exposes BOTH a settable `interactive` flag AND the
    // Flickable family's content metrics. ScrollView (Qt Quick
    // Controls) hides its real flickable behind a `.flickable` child
    // wrapper, so that child is unwrapped too.
    function findScrollParent(from) {
        var node = from ? from.parent : null;
        while (node != null) {
            // ScrollView/ScrollBar-backed containers expose .flickable.
            var exposed = node.flickable;
            if (exposed) {
                node = exposed;
                break;
            }
            var hasInteractive = (typeof node.interactive === "boolean");
            var hasContentY = (typeof node.contentY === "number");
            var hasContentHeight = (typeof node.contentHeight === "number");
            if (hasInteractive && hasContentY && hasContentHeight)
                break;

            node = node.parent;
        }
        return node;
    }

    // Acquire the lock: snapshot and disable scrolling so the drag
    // sticks to the slider. Idempotent; safe to call repeatedly.
    function lockScrollParent() {
        if (root.scrollLockHeld)
            return ;

        var target = root.findScrollParent(root);
        if (target == null)
            return ;

        root.lockedScrollParent = target;
        root.lockedScrollInteractive = target.interactive;
        target.interactive = false;
        root.scrollLockHeld = true;
    }

    // Release the lock: restore the original interactive state. Always
    // clears the held flag even if the scrollable vanished mid-drag.
    function unlockScrollParent() {
        if (!root.scrollLockHeld)
            return ;

        var target = root.lockedScrollParent;
        if (target != null)
            target.interactive = root.lockedScrollInteractive;

        root.lockedScrollParent = null;
        root.lockedScrollInteractive = false;
        root.scrollLockHeld = false;
    }

    anchors.left: inLayout ? undefined : parent.left
    anchors.right: inLayout ? undefined : parent.right
    Layout.fillWidth: true
    implicitHeight: barHeight
    Layout.preferredHeight: barHeight
    // Press -> freeze the enclosing scrollable; release/cancel ->
    // restore it. The slider's own drag must never feed the page's
    // gesture recognizer.
    onPressedChanged: {
        if (root.pressed)
            root.lockScrollParent();
        else
            root.unlockScrollParent();
    }
    // Final safety net: if the widget is destroyed while a lock is still
    // held (panel closes mid-drag, list recycles the delegate, ...), the
    // scrollable must not be left frozen forever.
    Component.onDestruction: root.unlockScrollParent()

    // propagateComposedEvents: true lets the wheel events (and any
    // composed clicks) continue down QtQuick's normal event transport
    // once handled here -- unchanged wheel behaviour on X11 and
    // Wayland, no dead/stuck UI thread.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        hoverEnabled: false
        propagateComposedEvents: true
        onWheel: (wheel) => {
            return SliderWheel.apply(root, wheel);
        }
    }

    // Generous invisible hit area, centered on the track, independent
    // of the slim visible track height -- makes dragging/clicking much
    // easier without changing how thick the bar looks.
    handle: Item {
        x: root.leftPadding
        y: root.topPadding
        width: root.availableWidth
        height: root.availableHeight

        Rectangle {
            id: track

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: root.currentTrackHeight
            radius: height / 2
            // Dim resting-state track -- just enough to show the full
            // range exists, without competing with the accent fill.
            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.16)

            // Always-visible filled progress, rounded to match the track.
            Rectangle {
                width: Math.max(track.height, root.visualPosition * track.width)
                height: parent.height
                radius: height / 2
                color: root.accentColor

                Behavior on width {
                    enabled: !root.pressed

                    NumberAnimation {
                        duration: Theme.durationFast
                        easing.type: Easing.OutQuad
                    }

                }

            }

            Behavior on height {
                NumberAnimation {
                    duration: Theme.durationFast
                    easing.type: Easing.OutQuad
                }

            }

        }

        // Single handle -- the thumb itself. (A separate "shadow" circle
        // used to sit behind this, positioned via `x: thumb.x - 1` PLUS
        // its own independent `Behavior on x`. Since thumb.x is itself
        // already animating on every value change, that second Behavior
        // was animating toward a constantly-moving target and lagged
        // behind, rendering as a dark ghost circle trailing the real
        // thumb. Removed rather than patched: this is the only handle
        // now, and its depth comes from its own border, not a second
        // layered shape that can drift out of sync with it.)
        Rectangle {
            id: thumb

            x: root.visualPosition * (parent.width - width)
            anchors.verticalCenter: parent.verticalCenter
            width: root.currentThumbSize
            height: root.currentThumbSize
            radius: width / 2
            color: root.accentColor
            opacity: root.thumbVisible ? 1 : 0
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.35)

            Behavior on width {
                NumberAnimation {
                    duration: Theme.durationFast
                    easing.type: Easing.OutQuad
                }

            }

            Behavior on height {
                NumberAnimation {
                    duration: Theme.durationFast
                    easing.type: Easing.OutQuad
                }

            }

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.durationFast
                    easing.type: Easing.OutQuad
                }

            }

            Behavior on x {
                enabled: !root.pressed

                NumberAnimation {
                    duration: Theme.durationFast
                    easing.type: Easing.OutQuad
                }

            }

        }

        // track) reveals the thumb.
        //
        // Note: on Qt 5.15 HoverHandler has no `propagateComposedEvents`
        // (added only in Qt 6.2), so it is intentionally omitted. Hover
        // events here are purely cosmetic (reveal the thumb); presses
        // fall straight through to the Slider's own grab handling which
        // our parent-Flickable lock (see onPressedChanged) already
        // protects from being stolen by the enclosing scrollable.
        HoverHandler {
            id: thumbHover

            target: parent
        }

    }

    background: Item {
    }

}
