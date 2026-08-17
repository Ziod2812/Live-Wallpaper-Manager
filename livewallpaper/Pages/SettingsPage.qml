import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Services"
import "../Components"

/*
 * SettingsPage.qml
 * -------------------
 * PHASE 2 -- "General settings" moved here from the panel: hosts
 * DirPanel.qml (wallpaper directory, Clear Cache, Exit Application)
 * plus the same shared ConfirmDialog the panel used for those two
 * destructive actions -- identical CacheService.clear() /
 * ApplicationService.exit() wiring, unmodified.
 *
 * PHASE 4 -- added an "Application" section below it: Autostart
 * (ApplicationService.autostartEnabled/setAutostart(), backed by the
 * new scripts/manage_autostart.sh), Desktop notifications
 * (NotifyService's new settings.notifications_enabled gate), and
 * System tray (TrayService.enabledSetting/setEnabled()). All three
 * reuse services/scripts introduced elsewhere this phase -- nothing
 * new is defined in this file itself, just the toggles.
 *
 * Root is a plain Item wrapping the scrollable Flickable + the
 * ConfirmDialog overlay as siblings (same fix already applied in
 * WallpapersModeContent.qml/PerformancePage.qml -- a dialog inside the
 * Flickable would size/position against scrollable content instead of
 * the viewport).
 */
Item {
    id: root

    function focusSettingSearch(query) {
        const q = String(query || "").trim().toLowerCase();
        if (!q.length)
            return;

        const matches = [
            { text: "wallpaper directory folder path browse save", y: 0 },
            { text: "clear cache", y: Math.max(0, dirPanel.y + dirPanel.height - 100) },
            { text: "exit application", y: Math.max(0, dirPanel.y + dirPanel.height - 60) },
            { text: "start login autostart", y: appSection.y },
            { text: "desktop notifications", y: desktopNotificationsRow.y },
            { text: "system tray tray icon", y: systemTrayRow.y }
        ];

        for (let i = 0; i < matches.length; i++) {
            if (matches[i].text.indexOf(q) !== -1) {
                const maxY = Math.max(0, flick.contentHeight - flick.height);
                flick.contentY = Math.min(Math.max(0, matches[i].y), maxY);
                return;
            }
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: content
            width: flick.width
            spacing: Theme.spacingLg

            DirPanel {
                id: dirPanel
                Layout.fillWidth: true
                onCloseRequested: {}
                onSaved: {}
                onClearCacheRequested: confirmDialog.request("clearCache")
                onExitRequested: confirmDialog.request("exit")
            }

            // ── Application (PHASE 4) ───────────────────────────────────────
            Rectangle {
                id: appSection
                Layout.fillWidth: true
                radius: Theme.radiusLg
                color: Theme.cardBg
                border.width: 1
                border.color: Theme.panelBorder
                implicitHeight: appContent.implicitHeight + Theme.spacingLg * 2

                ColumnLayout {
                    id: appContent
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLg
                    spacing: Theme.spacingMd

                    Text {
                        text: "Application"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeLg
                        font.bold: true
                    }

                    SettingRow {
                        label: "Start on login"
                        RowLayout {
                            spacing: Theme.spacingSm
                            Text {
                                visible: !ApplicationService.autostartAvailable
                                text: "checking…"
                                color: Theme.overlay0
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                            }
                            ToggleSwitch {
                                visible: ApplicationService.autostartAvailable
                                checked: ApplicationService.autostartEnabled
                                onToggled: ApplicationService.setAutostart(!ApplicationService.autostartEnabled)
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Adds a standard login-session autostart entry for \"quickshell -c livewallpaper\". On Hyprland specifically, also consider an exec-once line in hyprland.conf (see install.sh's output) -- Hyprland doesn't read this entry on its own."
                        color: Theme.overlay0
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.panelBorder }

                    SettingRow {
                        id: desktopNotificationsRow
                        label: "Desktop notifications"
                        ToggleSwitch {
                            checked: SettingsService.settings.notifications_enabled !== false
                            onToggled: SettingsService.set("notifications_enabled", !(SettingsService.settings.notifications_enabled !== false))
                        }
                    }

                    SettingRow {
                        id: systemTrayRow
                        label: "System tray icon"
                        RowLayout {
                            spacing: Theme.spacingSm
                            Text {
                                visible: TrayService.enabledSetting && !TrayService.available
                                text: "dbus-next/Pillow not installed"
                                color: Theme.subtext0
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                            }
                            ToggleSwitch {
                                checked: TrayService.enabledSetting
                                onToggled: TrayService.setEnabled(!TrayService.enabledSetting)
                            }
                        }
                    }
                }
            }
        }
    }

    // -------------------- CLEAR CACHE / EXIT CONFIRMATION --------------------
    // Same shared-instance pattern the panel used: covers the whole page
    // so the dialog properly dims everything behind it, not just
    // DirPanel's own bounds.
    ConfirmDialog {
        id: confirmDialog
        anchors.fill: parent

        property string pendingAction: ""

        function request(action) {
            pendingAction = action;
            if (action === "clearCache") {
                title = "Clear Cache?";
                message = "Removes thumbnails and other regenerable cache files. Settings, favorites, playlists, history, and your wallpapers are never touched.";
                confirmText = "Clear Cache";
                danger = false;
            } else {
                title = "Exit Live Wallpaper?";
                message = "This stops playback and closes the application.";
                confirmText = "Exit";
                danger = true;
            }
            open = true;
        }

        onAccepted: {
            open = false;
            if (pendingAction === "clearCache") CacheService.clear();
            else if (pendingAction === "exit") ApplicationService.exit();
            pendingAction = "";
        }
        onCancelled: {
            open = false;
            pendingAction = "";
        }
    }
}
