import QtQuick
import "../Config"

/*
 * IconButton.qml
 * ----------------
 * Base interactive control for the whole module: hover/press micro-
 * animations (scale + background fade), optional "active" (toggled) state,
 * optional accent color override. Used for nav arrows, tab pills,
 * resolution/fps chips, favorite star, etc.
 */
Item {
    id: root

    property string text: ""
    property bool active: false
    property bool danger: false
    property color accentColor: Theme.accent
    property real radius: Theme.radiusMd
    property real fontSize: Theme.fontSizeMd
    property bool bold: false
    // Idle (inactive, non-hovered) label color. Defaults to the existing
    // hardcoded Theme.text so every pre-existing IconButton is unaffected;
    // override to get a visibly "muted" idle look for toggles that need it.
    property color mutedColor: Theme.text
    // Optional fixed icon color, overriding the active/inactive logic
    // below entirely. Defaults to null (unset) so every pre-existing
    // IconButton keeps its current accent/muted color behavior untouched;
    // only a button that explicitly sets this gets a state-independent
    // icon color.
    property var iconColor: null
    signal clicked()

    implicitWidth: label.implicitWidth + Theme.spacingLg
    implicitHeight: 36

    readonly property color idleBg: Theme.cardBg
    readonly property color activeBg: danger ? Qt.rgba(0.9529, 0.5451, 0.6588, 0.28)
                                              : Qt.rgba(0.7961, 0.6510, 0.9686, 0.28)
    readonly property color hoverBg: Theme.cardHoverBg

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: root.radius
        color: root.active ? root.activeBg : (mouse.containsMouse ? root.hoverBg : root.idleBg)
        border.width: root.active ? 1 : 0
        border.color: root.danger ? Theme.danger : root.accentColor

        Behavior on color {
            ColorAnimation { duration: Theme.durationFast }
        }
    }

    scale: mouse.pressed ? 0.94 : (mouse.containsMouse ? 1.03 : 1.0)
    Behavior on scale {
        NumberAnimation {
            duration: Theme.durationFast
            easing.type: Easing.OutBack
            easing.overshoot: 1.8
        }
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.iconColor ? root.iconColor : (root.active ? (root.danger ? Theme.danger : root.accentColor) : root.mutedColor)
        font.family: Theme.fontFamily
        font.pixelSize: root.fontSize
        font.bold: root.bold

        Behavior on color {
            ColorAnimation { duration: Theme.durationFast }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
