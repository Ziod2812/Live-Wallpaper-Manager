pragma Singleton
import QtQuick
import "../Services"

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
    //
    // ── Smart Accent Color: background tints follow the accent hue ────
    // Previously only the accent/border/indicator colours changed with the
    // wallpaper while the backgrounds (base/mantle/crust/surface0-2) stayed
    // as fixed Catppuccin constants, giving the UI a "coloured outline on
    // an unrelated dark background" look.  `_accentTint()` blends
    // (Qt.tint) a small amount of the current accent into each base
    // colour, but ONLY when the feature is enabled -- the dark theme is
    // preserved; only the hue shifts to match the extracted wallpaper
    // colour so the entire window frame looks cohesive with the
    // accents/indicators/controls rather than clashing.  When the feature
    // is OFF the function returns the original Catppuccin value -- the
    // appearance is identical to the pre-Smart-Accent-Color build.
    readonly property real bgAccentTintAlpha: 0.16
    function _accentTint(hexColor) {
        return SmartAccentService.enabled
            ? Qt.tint(hexColor, Qt.rgba(accent.r, accent.g, accent.b, bgAccentTintAlpha))
            : hexColor;
    }

    // Not `readonly` (same reasoning as `accent` below): a Behavior needs
    // a writable animatable property slot. Nothing else in the app ever
    // assigns to these six directly -- exactly like `accent`, their only
    // "writer" is the binding expression here.
    property color base:     _accentTint("#1e1e2e")
    property color mantle:   _accentTint("#181825")
    property color crust:    _accentTint("#11111b")
    property color surface0: _accentTint("#313244")
    property color surface1: _accentTint("#45475a")
    property color surface2: _accentTint("#585b70")
    Behavior on base     { ColorAnimation { duration: 400 } }
    Behavior on mantle   { ColorAnimation { duration: 400 } }
    Behavior on crust    { ColorAnimation { duration: 400 } }
    Behavior on surface0 { ColorAnimation { duration: 400 } }
    Behavior on surface1 { ColorAnimation { duration: 400 } }
    Behavior on surface2 { ColorAnimation { duration: 400 } }
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
    //
    // ── Smart Accent Color integration ──────────────────────────────
    // `accent` is the ONE property every consumer across the app reads
    // (Sidebar's active-item text/border, Toolbar's search-focus border,
    // IconButton's border/active-bg/label color, SettingSlider's
    // fill/handle, ToggleSwitch, the "Start Wallpaper"/"Stop Wallpaper"
    // action buttons, title text, etc. -- see SmartAccentService.qml's
    // header for the full rationale). Re-pointing just THIS property at
    // SmartAccentService.accentColor when the feature is enabled is the
    // "one-file re-theme" this header already promised, so the dozens of
    // existing files above never need to change individually.
    //
    // When the feature is OFF (default -- see settings.sh's
    // smart_accent_enabled default), this evaluates to the exact same
    // `mauve` constant as before, so an existing install's look is
    // completely unchanged unless the user opts in from Settings.
    //
    // Behavior on color here gives the whole app ONE shared 400ms
    // cross-fade the instant the extracted color changes (new wallpaper
    // applied) -- individual consumers keep their own (already existing,
    // shorter) Behaviors on top of this for hover/press feedback, which
    // just means those repaint twice in quick succession; visually this
    // reads as a single smooth transition, never a color "jump".
    // Not `readonly` (unlike every other alias in this block): a
    // Behavior can only smooth transitions on a property the engine is
    // free to treat as an animatable value slot, which is the same
    // pattern every existing Rectangle in this codebase already relies
    // on for `color: <bound expression>` + `Behavior on color`. Nothing
    // else in the app ever assigns to `accent` directly -- its only
    // "writer" is the binding expression below.
    property color accent: SmartAccentService.enabled ? SmartAccentService.accentColor : mauve
    Behavior on accent {
        ColorAnimation { duration: 400 }
    }
    readonly property color accentAlt:     lavender
    readonly property color danger:        red
    readonly property color success:       green
    readonly property color onAccent:      crust

    // -------------------- WINDOWS 11 / MICA SURFACE --------------------
    // Derived from base/surface0/surface1 above (not fixed rgba literals
    // like before) so these Mica overlays pick up the same Smart Accent
    // Color tint automatically -- recomputed against whatever
    // base/surface0/surface1 currently are instead of hardcoding their
    // untinted channel values.
    //
    // ── Background blur (Settings -> Appearance -> "Background blur") ──
    // `uiBgOpacity` is user-adjustable (SliderRow in SettingsPage.qml,
    // stored as `ui_bg_opacity` via the generic SettingsService key/value
    // store). It is the stored index of the INVERSE "Background blur"
    // slider: the LOWER it is (minimum 0.15 = the slider's 0% end) the
    // STRONGER the real blur AND the DENSER every derived surface gets --
    // at the default it is alpha 1.0, completely concealing the wallpaper;
    // the HIGHER it is (1.0 = the slider's 100% end) the weaker the blur
    // and the THINNER/more transparent the surfaces. The same value also
    // drives blurRadius below -- lowest = MAX blur (64px).
    //
    // The wallpaper is NOT concealed with opaque paint anymore (v2.9.b):
    // it is smeared by a REAL blur --
    //   * Live desktop (CachyOS/Hyprland): the QML scene never renders
    //     the wallpaper (mpvpaper owns it on its own Background layer),
    //     so scripts/frosted_glass.sh enables Hyprland's compositor blur
    //     (decoration:blur:* + a `blur` layerrule per app namespace) and
    //     frosts the animated wallpaper behind every translucent
    //     panel/dock/dock-overlay in real time.
    //   * In-app wallpaper imagery (WallpaperPreviewDialog): a genuine
    //     MultiEffect (QtQuick.Effects, ShaderEffectSource-backed) with
    //     blurMax = blurRadius below.
    // Clamped to [0.15, 1.0] and falls back to 0.15 (the LOWEST stored
    // value = the slider's 0% / maximum-blur end, so the app boots fully
    // frosted and concealing) if the stored value is missing/invalid,
    // e.g. before settings.json has been read once. NOTE: keep this
    // fallback in sync with SettingsService.qml's defaults block and
    // scripts/settings.sh's DEFAULT_SETTINGS.
    readonly property real uiBgOpacity: {
        const v = Number(SettingsService.settings.ui_bg_opacity);
        return (isFinite(v) && v >= 0.15 && v <= 1.0) ? v : 0.15;
    }

    // REAL in-QML blur radius (px) for wallpaper imagery this app itself
    // draws (WallpaperPreviewDialog's MultiEffect). Bound inversely to
    // the Background blur slider exactly as requested: at the slider
    // MINIMUM (blur % -> 0, i.e. uiBgOpacity 0.15) it pins to the
    // MAXIMUM -- 64px -- so every backdrop pixel is smeared into an
    // unreadable frosted smudge; it only eases down to a still-heavy
    // 24px if the slider is dragged all the way to its maximum blur-ease
    // end (uiBgOpacity 1.0).
    // The compositor-side radius for the live desktop maps the same
    // stored value through scripts/frosted_glass.sh (blur size 12 at the
    // slider's 0% maximum-blur end, easing down to 3 at the slider's 100%
    // end).
    readonly property int blurRadius: {
        const x = uiBgOpacity;
        return Math.round(Math.min(64, Math.max(24, (1.0 - x) * 128)));
    }
    property color panelBg:     Qt.rgba(base.r, base.g, base.b, micaAlpha(1.0))
    readonly property color panelBorder: Qt.rgba(0.7059, 0.7451, 0.9961, 0.15) // lavender @ 15%
    // Mica alpha mapping for the derived surfaces -- INVERSE to the
    // "Background blur" slider, exactly as requested. `uiBgOpacity` is
    // the stored slider index: the SMALLER it is (slider dragged toward
    // the minimum, 0.15) the STRONGER the real blur (blurRadius 64px /
    // frosted_glass.sh size 12) -- and in that state EVERY derived
    // surface DENSIFIES all the way to fully opaque (alpha exactly
    // 1.0, no matter its `factor`), so the frosted glass becomes a
    // thick, dense smear that completely conceals the wallpaper behind
    // the UI: at the slider's 0% end panelBg, cardBg, cardHoverBg and
    // segmentTrackBg are ALL alpha 1.0 -- the animated background is
    // 100% hidden. Raising the slider eases the blur radius down (still
    // heavy >= 24px) and each surface THINS OUT toward its own
    // translucent base (factor * 0.30) instead, so at the 100% end the
    // UI is at its most transparent and the (weakly blurred) wallpaper
    // shows through the most. The clamp keeps every alpha in [0, 1]
    // regardless.
    function micaAlpha(factor) {
        // dense = 1.0 when blur is at its MAXIMUM (uiBgOpacity 0.15),
        //          0.0 when the slider is at its maximum (uiBgOpacity 1.0).
        const dense = 1.0 - (uiBgOpacity - 0.15) / 0.85;
        // `base` = this surface's own thin translucency at the slider's
        // 100% end; it ramps linearly to exactly 1.0 as `dense` grows,
        // so at the maximum-blur end every layer is fully opaque and
        // nothing of the wallpaper shows through.
        const base = factor * 0.30;
        const alpha = base + (1.0 - base) * dense;
        return Math.min(1.0, Math.max(0.20, alpha));
    }
    // Performance: real blur lives on the GPU -- Hyprland's multi-pass
    // compositor blur for the desktop, the MultiEffect ShaderEffectSource
    // only for the small in-app preview -- and falls back to zero cost on
    // compositors without decoration blur. The QML rectangles stay the
    // same cheap Catppuccin fills they always were; fully opaque surfaces
    // (alpha 1.0, the default at the slider's low end) are the cheapest
    // QML case, so the maximum-blur default doubles as a perf-saver on
    // weak iGPUs too.
    property color cardBg:      Qt.rgba(surface0.r, surface0.g, surface0.b, micaAlpha(0.61))
    property color cardHoverBg: Qt.rgba(surface1.r, surface1.g, surface1.b, micaAlpha(0.89))

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
    // Dedicated 450ms curve for the new Smart-Accent-Color hover/active
    // "glow" indicators (Sidebar's right-edge rail, WallpaperCard's hover
    // border + Apply button, FilterTabs' underline). Kept separate from
    // durationSlow (380ms) so this specific accent cross-fade can be tuned
    // independently without touching any other existing animation.
    readonly property int durationAccentGlow: 450

    // -------------------- SEGMENTED CONTROL (Fluent pill) --------------------
    // Scales with Theme.micaAlpha(0.65) -- at the slider MINIMUM (maximum
    // blur) the track is at its densest, and it thins out as the slider
    // rises and blur eases off -- so the "Background blur" slider affects
    // this track too, not just panels/cards, and the wallpaper stays fully
    // concealed whenever blur is strongest.
    readonly property color segmentTrackBg:   Qt.rgba(0.0667, 0.0667, 0.1059, micaAlpha(0.65))
    // Derived from `accent` (not a fixed mauve rgba literal like before)
    // so Sidebar's active-nav-item pill, and anywhere else that reads
    // segmentActiveBg, tint with the Smart Accent Color too -- same 22%
    // alpha as the original constant, just recomputed against whatever
    // `accent` currently is instead of hardcoding mauve's channel values.
    readonly property color segmentActiveBg:  Qt.rgba(accent.r, accent.g, accent.b, 0.22)
    readonly property color segmentHoverBg:   Qt.rgba(1, 1, 1, 0.06)
}
