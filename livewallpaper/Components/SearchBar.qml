import QtQuick
import "../Config"
import "../Services"

Rectangle {
    id: root
    height: 42
    radius: Theme.radiusMd
    color: Theme.cardBg
    border.width: input.activeFocus ? 1 : 0
    border.color: Theme.accent

    Behavior on border.width { NumberAnimation { duration: Theme.durationFast } }

    Item {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacingMd
        anchors.rightMargin: Theme.spacingMd

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "🔍"
            font.pixelSize: Theme.fontSizeMd
            color: Theme.subtext0
        }

        // Placeholder lives as a SIBLING overlay (not a child of TextInput)
        // positioned in the exact same spot, and is only ever drawn when
        // the field is truly empty (input.length, not text.length -- more
        // reliably updated on TextInput). Keeping it out of TextInput's own
        // child hierarchy avoids the two ever being composited together in
        // the same frame, which is what caused the garbled/overlapping
        // "placeholder + typed text" rendering seen before.
        Text {
            id: placeholder
            anchors.left: parent.left
            anchors.leftMargin: 28
            anchors.verticalCenter: parent.verticalCenter
            text: "Search wallpapers…"
            color: Theme.subtext0
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeMd
            visible: input.length === 0
        }

        TextInput {
            id: input
            anchors.left: parent.left
            anchors.leftMargin: 28
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeMd
            selectByMouse: true
            clip: true

            // One-way only: this field is the sole source of truth for
            // what's typed. It seeds itself once from WallpaperService.search
            // on load and never reads it again.
            Component.onCompleted: text = WallpaperService.search

            onTextEdited: debounce.restart()

            // Mirrors the old 150ms Eww :timeout debounce
            Timer {
                id: debounce
                interval: 150
                onTriggered: WallpaperService.search = input.text
            }
        }
    }

    function focusInput() { input.forceActiveFocus(); }
}
