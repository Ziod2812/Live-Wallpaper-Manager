import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Services"

/*
 * PeaclockCavaDock.qml
 * -----------------------------
 * Presentation surface for the standalone "Peaclock + Cava Dock" -- a
 * compact, Peaclock-inspired glass panel that pairs a standalone clock
 * with the existing Cava audio visualizer. This is a NEW, independent
 * dock (see Panels/PeaclockCavaDockOverlay.qml), not a layout option of
 * the existing Music Dock (Components/MusicDock.qml / Panels/
 * MusicDockOverlay.qml), which is untouched by this feature.
 *
 * INDEPENDENCE CONTRACT:
 *   - Every setting this file reads uses its own "pcdock_*" keys --
 *     never "music_dock_*" -- so toggling/tuning this dock never
 *     touches the existing Music Dock's settings, and vice versa.
 *   - Clock/date/day: <PeaclockClock> (Components/PeaclockClock.qml) --
 *     entirely self-contained, no Cava awareness, unmodified.
 *   - Audio visualization: CavaService.bars -- the exact same singleton
 *     / pipeline Components/MusicDock.qml's "bars" style already reads.
 *     No second cava process is started for this dock; CavaService's
 *     start()/stop() are called only from this dock's own overlay
 *     (Panels/PeaclockCavaDockOverlay.qml's _syncBackends()), mirroring
 *     -- not sharing -- the pattern Panels/MusicDockOverlay.qml already
 *     uses for the original dock.
 *   - Now-playing title: MprisService.title / MprisService.active,
 *     read-only, same singleton MusicDock.qml already reads.
 *
 * Cava and Peaclock never reference each other directly here -- this
 * component reads both independently and lays the results out; removing
 * either <PeaclockClock> or the Cava dots block below leaves the other
 * fully functional.
 */
Rectangle {
    id: root

    // ── Chrome settings -- own "pcdock_*" namespace, independent of
    // Music Dock's "music_dock_*" equivalents. ─────────────────────────
    readonly property real cfgOpacity: {
        const v = Number(SettingsService.settings.pcdock_opacity);
        return (v > 0 && v <= 1) ? v : 0.78;
    }
    readonly property int cfgRadius: {
        const v = parseInt(SettingsService.settings.pcdock_radius, 10);
        return (v >= 8 && v <= 40) ? v : 24;
    }
    readonly property bool cfgBlur: SettingsService.settings.pcdock_blur !== false
    readonly property bool cfgGlow: SettingsService.settings.pcdock_glow !== false
    readonly property color cfgAccent: {
        const c = SettingsService.settings.pcdock_accent;
        return (typeof c === "string" && c.length > 0) ? c : Theme.mauve;
    }
    readonly property bool cfgCavaEnabled: SettingsService.settings.pcdock_cava_enabled !== false

    // ── Glass background (same recipe as MusicDock.qml's own root) ──────
    color: cfgBlur ? Qt.rgba(0.1176, 0.1176, 0.1804, cfgOpacity * 0.86)
                    : Qt.rgba(0.1176, 0.1176, 0.1804, Math.min(cfgOpacity + 0.12, 0.97))
    radius: cfgRadius
    border.width: 1
    border.color: cfgGlow ? Qt.rgba(root.cfgAccent.r, root.cfgAccent.g, root.cfgAccent.b, 0.45)
                           : Theme.panelBorder

    Behavior on color { ColorAnimation { duration: Theme.durationNormal } }
    Behavior on border.color { ColorAnimation { duration: Theme.durationNormal } }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        z: -1
        visible: root.cfgBlur
        radius: parent.radius + 4
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.35)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingMd
        spacing: Theme.spacingSm

        // -------------------- CLOCK (independent component) --------------------
        PeaclockClock {
            Layout.fillWidth: true
            accentColor: root.cfgAccent
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.panelBorder }

        // -------------------- LIVE indicator --------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingMd

            Item { Layout.fillWidth: true }

            RowLayout {
                spacing: 4
                Rectangle {
                    width: 6; height: 6; radius: 3
                    color: root.cfgAccent
                    opacity: PlaybackService.running ? 1.0 : 0.35
                    SequentialAnimation on opacity {
                        running: PlaybackService.running
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.4; duration: 800; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
                    }
                }
                Text {
                    text: "LIVE"
                    color: root.cfgAccent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    font.bold: true
                }
            }
        }

        // -------------------- CAVA (independent component/service) --------------------
        // Label intentionally removed (target reference has no "CAVA" text
        // above the strip) -- the Text item is gone entirely, not just
        // hidden, so ColumnLayout's spacing collapses along with it and no
        // empty gap is left above the visualizer strip.

        // Same strip footprint as before (fillWidth, 16px tall) -- only
        // what's painted inside changed, from a fixed dot-row to the
        // Noctalia-style bars/waveform renderer. See
        // Components/PeaclockCavaVisualizer.qml and CavaService.qml's
        // "pcVisualizerStyle" header.
        Item {
            id: cavaStrip
            Layout.fillWidth: true
            Layout.preferredHeight: 16
            visible: root.cfgCavaEnabled && CavaService.available

            // CavaService.pcVisualizerHPosition now moves the ENTIRE dock
            // overlay window (see Panels/PeaclockCavaDockOverlay.qml), not
            // this strip's internal content, so the waveform/bars/line
            // keep their original always-anchors.fill placement inside
            // the strip regardless of that setting -- unchanged size,
            // unchanged position within the card, exactly as before this
            // dock had any horizontal-position control at all.
            PeaclockCavaVisualizer {
                anchors.fill: parent
            }
        }

        Item { Layout.fillHeight: true }

        // -------------------- NOW PLAYING (independent service) --------------------
        Text {
            Layout.fillWidth: true
            text: MprisService.active ? (MprisService.title || "Unknown title") : "Nothing playing"
            color: Theme.text
            font.family: Theme.fontFamilyUi
            font.pixelSize: Theme.fontSizeSm
            elide: Text.ElideRight
        }
    }
}
