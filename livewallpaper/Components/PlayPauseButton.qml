import QtQuick
import "../Config"
import "../Services"

/*
 * PlayPauseButton.qml
 * ----------------------
 * The Start/Stop Wallpaper toggle -- extracted verbatim out of
 * ActionBar.qml. Same PlaybackService.toggle() call, same running-state
 * styling; only the label text is configurable so callers can use the
 * original descriptive wording ("Start/Stop Wallpaper") or a shorter one
 * (the panel's compact controls) without duplicating the toggle logic.
 */
IconButton {
    id: root

    property string playLabel: "▶ Start Wallpaper"
    property string stopLabel: "⏹ Stop Wallpaper"

    text: PlaybackService.running ? root.stopLabel : root.playLabel
    danger: PlaybackService.running
    active: true
    accentColor: PlaybackService.running ? Theme.danger : Theme.success
    bold: true
    onClicked: PlaybackService.toggle()
}
