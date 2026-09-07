import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Services"

/*
 * ActionBar.qml
 * ---------------
 * Wallpapers-page action row: transport buttons + library Refresh +
 * Start/Stop Wallpaper. PHASE 2: the transport buttons and the toggle
 * button were extracted into TransportButtons.qml / PlayPauseButton.qml
 * (shared with the panel's compact PlaybackControls.qml) -- this file
 * now only composes them plus its own Refresh button. Layout, wording,
 * and behavior are byte-for-byte the same as before the extraction.
 */
RowLayout {
    id: root
    spacing: Theme.spacingMd

    TransportButtons {}

    Item { Layout.fillWidth: true }

    IconButton {
        text: WallpaperService.refreshing ? "Refreshing…" : " Refresh"
        onClicked: WallpaperService.refresh()
    }

    PlayPauseButton {}
}
