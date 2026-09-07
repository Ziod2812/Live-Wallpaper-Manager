import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "../Config"
import "../Services"

/*
 * WallpaperPreviewDialog.qml
 * -----------------------------
 * PHASE 3 -- "Preview" + "Large thumbnails" from the Wallpaper Library
 * requirement. Same scrim + centered card shape as ConfirmDialog.qml,
 * but sized for a large image + metadata instead of a Yes/No prompt.
 *
 * Deliberately shows the existing thumbnail file large (Image,
 * PreserveAspectFit) rather than actually playing the video -- doing
 * that would mean spawning a second mpv/mpvpaper instance just for a
 * preview, which the brief explicitly rules out ("No extra mpvpaper").
 *
 * Usage: set `wp` to a wallpaper object (same shape as WallpaperCard's
 * `wp`), then `open = true`.
 */
Item {
    id: root

    property bool open: false
    property var wp: null

    signal closed()

    visible: opacity > 0
    opacity: open ? 1 : 0
    z: 1000

    Behavior on opacity {
        NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutCubic }
    }

    function _close() {
        root.open = false;
        root.closed();
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.6)
        MouseArea {
            anchors.fill: parent
            onClicked: root._close()
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(640, root.width - Theme.spacingXl * 2)
        height: Math.min(680, root.height - Theme.spacingXl * 2)
        radius: Theme.radiusLg
        color: Theme.panelBg
        border.width: 1
        border.color: Theme.panelBorder

        scale: root.open ? 1.0 : 0.94
        Behavior on scale {
            NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        }

        MouseArea { anchors.fill: parent } // absorb clicks, don't fall through to scrim

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacingLg
            spacing: Theme.spacingMd
            visible: root.wp !== null

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: root.wp ? root.wp.name : ""
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeLg
                    font.bold: true
                    elide: Text.ElideRight
                }
                IconButton {
                    text: "✕"
                    accentColor: Theme.danger
                    onClicked: root._close()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radiusMd
                color: Theme.surface0
                clip: true

                Image {
                    id: thumb
                    anchors.fill: parent
                    source: (root.wp && root.wp.thumb) ? "file://" + root.wp.thumb : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                }

                // REAL GPU blur of the wallpaper imagery -- MultiEffect
                // from QtQuick.Effects (ShaderEffectSource-backed, Qt >=
                // 6.5; no Qt5Compat.GraphicalEffects needed). blurMax =
                // Theme.blurRadius, which is bound inversely to the
                // "Background blur" slider and pins to its MAXIMUM (64px)
                // whenever the slider is at/above the 50% blur mark
                // (uiBgOpacity <= 0.5) -- so this preview shows exactly
                // how completely the wallpaper is smeared by the
                // frosted-glass look. (The LIVE desktop is blurred by
                // the COMPOSITOR instead -- scripts/frosted_glass.sh --
                // because the QML scene never renders the wallpaper; see
                // Panels/LiveWallpaperPanel.qml's frosted-glass section.)
                MultiEffect {
                    anchors.fill: thumb
                    source: thumb
                    blurEnabled: true
                    blur: 1.0
                    blurMax: Math.max(Theme.blurRadius, 1)
                }
            }

            // -------------------- METADATA --------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingLg

                Text {
                    text: root.wp ? ((root.wp.resolution || "—") + " · " + (root.wp.fps || 0) + "fps · " + (root.wp.duration || "—")) : ""
                    color: Theme.subtext0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }
                Text {
                    // PHASE 4 -- #25 video metadata: codec was extracted by
                    // metadata.sh/wallpaper_list.sh already but never shown.
                    text: root.wp && root.wp.codec ? root.wp.codec.toUpperCase() : ""
                    color: Theme.subtext0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }
                Text {
                    text: root.wp ? (root.wp.filesize_human || "") : ""
                    color: Theme.subtext0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 4
                visible: root.wp && Array.isArray(root.wp.tags) && root.wp.tags.length > 0

                Repeater {
                    model: (root.wp && Array.isArray(root.wp.tags)) ? root.wp.tags : []
                    delegate: Rectangle {
                        radius: Theme.radiusSm
                        color: Theme.surface0
                        height: 20
                        width: tagRow.implicitWidth + 16
                        RowLayout {
                            id: tagRow
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                text: modelData
                                color: Theme.subtext0
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                            }
                            // PHASE 4 -- #22 remove a tag from this wallpaper.
                            Text {
                                text: "✕"
                                color: Theme.subtext0
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (root.wp) WallpaperService.removeTag(root.wp.path, modelData)
                                }
                            }
                        }
                    }
                }
            }

            // -------------------- ADD TAG --------------------
            // PHASE 4 -- #22 "Assign tags to a wallpaper". Tags could already be
            // displayed and filtered on (TagFilterBar), but there was no
            // way to actually assign one -- this closes that gap.
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSm
                visible: root.wp !== null

                Rectangle {
                    Layout.fillWidth: true
                    height: 28
                    radius: Theme.radiusSm
                    color: Theme.surface0

                    TextInput {
                        id: newTagInput
                        anchors.fill: parent
                        anchors.margins: 6
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        selectByMouse: true
                        clip: true

                        Text {
                            text: "Add tag…"
                            color: Theme.subtext0
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            visible: newTagInput.length === 0
                        }

                        Keys.onReturnPressed: addTagBtn.clicked()
                        Keys.onEnterPressed: addTagBtn.clicked()
                    }
                }
                IconButton {
                    id: addTagBtn
                    text: "+ Add"
                    fontSize: Theme.fontSizeSm
                    onClicked: {
                        if (!root.wp || newTagInput.text.trim().length === 0) return;
                        WallpaperService.addTag(root.wp.path, newTagInput.text);
                        newTagInput.text = "";
                    }
                }
            }

            // -------------------- PERFORMANCE PROFILE --------------------
            // Per-wallpaper FPS/resolution override (Services/WallpaperProfileService.qml,
            // #14 "Per-wallpaper performance profile"). GPU decode mode is
            // deliberately not offered here -- see that service's header
            // comment for why (it would require killing/relaunching the
            // persistent mpv player on every switch, which breaks the
            // project's "never kill mpv on a normal switch" contract).
            Rectangle {
                Layout.fillWidth: true
                radius: Theme.radiusMd
                color: Theme.surface0
                implicitHeight: profileCol.implicitHeight + Theme.spacingMd * 2
                visible: root.wp !== null

                ColumnLayout {
                    id: profileCol
                    anchors.fill: parent
                    anchors.margins: Theme.spacingMd
                    spacing: Theme.spacingSm

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: "⚙ Performance profile"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: true
                        }
                        IconButton {
                            text: "Clear"
                            fontSize: Theme.fontSizeSm
                            visible: root.wp && WallpaperProfileService.hasWallpaperProfile(root.wp.path)
                            onClicked: if (root.wp) WallpaperProfileService.clearWallpaperProfile(root.wp.path)
                        }
                    }

                    ProfileOptionRow {
                        label: "FPS"
                        currentValue: root.wp ? (WallpaperProfileService.wallpaperProfile(root.wp.path).fps || "") : ""
                        options: [
                            { value: "", text: "Auto" },
                            { value: "15", text: "15" },
                            { value: "24", text: "24" },
                            { value: "30", text: "30" },
                            { value: "60", text: "60" }
                        ]
                        onSelected: (value) => {
                            if (!root.wp) return;
                            const res = WallpaperProfileService.wallpaperProfile(root.wp.path).resolution || "";
                            WallpaperProfileService.setWallpaperProfile(root.wp.path, value, res);
                        }
                    }

                    ProfileOptionRow {
                        label: "Resolution"
                        currentValue: root.wp ? (WallpaperProfileService.wallpaperProfile(root.wp.path).resolution || "") : ""
                        options: [
                            { value: "", text: "Auto" },
                            { value: "480p", text: "480p" },
                            { value: "720p", text: "720p" },
                            { value: "1080p", text: "1080p" },
                            { value: "original", text: "Original" }
                        ]
                        onSelected: (value) => {
                            if (!root.wp) return;
                            const fps = WallpaperProfileService.wallpaperProfile(root.wp.path).fps || "";
                            WallpaperProfileService.setWallpaperProfile(root.wp.path, fps, value);
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Applies whenever this wallpaper plays. Thermal/Adaptive/Battery protection can still cap FPS lower."
                        color: Theme.subtext0
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        wrapMode: Text.WordWrap
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSm

                IconButton {
                    text: (root.wp && root.wp.favorite) ? "★ Favorited" : "☆ Favorite"
                    active: root.wp && root.wp.favorite === true
                    accentColor: Theme.yellow
                    onClicked: if (root.wp) WallpaperService.toggleFavorite(root.wp.path)
                }

                Item { Layout.fillWidth: true }

                IconButton {
                    text: "▶ Apply"
                    bold: true
                    accentColor: Theme.success
                    onClicked: {
                        if (root.wp) PlaybackService.apply(root.wp.path);
                        root._close();
                    }
                }
            }
        }
    }
}
