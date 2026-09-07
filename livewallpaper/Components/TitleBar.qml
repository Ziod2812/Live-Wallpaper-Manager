import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Services"

RowLayout {
    id: root
    spacing: Theme.spacingSm

    property bool showDirPanel: false
    property bool showPlaylistPanel: false
    property bool showMusicDockPanel: false
    property bool showSmartPlaybackPanel: false
    property bool zenMode: false
    property bool showTriggerDock: false
    // Which top-level app mode is active ("wallpapers" | "streaming" |
    // "web") and whether the ModeSwitcher should be locked (disabled)
    // while LiveWallpaperPanel's crossfade/slide transition is running.
    property string currentMode: "wallpapers"
    property bool modeSwitchLocked: false

    signal toggleDirPanel()
    signal togglePlaylistPanel()
    signal toggleMusicDockPanel()
    signal toggleSmartPlaybackPanel()
    signal toggleZenMode()
    signal closeRequested()
    signal minimizeToShortcut()
    signal modeSelected(string mode)

    Text {
        text: "󰸉  Live Wallpapers"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeXl
        font.bold: true
    }

    // Small status dots: auto-refresh watcher + battery-saver + Smart
    // Playback pause state, purely informational, sit right after the
    // title.
    Row {
        Layout.leftMargin: Theme.spacingSm
        spacing: 4
        visible: WatcherService.running || PowerService.onBattery || SmartPlaybackService.paused

        Rectangle {
            visible: WatcherService.running
            width: 6; height: 6; radius: 3
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.success
        }
        Rectangle {
            visible: PowerService.onBattery
            width: 6; height: 6; radius: 3
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.peach
        }
        Rectangle {
            visible: SmartPlaybackService.paused
            width: 6; height: 6; radius: 3
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.yellow
        }
    }

    Item { Layout.fillWidth: true }

    // Segmented Wallpapers/Streaming/Web mode switcher, centered in the
    // gap between the title and the icon-button group. Both flanking
    // spacers are Layout.fillWidth, so it stays centered at any panel
    // width and simply gets more breathing room on wider panels.
    ModeSwitcher {
        currentMode: root.currentMode
        locked: root.modeSwitchLocked
        onModeSelected: mode => root.modeSelected(mode)
    }

    Item { Layout.fillWidth: true }

    // Keep the green minimize/shortcut control in the same top toolbar row.
    // It always re-enables the persistent LW shortcut before closing the
    // full panel; the shortcut's red × remains the close action for the dock.
    IconButton {
        text: "⌄"
        active: root.showTriggerDock
        accentColor: Theme.success
        fontSize: Theme.fontSizeLg
        onClicked: root.minimizeToShortcut()
    }

    IconButton {
        text: "▶"
        active: root.showPlaylistPanel || PlaylistService.enabled
        accentColor: Theme.teal
        onClicked: root.togglePlaylistPanel()
    }

    IconButton {
        text: "🎵"
        active: root.showMusicDockPanel || SettingsService.settings.music_dock_enabled === true
        accentColor: Theme.mauve
        onClicked: root.toggleMusicDockPanel()
    }

    IconButton {
        text: "⏯"
        active: root.showSmartPlaybackPanel || SmartPlaybackService.enabled
        accentColor: Theme.yellow
        iconColor: "#FFFFFF"
        onClicked: root.toggleSmartPlaybackPanel()
    }

    IconButton {
        text: "📁"
        active: root.showDirPanel
        onClicked: root.toggleDirPanel()
    }

    IconButton {
        text: "◱"
        active: root.zenMode
        onClicked: root.toggleZenMode()
    }

    IconButton {
        text: "✕"
        accentColor: Theme.danger
        onClicked: root.closeRequested()
    }
}
