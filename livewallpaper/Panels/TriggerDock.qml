import QtQuick
import Quickshell
import Quickshell.Wayland
import "../Config"

// TriggerDock.qml
// ------------------
// Small persistent shortcut icon pinned to the top-right corner, the QML
// equivalent of the old `wallpaper-trigger` Eww dock window. Clicking it
// toggles LiveWallpaperPanel's visibility via `targetPanel.toggle()` --
// the exact same function the panel's own ▼ button calls (see
// MiniTitleBar's onMinimizeToShortcut, wired in LiveWallpaperPanel.qml).
// Those two buttons are the project's only show/hide controls, and both
// drive the one `visible` property on the panel; this window's own
// `visible` is deliberately NOT a property owned here -- see shell.qml,
// which binds it as the exact inverse of the panel's `visible`, so there
// is a single shared boolean behind both windows instead of two that
// would need to be kept in sync by hand.
//
// If embedding this module into an existing Caelestia bar instead (e.g.
// as a bar pill/module) this window can be skipped entirely - just call
// `panel.toggle()` from your own bar button. This file exists purely for
// a drop-in, bar-independent shortcut.
PanelWindow {
    id: dock

    property var targetPanel

    implicitWidth: 72
    implicitHeight: 28
    color: "transparent"
    exclusiveZone: 0
    focusable: false

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "livewallpaper-trigger"

    anchors.top: true
    anchors.right: true
    margins.top: 12
    margins.right: 12

    Row {
        anchors.fill: parent
        spacing: 4

        Rectangle {
            id: shortcutButton
            width: 40
            height: parent.height
            radius: Theme.radiusSm
            color: shortcutMouse.containsMouse ? Theme.cardHoverBg : Theme.cardBg
            border.width: 1
            border.color: Theme.panelBorder

            Behavior on color { ColorAnimation { duration: Theme.durationFast } }

            scale: shortcutMouse.pressed ? 0.9 : (shortcutMouse.containsMouse ? 1.06 : 1.0)
            Behavior on scale {
                NumberAnimation { duration: Theme.durationFast; easing.type: Easing.OutBack; easing.overshoot: 2.0 }
            }

            Text {
                anchors.centerIn: parent
                text: "LW"
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                font.bold: true
            }

            MouseArea {
                id: shortcutMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (dock.targetPanel) dock.targetPanel.toggle();
                }
            }
        }

    }
}
