import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Services"

/*
 * MusicDock.qml
 * ----------------
 * Pure visual content for the Music Dock overlay -- Panels/MusicDockOverlay
 * hosts this inside its own layer-shell PanelWindow (see that file for the
 * window/lifecycle side); this component only reads MprisService/
 * CavaService/SettingsService and renders. Kept window-agnostic so it
 * could, in principle, also be dropped into the main panel/a future
 * Caelestia bar module without change.
 *
 * Layout (left -> right), matching the design reference:
 *   album art | title/artist + progress bar | shuffle/prev/play/next/repeat | cava bars
 *
 * Glassmorphism note: this codebase has no Qt5Compat.GraphicalEffects
 * dependency anywhere (see LiveWallpaperPanel's own comment on why), so
 * "blur" here is the same technique already used for panelBg/cardBg --
 * layered semi-transparent Catppuccin Mocha rectangles plus a soft glow
 * border -- not a true GPU blur. Toggling the Blur setting switches
 * between that layered look and a flatter, more opaque background.
 */
Rectangle {
    id: root

    // ── Settings-driven appearance (all optional, all default sanely) ────
    readonly property real cfgOpacity: {
        const v = Number(SettingsService.settings.music_dock_opacity);
        return (v > 0 && v <= 1) ? v : 0.78;
    }
    readonly property int cfgRadius: {
        const v = parseInt(SettingsService.settings.music_dock_radius, 10);
        return (v >= 8 && v <= 40) ? v : 24;
    }
    readonly property bool cfgBlur: SettingsService.settings.music_dock_blur !== false
    readonly property bool cfgGlow: SettingsService.settings.music_dock_glow !== false
    readonly property color cfgAccent: {
        const c = SettingsService.settings.music_dock_accent;
        return (typeof c === "string" && c.length > 0) ? c : Theme.mauve;
    }
    readonly property int cfgArtSize: {
        const v = parseInt(SettingsService.settings.music_dock_art_size, 10);
        return (v >= 36 && v <= 96) ? v : 56;
    }
    readonly property int cfgBarWidth: {
        const v = parseInt(SettingsService.settings.music_dock_bar_width, 10);
        return (v >= 2 && v <= 10) ? v : 3;
    }
    readonly property int cfgBarSpacing: {
        const v = parseInt(SettingsService.settings.music_dock_bar_spacing, 10);
        return (v >= 0 && v <= 8) ? v : 2;
    }
    readonly property int cfgAnimSpeed: {
        const v = parseInt(SettingsService.settings.music_dock_anim_speed, 10);
        return (v >= 30 && v <= 600) ? v : 120;
    }
    readonly property bool cfgCavaEnabled: SettingsService.settings.music_dock_cava_enabled !== false

    radius: cfgRadius
    color: cfgBlur ? Qt.rgba(0.1176, 0.1176, 0.1804, cfgOpacity * 0.86)
                    : Qt.rgba(0.1176, 0.1176, 0.1804, Math.min(cfgOpacity + 0.12, 0.97))
    border.width: 1
    border.color: cfgGlow ? Qt.rgba(root.cfgAccent.r, root.cfgAccent.g, root.cfgAccent.b, 0.45)
                           : Theme.panelBorder

    Behavior on color { ColorAnimation { duration: Theme.durationNormal } }
    Behavior on border.color { ColorAnimation { duration: Theme.durationNormal } }

    // Extra soft translucent layer underneath -- the same "Mica elevation"
    // trick LiveWallpaperPanel's own surface uses, only shown when Blur
    // is on so turning it off genuinely reads as a flatter dock.
    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        z: -1
        visible: root.cfgBlur
        radius: parent.radius + 4
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.35)
    }

    // Pulsing glow border while something is actually playing -- purely
    // decorative, disabled entirely when Glow is off.
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: "transparent"
        border.width: 1
        border.color: root.cfgAccent
        visible: root.cfgGlow && MprisService.isPlaying
        opacity: 0.0
        SequentialAnimation on opacity {
            running: root.cfgGlow && MprisService.isPlaying
            loops: Animation.Infinite
            NumberAnimation { to: 0.55; duration: 1100; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0.0; duration: 1100; easing.type: Easing.InOutSine }
        }
    }

    function _fmtTime(seconds) {
        const s = Math.max(0, Math.floor(seconds || 0));
        const m = Math.floor(s / 60);
        const r = s % 60;
        return m + ":" + (r < 10 ? "0" : "") + r;
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingMd
        spacing: Theme.spacingMd

        // -------------------- ALBUM ART --------------------
        Rectangle {
            id: artFrame
            Layout.preferredWidth: root.cfgArtSize
            Layout.preferredHeight: root.cfgArtSize
            Layout.alignment: Qt.AlignVCenter
            radius: Theme.radiusMd
            color: Theme.surface0
            clip: true

            Image {
                id: artImage
                anchors.fill: parent
                source: MprisService.artUrl || ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                opacity: status === Image.Ready ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: Theme.durationNormal } }
            }

            Image {
                anchors.fill: parent
                anchors.margins: parent.width * 0.18
                source: "../assets/placeholder.png"
                fillMode: Image.PreserveAspectFit
                visible: artImage.status !== Image.Ready
                opacity: 0.6
            }
        }

        // -------------------- TITLE / ARTIST / PROGRESS --------------------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: MprisService.active ? (MprisService.title || "Unknown title") : "Nothing playing"
                color: Theme.text
                font.family: Theme.fontFamilyUi
                font.pixelSize: Theme.fontSizeMd
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: MprisService.active
                text: MprisService.artist || ""
                color: Theme.subtext0
                font.family: Theme.fontFamilyUi
                font.pixelSize: Theme.fontSizeSm
                elide: Text.ElideRight
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: Theme.spacingSm
                visible: MprisService.active

                Text {
                    text: root._fmtTime(MprisService.position)
                    color: Theme.subtext1
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm - 1
                }

                // Restyled progress-bar look, wheel support, big thumb and
                // the generous hit area under the thin visible track are
                // all implemented exactly once in SettingSlider.qml (also
                // used by every MusicDockPanel.qml setting and by
                // StreamingPanel.qml's seek slider) -- no hand-rolled
                // background/handle/wheel-MouseArea here anymore.
                // inLayout: true because this sits directly inside a real
                // RowLayout (unlike SettingRow's plain-Item slot), so the
                // slider relies on Layout.fillWidth for its width instead
                // of anchors. barHeight/trackHeight/thumbSize match
                // SettingSlider.qml's own thin-track defaults now.
                // accentColor passes this dock's own user-configurable
                // accent through instead of the component's Theme.accent
                // default.
                SettingSlider {
                    id: progressSlider
                    inLayout: true
                    barHeight: 24
                    // Was 6/18 -- see StreamingPanel.qml's seekSlider for
                    // the same change; both now match SettingSlider.qml's
                    // thin, hover-reveals-thumb defaults.
                    trackHeight: 3
                    thumbSize: 11
                    accentColor: root.cfgAccent
                    enabled: MprisService.seekable
                    from: 0
                    to: Math.max(MprisService.duration, 0.001)

                    // Same pattern as PlaybackService's stream seek slider:
                    // real position is pushed in imperatively (not a plain
                    // binding) so it keeps tracking after the user's first
                    // drag, and only while the handle isn't currently held.
                    Connections {
                        target: MprisService
                        function onPositionChanged() {
                            if (!progressSlider.pressed) progressSlider.value = MprisService.position;
                        }
                        function onDurationChanged() {
                            if (!progressSlider.pressed) progressSlider.value = MprisService.position;
                        }
                    }
                    Component.onCompleted: value = MprisService.position

                    onMoved: MprisService.seek(value)
                }

                Text {
                    text: root._fmtTime(MprisService.duration)
                    color: Theme.subtext1
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm - 1
                }
            }
        }

        // -------------------- TRANSPORT CONTROLS --------------------
        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: Theme.spacingXs
            visible: MprisService.active

            IconButton {
                text: "⇄"
                fontSize: Theme.fontSizeMd
                active: MprisService.shuffle
                accentColor: root.cfgAccent
                implicitWidth: 30; implicitHeight: 30
                onClicked: MprisService.toggleShuffle()
            }
            IconButton {
                text: "⏮"
                fontSize: Theme.fontSizeMd
                accentColor: root.cfgAccent
                implicitWidth: 32; implicitHeight: 32
                onClicked: MprisService.previous()
            }

            // Circular accent play/pause button -- the one visually
            // "primary" control, matching the reference image's filled
            // purple circle.
            Rectangle {
                id: playBtn
                implicitWidth: 40
                implicitHeight: 40
                radius: width / 2
                color: root.cfgAccent
                scale: playMouse.pressed ? 0.92 : (playMouse.containsMouse ? 1.05 : 1.0)
                Behavior on scale {
                    NumberAnimation { duration: Theme.durationFast; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                }

                Text {
                    anchors.centerIn: parent
                    text: MprisService.isPlaying ? "⏸" : "▶"
                    color: Theme.onAccent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeLg
                }

                MouseArea {
                    id: playMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: MprisService.playPause()
                }
            }

            IconButton {
                text: "⏭"
                fontSize: Theme.fontSizeMd
                accentColor: root.cfgAccent
                implicitWidth: 32; implicitHeight: 32
                onClicked: MprisService.next()
            }
            IconButton {
                // Repeat cycle: Off → Repeat One → Repeat All → Off
                // Use distinct glyphs so the active mode is immediately visible.
                text: MprisService.loopStatus === "Track" ? "󰑘" : "󰑖"
                fontSize: Theme.fontSizeMd
                active: MprisService.loopStatus !== "None"
                accentColor: root.cfgAccent
                implicitWidth: 30; implicitHeight: 30
                onClicked: MprisService.cycleLoop()
            }
        }

        // -------------------- CAVA VISUALIZER --------------------
        // PHASE 3: two render styles now share this slot, switched by
        // CavaService.visualizerStyle -- both read the exact same
        // CavaService.bars frame data, so there is still only ever one
        // cava pipeline (start()/stop() in CavaService.qml are
        // completely unaffected by this).
        Item {
            id: visualizer
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: CavaService.barCount * (root.cfgBarWidth + root.cfgBarSpacing)
            Layout.preferredHeight: (CavaService.visualizerStyle === "waveform" && CavaService.floatingWaveform)
                ? root.cfgArtSize * 1.15
                : root.cfgArtSize * 0.8
            visible: root.cfgCavaEnabled && CavaService.available

            // ── Media-state gating (fix) ────────────────────────────────
            // CavaService's `bars` is raw, continuous system-audio capture
            // -- it has no idea what MPRIS is doing, so left unguarded the
            // strip keeps showing whatever it last captured even while the
            // current track is paused/stopped (frozen or stale levels).
            // `effectiveBars` is the ONE place that gets fixed: it reads
            // the exact same live CavaService.bars array (still the one
            // shared cava pipeline -- no second process, no watcher, no
            // fake data) but reports it as empty whenever MPRIS isn't
            // actively playing. Both render paths below already treat a
            // short/empty bars array as "level 0 for this index" (see the
            // Repeater delegate's `level` and the waveform's `_path()`),
            // so this alone makes paused/stopped read as the same
            // baseline/inactive strip they already draw for "no data yet"
            // -- no new visual state, no animation change, no styling
            // change. Purely a reactive property binding on the existing
            // MprisService.isPlaying, so play/pause/resume/track-change
            // all take effect on the very next frame with zero polling.
            readonly property var effectiveBars: MprisService.isPlaying ? CavaService.bars : []

            // -------------------- BARS (original, unchanged) --------------------
            Row {
                anchors.fill: parent
                visible: CavaService.visualizerStyle === "bars"
                spacing: root.cfgBarSpacing
                layoutDirection: Qt.LeftToRight

                Repeater {
                    model: CavaService.barCount
                    delegate: Rectangle {
                        required property int index
                        readonly property int level: (visualizer.effectiveBars.length > index) ? visualizer.effectiveBars[index] : 0
                        width: root.cfgBarWidth
                        anchors.bottom: parent.bottom
                        radius: width / 2
                        height: Math.max(2, (level / 255) * visualizer.height)
                        // Manual/Random/Rainbow -- see CavaService.qml's
                        // "Visualizer color system" header. Only this fill
                        // color changed; height/opacity/animation are the
                        // same as before.
                        color: CavaService.visualizerColor
                        opacity: 0.55 + 0.45 * (level / 255)
                        Behavior on height { NumberAnimation { duration: root.cfgAnimSpeed; easing.type: Easing.OutQuad } }
                        Behavior on opacity { NumberAnimation { duration: root.cfgAnimSpeed } }
                    }
                }
            }

            // -------------------- WAVEFORM (new) --------------------
            // Same bar levels, drawn as a smooth mirrored line around a
            // center baseline instead of discrete bars. When
            // floatingWaveform is on, the line is drawn twice (a wider,
            // dimmer pass behind a thinner, brighter one) for a soft
            // "glow" look without pulling in Qt5Compat.GraphicalEffects
            // (same no-extra-module approach LiveWallpaperPanel.qml's
            // own drop-shadow substitute already uses).
            Canvas {
                id: waveCanvas
                anchors.fill: parent
                visible: CavaService.visualizerStyle === "waveform"
                readonly property bool floating: CavaService.floatingWaveform
                readonly property var levels: visualizer.effectiveBars
                readonly property color waveColor: CavaService.visualizerColor

                onLevelsChanged: requestPaint()
                onWaveColorChanged: requestPaint()
                onFloatingChanged: requestPaint()

                function _path(ctx, ampScale) {
                    const n = CavaService.barCount;
                    const mid = height / 2;
                    ctx.beginPath();
                    for (let i = 0; i < n; i++) {
                        const level = (levels.length > i) ? levels[i] : 0;
                        const amp = (level / 255) * mid * ampScale;
                        const x = (n <= 1) ? 0 : (i / (n - 1)) * width;
                        const y = mid - amp;
                        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                    }
                    for (let i = n - 1; i >= 0; i--) {
                        const level = (levels.length > i) ? levels[i] : 0;
                        const amp = (level / 255) * mid * ampScale;
                        const x = (n <= 1) ? 0 : (i / (n - 1)) * width;
                        const y = mid + amp;
                        ctx.lineTo(x, y);
                    }
                    ctx.closePath();
                }

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    if (floating) {
                        ctx.globalAlpha = 0.30;
                        ctx.fillStyle = waveColor;
                        _path(ctx, 1.35);
                        ctx.fill();
                    }
                    ctx.globalAlpha = 0.85;
                    ctx.fillStyle = waveColor;
                    _path(ctx, 1.0);
                    ctx.fill();
                }
            }
        }
    }
}
