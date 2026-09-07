import QtQuick
import "../Config"
import "../Services"

/*
 * WallpaperCard.qml
 * --------------------
 * One tile in the grid. Clicking the thumbnail or the Apply button plays
 * that wallpaper at the currently selected resolution/fps. The star
 * toggles favorite state. The meta row shows the *source* video's native
 * fps/resolution/duration (from ffprobe, read-only/informational) — not
 * to be confused with the playback resolution/fps selector, which caps
 * what's rendered.
 */
Item {
    id: root

    property var wp
    readonly property bool isCurrent: PlaybackService.currentPath === wp.path

    // PHASE 3 -- large-thumbnail toggle (see WallpaperGrid.qml/
    // WallpapersModeContent.qml). Scales the thumbnail + card footprint
    // up; metadata/name/buttons keep the same layout, just wider.
    property bool large: false
    // Shared by GIF mode so both tabs render the same card geometry.
    property bool gifAsset: false
    property bool showPreviewButton: true

    readonly property int thumbW: large ? 288 : 190
    readonly property int thumbH: large ? 168 : 110
    readonly property bool hasTags: Array.isArray(wp.tags) && wp.tags.length > 0

    signal previewRequested(var wp)
    signal collectionRequested(var wp)
    signal favoriteToggled(string path)

    implicitWidth: thumbW
    // thumb + name/favorite/apply row (34) + metadata row (16) + tags
    // row (22, only when present) + spacing between each visible row.
    implicitHeight: thumbH + 34 + 16 + (hasTags ? 22 : 0) + Theme.spacingSm * (hasTags ? 3 : 2)

    Column {
        anchors.fill: parent
        spacing: Theme.spacingSm

        // -------------------- THUMBNAIL --------------------
        Rectangle {
            id: thumbFrame
            width: root.thumbW
            height: root.thumbH
            radius: Theme.radiusMd
            color: Theme.surface0
            // ── Smart Accent Color: glow border on hover ─────────────
            // Previously the border only showed when the card was the current
            // wallpaper (isCurrent). Now hover also activates the accent border
            // so users can immediately see which card is being pointed at,
            // synchronised with Theme.accent (Smart Accent Color runtime).
            border.width: (root.isCurrent || thumbMouse.containsMouse) ? 2 : 0
            border.color: Theme.accent
            clip: true

            // Same combined-hover reasoning as the buttons below: without
            // OR-ing in the buttons' own hover, this scale would flicker
            // in/out as the cursor crosses onto "+"/"🔍".
            scale: thumbMouse.pressed ? 0.97
                : (thumbMouse.containsMouse || previewBtn.hovered || collectionBtn.hovered) ? 1.02 : 1.0
            Behavior on scale {
                NumberAnimation { duration: Theme.durationFast; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
            }
            Behavior on border.width {
                NumberAnimation { duration: Theme.durationFast }
            }
            // Smooth 450ms cross-fade whenever the accent color itself
            // changes (new wallpaper applied while this card is hovered/
            // current) instead of the border color snapping instantly.
            Behavior on border.color {
                ColorAnimation { duration: Theme.durationAccentGlow; easing.type: Easing.InOutQuad }
            }

            Image {
                id: thumb
                anchors.fill: parent
                source: wp.thumb ? "file://" + wp.thumb : (root.gifAsset && wp.path ? "file://" + wp.path : "")
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                // Decode at the on-screen size instead of the thumbnail's
                // native resolution -- avoids decoding/holding a full-size
                // bitmap in memory for every card in the grid, which adds
                // up fast once there are dozens of wallpapers visible.
                sourceSize.width: root.thumbW
                sourceSize.height: root.thumbH
                opacity: status === Image.Ready ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: Theme.durationNormal } }
            }

            // Placeholder while the thumbnail loads or is missing
            Rectangle {
                anchors.fill: parent
                visible: thumb.status !== Image.Ready
                color: Theme.surface0
                Text {
                    anchors.centerIn: parent
                    text: "󰈰"
                    font.family: Theme.fontFamily
                    font.pixelSize: 28
                    color: Theme.overlay0
                }
            }

            // Click-to-apply MouseArea for the whole thumbnail. Declared
            // BEFORE the buttons below (in QML, later siblings paint and
            // hit-test on top of earlier ones) so the "🔍" and "+" buttons
            // actually receive their own clicks instead of this MouseArea
            // swallowing every click in the thumbnail -- including taps
            // square on top of those buttons -- as "apply wallpaper".
            MouseArea {
                id: thumbMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: PlaybackService.apply(wp.path)
            }

            // Now-playing pulse indicator
            Rectangle {
                visible: root.isCurrent
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 6
                width: 10
                height: 10
                radius: 5
                color: Theme.accent
                SequentialAnimation on opacity {
                    running: root.isCurrent
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                }
            }

            // PHASE 3 -- Preview button, only visible on hover so it
            // doesn't compete with the click-to-apply thumbnail. Opens
            // WallpaperPreviewDialog (owned by the page, not this card --
            // see WallpapersModeContent.qml) via previewRequested. Declared
            // after thumbMouse above so it sits on top and gets first
            // claim on clicks in its corner of the thumbnail. Visibility
            // is thumbMouse's hover OR this button's own hover (see
            // IconButton.hovered) so it doesn't blink out from under the
            // cursor the instant the cursor reaches it -- see thumbFrame's
            // hoverAny doc comment above for why that combination matters.
            IconButton {
                id: previewBtn
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 6
                visible: root.showPreviewButton && (thumbMouse.containsMouse || hovered || collectionBtn.hovered)
                text: "🔍"
                fontSize: Theme.fontSizeSm
                implicitWidth: 28
                implicitHeight: 28
                onClicked: root.previewRequested(root.wp)
            }

            // Add-to-collection ("+"), same hover-only visibility as the
            // preview button above -- opens AddToCollectionDialog (see
            // WallpapersModeContent.qml) so this wallpaper can be filed
            // into one or more named groups (Anime/Nature/...). Also
            // declared after thumbMouse so this actually opens the dialog
            // instead of being swallowed as an "apply" click.
            IconButton {
                id: collectionBtn
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 6
                visible: thumbMouse.containsMouse || hovered || previewBtn.hovered
                text: "+"
                fontSize: Theme.fontSizeSm
                implicitWidth: 28
                implicitHeight: 28
                onClicked: root.collectionRequested(root.wp)
            }
        }

        // -------------------- NAME + FAVORITE + APPLY --------------------
        Row {
            width: root.thumbW
            spacing: Theme.spacingSm

            IconButton {
                text: wp.favorite ? "★" : "☆"
                active: wp.favorite === true
                accentColor: Theme.yellow
                width: 32
                implicitWidth: 32
                fontSize: Theme.fontSizeLg
                onClicked: root.gifAsset ? root.favoriteToggled(wp.path) : WallpaperService.toggleFavorite(wp.path)
            }

            Text {
                width: root.thumbW - 32 - 60 - Theme.spacingSm * 2
                text: wp.name
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }

            // ── Smart Accent Color: border frame for the Apply button ─────
            // Wraps the "Apply" IconButton in its own border frame, synced to
            // Theme.accent and glowing at the same time as the Card's border
            // on hover (thumbMouse in the THUMBNAIL block above), rather
            // than relying only on the button's own hover state.
            Rectangle {
                id: applyGlow
                width: applyBtn.implicitWidth
                height: applyBtn.implicitHeight
                radius: Theme.radiusMd
                color: "transparent"
                border.width: (thumbMouse.containsMouse || applyBtn.hovered) ? 1.5 : 0
                border.color: Theme.accent

                Behavior on border.width {
                    NumberAnimation { duration: Theme.durationFast }
                }
                Behavior on border.color {
                    ColorAnimation { duration: Theme.durationAccentGlow; easing.type: Easing.InOutQuad }
                }

                IconButton {
                    id: applyBtn
                    anchors.centerIn: parent
                    text: "Apply"
                    fontSize: Theme.fontSizeSm
                    onClicked: PlaybackService.apply(wp.path)
                }
            }
        }

        // -------------------- METADATA ROW --------------------
        // Kept visible for every asset type so GIF and video cards retain
        // identical vertical geometry. Missing GIF metadata uses fixed-width
        // fallbacks instead of collapsing the row.
        Row {
            width: root.thumbW
            spacing: Theme.spacingSm
            visible: true

            Text {
                text: (wp.isGif === true || root.gifAsset)
                    ? "Animated"
                    : (Number(wp.fps) > 0
                        ? String(wp.fps) + "fps"
                        : "-- fps")
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }
            Text {
                text: wp.resolution && String(wp.resolution).length > 0
                    ? String(wp.resolution)
                    : "--x--"
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }
            Text {
                text: (wp.isGif === true || root.gifAsset)
                    ? "--:--"
                    : (wp.duration && String(wp.duration).length > 0
                        ? String(wp.duration)
                        : "--:--")
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }
        }

        // -------------------- TAGS (PHASE 3) --------------------
        Flow {
            width: root.thumbW
            spacing: 4
            visible: Array.isArray(wp.tags) && wp.tags.length > 0

            Repeater {
                model: Array.isArray(wp.tags) ? wp.tags.slice(0, root.large ? 6 : 3) : []
                delegate: Rectangle {
                    radius: Theme.radiusSm
                    color: Theme.surface0
                    height: 16
                    width: tagLabel.implicitWidth + 10
                    Text {
                        id: tagLabel
                        anchors.centerIn: parent
                        text: modelData
                        color: Theme.subtext0
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                    }
                }
            }
        }
    }
}
