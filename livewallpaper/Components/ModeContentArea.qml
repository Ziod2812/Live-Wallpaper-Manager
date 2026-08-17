import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Services"

/*
 * ModeContentArea.qml
 * ----------------------
 * Hosts the three mode bodies (Wallpapers / Streaming / Web) stacked in
 * the same panel area and crossfades between them:
 *
 *   - All three views are instantiated exactly once, for the lifetime of
 *     the panel, and never destroyed/recreated on switch (no Loader
 *     active-toggling) -- so each mode keeps its own in-progress state
 *     (search text, streaming URL, web source...) when you switch away
 *     and back, and no service singleton (WallpaperService,
 *     PlaybackService, ...) is ever re-instantiated by a
 *     mode switch.
 *   - The panel's own fixed size never changes -- this Item just fills
 *     whatever Layout space LiveWallpaperPanel already gives it.
 *   - Each mode view lives inside a thin wrapper Item that anchors only
 *     top/bottom/width to the parent (NOT anchors.fill) so the slide
 *     animation is free to own `x` outright -- anchors.fill would bind x
 *     through the anchoring engine and fight the NumberAnimation below.
 *   - `animating` is exposed so the TitleBar's ModeSwitcher can lock
 *     itself for the duration; `_switchTo` also refuses to start a
 *     second transition while one is already running, so animations can
 *     never overlap even if something tries to force `currentMode`
 *     twice in a row.
 */
Item {
    id: root
    clip: true

    property string currentMode: "wallpapers" // authoritative, set by the parent
    property string visibleMode: currentMode  // what's actually on screen right now
    property bool zenMode: false
    property bool animating: false

    signal animationFinished()

    readonly property var modeOrder: ["wallpapers", "streaming", "web"]
    readonly property real slideDistance: 24
    readonly property int phaseDuration: Theme.durationModeSwitch / 2 // 100ms out + 100ms in = 200ms total

    function _indexOf(m) { return modeOrder.indexOf(m); }

    function _wrapFor(m) {
        switch (m) {
            case "streaming": return streamingWrap;
            case "web": return webWrap;
            default: return wallpapersWrap;
        }
    }

    // Kicks off the swap whenever the parent changes currentMode. Guarded
    // against re-entrancy in _switchTo, so even if currentMode is poked
    // again mid-animation this never stacks a second transition.
    onCurrentModeChanged: _switchTo(currentMode)

    function _switchTo(newMode) {
        if (newMode === visibleMode) return;
        if (animating) return; // never let transitions overlap
        const oldMode = visibleMode;
        animating = true;

        const dir = _indexOf(newMode) > _indexOf(oldMode) ? 1 : -1;
        const oldWrap = _wrapFor(oldMode);
        const newWrap = _wrapFor(newMode);

        newWrap.opacity = 0;
        newWrap.x = dir * root.slideDistance;
        newWrap.visible = true;
        newWrap.z = 1;
        oldWrap.z = 0;

        switchAnim.oldWrap = oldWrap;
        switchAnim.newWrap = newWrap;
        switchAnim.dir = dir;
        switchAnim.pendingMode = newMode;
        switchAnim.start();
    }

    SequentialAnimation {
        id: switchAnim
        property var oldWrap: null
        property var newWrap: null
        property int dir: 1
        property string pendingMode: ""

        // Phase 1 (100ms): fade + slide the current view out.
        ParallelAnimation {
            OpacityAnimator {
                target: switchAnim.oldWrap
                from: 1; to: 0
                duration: root.phaseDuration
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: switchAnim.oldWrap
                property: "x"
                to: -switchAnim.dir * root.slideDistance
                duration: root.phaseDuration
                easing.type: Easing.OutCubic
            }
        }

        // Swap the "actual" visible mode the instant the old view has
        // fully faded, before the new view starts fading in.
        ScriptAction {
            script: {
                switchAnim.oldWrap.visible = false;
                switchAnim.oldWrap.x = 0;
                switchAnim.oldWrap.opacity = 1;
                root.visibleMode = switchAnim.pendingMode;
            }
        }

        // Phase 2 (100ms): fade + slide the new view in.
        ParallelAnimation {
            OpacityAnimator {
                target: switchAnim.newWrap
                from: 0; to: 1
                duration: root.phaseDuration
                easing.type: Easing.InOutCubic
            }
            NumberAnimation {
                target: switchAnim.newWrap
                property: "x"
                from: switchAnim.dir * root.slideDistance; to: 0
                duration: root.phaseDuration
                easing.type: Easing.InOutCubic
            }
        }

        onFinished: {
            root.animating = false;
            root.animationFinished();
            // If currentMode moved on again while this transition was
            // running (shouldn't happen -- the switcher locks itself off
            // `animating` -- but this keeps state consistent if it ever
            // does), immediately catch up to the latest requested mode.
            if (root.currentMode !== root.visibleMode) {
                root._switchTo(root.currentMode);
            }
        }
    }

    Component.onCompleted: {
        streamingWrap.visible = false;
        webWrap.visible = false;
    }

    Item {
        id: wallpapersWrap
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: parent.width
        visible: true

        WallpapersModeContent {
            id: wallpapersContent
            anchors.fill: parent
            zenMode: root.zenMode
        }
    }

    Item {
        id: streamingWrap
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: parent.width
        visible: false

        StreamingPanel {
            anchors.fill: parent
        }
    }

    Item {
        id: webWrap
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: parent.width
        visible: false

        WebWallpaperPanel {
            anchors.fill: parent
        }
    }

    // Re-exposed for LiveWallpaperPanel's post-open focus timer.
    function focusSearch() {
        wallpapersContent.focusSearch();
    }
}
