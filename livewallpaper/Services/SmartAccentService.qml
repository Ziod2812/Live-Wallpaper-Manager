pragma Singleton
import Quickshell
import QtQuick

/*
 * SmartAccentService.qml
 * ------------------------
 * Reactive view of the "Smart Accent Color" feature's output.
 *
 * apply_smart_color.py (scripts/apply_smart_color.py) runs ASYNCHRONOUSLY
 * in the background right after a wallpaper/GIF/live-wallpaper is applied
 * (see _apply_worker.sh / _web_worker.sh). It writes the extracted HEX
 * color into settings.json's "active_accent_color" key via settings.sh's
 * atomic mset -- this service just reads that one key the exact same way
 * every other reactive setting is read (SettingsService.settings.*), so
 * no new FileView/polling is introduced here; SettingsService's existing
 * watchChanges reload already picks it up.
 *
 * `enabled` gates the WHOLE feature behind the "Smart Accent Color"
 * toggle in Settings (default OFF -- see settings.sh's DEFAULT_SETTINGS)
 * so a fresh install/existing user keeps today's fixed Catppuccin Mauve
 * theme untouched unless they explicitly opt in. Theme.qml (accent /
 * segmentActiveBg) reads `active` below rather than accentColor directly,
 * so every consumer of Theme.accent across the app (Sidebar border,
 * Toolbar search-focus border, IconButton borders/active bg, sliders,
 * ToggleSwitch, "Start/Stop Wallpaper" buttons, title text, etc.) gets
 * the feature for free without touching 30+ files individually.
 *
 * Color transitions are intentionally NOT animated here -- Theme.qml
 * applies the single `Behavior on color { ColorAnimation { duration: 400 } }`
 * fade for `accent`, and every consumer above already re-derives its own
 * (already-existing) Behavior on top of that, so the 400ms cross-fade
 * happens exactly once at the source instead of being duplicated in
 * every reader.
 */
QtObject {
    id: service

    // Master on/off switch (Settings > Appearance > "Smart Accent Color").
    readonly property bool enabled: SettingsService.settings.smart_accent_enabled === true

    // Raw HEX string as last written by apply_smart_color.py. Falls back
    // to the same dark system color the Python side uses on error
    // (FALLBACK_COLOR = "#353446"), so an empty/corrupt settings.json
    // value can never produce an invalid `color` binding below.
    readonly property string accentHex: {
        const c = SettingsService.settings.active_accent_color;
        return (typeof c === "string" && /^#[0-9a-fA-F]{6}$/.test(c)) ? c : "#353446";
    }

    // The actual QML color other modules bind to. Theme.qml (the only
    // consumer of this service, by design -- see its header) combines
    // this with its own static Mauve constant to decide what `Theme.accent`
    // should render as; kept as a plain accentColor here (no `enabled`
    // branching in this property) so SmartAccentService never needs to
    // know about Theme's palette at all, avoiding a Config <-> Services
    // import cycle.
    readonly property color accentColor: accentHex
}
