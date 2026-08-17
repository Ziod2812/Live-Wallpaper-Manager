import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQCB
import "../Config"
import "../Services"

/*
 * GpuSelector.qml
 * ------------------
 * Compact "GPU: <mode> ▼" control for the GPU Switching feature --
 * lets the user choose which physical GPU mpvpaper renders the
 * wallpaper with (Services/GPUManagerService.qml). Pure view: every
 * click goes through GPUManagerService.setMode(), which validates
 * availability, persists the choice, and (only on a real change) asks
 * PlaybackService to relaunch mpvpaper with the new environment and
 * restore whatever wallpaper was already playing.
 *
 * Used by GpuPanel.qml (Performance > GPU card) only when 2+ GPUs are
 * detected -- GpuPanel hides this control entirely on 0/1-GPU systems in
 * favor of an explicit "GPU switching is unavailable" notice. This
 * component still degrades gracefully on its own if reused anywhere with
 * fewer GPUs: with 0/1 GPU detected it renders as a disabled, dimmed,
 * read-only trigger naming that GPU (e.g. "Intel UHD Graphics (Only GPU
 * Detected)", taken straight from GPUManagerService.gpus -- never
 * hardcoded, so it matches whatever hardware actually got detected).
 * Only with 2+ GPUs does it become a clickable dropdown. Items in the
 * dropdown are additionally filtered to only the modes GPUManagerService
 * reports as actually available, so an Intel-only hybrid system never
 * even offers "NVIDIA GPU" etc.
 */
Item {
    id: root

    implicitWidth: trigger.implicitWidth
    implicitHeight: trigger.implicitHeight
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight

    readonly property var _labels: ({
        "auto": "Auto",
        "intel": "Intel GPU",
        "amd": "AMD GPU",
        "nvidia": "NVIDIA GPU",
        "power-saving": "Power Saving",
        "high-performance": "High Performance"
    })
    function _label(mode) {
        return root._labels[mode] || mode;
    }

    // Only 2+ detected GPUs makes switching meaningful -- 0 or 1 GPU
    // means there is nothing to switch between, so the trigger stays
    // disabled and just states what was (or wasn't) found. Reuses
    // GPUManagerService.selectorVisible (its own "more than one GPU"
    // check) instead of re-deriving the same condition here.
    readonly property bool _switchable: GPUManagerService.selectorVisible

    readonly property string _triggerLabel: {
        if (!GPUManagerService.detected) return "Detecting…";
        if (GPUManagerService.gpus.length === 0) return "No GPU Detected";
        if (GPUManagerService.gpus.length === 1) return GPUManagerService.gpus[0].label + " (Only GPU Detected)";
        return "GPU: " + root._label(GPUManagerService.selectedMode) + "  ▼";
    }

    IconButton {
        id: trigger
        text: root._triggerLabel
        fontSize: Theme.fontSizeSm
        enabled: root._switchable
        opacity: enabled ? 1.0 : 0.4
        onClicked: menu.visible ? menu.close() : menu.open()
    }

    QQCB.Popup {
        id: menu
        y: trigger.height + Theme.spacingXs
        x: 0
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
                model: GPUManagerService.modes.filter(m => GPUManagerService.modeAvailable(m))

                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 168
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
                        text: (modelData === GPUManagerService.selectedMode ? "✓ " : "   ") + root._label(modelData)
                        color: modelData === GPUManagerService.selectedMode ? Theme.accent : Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                    }

                    MouseArea {
                        id: itemMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            GPUManagerService.setMode(modelData);
                            menu.close();
                        }
                    }
                }
            }
        }
    }
}
