import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Services"
import "../Components"

/*
 * PerformancePage.qml
 * -----------------------
 * Performance settings: Smart Playback, GPU selection, system stats,
 * and cache management.
 *
 * PHASE 3 -- added SystemStatsPanel (CPU/RAM/Processes -- see the new,
 * read-only SystemStatsService) and a Cache section reusing
 * CacheService exactly as SettingsPage.qml already does (no duplicated
 * service, no new Clear Cache logic -- just a second place it's
 * surfaced, matching Ziod's own request to see Cache on THIS page).
 *
 * GPU card -- the GPU Switching feature's UI, moved here from Toolbar.qml.
 * Reuses Services/GPUManagerService.qml and Components/GpuSelector.qml
 * unmodified (see Components/GpuPanel.qml); the Toolbar's old inline
 * selector is gone, this card is now the only place it lives.
 *
 * "FPS" here is the currently CONFIGURED playback target
 * (PlaybackService.selectedFps/selectedResolution -- already-existing
 * data), not a new live frame-rate meter: getting a true live FPS
 * reading would mean querying mpv's IPC socket for render stats, which
 * risks touching the playback pipeline the brief says to leave alone.
 * See SystemStatsPanel.qml's own comment on this same point.
 *
 * SystemStatsService.active is gated to this page's own lifecycle, so
 * its 3s poll only runs while this page is actually open -- zero cost
 * the rest of the time the app is up.
 *
 * Root is a plain Item wrapping the scrollable Flickable + the
 * ConfirmDialog overlay as siblings (not dialog-inside-Flickable, which
 * would size/position the dialog against scrollable content instead of
 * the viewport -- same fix already applied in WallpapersModeContent.qml).
 */
Item {
    id: root

    function focusSettingSearch(query) {
        const q = String(query || "").trim().toLowerCase();
        if (!q.length)
            return;

        const matches = [
            { text: "gpu gpu mode gpu switching graphics card graphics render", y: gpuPanel.y },
            { text: "cache thumbnails clear cache", y: cacheContent.parent.y },
            { text: "smart playback fullscreen lock sleep battery game", y: smartPlaybackPanel.y },
            { text: "cpu ram processes system stats performance fps resolution", y: 0 }
        ];

        for (let i = 0; i < matches.length; i++) {
            if (matches[i].text.indexOf(q) !== -1) {
                const maxY = Math.max(0, flick.contentHeight - flick.height);
                flick.contentY = Math.min(Math.max(0, matches[i].y), maxY);
                return;
            }
        }
    }

    Component.onCompleted: {
        SystemStatsService.active = true;
        GPUManagerService.statsActive = true;
    }
    Component.onDestruction: {
        SystemStatsService.active = false;
        GPUManagerService.statsActive = false;
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

            SystemStatsPanel {
                Layout.fillWidth: true
            }

            // ── Cache ────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                radius: Theme.radiusLg
                color: Theme.cardBg
                border.width: 1
                border.color: Theme.panelBorder
                implicitHeight: cacheContent.implicitHeight + Theme.spacingLg * 2

                ColumnLayout {
                    id: cacheContent
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLg
                    spacing: Theme.spacingMd

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: "🗄 Cache"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeLg
                            font.bold: true
                        }
                        Text {
                            text: CacheService.thumbnailCount + " thumbnails · " + CacheService.thumbnailSizeLabel
                            color: Theme.subtext0
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        IconButton {
                            text: CacheService.clearing ? "Clearing…" : "Clear Cache"
                            fontSize: Theme.fontSizeSm
                            accentColor: Theme.danger
                            onClicked: cacheConfirm.open = true
                        }
                    }
                }
            }

            GpuPanel {
                id: gpuPanel
                Layout.fillWidth: true
            }

            SmartPlaybackPanel {
                id: smartPlaybackPanel
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                onCloseRequested: {}
            }
        }
    }

    ConfirmDialog {
        id: cacheConfirm
        anchors.fill: parent
        title: "Clear Cache?"
        message: "Removes thumbnails and other regenerable cache files. Settings, favorites, playlists, history, and your wallpapers are never touched."
        confirmText: "Clear Cache"
        danger: false
        onAccepted: { open = false; CacheService.clear(); }
        onCancelled: open = false
    }
}
