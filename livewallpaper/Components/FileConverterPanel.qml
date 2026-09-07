import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQCB
import "../Config"
import "../Services"

/*
 * FileConverterPanel.qml
 * ---------------
 * Simple link-out card to convert.to.it (p2r3/convert on GitHub) -- a
 * free, on-device (WASM, runs entirely in the browser -- no upload)
 * universal file converter for video/image/audio/etc. This card does
 * NOT bundle or embed the converter itself.
 *
 * "Open File Converter" opens a "choose a browser" popup (browsers
 * detected by BrowserPickerService, same Repeater-list-in-a-QQCB.Popup
 * shape GpuSelector.qml uses for GPU modes) instead of always going
 * straight through Qt.openUrlExternally() -- i.e. whatever the desktop's
 * single default browser happens to be. If detection hasn't found any
 * browsers (still running at startup, or a genuinely empty result), the
 * button falls back to the old Qt.openUrlExternally() behavior so the
 * click still does something rather than silently no-op-ing.
 *
 * Placed directly below GpuPanel on PerformancePage -- see that file.
 */
Rectangle {
    id: root
    radius: Theme.radiusLg
    color: Theme.cardBg
    border.width: 1
    border.color: Theme.panelBorder
    implicitHeight: content.implicitHeight + Theme.spacingLg * 2

    readonly property string converterUrl: "https://convert.to.it/"

    ColumnLayout {
        id: content
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: Theme.spacingLg }
        spacing: Theme.spacingMd

        // ── Header ───────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            Text {
                text: "🔄 File Converter"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMd
                font.bold: true
                Layout.fillWidth: true
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.panelBorder }

        Text {
            Layout.fillWidth: true
            text: "Convert video, image, audio, and other files on-device, right in your browser -- nothing is uploaded. Powered by convert.to.it (p2r3/convert)."
            color: Theme.subtext0
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Item { Layout.fillWidth: true }

            // Plain Item wrapping trigger+Popup -- same shape as
            // GpuSelector.qml -- so the RowLayout only ever sees a single
            // normal child sized to the button (implicitWidth/Height
            // below) and never tries to manage the Popup itself.
            Item {
                id: openWrap
                implicitWidth: openTrigger.implicitWidth
                implicitHeight: openTrigger.implicitHeight
                Layout.preferredWidth: implicitWidth
                Layout.preferredHeight: implicitHeight

                IconButton {
                    id: openTrigger
                    text: "Open File Converter ↗"
                    fontSize: Theme.fontSizeSm
                    accentColor: Theme.accent
                    bold: true
                    onClicked: {
                        // No browsers detected (still detecting, or a
                        // genuinely empty result) -- fall back to the old
                        // single-default behavior instead of a dead click.
                        if (BrowserPickerService.browsers.length === 0) {
                            Qt.openUrlExternally(root.converterUrl);
                            return;
                        }
                        browserMenu.visible ? browserMenu.close() : browserMenu.open();
                    }
                }

                QQCB.Popup {
                    id: browserMenu
                    y: openTrigger.height + Theme.spacingXs
                    x: openTrigger.width - implicitWidth
                    padding: Theme.spacingXs
                    modal: false
                    focus: true
                    closePolicy: QQCB.Popup.CloseOnEscape | QQCB.Popup.CloseOnPressOutside

                    background: Rectangle {
                        color: Theme.cardBg
                        radius: Theme.radiusMd
                        border.width: 1
                        border.color: Theme.panelBorder
                    }

                    contentItem: ColumnLayout {
                        spacing: 2

                        Repeater {
                            model: BrowserPickerService.browsers

                            delegate: Rectangle {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 200
                                implicitHeight: itemLabel.implicitHeight + Theme.spacingSm
                                radius: Theme.radiusSm
                                color: itemMouse.containsMouse ? Theme.cardHoverBg : "transparent"

                                Text {
                                    id: itemLabel
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.spacingSm
                                    anchors.right: parent.right
                                    anchors.rightMargin: Theme.spacingSm
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.name
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                    elide: Text.ElideRight
                                }

                                MouseArea {
                                    id: itemMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        BrowserPickerService.launch(modelData.id, root.converterUrl);
                                        browserMenu.close();
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
