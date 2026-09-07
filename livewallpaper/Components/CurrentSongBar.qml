import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Services"

/*
 * CurrentSongBar.qml
 * ---------------------
 * Compact "Current song" readout for the panel -- same visual language
 * as CurrentBar.qml (status dot + label + name), but for MprisService
 * instead of PlaybackService. Deliberately NOT the full Music Dock
 * widget (Components/MusicDock.qml, which owns album art, a progress
 * bar, and its own transport controls, and is sized/themed for its own
 * floating overlay window) -- this is only ever a one-line status
 * readout, so it fits the panel's fixed-height layout regardless of
 * whether Music Dock is enabled. MprisService itself is untouched;
 * this only reads title/artist/status/active, exactly like MusicDock.qml
 * already does.
 */
RowLayout {
    id: root
    spacing: Theme.spacingSm

    visible: MprisService.active

    Text {
        text: "●"
        color: MprisService.isPlaying ? Theme.success : Theme.overlay0
        font.pixelSize: 10

        SequentialAnimation on opacity {
            running: MprisService.isPlaying
            loops: Animation.Infinite
            NumberAnimation { to: 0.4; duration: 900; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
        }
    }

    Text {
        text: "Song:"
        color: Theme.subtext0
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
    }

    Text {
        Layout.fillWidth: true
        text: MprisService.artist.length > 0
            ? (MprisService.artist + " — " + MprisService.title)
            : MprisService.title
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        font.bold: true
        elide: Text.ElideRight
    }
}
