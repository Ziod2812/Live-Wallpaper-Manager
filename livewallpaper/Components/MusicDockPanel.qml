import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQCB
import "../Config"
import "../Services"

// QtQuick.Controls.Basic gives us QQCB.ScrollBar with a fully custom
// contentItem/background, which is what makes the thin, auto-hiding
// scrollbar below possible (the styled controls set doesn't expose that
// without a style plugin).

/*
 * MusicDockPanel.qml
 * ----------------------
 * Settings page for the Music Dock overlay (Panels/MusicDockOverlay.qml +
 * Components/MusicDock.qml). Same toggle-panel shape as MusicDockPanel.qml
 * (RowLayout header with a close button, ColumnLayout body) so it slots
 * into LiveWallpaperPanel exactly like the other manager panels do.
 *
 * Every control here writes through SettingsService.set("music_dock_*",
 * value) -- the same generic, arbitrary-key persistence every other
 * setting in this project already uses (see SettingsService.qml's own
 * doc comment) -- so no schema/default-value changes were needed
 * anywhere else. Reads use an inline "guarded fallback" (matching
 * PlaybackService's streamLoop/streamMuted/streamQuality pattern) rather
 * than adding new keys to SettingsService's DEFAULT_SETTINGS, so an
 * upgrade with no settings.json entry yet still renders sane defaults.
 *
 * Sizing / scrolling: the settings list here is taller than the space
 * LiveWallpaperPanel has available for it (it sits above the
 * fill-height ModeContentArea, inside a fixed 960x840 window), so the
 * panel no longer sizes itself to its content (that used to be
 * `content.implicitHeight`, which just pushed everything below it off
 * the bottom of the window). Instead `root` keeps a fixed footprint --
 * same idea as WallpaperGrid's `implicitHeight: zenMode ? 560 : 380` --
 * and the body scrolls internally inside a Flickable. The header row
 * (title/status/close button) lives outside that Flickable so it stays
 * put while the settings list scrolls under it.
 */

// ToggleSwitch / SettingRow / SettingSlider used below now live in their
// own files (Components/ToggleSwitch.qml, SettingRow.qml,
// SettingSlider.qml) -- same directory, so no import needed, exactly
// like IconButton is used elsewhere in this project without an explicit
// import. (Previously inline QML6 `component` blocks here; moved out
// after a real-device test hit a syntax error loading them inline --
// separate files follow the reusable-component pattern
// already use and avoid depending on that engine feature entirely.)

Rectangle {
    id: root
    radius: Theme.radiusLg
    color: Theme.cardBg
    border.width: 1
    border.color: Theme.panelBorder

    // Fixed footprint -- do NOT size this to content (that's what made the
    // panel taller than the window in the first place). Matches the
    // pattern WallpaperGrid already uses for the same reason
    // (`implicitHeight: zenMode ? 560 : 380`). The scrollable body below
    // handles content taller than this.
    implicitHeight: 420

    signal closeRequested()

    // ── Settings reads (guarded fallback, see header) ────────────────────
    readonly property bool enabled:      SettingsService.settings.music_dock_enabled === true
    readonly property bool cavaEnabled:  SettingsService.settings.music_dock_cava_enabled !== false
    readonly property bool autoHide:     SettingsService.settings.music_dock_autohide === true
    readonly property bool clickThrough: SettingsService.settings.music_dock_click_through === true
    readonly property bool blurOn:       SettingsService.settings.music_dock_blur !== false
    readonly property bool glowOn:       SettingsService.settings.music_dock_glow !== false
    readonly property real opacityVal: {
        const v = Number(SettingsService.settings.music_dock_opacity);
        return (v > 0 && v <= 1) ? v : 0.78;
    }
    readonly property int widthVal: {
        const v = parseInt(SettingsService.settings.music_dock_width, 10);
        return (v >= 360 && v <= 1400) ? v : 640;
    }
    readonly property int heightVal: {
        const v = parseInt(SettingsService.settings.music_dock_height, 10);
        return (v >= 64 && v <= 200) ? v : 88;
    }
    readonly property int radiusVal: {
        const v = parseInt(SettingsService.settings.music_dock_radius, 10);
        return (v >= 8 && v <= 40) ? v : 24;
    }
    readonly property var barCountOptions: [32, 48, 64, 128, 256, 512]
    readonly property int barCountVal: {
        const v = parseInt(SettingsService.settings.music_dock_bar_count, 10);
        return root.barCountOptions.includes(v) ? v : 48;
    }
    readonly property int barSpacingVal: {
        const v = parseInt(SettingsService.settings.music_dock_bar_spacing, 10);
        return (v >= 0 && v <= 8) ? v : 2;
    }
    readonly property int barWidthVal: {
        const v = parseInt(SettingsService.settings.music_dock_bar_width, 10);
        return (v >= 2 && v <= 10) ? v : 3;
    }
    readonly property int sensitivityVal: {
        const v = parseInt(SettingsService.settings.music_dock_sensitivity, 10);
        return (v >= 10 && v <= 300) ? v : 100;
    }
    readonly property int animSpeedVal: {
        const v = parseInt(SettingsService.settings.music_dock_anim_speed, 10);
        return (v >= 30 && v <= 600) ? v : 120;
    }
    readonly property int artSizeVal: {
        const v = parseInt(SettingsService.settings.music_dock_art_size, 10);
        return (v >= 36 && v <= 96) ? v : 56;
    }
    readonly property string monitorVal: SettingsService.settings.music_dock_monitor || "auto"

    // ── Visualizer position -- see Panels/MusicDockOverlay.qml's
    // "Placement (Visualizer Position)" section for how this actually
    // repositions the (one and only) overlay window. Same guarded-
    // fallback pattern as every other music_dock_* read on this page.
    readonly property var positionOptions: [
        { key: "bottom", label: "Bottom" },
        { key: "center", label: "Center" },
        { key: "top",    label: "Top" }
    ]
    readonly property string positionVal: {
        const p = SettingsService.settings.music_dock_position;
        return (p === "top" || p === "center") ? p : "bottom";
    }

    readonly property var accentPalette: [
        { name: "Mauve", value: Theme.mauve },
        { name: "Blue",  value: Theme.blue },
        { name: "Pink",  value: Theme.pink },
        { name: "Teal",  value: Theme.teal },
        { name: "Peach", value: Theme.peach },
        { name: "Green", value: Theme.green },
        { name: "Red",   value: Theme.red },
        { name: "Yellow", value: Theme.yellow }
    ]
    readonly property string accentVal: SettingsService.settings.music_dock_accent || Theme.mauve

    // ── Visualizer color mode -- see CavaService.qml's "Visualizer
    // color system" header for where colorMode/randomColor/
    // rainbowCycleSeconds/rainbowSpeed actually live; this panel only
    // reads them plus the two random-mode auto-trigger toggles that
    // don't have a CavaService-side computed property of their own.
    readonly property var colorModeOptions: [
        { key: "manual",  label: "Manual" },
        { key: "random",  label: "🎲 Random" },
        { key: "rainbow", label: "🌈 Rainbow" }
    ]
    readonly property var rainbowCycleOptions: [5, 10, 20, 30, 60]
    readonly property bool randomOnWallpaperChange: SettingsService.settings.music_dock_random_on_wallpaper_change === true
    readonly property bool randomOnRestart: SettingsService.settings.music_dock_random_on_restart === true

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
                text: "🎵  Music Dock"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMd
                font.bold: true
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                width: 8; height: 8; radius: 4
                color: root.enabled ? Theme.success : Theme.overlay0
            }
            Text {
                text: root.enabled ? "Enabled" : "Disabled"
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
            }
            IconButton {
                text: "✕"
                fontSize: Theme.fontSizeMd
                onClicked: root.closeRequested()
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.panelBorder }

        // ── Scrollable body ──────────────────────────────────────────────
        // Flickable rather than ListView/GridView since the content below
        // is a fixed hand-authored ColumnLayout of mixed row types, not a
        // repeated model -- same reasoning WallpaperGrid uses GridView
        // (repeated cards) while this stays a plain scroll container.
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

            // Qt's Flickable already answers wheel events with its own
            // smooth/deceleration curve (no separate WheelHandler needed --
            // stacking one on top would just fight the built-in handling),
            // so plain mouse-wheel scrolling here is smooth by default and
            // matches the momentum feel WallpaperGrid's GridView already
            // has elsewhere in this panel.

            ColumnLayout {
                id: content
                width: flick.width
                // Was spacingSm (8px) -- every row (toggles, sliders,
                // bar count, accent color, monitor) now gets noticeably
                // more room to breathe. The panel's own footprint stays
                // fixed (root.implicitHeight above is untouched); the
                // extra height this adds just scrolls under the header,
                // same as it already did before.
                spacing: Theme.spacingLg

                // ── Core toggles ──────────────────────────────────────────────────
        SettingRow {
            label: "Enable Music Dock"
            ToggleSwitch {
                checked: root.enabled
                onToggled: SettingsService.set("music_dock_enabled", !root.enabled)
            }
        }
        SettingRow {
            label: "Enable Cava visualizer"
            ToggleSwitch {
                checked: root.cavaEnabled
                onToggled: SettingsService.set("music_dock_cava_enabled", !root.cavaEnabled)
            }
        }
        SettingRow {
            label: "Auto-hide when idle"
            ToggleSwitch {
                checked: root.autoHide
                onToggled: SettingsService.set("music_dock_autohide", !root.autoHide)
            }
        }
        SettingRow {
            label: "Click-through"
            ToggleSwitch {
                checked: root.clickThrough
                onToggled: SettingsService.set("music_dock_click_through", !root.clickThrough)
            }
        }
        SettingRow {
            label: "Blur (layered translucency)"
            ToggleSwitch {
                checked: root.blurOn
                onToggled: SettingsService.set("music_dock_blur", !root.blurOn)
            }
        }
        SettingRow {
            label: "Glow"
            ToggleSwitch {
                checked: root.glowOn
                onToggled: SettingsService.set("music_dock_glow", !root.glowOn)
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.panelBorder }

        // ── Sliders ───────────────────────────────────────────────────────
        SliderRow {
            label: "Opacity"
            from: 0.3; to: 1.0
            value: root.opacityVal
            formatValue: (v) => Math.round(v * 100) + "%"
            onMoved: SettingsService.set("music_dock_opacity", value.toFixed(2))
        }
        SliderRow {
            label: "Width"
            from: 360; to: 1400; stepSize: 10
            value: root.widthVal
            suffix: "px"
            onMoved: SettingsService.set("music_dock_width", Math.round(value))
        }
        SliderRow {
            label: "Height"
            from: 64; to: 200; stepSize: 2
            value: root.heightVal
            suffix: "px"
            onMoved: SettingsService.set("music_dock_height", Math.round(value))
        }
        SliderRow {
            label: "Corner radius"
            from: 8; to: 40; stepSize: 1
            value: root.radiusVal
            suffix: "px"
            onMoved: SettingsService.set("music_dock_radius", Math.round(value))
        }
        SliderRow {
            label: "Album art size"
            from: 36; to: 96; stepSize: 2
            value: root.artSizeVal
            suffix: "px"
            onMoved: SettingsService.set("music_dock_art_size", Math.round(value))
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.panelBorder }

        // ── Cava tuning ───────────────────────────────────────────────────
        SettingRow {
            label: "Bar count"
            RowLayout {
                spacing: Theme.spacingSm
                Repeater {
                    model: root.barCountOptions
                    delegate: IconButton {
                        text: String(modelData)
                        fontSize: Theme.fontSizeSm
                        active: root.barCountVal === modelData
                        onClicked: {
                            SettingsService.set("music_dock_bar_count", modelData);
                            CavaService.restart();
                        }
                    }
                }
            }
        }
        SliderRow {
            label: "Bar width"
            from: 2; to: 10; stepSize: 1
            value: root.barWidthVal
            suffix: "px"
            onMoved: SettingsService.set("music_dock_bar_width", Math.round(value))
        }
        SliderRow {
            label: "Bar spacing"
            from: 0; to: 8; stepSize: 1
            value: root.barSpacingVal
            suffix: "px"
            onMoved: SettingsService.set("music_dock_bar_spacing", Math.round(value))
        }
        SliderRow {
            label: "Sensitivity"
            from: 10; to: 300; stepSize: 5
            value: root.sensitivityVal
            suffix: "%"
            onMoved: SettingsService.set("music_dock_sensitivity", Math.round(value))
            onPressedChanged: if (!pressed) CavaService.restart()
        }
        SliderRow {
            label: "Animation speed"
            from: 30; to: 600; stepSize: 10
            value: root.animSpeedVal
            suffix: "ms"
            onMoved: SettingsService.set("music_dock_anim_speed", Math.round(value))
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.panelBorder }

        // ── Visualizer color ─────────────────────────────────────────────
        // Mode is mutually exclusive (Manual/Random/Rainbow) -- same
        // segmented-IconButton-row pattern as "Bar count" above. Only
        // the bars themselves change color; nothing else re-renders,
        // nothing restarts cava (see CavaService.qml).
        SettingRow {
            label: "Visualizer color"
            RowLayout {
                spacing: Theme.spacingSm
                Repeater {
                    model: root.colorModeOptions
                    delegate: IconButton {
                        text: modelData.label
                        fontSize: Theme.fontSizeSm
                        active: CavaService.colorMode === modelData.key
                        onClicked: SettingsService.set("music_dock_color_mode", modelData.key)
                    }
                }
            }
        }

        // Mode 1 -- Manual. The original picker, byte-for-byte
        // unchanged, just now only shown while Manual is the active
        // mode (it still works exactly the same when it is).
        SettingRow {
            label: "Manual color"
            visible: CavaService.colorMode === "manual"
            RowLayout {
                spacing: Theme.spacingSm
                Repeater {
                    model: root.accentPalette
                    delegate: Rectangle {
                        width: 22; height: 22; radius: 11
                        color: modelData.value
                        border.width: root.accentVal === modelData.value ? 2 : 0
                        border.color: Theme.text
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: SettingsService.set("music_dock_accent", modelData.value)
                        }
                    }
                }
            }
        }

        // Mode 2 -- Random. Button rolls + saves a new color immediately
        // (CavaService.generateRandomColor()); the swatch mirrors
        // whatever's currently active/persisted.
        SettingRow {
            label: "Random color"
            visible: CavaService.colorMode === "random"
            RowLayout {
                spacing: Theme.spacingSm
                IconButton {
                    text: "🎲  Random Color"
                    fontSize: Theme.fontSizeSm
                    onClicked: CavaService.generateRandomColor()
                }
                Rectangle {
                    width: 22; height: 22; radius: 11
                    color: CavaService.randomColor
                    border.width: 1
                    border.color: Theme.text
                }
            }
        }
        SettingRow {
            label: "Randomize on wallpaper change"
            visible: CavaService.colorMode === "random"
            ToggleSwitch {
                checked: root.randomOnWallpaperChange
                onToggled: SettingsService.set("music_dock_random_on_wallpaper_change", !root.randomOnWallpaperChange)
            }
        }
        SettingRow {
            label: "Randomize on app restart"
            visible: CavaService.colorMode === "random"
            ToggleSwitch {
                checked: root.randomOnRestart
                onToggled: SettingsService.set("music_dock_random_on_restart", !root.randomOnRestart)
            }
        }

        // Mode 3 -- Rainbow. Cycle time is a fixed preset (matches Bar
        // count's segmented style); speed is a free 0.1x-5x multiplier.
        // Both just feed CavaService's rainbowTimer -- no restart, no
        // panel reload.
        SettingRow {
            label: "Rainbow cycle time"
            visible: CavaService.colorMode === "rainbow"
            RowLayout {
                spacing: Theme.spacingSm
                Repeater {
                    model: root.rainbowCycleOptions
                    delegate: IconButton {
                        text: modelData + "s"
                        fontSize: Theme.fontSizeSm
                        active: CavaService.rainbowCycleSeconds === modelData
                        onClicked: SettingsService.set("music_dock_rainbow_cycle_seconds", modelData)
                    }
                }
            }
        }
        SliderRow {
            label: "Rainbow speed"
            visible: CavaService.colorMode === "rainbow"
            from: 0.1; to: 5.0; stepSize: 0.1
            value: CavaService.rainbowSpeed
            formatValue: (v) => v.toFixed(1) + "x"
            onMoved: SettingsService.set("music_dock_rainbow_speed", value.toFixed(1))
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.panelBorder }

        // ── Visualizer style (PHASE 3) ─────────────────────────────────────
        // Bars = the original look; Waveform = a smooth mirrored line.
        // Both read CavaService.bars -- see MusicDock.qml's visualizer
        // Item and CavaService.qml's visualizerStyle. No pipeline change.
        SettingRow {
            label: "Visualizer style"
            RowLayout {
                spacing: Theme.spacingSm
                IconButton {
                    text: "▮▮▮ Bars"
                    fontSize: Theme.fontSizeSm
                    active: CavaService.visualizerStyle === "bars"
                    onClicked: SettingsService.set("music_dock_visualizer_style", "bars")
                }
                IconButton {
                    text: "〜 Waveform"
                    fontSize: Theme.fontSizeSm
                    active: CavaService.visualizerStyle === "waveform"
                    onClicked: SettingsService.set("music_dock_visualizer_style", "waveform")
                }
            }
        }
        SettingRow {
            label: "Floating waveform"
            visible: CavaService.visualizerStyle === "waveform"
            ToggleSwitch {
                checked: CavaService.floatingWaveform
                onToggled: SettingsService.set("music_dock_floating_waveform", !CavaService.floatingWaveform)
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.panelBorder }

        // ── Visualizer position ──────────────────────────────────────────
        // Mutually exclusive (Bottom/Center/Top), same segmented-
        // IconButton-row pattern as "Bar count"/"Visualizer color" above.
        // Repositions the existing Music Dock overlay in place -- no
        // restart of CavaService/MprisService, no second window.
        //
        // Compact RowLayout group (Theme.spacingSm gap, same as every
        // other segmented row on this panel) -- the three buttons sit
        // back-to-back in whatever order root.positionOptions lists
        // them, Bottom/Center/Top, so Center is simply the middle button
        // of the tight group, not centered across the row/panel.
        SettingRow {
            label: "Visualizer position"
            RowLayout {
                spacing: Theme.spacingSm
                Repeater {
                    model: root.positionOptions
                    delegate: IconButton {
                        text: modelData.label
                        fontSize: Theme.fontSizeSm
                        active: root.positionVal === modelData.key
                        onClicked: SettingsService.set("music_dock_position", modelData.key)
                    }
                }
            }
        }

        // ── Monitor ───────────────────────────────────────────────────────
        SettingRow {
            label: "Monitor"
            RowLayout {
                spacing: Theme.spacingSm
                IconButton {
                    text: "Auto"
                    fontSize: Theme.fontSizeSm
                    active: root.monitorVal === "auto"
                    onClicked: SettingsService.set("music_dock_monitor", "auto")
                }
                Repeater {
                    model: MultiMonitorService.monitors
                    delegate: IconButton {
                        text: modelData.name
                        fontSize: Theme.fontSizeSm
                        active: root.monitorVal === modelData.name
                        onClicked: SettingsService.set("music_dock_monitor", modelData.name)
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacingXs
            visible: !CavaService.available
            text: "cava isn't installed -- the visualizer will stay hidden until it is. Re-run install.sh to add it."
            color: Theme.yellow
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm - 1
            wrapMode: Text.WordWrap
        }
        Text {
            Layout.fillWidth: true
            visible: !MprisService.available
            text: "playerctl isn't installed -- Music Dock can't detect players until it is. Re-run install.sh to add it."
            color: Theme.yellow
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm - 1
            wrapMode: Text.WordWrap
        }
            } // content (scrollable ColumnLayout)

            // ── Thin, auto-hiding scrollbar ──────────────────────────────
            // Only visible while actively scrolling/dragging (`active`) or
            // hovered (`pressed`/hover handled by QQCB.ScrollBar itself);
            // fades out via the opacity Behavior otherwise so it never sits
            // on screen as visual clutter over the Glassmorphism card.
            QQCB.ScrollBar.vertical: QQCB.ScrollBar {
                id: vbar
                // Qt wires size/position/anchoring to `flick` automatically
                // once assigned to this attached property -- only policy
                // and appearance need setting here.
                policy: QQCB.ScrollBar.AsNeeded

                opacity: (vbar.active || vbar.pressed || vbar.hovered) ? 0.85 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.durationNormal } }

                contentItem: Rectangle {
                    implicitWidth: 4
                    radius: 2
                    color: Theme.overlay1
                }
                background: Item {}
            }
        } // Flickable
    } // shell
}
