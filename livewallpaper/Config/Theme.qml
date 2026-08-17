pragma Singleton
import QtQuick

/*
 * Theme.qml
 * ----------
 * Central design-token singleton: Catppuccin Mocha palette, radii,
 * spacing and the Windows-11-flavoured Fluent/Mica look, plus the
 * animation curves used across Caelestia so this module feels native to
 * the shell rather than bolted on.
 *
 * Every Component in this module reads colors/metrics from here instead
 * of hardcoding them, so re-theming (e.g. switching to Catppuccin Latte)
 * is a one-file change.
 */
QtObject {
    id: theme

    // -------------------- CATPPUCCIN MOCHA PALETTE --------------------
    readonly property color base:     "#1e1e2e"
    readonly property color mantle:   "#181825"
    readonly property color crust:    "#11111b"
    readonly property color surface0: "#313244"
    readonly property color surface1: "#45475a"
    readonly property color surface2: "#585b70"
    readonly property color overlay0: "#6c7086"
    readonly property color overlay1: "#7f849c"
    readonly property color text:     "#cdd6f4"
    readonly property color subtext0: "#a6adc8"
    readonly property color subtext1: "#bac2de"
    readonly property color blue:     "#89b4fa"
    readonly property color sky:      "#89dceb"
    readonly property color lavender: "#b4befe"
    readonly property color mauve:    "#cba6f7"
    readonly property color pink:     "#f5c2e7"
    readonly property color red:      "#f38ba8"
    readonly property color maroon:   "#eba0ac"
    readonly property color green:    "#a6e3a1"
    readonly property color teal:     "#94e2d5"
    readonly property color peach:    "#fab387"
    readonly property color yellow:   "#f9e2af"

    // Semantic aliases so components read intent, not raw palette names
    readonly property color accent:        mauve
    readonly property color accentAlt:     lavender
    readonly property color danger:        red
    readonly property color success:       green
    readonly property color onAccent:      crust

    // -------------------- WINDOWS 11 / MICA SURFACE --------------------
    readonly property color panelBg:     Qt.rgba(0.1176, 0.1176, 0.1804, 0.82) // base @ 82%
    readonly property color panelBorder: Qt.rgba(0.7059, 0.7451, 0.9961, 0.15) // lavender @ 15%
    readonly property color cardBg:      Qt.rgba(0.1922, 0.1961, 0.2667, 0.55) // surface0 @ 55%
    readonly property color cardHoverBg: Qt.rgba(0.2706, 0.2784, 0.3529, 0.72) // surface1 @ 72%

    // -------------------- RADII --------------------
    readonly property real radiusXl: 20
    readonly property real radiusLg: 16
    readonly property real radiusMd: 12
    readonly property real radiusSm: 8
    readonly property real radiusXs: 6

    // -------------------- SPACING --------------------
    readonly property real spacingXs: 4
    readonly property real spacingSm: 8
    readonly property real spacingMd: 12
    readonly property real spacingLg: 16
    readonly property real spacingXl: 22

    // -------------------- TYPOGRAPHY --------------------
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property string fontFamilyUi: "Rubik"
    readonly property real fontSizeSm: 12
    readonly property real fontSizeMd: 14
    readonly property real fontSizeLg: 16
    readonly property real fontSizeXl: 22

    // -------------------- ANIMATION (Caelestia-consistent curves) --------------------
    // Matches the "expressive" easing Caelestia uses for its own bar/panel
    // motion: a fast, slightly overshooting ease-out for entrances, a
    // plain ease-in-out for toggles, and quick microinteractions for
    // hover/press feedback.
    readonly property var emphasizedEasing: [0.05, 0.7, 0.1, 1.0, 1, 1]
    readonly property var standardEasing: [0.2, 0.0, 0.0, 1.0, 1, 1]

    readonly property int durationFast: 120
    readonly property int durationNormal: 220
    readonly property int durationSlow: 380
    // Dedicated 200ms curve for the TitleBar mode switcher's crossfade+slide
    // (Wallpapers / Streaming / Web) -- kept separate from durationNormal so
    // that value can change independently later without touching this.
    readonly property int durationModeSwitch: 200

    // -------------------- SEGMENTED CONTROL (Fluent pill) --------------------
    readonly property color segmentTrackBg:   Qt.rgba(0.0667, 0.0667, 0.1059, 0.55) // crust @ 55%
    readonly property color segmentActiveBg:  Qt.rgba(0.7961, 0.6510, 0.9686, 0.22) // accent(mauve) @ 22%
    readonly property color segmentHoverBg:   Qt.rgba(1, 1, 1, 0.06)
}
