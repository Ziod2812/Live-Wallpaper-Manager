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
                    browseProc.command = ["bash", Paths.script("folder_picker.sh"), "Select wallpaper folder", pathInput.text];
                    browseOut.clear();
                    browseErr.clear();
                    _dbgLog("Process started: " + JSON.stringify(browseProc.command));
                    browseProc.running = true;
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
    // xdg-desktop-portal -> zenity -> yad -> kdialog -> Qt FileDialog.
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
    property Process browseProc: Process {
        id: browseProc
        stdout: StdioCollector { id: browseOut }
        stderr: StdioCollector { id: browseErr }
        onRunningChanged: {
            root._dbgLog("Process running changed -> " + running + " (command: " + JSON.stringify(command) + ")");
        }
        onExited: (code, status) => {
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
