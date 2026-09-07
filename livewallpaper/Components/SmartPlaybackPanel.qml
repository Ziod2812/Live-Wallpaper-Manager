import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Services"

/*
 * SmartPlaybackPanel.qml
 * ----------------------
 * Settings page for Smart Playback
 * (Services/SmartPlaybackService.qml + PlaybackService's full
 * stop/restore primitives -- mpvpaper is genuinely terminated and
 * relaunched, not frozen in place). Same toggle-panel shape as
 * MusicDockPanel.qml/
 * reusable panel components (RowLayout header with a close button, ColumnLayout body
 * inside a Flickable) so it slots into LiveWallpaperPanel exactly like
 * they do.
 *
 * Every control writes through SmartPlaybackService.setEnabled()/
 * setOption()/setScope(), which are themselves thin wrappers around
 * SettingsService.set("smart_playback_*", value) -- the same generic,
 * arbitrary-key persistence every other setting in this project already
 * uses. All reads come from SmartPlaybackService's own guarded-fallback
 * properties, so this file has no settings knowledge of its own and
 * can't drift out of sync with the service that actually acts on them.
 *
 * Every row below the master toggle is disabled + dimmed whenever Smart
 * Playback itself is off, per the "(only enabled when Smart Playback is
 * ON)" requirement -- flipping the master toggle off also fully stops
 * SmartPlaybackService's background work (see that file), so this is
 * both a visual and a functional gate.
 */
Rectangle {
    id: root
    radius: Theme.radiusLg
    color: Theme.cardBg
    border.width: 1
    border.color: Theme.panelBorder

    // Fixed footprint, same reasoning as MusicDockPanel.qml -- do not
    // size this to content.
    implicitHeight: 420

    signal closeRequested()

    readonly property bool spEnabled: SmartPlaybackService.enabled
    readonly property bool multiMonitor: MultiMonitorService.monitors.length > 1

    readonly property string statusText: {
        if (!root.spEnabled) return "Disabled";
        if (SmartPlaybackService.paused) {
            return SmartPlaybackService.pauseReason
                ? "Stopped \u2014 " + SmartPlaybackService.pauseReason
                : "Stopped";
        }
        return "Playing";
    }
    readonly property color statusColor: {
        if (!root.spEnabled) return Theme.overlay0;
        return SmartPlaybackService.paused ? Theme.peach : Theme.success;
    }

    ColumnLayout {
        id: shell
        anchors.fill: parent
        anchors.margins: Theme.spacingLg
        spacing: Theme.spacingSm

        // ── Header (fixed -- outside the Flickable, never scrolls) ─────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            Text {
                text: "\u23EF  Smart Playback"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMd
                font.bold: true
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                width: 8; height: 8; radius: 4
                color: root.statusColor
            }
            Text {
                text: root.statusText
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
            }
            IconButton {
                text: "\u2715"
                fontSize: Theme.fontSizeMd
                onClicked: root.closeRequested()
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.panelBorder }

        // ── Scrollable body ──────────────────────────────────────────────
        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: 1500
            maximumFlickVelocity: 2500
            contentWidth: width
            contentHeight: content.implicitHeight

            ColumnLayout {
                id: content
                width: flick.width
                spacing: Theme.spacingSm

                // ── Master toggle ────────────────────────────────────────────
                SettingRow {
                    label: "Enable Smart Playback"
                    ToggleSwitch {
                        checked: root.spEnabled
                        onToggled: SmartPlaybackService.setEnabled(!root.spEnabled)
                    }
                }
                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: -Theme.spacingXs
                    text: root.spEnabled
                        ? "Wallpapers stop completely (CPU/GPU usage drops to ~0) and restore automatically afterward."
                        : "Wallpapers always keep playing -- no detection, no CPU overhead."
                    color: Theme.subtext0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    wrapMode: Text.WordWrap
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.panelBorder }

                // ── Stop conditions ──────────────────────────────────────────
                Text {
                    text: "Stop when..."
                    color: Theme.subtext0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    font.bold: true
                }
                SettingRow {
                    label: "Fullscreen app is active"
                    enabled: root.spEnabled
                    opacity: root.spEnabled ? 1.0 : 0.5
                    ToggleSwitch {
                        checked: SmartPlaybackService.pauseOnFullscreen
                        onToggled: SmartPlaybackService.setOption("smart_playback_pause_fullscreen", !SmartPlaybackService.pauseOnFullscreen)
                    }
                }
                SettingRow {
                    label: "On battery"
                    enabled: root.spEnabled
                    opacity: root.spEnabled ? 1.0 : 0.5
                    ToggleSwitch {
                        checked: SmartPlaybackService.pauseOnBattery
                        onToggled: SmartPlaybackService.setOption("smart_playback_pause_battery", !SmartPlaybackService.pauseOnBattery)
                    }
                }
                SettingRow {
                    label: "Monitor is sleeping"
                    enabled: root.spEnabled
                    opacity: root.spEnabled ? 1.0 : 0.5
                    ToggleSwitch {
                        checked: SmartPlaybackService.pauseOnMonitorSleep
                        onToggled: SmartPlaybackService.setOption("smart_playback_pause_monitor_sleep", !SmartPlaybackService.pauseOnMonitorSleep)
                    }
                }
                SettingRow {
                    label: "Screen is locked"
                    enabled: root.spEnabled
                    opacity: root.spEnabled ? 1.0 : 0.5
                    ToggleSwitch {
                        checked: SmartPlaybackService.pauseOnScreenLock
                        onToggled: SmartPlaybackService.setOption("smart_playback_pause_screen_lock", !SmartPlaybackService.pauseOnScreenLock)
                    }
                }
                SettingRow {
                    label: "Gaming"
                    enabled: root.spEnabled
                    opacity: root.spEnabled ? 1.0 : 0.5
                    ToggleSwitch {
                        checked: SmartPlaybackService.pauseWhileGaming
                        onToggled: SmartPlaybackService.setOption("smart_playback_pause_gaming", !SmartPlaybackService.pauseWhileGaming)
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.panelBorder }

                // ── Multi-monitor scope ──────────────────────────────────────
                SettingRow {
                    label: "Multi-monitor"
                    visible: root.multiMonitor
                    enabled: root.spEnabled
                    opacity: root.spEnabled ? 1.0 : 0.5
                    RowLayout {
                        spacing: Theme.spacingXs
                        IconButton {
                            text: "All monitors"
                            fontSize: Theme.fontSizeSm
                            active: SmartPlaybackService.scope === "all"
                            onClicked: SmartPlaybackService.setScope("all")
                        }
                        IconButton {
                            text: "Only affected monitor"
                            fontSize: Theme.fontSizeSm
                            active: SmartPlaybackService.scope === "focused"
                            onClicked: SmartPlaybackService.setScope("focused")
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: root.multiMonitor && root.spEnabled
                    text: "Applies to the fullscreen-app and monitor-sleep conditions -- battery, lock, and gaming always pause every monitor."
                    color: Theme.subtext0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    wrapMode: Text.WordWrap
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.panelBorder; visible: root.multiMonitor }

                // ── Notifications ─────────────────────────────────────────────
                SettingRow {
                    label: "Stop/restore notifications"
                    enabled: root.spEnabled
                    opacity: root.spEnabled ? 1.0 : 0.5
                    ToggleSwitch {
                        checked: SmartPlaybackService.notificationsOn
                        onToggled: SmartPlaybackService.setOption("smart_playback_notifications", !SmartPlaybackService.notificationsOn)
                    }
                }
            }
        }
    }
}
