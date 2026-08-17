import QtQuick
import QtQuick.Layouts
import "../Config"

/*
 * PlaybackControls.qml
 * ----------------------
 * Panel's compact transport row: Previous / Random / Next / Play-Pause.
 * Purely a composition of TransportButtons.qml + PlayPauseButton.qml --
 * the same two components ActionBar.qml (Wallpapers page) uses -- so the
 * panel and the app's Wallpapers page can never drift out of sync and no
 * PlaybackService call is wired up twice.
 */
RowLayout {
    id: root
    spacing: Theme.spacingMd

    TransportButtons {}

    PlayPauseButton {
        playLabel: "▶ Play"
        stopLabel: "⏹ Stop"
    }
}
