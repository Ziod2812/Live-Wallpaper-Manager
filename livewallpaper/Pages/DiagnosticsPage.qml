import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../Config"
import "../Services"
import "../Components"

Item {
    id: root
    property string statusText: "Ready"
    property string profilePath: Paths.dataDir + "/livewallpaper-profile.json"
    property string healthText: "Not checked"
    property string usageText: "Not checked"

    function runHealth() {
        healthProc.running = true;
        root.statusText = "Running diagnostics…";
    }
    function runUsage() {
        usageProc.running = true;
        root.statusText = "Reading usage history…";
    }

    // Opens a native "Save As" dialog (defaulting to root.profilePath),
    // then runs profile_backup.sh export against whatever path the user
    // picks -- so Export visibly does something and lands where the
    // user chose, instead of silently overwriting a fixed hidden file.
    function exportProfile() {
        pickProc.mode = "export";
        pickProc.command = ["bash", Paths.script("file_picker.sh"), "save",
            "Export Profile", root.profilePath, "JSON files", "*.json"];
        pickProc.running = true;
        root.statusText = "Choose where to save the profile…";
    }
    // Opens a native "Open" dialog filtered to *.json, then runs
    // profile_backup.sh import against the chosen file.
    function importProfile() {
        pickProc.mode = "import";
        pickProc.command = ["bash", Paths.script("file_picker.sh"), "open",
            "Import Profile", root.profilePath, "JSON files", "*.json"];
        pickProc.running = true;
        root.statusText = "Choose a profile to import…";
    }
    function cleanCache() {
        cleanProc.running = true;
        root.statusText = "Cleaning cache…";
    }
    function pickSmartWallpaper() {
        smartProc.running = true;
        root.statusText = "Picking a wallpaper…";
    }

    // File-picker dialog: routes its result to either export or import
    // once the user has actually chosen a path (mode set right before
    // pickProc.running is flipped on above).
    Process {
        id: pickProc
        property string mode: ""
        stdout: StdioCollector { id: pickOut }
        stderr: StdioCollector { id: pickErr }
        onExited: (code, status) => {
            const chosen = pickOut.text.trim();
            if (code !== 0 || chosen.length === 0) {
                // Exit code 1 = user cancelled the dialog -- stay quiet.
                if (code !== 1) {
                    const msg = pickErr.text.trim();
                    NotifyService.error(msg.length > 0 ? msg : "No file dialog available. Install zenity or kdialog.");
                    root.statusText = "Cancelled";
                } else {
                    root.statusText = "Ready";
                }
                return;
            }
            if (pickProc.mode === "export") {
                exportProc.command = ["bash", Paths.script("profile_backup.sh"), "export", chosen];
                exportProc.running = true;
            } else if (pickProc.mode === "import") {
                importProc.command = ["bash", Paths.script("profile_backup.sh"), "import", chosen];
                importProc.running = true;
            }
        }
    }

    Process {
        id: healthProc
        command: ["bash", Paths.script("health_check.sh")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(String(text || "{}"));
                    const rows = data.checks || [];
                    root.healthText = rows.map(r => (r.status === "ok" ? "✓ " : "⚠ ") + r.name + ": " + r.detail).join("\n");
                    root.statusText = "Diagnostics completed";
                } catch (e) {
                    root.healthText = "Could not parse diagnostics output";
                    root.statusText = "Diagnostics failed";
                }
            }
        }
    }
    Process {
        id: usageProc
        command: ["bash", Paths.script("usage_stats.sh")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(String(text || "{}"));
                    root.usageText = "Total runtime: " + Math.round((data.total_seconds || 0) / 60) +
                        " minutes\nMost used: " + ((data.top && data.top.path) ? data.top.path.split("/").pop() : "None") +
                        " (" + ((data.top && data.top.uses) || 0) + " launches)";
                    root.statusText = "Usage refreshed";
                } catch (e) { root.usageText = "Could not read usage history"; }
            }
        }
    }
    Process {
        id: exportProc
        stdout: StdioCollector { id: exportOut }
        stderr: StdioCollector { id: exportErr }
        onExited: (code, status) => {
            if (code === 0) {
                const savedTo = exportOut.text.trim();
                NotifyService.info("Profile exported" + (savedTo ? " to " + savedTo.split("/").pop() : ""));
                root.statusText = "Exported to " + (savedTo || "profile file");
            } else {
                const msg = exportErr.text.trim();
                NotifyService.error(msg.length > 0 ? msg : "Failed to export profile.");
                root.statusText = "Export failed";
            }
        }
    }
    Process {
        id: importProc
        stdout: StdioCollector { id: importOut }
        stderr: StdioCollector { id: importErr }
        onExited: (code, status) => {
            if (code === 0) {
                // Only reload -- and only now, after the import has
                // actually finished writing -- so the app picks up the
                // imported settings/wallpapers/history instead of
                // reloading whatever was there a moment earlier.
                SettingsService.reload();
                WallpaperService.reload();
                HistoryService.reload();
                NotifyService.info("Profile imported");
                root.statusText = "Import completed";
            } else {
                const msg = importErr.text.trim();
                NotifyService.error(msg.length > 0 ? msg : "Failed to import profile.");
                root.statusText = "Import failed";
            }
        }
    }
    Process {
        id: cleanProc
        command: ["bash", Paths.script("maintenance.sh"), "cleanup", "30"]
        stdout: StdioCollector { id: cleanOut }
        stderr: StdioCollector { id: cleanErr }
        onExited: (code, status) => {
            if (code === 0) {
                const msg = cleanOut.text.trim();
                NotifyService.info(msg.length > 0 ? msg : "Cache cleaned");
                root.statusText = msg.length > 0 ? msg : "Cache cleaned";
            } else {
                const msg = cleanErr.text.trim();
                NotifyService.error(msg.length > 0 ? msg : "Failed to clean cache.");
                root.statusText = "Cleanup failed";
            }
        }
    }
    Process {
        id: smartProc
        command: ["bash", Paths.script("smart_select.sh")]
        stdout: StdioCollector { id: smartOut }
        stderr: StdioCollector { id: smartErr }
        onExited: (code, status) => {
            const path = smartOut.text.trim();
            if (code === 0 && path.length > 0) {
                PlaybackService.apply(path);
                const name = path.split("/").pop();
                NotifyService.info("Applied smart wallpaper: " + name);
                root.statusText = "Applied " + name;
            } else {
                const msg = smartErr.text.trim();
                NotifyService.error(msg.length > 0 ? msg : "No wallpapers available to pick from.");
                root.statusText = "No wallpaper picked";
            }
        }
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: body.height + Theme.spacingLg
        clip: true
        Column {
            id: body
            width: parent.width
            spacing: Theme.spacingLg

            Text {
                text: "Diagnostics & Data"
                color: Theme.text
                font.family: Theme.fontFamilyUi
                font.pixelSize: Theme.fontSizeXl
                font.bold: true
            }
            Text { text: root.statusText; color: Theme.subtext0; font.family: Theme.fontFamilyUi; font.pixelSize: Theme.fontSizeSm }

            Rectangle {
                width: parent.width
                height: healthCol.implicitHeight + Theme.spacingLg * 2
                color: Theme.cardBg; radius: Theme.radiusLg; border.color: Theme.panelBorder; border.width: 1
                Column {
                    id: healthCol
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.margins: Theme.spacingLg; spacing: Theme.spacingSm
                    Text { text: "Health check"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeLg; font.bold: true }
                    Text { width: parent.width; text: root.healthText; color: Theme.subtext0; font.family: Theme.fontFamilyUi; font.pixelSize: Theme.fontSizeSm; wrapMode: Text.Wrap }
                    IconButton { text: "Run Diagnostics"; fontSize: Theme.fontSizeSm; onClicked: root.runHealth() }
                }
            }

            Rectangle {
                width: parent.width
                height: usageCol.implicitHeight + Theme.spacingLg * 2
                color: Theme.cardBg; radius: Theme.radiusLg; border.color: Theme.panelBorder; border.width: 1
                Column {
                    id: usageCol
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.margins: Theme.spacingLg; spacing: Theme.spacingSm
                    Text { text: "Usage statistics"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeLg; font.bold: true }
                    Text { width: parent.width; text: root.usageText; color: Theme.subtext0; font.family: Theme.fontFamilyUi; font.pixelSize: Theme.fontSizeSm; wrapMode: Text.Wrap }
                    IconButton { text: "Refresh Usage"; fontSize: Theme.fontSizeSm; onClicked: root.runUsage() }
                }
            }

            Rectangle {
                width: parent.width
                height: profilesCol.implicitHeight + Theme.spacingLg * 2
                color: Theme.cardBg; radius: Theme.radiusLg; border.color: Theme.panelBorder; border.width: 1
                Column {
                    id: profilesCol
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.margins: Theme.spacingLg; spacing: Theme.spacingSm
                    Text { text: "Profiles & cache"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeLg; font.bold: true }
                    Text { text: root.profilePath; color: Theme.subtext0; font.family: Theme.fontFamilyUi; font.pixelSize: Theme.fontSizeSm; elide: Text.ElideMiddle; width: parent.width }
                    Row {
                        spacing: Theme.spacingSm
                        IconButton { text: "Export"; fontSize: Theme.fontSizeSm; onClicked: root.exportProfile() }
                        IconButton { text: "Import"; fontSize: Theme.fontSizeSm; onClicked: root.importProfile() }
                        IconButton { text: "Clean Cache"; fontSize: Theme.fontSizeSm; onClicked: root.cleanCache() }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: smartCol.implicitHeight + Theme.spacingLg * 2
                color: Theme.cardBg; radius: Theme.radiusLg; border.color: Theme.panelBorder; border.width: 1
                Column {
                    id: smartCol
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.margins: Theme.spacingLg; spacing: Theme.spacingSm
                    Text { text: "Smart wallpaper selection"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeLg; font.bold: true }
                    Text { width: parent.width; text: "Selects a favorite with the lowest usage, then the least-used wallpaper."; color: Theme.subtext0; font.family: Theme.fontFamilyUi; font.pixelSize: Theme.fontSizeSm; wrapMode: Text.WordWrap }
                    IconButton { text: "Pick Smart Wallpaper"; fontSize: Theme.fontSizeSm; onClicked: root.pickSmartWallpaper() }
                }
            }
        }
    }
}
