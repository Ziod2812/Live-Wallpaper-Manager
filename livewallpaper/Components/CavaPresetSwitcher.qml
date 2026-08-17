import QtQuick
import QtQuick.Layouts
import "../Config"

/*
 * CavaPresetSwitcher.qml
 * -------------------------
 * NEW, ADDITIVE component. Segmented "pill" control for the visualizer/
 * dock presets, visually matching Components/ModeSwitcher.qml (same
 * track/segment styling, same Theme tokens) so it reads as a native part
 * of the existing UI -- but a separate file, since ModeSwitcher.qml's
 * three Wallpapers/Streaming/Web modes are a hardcoded, unrelated concern
 * (wallpaper source mode, owned by LiveWallpaperPanel/TitleBar) and this
 * preset's set of DO-NOT-MODIFY files explicitly includes anything already
 * working. Copying the pattern into its own component means zero risk of
 * touching that file or its behavior.
 *
 * Two INDEPENDENT features, each its own on/off toggle -- NOT mutually
 * exclusive:
 *   "cava"          -- Cava (Music Dock's visualizer backend).
 *   "cava_peaclock"  -- Cava + Peaclock (Peaclock + Cava Dock).
 *
 * Both can be active at once, both can be off, either can be on alone --
 * every combination is valid. This used to be a true single-select
 * segmented switch (one sliding highlight, `currentPreset` /
 * `presetSelected`) which is exactly the shape that made the two presets
 * exclusive; that control mechanism has been replaced with independent
 * per-segment toggles while keeping the same pill/track/segment visual
 * language (rounded track, per-segment rounded highlight, hover/press
 * feedback) so the control still reads as the same component.
 *
 * Purely presentational, same contract as before: only ever emits an
 * event, never touches settings itself. The embedder (VisualizerPage.qml)
 * owns the actual state -- each preset's `active` flag here is just a
 * direct read of that preset's own independent enable setting, and this
 * component still has no notion of Peaclock/Cava lifecycle.
 */
Item {
    id: root

    // Array of currently-active preset keys, e.g. [], ["cava"],
    // ["cava_peaclock"], or ["cava", "cava_peaclock"] -- all four are
    // valid and independent of one another.
    property var activePresets: []
    property bool locked: false

    // Emitted whenever a segment is clicked; the embedder decides what
    // that means for its own settings (this component never assumes
    // toggling one preset should affect the other).
    signal presetToggled(string preset, bool enabled)

    readonly property var presets: [
        { key: "cava",          icon: "\u25D0", label: "Cava" },
        { key: "cava_peaclock", icon: "\u23F0", label: "Cava + Peaclock" }
    ]

    function _isActive(key) {
        return root.activePresets.indexOf(key) !== -1;
    }

    implicitWidth: track.implicitWidth
    implicitHeight: 36

    Rectangle {
        id: track
        anchors.centerIn: parent
        implicitWidth: segmentsRow.implicitWidth + Theme.spacingXs * 2
        implicitHeight: 36
        radius: height / 2
        color: Theme.segmentTrackBg
        border.width: 1
        border.color: Theme.panelBorder

        opacity: root.locked ? 0.7 : 1.0
        Behavior on opacity { NumberAnimation { duration: Theme.durationFast } }

        Row {
            id: segmentsRow
            x: Theme.spacingXs
            y: Theme.spacingXs
            height: parent.height - Theme.spacingXs * 2
            spacing: 2

            Repeater {
                id: repeater
                model: root.presets

                delegate: Item {
                    id: segment
                    required property var modelData
                    required property int index

                    readonly property bool isActive: root._isActive(modelData.key)

                    height: segmentsRow.height
                    width: segLabel.implicitWidth + Theme.spacingMd * 2

                    scale: mouse.pressed && !root.locked ? 0.96
                         : (mouse.containsMouse && !root.locked ? 1.02 : 1.0)
                    Behavior on scale {
                        NumberAnimation { duration: Theme.durationFast; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                    }

                    // Each segment now carries its OWN highlight (rather
                    // than one shared sliding thumb) since more than one
                    // can be active at the same time -- a single sliding
                    // highlight has no valid position/width for "both
                    // active". Same fill/border tokens as the old thumb,
                    // just scoped per-segment, and still smoothly
                    // animated in/out.
                    Rectangle {
                        anchors.fill: parent
                        z: -1
                        radius: height / 2
                        color: segment.isActive ? Theme.segmentActiveBg
                             : (mouse.containsMouse && !root.locked ? Theme.segmentHoverBg : "transparent")
                        border.width: segment.isActive ? 1 : 0
                        border.color: Theme.accent
                        Behavior on color { ColorAnimation { duration: Theme.durationModeSwitch } }
                        Behavior on border.width { NumberAnimation { duration: Theme.durationModeSwitch } }
                    }

                    RowLayout {
                        id: segLabel
                        anchors.centerIn: parent
                        spacing: 6

                        Item {
                            id: iconSlot
                            readonly property real iconSlotSize: Theme.fontSizeLg
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: iconSlotSize
                            Layout.preferredHeight: iconSlotSize

                            Text {
                                id: iconText
                                anchors.fill: parent
                                text: segment.modelData.icon
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeMd
                                color: segment.isActive ? Theme.text : Theme.subtext0
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                            }
                        }
                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: segment.modelData.label
                            font.family: Theme.fontFamilyUi
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: segment.isActive
                            color: segment.isActive ? Theme.text : Theme.subtext0
                            Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                        }
                    }

                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !root.locked
                        cursorShape: root.locked ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: {
                            if (root.locked) return;
                            // Toggle this segment only -- independent of
                            // whatever state the other segment is in.
                            root.presetToggled(segment.modelData.key, !segment.isActive);
                        }
                    }
                }
            }
        }
    }
}
