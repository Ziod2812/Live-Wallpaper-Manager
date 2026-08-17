import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Services"

/*
 * MiniTitleBar.qml
 * -------------------
 * PHASE 2 replacement for TitleBar.qml on the panel. TitleBar's
 * DirPanel/PlaylistPanel/MusicDockPanel/SmartPlaybackPanel/
 * ModeSwitcher toggles are all gone from the panel now that those
 * config surfaces live in the Manager app (see Pages/), so this header
 * only keeps what the simplified panel still needs: title, the small
 * informational status dots (unchanged -- same WatcherService/
 * PowerService/SmartPlaybackService reads TitleBar already had), the
 * new "Open Manager" action, the minimize-to-shortcut control, and
 * close. TitleBar.qml itself is left in place (unused by the panel from
 * this phase on) rather than deleted, in case a future phase still
 * wants its fuller toggle-bar shape somewhere.
 */
RowLayout {
    id: root
    spacing: Theme.spacingSm

    // Fed live from LiveWallpaperPanel.qml, which in turn just relays
    // shell.qml's single `triggerDockVisible` source of truth -- read-only
    // here, purely to paint the ▼ button's on/off (toggle-switch) look via
    // IconButton's existing `active` state. Never written from this file.
    property bool triggerDockActive: false

    signal toggleTriggerDockRequested()
    signal closeRequested()
    signal openManagerRequested()

    Text {
        text: "󰸉  Live Wallpapers"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeXl
        font.bold: true
    }

    // Same three informational status dots TitleBar.qml showed --
    // auto-refresh watcher / battery-saver / Smart Playback paused --
    // unchanged reads, just relocated.
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

    IconButton {
        text: "🗔  Open Manager"
        accentColor: Theme.mauve
        bold: true
        onClicked: root.openManagerRequested()
    }

    IconButton {
        text: "⌄"
        // ▼ is an independent on/off switch for TriggerDock (the "LW"
        // corner shortcut) -- NOT a "minimize the panel" control anymore.
        // Clicking it only ever flips shell.qml's single `triggerDockVisible`
        // flag; it never touches liveWallpaperPanel.visible,
        // managerWindow.visible, or playback, so this panel (and this
        // button) stay on screen across repeated clicks -- Show, Hide,
        // Show, Hide, forever. `active` gives it a real toggle-switch look
        // (highlighted + bordered when TriggerDock is showing, muted when
        // it's not), driven by the same read-only `triggerDockActive` prop
        // above -- see that property's comment for where it actually comes
        // from.
        active: root.triggerDockActive
        accentColor: Theme.success
        fontSize: Theme.fontSizeLg
        onClicked: root.toggleTriggerDockRequested()
    }

    IconButton {
        text: "✕"
        accentColor: Theme.danger
        onClicked: root.closeRequested()
    }
}
