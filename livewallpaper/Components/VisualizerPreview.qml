import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Services"

/*
 * VisualizerPreview.qml
 * ------------------------
 * PHASE 3 -- lets the Visualizer settings page show what the current
 * Bars/Waveform + color-mode choice actually looks like without
 * requiring Music Dock to be enabled/visible elsewhere. Reads
 * CavaService.bars/visualizerColor/visualizerStyle/floatingWaveform
 * directly -- the exact same live frame data MusicDock.qml's visualizer
 * renders, so this is a second VIEW of one pipeline, not a second
 * pipeline. If cava isn't running, this just shows a flat idle line/bars
 * (bars stays [] -> every level reads 0) rather than starting anything.
 */
Rectangle {
    id: root
    implicitHeight: 140
    radius: Theme.radiusLg
    color: Theme.cardBg
    border.width: 1
    border.color: Theme.panelBorder

    readonly property int previewBarCount: 32

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingLg
        spacing: Theme.spacingSm

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "Live preview"
                color: Theme.text
                font.family: Theme.fontFamilyUi
                font.pixelSize: Theme.fontSizeMd
                font.bold: true
            }
            Item { Layout.fillWidth: true }
            Text {
                text: CavaService.available
                    ? (CavaService.running ? "● audio active" : "○ no audio yet")
                    : "cava not installed"
                color: CavaService.running ? Theme.success : Theme.subtext0
                font.family: Theme.fontFamilyUi
                font.pixelSize: Theme.fontSizeSm
            }
        }

        Item {
            id: stage
            Layout.fillWidth: true
            Layout.fillHeight: true

            Row {
                anchors.centerIn: parent
                visible: CavaService.visualizerStyle === "bars"
                spacing: 3
                Repeater {
                    model: root.previewBarCount
                    delegate: Rectangle {
                        required property int index
                        readonly property int level: {
                            const n = CavaService.bars.length;
                            if (n === 0) return 0;
                            return CavaService.bars[Math.floor((index / root.previewBarCount) * n)] || 0;
                        }
                        width: 5
                        radius: 2.5
                        anchors.bottom: parent.bottom
                        height: Math.max(3, (level / 255) * stage.height)
                        color: CavaService.visualizerColor
                        opacity: 0.55 + 0.45 * (level / 255)
                        Behavior on height { NumberAnimation { duration: 90 } }
                    }
                }
            }

            Canvas {
                id: waveCanvas
                anchors.fill: parent
                visible: CavaService.visualizerStyle === "waveform"
                readonly property var levels: CavaService.bars
                readonly property color waveColor: CavaService.visualizerColor
                readonly property bool floating: CavaService.floatingWaveform

                onLevelsChanged: requestPaint()
                onWaveColorChanged: requestPaint()
                onFloatingChanged: requestPaint()

                function _path(ctx, ampScale) {
                    const n = root.previewBarCount;
                    const mid = height / 2;
                    ctx.beginPath();
                    for (let i = 0; i < n; i++) {
                        const src = levels.length > 0 ? levels[Math.floor((i / n) * levels.length)] || 0 : 0;
                        const amp = (src / 255) * mid * ampScale;
                        const x = (i / (n - 1)) * width;
                        const y = mid - amp;
                        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                    }
                    for (let i = n - 1; i >= 0; i--) {
                        const src = levels.length > 0 ? levels[Math.floor((i / n) * levels.length)] || 0 : 0;
                        const amp = (src / 255) * mid * ampScale;
                        const x = (i / (n - 1)) * width;
                        const y = mid + amp;
                        ctx.lineTo(x, y);
                    }
                    ctx.closePath();
                }

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    if (floating) {
                        ctx.globalAlpha = 0.30;
                        ctx.fillStyle = waveColor;
                        _path(ctx, 1.35);
                        ctx.fill();
                    }
                    ctx.globalAlpha = 0.85;
                    ctx.fillStyle = waveColor;
                    _path(ctx, 1.0);
                    ctx.fill();
                }
            }
        }
    }

    // Repaint the waveform on a light timer too -- Canvas.onPaint only
    // fires on the property-changed signals above, and `levels` is the
    // same array reference mutating in place often enough in practice,
    // but this guarantees the preview never looks stuck if a frame's
    // array identity doesn't change.
    Timer {
        interval: 66
        running: CavaService.visualizerStyle === "waveform" && root.visible
        repeat: true
        onTriggered: waveCanvas.requestPaint()
    }
}
