import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../Config"
import "../Services"

Rectangle {
    id: root
    radius: Theme.radiusLg
    color: Theme.cardBg
    border.width: 1
    border.color: Theme.panelBorder
    implicitHeight: content.implicitHeight + Theme.spacingLg * 2

    property alias inputText: pathInput.text
    signal closeRequested()
    signal saved()
    // Bubbled up to LiveWallpaperPanel, which owns the single shared
    // ConfirmDialog overlay (anchored to the whole panel, not just this
    // rectangle -- a modal confirmation needs to cover the full window,
    // not be clipped to DirPanel's own small bounds).
    signal clearCacheRequested()
    signal exitRequested()

    Component.onCompleted: pathInput.text = SettingsService.wallpaperDirectory

    Connections {
        target: SettingsService
        function onSettingsChanged() { pathInput.text = SettingsService.wallpaperDirectory; }
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Theme.spacingLg
        spacing: Theme.spacingSm

        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: "Wallpaper directory"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMd
                font.bold: true
            }
            IconButton {
                text: "✕"
                onClicked: root.closeRequested()
            }
        }

        Text {
            text: "Currently using: " + SettingsService.wallpaperDirectory
            color: Theme.subtext0
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            elide: Text.ElideMiddle
            Layout.fillWidth: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Rectangle {
                Layout.fillWidth: true
                height: 36
                radius: Theme.radiusSm
                color: Theme.surface0
                border.width: pathInput.activeFocus ? 1 : 0
                border.color: Theme.accent

                TextInput {
                    id: pathInput
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingSm
                    anchors.rightMargin: Theme.spacingSm
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    selectByMouse: true
                    clip: true
                }
            }

            IconButton {
                text: browsing ? "Browsing…" : "Browse…"
                fontSize: Theme.fontSizeSm
                enabled: !browsing
                onClicked: {
                    browsing = true;
                    browseProc.command = ["bash", Paths.script("folder_picker.sh"), "Select Wallpaper Folder", pathInput.text];
                    _dbgLog("Process started: " + JSON.stringify(browseProc.command));
                    browseProc.running = true;
                    Qt.callLater(function(){ if(root.browsing) root.browsing=false; });
                }
            }

            IconButton {
                text: "Save"
                fontSize: Theme.fontSizeSm
                bold: true
                accentColor: Theme.success
                onClicked: {
                    SettingsService.changeWallpaperDirectory(pathInput.text);
                    root.saved();
                }
            }
        }

        // -------------------- GIF WALLPAPER DIRECTORY --------------------
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Text {
                text: "GIF wallpaper directory"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMd
                font.bold: true
                Layout.fillWidth: true
            }

            Text {
                text: "Currently using: " + SettingsService.gifWallpaperDirectory
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                elide: Text.ElideMiddle
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSm

                Rectangle {
                    Layout.fillWidth: true
                    height: 36
                    radius: Theme.radiusSm
                    color: Theme.surface0
                    border.width: gifPathInput.activeFocus ? 1 : 0
                    border.color: Theme.accent

                    TextInput {
                        id: gifPathInput
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingSm
                        anchors.rightMargin: Theme.spacingSm
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        selectByMouse: true
                        clip: true
                        Component.onCompleted: text = SettingsService.gifWallpaperDirectory
                    }
                }

                IconButton {
                    text: gifBrowsing ? "Browsing…" : "Browse…"
                    fontSize: Theme.fontSizeSm
                    enabled: !gifBrowsing
                    onClicked: {
                        gifBrowsing = true;
                        gifBrowseProc.command = ["bash", Paths.script("folder_picker.sh"),
                            "Select GIF Wallpaper Folder", gifPathInput.text];
                        gifBrowseProc.running = true;
                    }
                }

                IconButton {
                    text: "Save"
                    fontSize: Theme.fontSizeSm
                    bold: true
                    accentColor: Theme.success
                    onClicked: {
                        SettingsService.set("gif_wallpaper_directory", gifPathInput.text);
                        root.saved();
                    }
                }
            }
        }

        // -------------------- MANAGEMENT ROW --------------------
        // Clear Cache / Exit Application: destructive/disruptive actions,
        // so both are gated behind ConfirmDialog rather than firing on a
        // single click. Placed in a visually separated row below the
        // directory controls per the panel's existing spacing rhythm.
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacingXs
            height: 1
            color: Theme.panelBorder
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacingXs
            spacing: Theme.spacingSm

            IconButton {
                text: "🧹 Clear Cache"
                fontSize: Theme.fontSizeSm
                onClicked: root.clearCacheRequested()
            }

            Item { Layout.fillWidth: true }

            IconButton {
                text: "⏻ Exit Application"
                fontSize: Theme.fontSizeSm
                danger: true
                accentColor: Theme.danger
                onClicked: root.exitRequested()
            }
        }
    }

    // Robust cross-desktop folder picker (see scripts/folder_picker.sh):
    // zenity -> kdialog -> yad -> qarma -> python3/tkinter, with a
    // Nautilus/Dolphin/Thunar/Nemo/PCManFM file-manager window as the
    // final fallback if none of those five are installed. install.sh's
    // dependency checker tracks the same five backends.
    // Never fails silently -- a missing backend or a real error always
    // surfaces via NotifyService.error(); a plain user cancel (exit 1)
    // is intentionally quiet.
    property bool browsing: false
    // Temporary trace instrumentation for the "Browse... never returns to
    // idle" investigation. Gated behind LWM_DEBUG/DEBUG so it's silent by
    // default; set either env var to 1 before launching Quickshell to see
    // every step. Timestamps here are directly comparable against
    // folder_picker.sh's own [pid ...] log lines (LW_DEBUG_LOG, default
    // /tmp/lwm_folder_picker_debug.log) to line up the QML-side view of
    // the process against the shell-side view of the same run.
    readonly property bool _dbg: Quickshell.env("LWM_DEBUG") === "1" || Quickshell.env("DEBUG") === "1"
    function _dbgLog(msg) {
        if (root._dbg) console.log("[DirPanel][" + new Date().toISOString() + "] " + msg);
    }
    property bool gifBrowsing: false
    property Process gifBrowseProc: Process {
        id: gifBrowseProc
        stdout: StdioCollector { id: gifBrowseOut }
        stderr: StdioCollector { id: gifBrowseErr }
        onExited: (code, status) => {
            root.gifBrowsing = false;
            if (code === 0) {
                const p = gifBrowseOut.text.trim();
                if (p.length > 0)
                    gifPathInput.text = p;
            } else if (code !== 1) {
                const msg = gifBrowseErr.text.trim();
                NotifyService.error(msg.length > 0 ? msg : "Could not open a folder picker.");
            }
        }
    }

    property Process browseProc: Process {
        id: browseProc
        stdout: StdioCollector { id: browseOut }
        stderr: StdioCollector { id: browseErr }
        onRunningChanged: {
            root._dbgLog("Process running changed -> " + running + " (command: " + JSON.stringify(command) + ")");
        }
        onExited: (code, status) => {
        root.browsing = false
            root._dbgLog("onExited fired: exitCode=" + code + " exitStatus=" + status
                + " stdoutLength=" + browseOut.text.length
                + " stderrLength=" + browseErr.text.length
                + " stderr=" + JSON.stringify(browseErr.text.trim()));
            root.browsing = false;
            if (code === 0) {
                const p = browseOut.text.trim();
                if (p.length > 0) pathInput.text = p;
            } else if (code === 1) {
                // User cancelled the dialog -- not an error, stay quiet.
            } else {
                const msg = browseErr.text.trim();
                NotifyService.error(msg.length > 0 ? msg : "Could not open a folder picker. Install xdg-desktop-portal, zenity, yad, or kdialog.");
            }
        }
    }
}
