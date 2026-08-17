import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../Config"
import "../Services"

/*
 * PeaclockCavaDockPanel.qml
 * -----------------------------
 * Settings panel for the new, independent Peaclock + Cava Dock
 * (Panels/PeaclockCavaDockOverlay.qml + Components/PeaclockCavaDock.qml).
 *
 * Same shape/pattern as Components/MusicDockPanel.qml (guarded-fallback
 * settings reads, SettingRow/ToggleSwitch/SliderRow rows), but every
 * control here writes through its OWN "pcdock_*" keys -- never
 * "music_dock_*" -- so this dock's settings are completely independent
 * of the existing Music Dock's. Enabling/disabling/tuning either dock
 * never affects the other.
 *
 * Cava tuning (bar count, sensitivity, color mode, etc.) is intentionally
 * NOT duplicated here -- CavaService is a single shared pipeline/singleton
 * (see CavaService.qml), so those knobs already live in one place
 * (Music Dock's settings / the Visualizer page) and apply to whichever
 * dock is currently rendering the bars. Duplicating them here would just
 * be two controls for the same one value.
 */
Rectangle {
    id: root
    radius: Theme.radiusLg
    color: Theme.cardBg
    border.width: 1
    border.color: Theme.panelBorder
    implicitHeight: content.implicitHeight + Theme.spacingLg * 2

    // ── Settings reads (guarded fallback, see header) ────────────────────
    readonly property bool enabled:      SettingsService.settings.pcdock_enabled === true
    readonly property bool cavaEnabled:  SettingsService.settings.pcdock_cava_enabled !== false
    readonly property bool autoHide:     SettingsService.settings.pcdock_autohide === true
    readonly property bool clickThrough: SettingsService.settings.pcdock_click_through === true
    readonly property bool blurOn:       SettingsService.settings.pcdock_blur !== false
    readonly property bool glowOn:       SettingsService.settings.pcdock_glow !== false
    readonly property real opacityVal: {
        const v = Number(SettingsService.settings.pcdock_opacity);
        return (v > 0 && v <= 1) ? v : 0.78;
    }
    readonly property int widthVal: {
        const v = parseInt(SettingsService.settings.pcdock_width, 10);
        return (v >= 220 && v <= 520) ? v : 300;
    }
    readonly property int heightVal: {
        const v = parseInt(SettingsService.settings.pcdock_height, 10);
        return (v >= 200 && v <= 520) ? v : 300;
    }
    readonly property int radiusVal: {
        const v = parseInt(SettingsService.settings.pcdock_radius, 10);
        return (v >= 8 && v <= 40) ? v : 24;
    }
    readonly property string monitorVal: SettingsService.settings.pcdock_monitor || "auto"

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

    // ── Visualizer render style -- Noctalia-style spectrum bars, a
    // mirrored oscilloscope waveform, or a thin zigzag pulse line, see
    // CavaService.qml's "pcVisualizerStyle" header and Components/
    // PeaclockCavaVisualizer.qml. Own "pcdock_cava_visualizer_style" key,
    // independent of Music Dock's "music_dock_visualizer_style".
    readonly property var visualizerStyleOptions: [
        { key: "bars",     label: "▮▮▮ Bars" },
        { key: "waveform", label: "〜 Waveform" },
        { key: "line",     label: "⌇ Line" }
    ]

    // ── Waveform sensitivity -- pure client-side amplitude gain applied
    // in Components/PeaclockCavaVisualizer.qml, see CavaService.qml's
    // "pcSensitivityGain" header for why this never touches the cava
    // process/config itself. Own "pcdock_cava_sensitivity" key, same
    // enumerated-value shape as "Visualizer style" above -- 128 is the
    // default (matches the strip's look before this setting existed).
    readonly property var sensitivityOptions: [
        { key: 32,  label: "32" },
        { key: 64,  label: "64" },
        { key: 128, label: "128" },
        { key: 256, label: "256" }
    ]

    // ── Visualizer horizontal position -- see CavaService.qml's
    // "pcVisualizerHPosition" header. Own "pcdock_cava_hposition" key,
    // same enumerated segmented-row shape as "Waveform sensitivity"/
    // "Visualizer style" above. Together with the "Visualizer position"
    // row further below (vertical: top/bottom/center) this fully
    // controls where the whole dock overlay window sits on the target
    // monitor -- the two axes are independent, so all nine combinations
    // are reachable.
    readonly property var hPositionOptions: [
        { key: "left",   label: "Left" },
        { key: "center", label: "Center" },
        { key: "right",  label: "Right" }
    ]

    // ── Visualizer color mode -- see CavaService.qml's "Peaclock + Cava
    // Dock: independent visualizer color system" header. Own "pcdock_
    // cava_*" keys throughout, completely separate from the dock's
    // chrome accent ("pcdock_accent", unchanged, no longer exposed as a
    // row in this panel -- see below) and from Music Dock's own
    // "music_dock_*" color settings -- changing this never affects
    // either of those.
    readonly property var colorModeOptions: [
        { key: "manual",  label: "Manual" },
        { key: "random",  label: "🎲 Random" },
        { key: "rainbow", label: "🌈 Rainbow" }
    ]

    // ── Rainbow cycle time options -- same fixed preset set as Music
    // Dock's identical row (Components/MusicDockPanel.qml). Both rows
    // read/write the exact same CavaService.rainbowCycleSeconds /
    // "music_dock_rainbow_cycle_seconds" -- there is only one shared
    // rainbowTimer/rainbowHue in CavaService.qml (see that file's
    // header), so this dock's Rainbow mode already rides the same
    // sweep Music Dock's does; this row just exposes the same one
    // control here too instead of duplicating a second, disconnected
    // timer.
    readonly property var rainbowCycleOptions: [5, 10, 20, 30, 60]

    // ── Visualizer position -- see Panels/PeaclockCavaDockOverlay.qml's
    // "Placement (Visualizer Position)" section for how this repositions
    // the dock's own overlay window. Same shape as Music Dock's identical
    // setting, own "pcdock_position" key.
    readonly property var positionOptions: [
        { key: "bottom", label: "Bottom" },
        { key: "center", label: "Center" },
        { key: "top",    label: "Top" }
    ]
    readonly property string positionVal: {
        const p = SettingsService.settings.pcdock_position;
        return (p === "top" || p === "center") ? p : "bottom";
    }

    // One-shot "is the peaclock package actually on PATH" check -- same
    // graceful-degrade convention as CavaService.available/MprisService.
    // available below (see the two warning Texts at the bottom of this
    // panel), but resolved locally with a tiny Process rather than a new
    // singleton service, since nothing else in the app needs this value.
    // Never blocks or crashes the panel: peaclockAvailable simply stays
    // false (its safe default) until/unless the check succeeds.
    property bool peaclockAvailable: false
    Process {
        id: peaclockCheckProc
        command: ["bash", "-c", "command -v peaclock"]
        onExited: (code, status) => { root.peaclockAvailable = (code === 0); }
    }
    Component.onCompleted: peaclockCheckProc.running = true

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Theme.spacingLg
        spacing: Theme.spacingLg

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            Text {
                text: "\u23F0  Peaclock + Cava Dock"
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
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.panelBorder }

        // ── Core toggles ──────────────────────────────────────────────────
        SettingRow {
            label: "Enable Peaclock + Cava Dock"
            ToggleSwitch {
                checked: root.enabled
                onToggled: SettingsService.set("pcdock_enabled", !root.enabled)
            }
        }
        SettingRow {
            label: "Enable Cava visualizer"
            ToggleSwitch {
                checked: root.cavaEnabled
                onToggled: SettingsService.set("pcdock_cava_enabled", !root.cavaEnabled)
            }
        }
        SettingRow {
            label: "Auto-hide when idle"
            ToggleSwitch {
                checked: root.autoHide
                onToggled: SettingsService.set("pcdock_autohide", !root.autoHide)
            }
        }
        SettingRow {
            label: "Click-through"
            ToggleSwitch {
                checked: root.clickThrough
                onToggled: SettingsService.set("pcdock_click_through", !root.clickThrough)
            }
        }
        SettingRow {
            label: "Blur (layered translucency)"
            ToggleSwitch {
                checked: root.blurOn
                onToggled: SettingsService.set("pcdock_blur", !root.blurOn)
            }
        }
        SettingRow {
            label: "Glow"
            ToggleSwitch {
                checked: root.glowOn
                onToggled: SettingsService.set("pcdock_glow", !root.glowOn)
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.panelBorder }

        // ── Sliders ───────────────────────────────────────────────────────
        SliderRow {
            label: "Opacity"
            from: 0.3; to: 1.0
            value: root.opacityVal
            formatValue: (v) => Math.round(v * 100) + "%"
            onMoved: SettingsService.set("pcdock_opacity", value.toFixed(2))
        }
        SliderRow {
            label: "Width"
            from: 220; to: 520; stepSize: 10
            value: root.widthVal
            suffix: "px"
            onMoved: SettingsService.set("pcdock_width", Math.round(value))
        }
        SliderRow {
            label: "Height"
            from: 200; to: 520; stepSize: 10
            value: root.heightVal
            suffix: "px"
            onMoved: SettingsService.set("pcdock_height", Math.round(value))
        }
        SliderRow {
            label: "Corner radius"
            from: 8; to: 40; stepSize: 1
            value: root.radiusVal
            suffix: "px"
            onMoved: SettingsService.set("pcdock_radius", Math.round(value))
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.panelBorder }

        // ── Visualizer style -- Bars/Waveform, same segmented-IconButton
        // row pattern as Music Dock's equivalent (Components/
        // MusicDockPanel.qml). Only changes what's painted inside the
        // existing CAVA strip -- see Components/PeaclockCavaVisualizer.
        // qml and PeaclockCavaDock.qml.
        SettingRow {
            label: "Visualizer style"
            RowLayout {
                spacing: Theme.spacingSm
                Repeater {
                    model: root.visualizerStyleOptions
                    delegate: IconButton {
                        text: modelData.label
                        fontSize: Theme.fontSizeSm
                        active: CavaService.pcVisualizerStyle === modelData.key
                        onClicked: SettingsService.set("pcdock_cava_visualizer_style", modelData.key)
                    }
                }
            }
        }

        // ── Waveform sensitivity -- same segmented-IconButton row pattern
        // as "Visualizer style" directly above (its natural home). Scales
        // the amplitude of the exact same real cava frame data everything
        // else here reads -- see CavaService.qml/PeaclockCavaVisualizer.
        // qml headers. 128 is the default.
        SettingRow {
            label: "Waveform sensitivity"
            RowLayout {
                spacing: Theme.spacingSm
                Repeater {
                    model: root.sensitivityOptions
                    delegate: IconButton {
                        text: modelData.label
                        fontSize: Theme.fontSizeSm
                        active: CavaService.pcSensitivity === modelData.key
                        onClicked: SettingsService.set("pcdock_cava_sensitivity", modelData.key)
                    }
                }
            }
        }

        // ── Visualizer horizontal position -- same segmented-IconButton
        // row pattern as "Waveform sensitivity" directly above. Moves
        // the ENTIRE dock overlay (clock, date, LIVE indicator, Cava
        // strip, now-playing text, card background/border) left/center/
        // right on the target monitor -- see CavaService.qml's
        // "pcVisualizerHPosition" header and Panels/
        // PeaclockCavaDockOverlay.qml's "Placement" section, which is
        // where this setting is actually applied (same PanelWindow the
        // "Visualizer position" row below repositions vertically; the
        // two anchor axes are independent). The waveform/bars/line stay
        // put inside the card at every position -- see Components/
        // PeaclockCavaDock.qml's cavaStrip.
        SettingRow {
            label: "Visualizer horizontal position"
            RowLayout {
                spacing: Theme.spacingSm
                Repeater {
                    model: root.hPositionOptions
                    delegate: IconButton {
                        text: modelData.label
                        fontSize: Theme.fontSizeSm
                        active: CavaService.pcVisualizerHPosition === modelData.key
                        onClicked: SettingsService.set("pcdock_cava_hposition", modelData.key)
                    }
                }
            }
        }

        // ── Visualizer color -- independent from Music Dock's own color
        // mode (see CavaService.qml). Mutually exclusive Manual/Random/
        // Rainbow, same segmented-IconButton-row pattern as Music Dock's
        // equivalent row. Only the visualizer's color changes -- nothing
        // restarts cava, nothing else re-renders (see CavaService.qml).
        SettingRow {
            label: "Visualizer color"
            RowLayout {
                spacing: Theme.spacingSm
                Repeater {
                    model: root.colorModeOptions
                    delegate: IconButton {
                        text: modelData.label
                        fontSize: Theme.fontSizeSm
                        active: CavaService.pcColorMode === modelData.key
                        onClicked: SettingsService.set("pcdock_cava_color_mode", modelData.key)
                    }
                }
            }
        }

        // Mode 1 -- Manual. The bars-only manual color picker
        // ("pcdock_cava_accent" swatches) has been removed from this
        // panel per request -- CavaService.pcManualColor itself (and its
        // Theme.mauve fallback) is untouched, so the "bars" render style
        // still has a valid color if selected; there's simply no swatch
        // row for it here anymore. "Waveform Color" directly below is
        // unaffected -- it's a separate key/control.

        // ── Waveform Color (NEW, additive) ──────────────────────────────
        // Dedicated color picker for the "waveform" render style only --
        // see CavaService.qml's "pcWaveformColor" header. Own
        // "pcdock_cava_waveform_color" key; never writes/reads
        // "pcdock_cava_accent" (Manual color, above), "pcdock_accent"
        // (clock/LIVE label/border chrome), or any card/background/text
        // color, so this control affects ONLY the waveform trace in
        // Components/PeaclockCavaVisualizer.qml. Same picker pattern as
        // "Manual color" above; defaults to today's effective waveform
        // color until a swatch here is picked (see pcWaveformManualColor).
        SettingRow {
            label: "Waveform Color"
            visible: CavaService.pcColorMode === "manual"
            RowLayout {
                spacing: Theme.spacingSm
                Repeater {
                    model: root.accentPalette
                    delegate: Rectangle {
                        width: 22; height: 22; radius: 11
                        color: modelData.value
                        border.width: CavaService.pcWaveformManualColor === modelData.value ? 2 : 0
                        border.color: Theme.text
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: SettingsService.set("pcdock_cava_waveform_color", modelData.value)
                        }
                    }
                }
            }
        }

        // Mode 2 -- Random. Button rolls + saves a new color immediately
        // (CavaService.pcGenerateRandomColor()); the swatch mirrors
        // whatever's currently active/persisted for this dock only.
        SettingRow {
            label: "Random color"
            visible: CavaService.pcColorMode === "random"
            RowLayout {
                spacing: Theme.spacingSm
                IconButton {
                    text: "🎲  Random Color"
                    fontSize: Theme.fontSizeSm
                    onClicked: CavaService.pcGenerateRandomColor()
                }
                Rectangle {
                    width: 22; height: 22; radius: 11
                    color: CavaService.pcRandomColor
                    border.width: 1
                    border.color: Theme.text
                }
            }
        }
        // Waveform-only counterpart of "Random color" above -- rolls/
        // saves CavaService.pcWaveformRandomColor, never touching
        // pcRandomColor (bars). The two "Randomize on ..." toggles below
        // already govern both (see CavaService.qml's
        // _maybeRandomizeOnRestart()/_wallpaperChangeConn) -- "respect
        // existing random settings" per spec -- so no separate toggles
        // are added here.
        SettingRow {
            label: "Random waveform color"
            visible: CavaService.pcColorMode === "random"
            RowLayout {
                spacing: Theme.spacingSm
                IconButton {
                    text: "🎲  Random Color"
                    fontSize: Theme.fontSizeSm
                    onClicked: CavaService.pcGenerateWaveformRandomColor()
                }
                Rectangle {
                    width: 22; height: 22; radius: 11
                    color: CavaService.pcWaveformRandomColor
                    border.width: 1
                    border.color: Theme.text
                }
            }
        }
        SettingRow {
            label: "Randomize on wallpaper change"
            visible: CavaService.pcColorMode === "random"
            ToggleSwitch {
                checked: CavaService.pcRandomizeOnWallpaperChange
                onToggled: SettingsService.set("pcdock_cava_random_on_wallpaper_change", !CavaService.pcRandomizeOnWallpaperChange)
            }
        }
        SettingRow {
            label: "Randomize on app restart"
            visible: CavaService.pcColorMode === "random"
            ToggleSwitch {
                checked: CavaService.pcRandomizeOnRestart
                onToggled: SettingsService.set("pcdock_cava_random_on_restart", !CavaService.pcRandomizeOnRestart)
            }
        }

        // Mode 3 -- Rainbow. Cycle time is a fixed preset (matches Music
        // Dock's identical row); speed is a free 0.1x-5x multiplier.
        // Both feed CavaService's one shared rainbowTimer/rainbowHue --
        // moving this slider also moves Music Dock's identical row (and
        // vice versa), since there is only ever one rainbow sweep in the
        // whole app (see CavaService.qml's header) -- no restart, no
        // panel reload, no second timer.
        SettingRow {
            label: "Rainbow cycle time"
            visible: CavaService.pcColorMode === "rainbow"
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
            visible: CavaService.pcColorMode === "rainbow"
            from: 0.1; to: 5.0; stepSize: 0.1
            value: CavaService.rainbowSpeed
            formatValue: (v) => v.toFixed(1) + "x"
            onMoved: SettingsService.set("music_dock_rainbow_speed", value.toFixed(1))
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.panelBorder }

        // ── Visualizer position ──────────────────────────────────────────
        // Mutually exclusive (Bottom/Center/Top), same segmented row
        // pattern as "Visualizer color" above. Repositions the existing
        // Peaclock + Cava overlay in place (see PeaclockCavaDockOverlay.
        // qml) -- no restart of CavaService/MprisService, no second window.
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
                        onClicked: SettingsService.set("pcdock_position", modelData.key)
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
                    onClicked: SettingsService.set("pcdock_monitor", "auto")
                }
                Repeater {
                    model: MultiMonitorService.monitors
                    delegate: IconButton {
                        text: modelData.name
                        fontSize: Theme.fontSizeSm
                        active: root.monitorVal === modelData.name
                        onClicked: SettingsService.set("pcdock_monitor", modelData.name)
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
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
            text: "playerctl isn't installed -- Peaclock + Cava Dock can't detect players until it is. Re-run install.sh to add it."
            color: Theme.yellow
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm - 1
            wrapMode: Text.WordWrap
        }
        Text {
            // Informational only -- the clock face itself is always
            // rendered by PeaclockClock.qml (self-contained QML, see that
            // file's header) and never depends on this package, so its
            // absence never hides or breaks anything in this dock. This
            // just surfaces whether install.sh's optional "peaclock"
            // dependency (see install.sh's DEP_TABLE) is present, for
            // parity with the cava/playerctl notices above.
            Layout.fillWidth: true
            visible: !root.peaclockAvailable
            text: "peaclock isn't installed -- optional, the clock still works without it. Re-run install.sh to add it."
            color: Theme.yellow
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm - 1
            wrapMode: Text.WordWrap
        }
    }
}
