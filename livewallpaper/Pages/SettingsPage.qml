import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Controls
import QtCore
import Quickshell.Io
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
    property string logSavePath: ""

    id: root
    property bool debugMenu: false

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
            { text: "system tray tray icon", y: systemTrayRow.y },
            { text: "smart accent color appearance wallpaper theme", y: smartAccentRow.y },
            { text: "background blur transparency translucency opacity panel card", y: bgBlurRow.y },
            { text: "bandwidth limit download speed", y: bandwidthRow.y },
            { text: "auto-check auto update new wallpapers metadata", y: webMetadataRow.y },
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
                // v2.9 blur smoothing: `antialiasing` keeps the rounded
                // edges of this translucent card crisp (no jaggies on the
                // border/radius), and the Behavior crossfades the card's
                // derived color whenever ui_bg_opacity changes (Background
                // blur slider drag, smart-accent re-tint, settings.json
                // reload) instead of hard-stepping -- cheap smoothness
                // with zero GPU-blur-shader cost.
                antialiasing: true
                Behavior on color { ColorAnimation { duration: Theme.durationFast } }

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
                        text: "Adds a standard login-session autostart entry for \"quickshell -c livewallpaper -n\". On Hyprland, this also writes a matching hl.on(\"hyprland.start\", ...) entry into ~/.config/hypr/hyprland.lua (or a legacy exec-once line into hyprland.conf if that's what you use) so it actually launches after reboot -- no manual config editing needed. Turning this off removes both automatically."
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

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.panelBorder }

                    Text {
                        text: "Appearance"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeLg
                        font.bold: true
                    }

                    SettingRow {
                        id: smartAccentRow
                        label: "Smart accent color"
                        ToggleSwitch {
                            checked: SettingsService.settings.smart_accent_enabled === true
                            onToggled: SettingsService.set("smart_accent_enabled", !(SettingsService.settings.smart_accent_enabled === true))
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSm
                        visible: SettingsService.settings.smart_accent_enabled === true

                        Rectangle {
                            width: 22; height: 22; radius: 11
                            color: SmartAccentService.accentColor
                            border.width: 1
                            border.color: Theme.text
                            Behavior on color { ColorAnimation { duration: 400 } }
                        }
                        Text {
                            text: "Currently: " + SmartAccentService.accentHex
                            color: Theme.subtext0
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Automatically extracts the dominant color from whatever wallpaper, GIF or live wallpaper is currently applied, and uses it as the app's accent color (borders, sidebar, sliders, Start/Stop buttons) -- and, if turned on there too, the Music Dock / Peaclock + Cava visualizer color (see Visualizer page's \"Smart\" color mode). Falls back to the default dark accent if extraction fails for any reason. Off by default -- turning it off restores the original fixed accent color immediately."
                        color: Theme.overlay0
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    // ── Background blur (INVERSE slider) ────────────────────────
                    // Controls Theme.uiBgOpacity, from which panelBg/
                    // cardBg/cardHoverBg/segmentTrackBg, blurRadius and
                    // LiveWallpaperPanel's compositor blur are all derived
                    // (see Config/Theme.qml's "WINDOWS 11 / MICA SURFACE"
                    // section).
                    //
                    // THE SLIDER IS INVERTED: its value is a "blur
                    // emphasis" percentage, 0%..100%, where DRAGGING IT
                    // DOWN toward the minimum RAMPS THE REAL BLUR UP TO
                    // ITS MAXIMUM -- exactly as requested -- and dragging
                    // it up eases the blur back down. The slider's native
                    // value is `(Theme.uiBgOpacity - 0.15) / 0.85`, so a
                    // LOW stored ui_bg_opacity sits at the LEFT of the
                    // track (the maximum-blur end):
                    //    0%   (uiBgOpacity 0.15) -> MAXIMUM blur
                    //        (64px in-app / compositor size 12): every
                    //        wallpaper pixel behind the UI collapses into
                    //        an unreadable frosted smudge -- details,
                    //        clouds, stars, text: all gone. At the same
                    //        time micaAlpha() (Theme.qml) DENSIFIES every
                    //        derived surface toward full opacity, so the
                    //        frosted glass becomes a thick smear that
                    //        completely conceals the wallpaper behind the
                    //        app.
                    //    50%  (uiBgOpacity 0.575) -> still heavy
                    //        (~54px / size ~8).
                    //    100% (uiBgOpacity 1.0) -> weakest blur
                    //        (24px / size 3): the wallpaper is still
                    //        smeared, but its motion reads through.
                    //
                    // The real blur is GPU-side and compositor-driven:
                    // Hyprland's decoration blur + a `blur` layerrule for
                    // every namespace this app owns (the QML scene never
                    // renders the desktop wallpaper -- mpvpaper does -- so
                    // only the compositor can frost it -- see
                    // Panels/LiveWallpaperPanel.qml's onBlurPctChanged
                    // + scripts/frosted_glass.sh), plus a MultiEffect
                    // (QtQuick.Effects) for in-app wallpaper imagery.
                    //
                    // Sync contract (relied on by Theme.qml/panelBg):
                    // `value: (Theme.uiBgOpacity - 0.15) / 0.85` is a
                    // one-way binding from the theme singleton, so the
                    // slider always reflects the agreed value -- including
                    // external edits to settings.json picked up by
                    // SettingsService's FileView watchChanges reload.
                    // `onMoved` persists through
                    // SettingsService.set("ui_bg_opacity",
                    //     (0.15 + 0.85 * value).toFixed(2)):
                    // optimistic update keeps the UI live mid-drag, while
                    // the per-key coalescing write queue (SettingsService.qml)
                    // emits at most one atomic settings.sh run with the
                    // FINAL value. The (0.15 + 0.85 * value) mapping keeps
                    // the stored range [0.15, 1.0] intact (Theme.uiBgOpacity's
                    // floor preserved at slider 0%); `stepSize: 0.01` pins
                    // the drag granularity to a clean 1%-per-step (same
                    // resolution as the toFixed(2) writes) so
                    // wheel/keyboard/drag all stay in sync and no redundant
                    // sub-percent values are written.
                    SliderRow {
                        id: bgBlurRow
                        Layout.fillWidth: true
                        label: "Background blur"
                        from: 0; to: 1.0
                        stepSize: 0.01
                        value: (Theme.uiBgOpacity - 0.15) / 0.85
                        formatValue: (v) => Math.round(v * 100) + "%"
                        onMoved: SettingsService.set("ui_bg_opacity", (0.15 + 0.85 * value).toFixed(2))
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.panelBorder }

                    Text {
                        text: "Developer"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeLg
                        font.bold: true
                    }

                    SettingRow {
                        label: "Debug"
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: debugMenu = !debugMenu
                        }
                        Text {
                            text: debugMenu ? "Hide developer menu" : "Show developer menu"
                            color: Theme.subtext0
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                        }
                    }

                    SettingRow {
                        visible: debugMenu
                        label: "Log File"
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const logDir = String(Paths.logDir || "").trim()

                                if (logDir.length === 0) {
                                    NotifyService.error(
                                        "Unable to resolve the LiveWallpaperLogs directory."
                                    )
                                    return
                                }

                                logSaveDir = logDir
                                logProc.running = true

                                NotifyService.info(
                                    "Generating system diagnostic log report…"
                                )
                            }
                        }
                        Text {
                            text: "Create log report file"
                            color: Theme.subtext0
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                        }
                    }
                }
            }

        }
    }

    

    property string logSaveDir: ""

    Process {
        id: logProc

        command: [
            "bash",
            Paths.script("profile_backup.sh"),
            logSaveDir,
            "report"
        ]

        running: false

        onExited: (code, status) => {
            if (code !== 0) {
                NotifyService.error(
                    "Failed to create the log report."
                )
                return
            }

            NotifyService.success(
                "Log report created successfully in " +
                logSaveDir
            )
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
