import QtQuick
import QtQuick.Layouts
import "../Config"

/*
 * ModeSwitcher.qml
 * ------------------
 * Fluent/Windows-11-style segmented "pill" control that sits in the
 * TitleBar's empty space between the title and the icon-button group.
 * Three mutually exclusive modes: Wallpapers / Streaming / Web.
 *
 * - A sliding highlight (`thumb`) animates to whichever segment is active,
 *   Fluent-pivot style, instead of each segment repainting independently.
 * - `locked` disables all segment interaction (hover/press/click) while
 *   the panel's own crossfade+slide transition is in flight, so rapid
 *   clicking can't queue up overlapping mode switches.
 * - Purely presentational: it only ever emits `modeSelected`. Whoever
 *   embeds this (TitleBar -> LiveWallpaperPanel) owns the actual mode
 *   state and the transition/animation lock.
 */
Item {
    id: root

    property string currentMode: "wallpapers" // "wallpapers" | "streaming" | "web"
    property bool locked: false

    signal modeSelected(string mode)

    readonly property var modes: [
        { key: "wallpapers", icon: "🖼", label: "Wallpapers" },
        { key: "streaming",  icon: "🌐", label: "Streaming" },
        { key: "web",        icon: "🌍", label: "Web" }
    ]

    implicitWidth: track.implicitWidth
    implicitHeight: 36

    // Center the pill in whatever space Layout.fillWidth spacers give it.
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

        // Sliding active-segment highlight, Fluent pivot-style.
        Rectangle {
            id: thumb
            y: Theme.spacingXs
            height: parent.height - Theme.spacingXs * 2
            radius: height / 2
            color: Theme.segmentActiveBg
            border.width: 1
            border.color: Theme.accent

            readonly property var activeItem: repeater.itemAt(
                root.modes.findIndex(m => m.key === root.currentMode))

            // BUG FIX: `thumb` and `segmentsRow` are siblings inside `track`,
            // but `activeItem.x` is relative to `segmentsRow`'s own
            // coordinate space (segmentsRow itself sits at x: Theme.spacingXs
            // within track). Without adding that offset back, the highlight
            // pill was consistently drawn Theme.spacingXs too far left of
            // the segment it's supposed to outline -- squeezing the visible
            // left padding and stretching the right padding for every tab
            // (most noticeable on the rightmost one, "Web").
            x: activeItem ? activeItem.x + segmentsRow.x : Theme.spacingXs
            width: activeItem ? activeItem.width : 0

            Behavior on x {
                NumberAnimation { duration: Theme.durationModeSwitch; easing.type: Easing.InOutCubic }
            }
            Behavior on width {
                NumberAnimation { duration: Theme.durationModeSwitch; easing.type: Easing.InOutCubic }
            }
        }

        Row {
            id: segmentsRow
            x: Theme.spacingXs
            y: Theme.spacingXs
            height: parent.height - Theme.spacingXs * 2
            spacing: 2

            Repeater {
                id: repeater
                model: root.modes

                delegate: Item {
                    id: segment
                    required property var modelData
                    required property int index

                    readonly property bool isActive: modelData.key === root.currentMode

                    height: segmentsRow.height
                    width: segLabel.implicitWidth + Theme.spacingMd * 2

                    scale: mouse.pressed && !root.locked ? 0.96
                         : (mouse.containsMouse && !root.locked ? 1.02 : 1.0)
                    Behavior on scale {
                        NumberAnimation { duration: Theme.durationFast; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                    }

                    // Hover wash sits under the sliding thumb (z: -1) so it
                    // never masks the active-segment highlight.
                    Rectangle {
                        anchors.fill: parent
                        z: -1
                        radius: height / 2
                        color: (mouse.containsMouse && !segment.isActive && !root.locked) ? Theme.segmentHoverBg : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                    }

                    RowLayout {
                        id: segLabel
                        anchors.centerIn: parent
                        spacing: 6

                        // Fixed-size slot for the icon glyph -- both width
                        // AND height are hard constants (iconSlotSize),
                        // never derived from the glyph's own implicitWidth/
                        // implicitHeight. 🖼 🌐 🌍 don't all resolve to the
                        // same fallback font under "JetBrainsMono Nerd
                        // Font" (it patches in symbol glyphs but not full
                        // color-emoji coverage), and different fallback
                        // fonts report different font metrics (ascent/
                        // descent/advance) for the same pixelSize. That
                        // previously left "Wallpapers" sitting on a subtly
                        // different baseline/box size than "Streaming" and
                        // "Web" even though each glyph was individually
                        // centered in its own auto-sized box -- the boxes
                        // themselves weren't the same size. Anchoring the
                        // Text with anchors.fill + explicit horizontal/
                        // vertical alignment inside an identically-sized
                        // box makes every icon share the exact same slot
                        // geometry, so size, baseline, and padding line up
                        // across all three tabs regardless of per-glyph
                        // font-fallback differences.
                        //
                        // NOTE: this used to be a plain `Row` with
                        // `anchors.verticalCenter` set on this Item -- but
                        // Row (and Column/Grid/Flow) positioners explicitly
                        // don't support anchoring their children (Qt docs:
                        // the positioner overrides an anchored child's
                        // position, producing undefined/inconsistent
                        // results). That's exactly why the icon looked
                        // vertically centered but the "Wallpapers" label
                        // next to it didn't -- Row was silently top-aligning
                        // the label at y:0 instead. RowLayout supports a
                        // real per-child Layout.alignment, so both children
                        // now center against the SAME baseline correctly.
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
                            if (root.locked || segment.isActive) return;
                            root.modeSelected(segment.modelData.key);
                        }
                    }
                }
            }
        }
    }
}
