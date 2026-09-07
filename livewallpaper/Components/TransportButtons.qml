import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Services"

/*
 * TransportButtons.qml
 * -----------------------
 * Previous / Random / Next -- extracted verbatim out of ActionBar.qml so
 * ActionBar (Wallpapers page) and the panel's compact controls can share
 * one implementation. No new logic: same three PlaybackService calls as
 * before.
 */
RowLayout {
    id: root
    spacing: Theme.spacingMd

    IconButton {
        text: "⏮"
        fontSize: Theme.fontSizeLg
        onClicked: PlaybackService.previous()
    }
    IconButton {
        text: "⇄"
        fontSize: Theme.fontSizeLg
        onClicked: PlaybackService.random()
    }
    IconButton {
        text: "⏭"
        fontSize: Theme.fontSizeLg
        onClicked: PlaybackService.next()
    }
}
