import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Components"
import "../Services"

/*
 * VisualizerPage.qml
 * ----------------------
 * PHASE 2 -- "Visualizer settings" moved here from the panel.
 *
 * UI SIMPLIFICATION: the standalone Music page has been removed (see
 * Manager/Navigation.qml) -- it only ever hosted MusicDockPanel.qml,
 * which this page already embedded too, so the two pages were showing
 * identical settings under different names. This page is now the single
 * home for both:
 *
 *   Section 1 -- Visualizer: the Cava preview (VisualizerPreview.qml).
 *   Section 2 -- Music Dock: MusicDockPanel.qml, unmodified -- same
 *     component, same SettingsService.set("music_dock_*", ...) keys,
 *     so every existing Music Dock setting (enable/autohide/click-
 *     through/blur/glow, opacity/size/radius sliders, monitor
 *     placement, plus the Cava bar-count/width/spacing/sensitivity/
 *     color-mode rows the component also owns) keeps working exactly
 *     as before. Nothing was rewritten or duplicated to make this
 *     merge -- just the two pages collapsed into one.
 *
 * CavaService's own header says it plainly: it "owns the real audio-
 * visualizer pipeline for Music Dock" -- the two were never really
 * separate features, just two settings surfaces for the same thing.
 *
 * FIX (preset visibility + scroll/clipping) -- two, independent, minimal
 * changes on top of the above, neither touching Music Dock or Peaclock +
 * Cava Dock's own component files:
 *
 *   1. Root is now a Flickable (root.cavaOn / root.peaclockOn drive which
 *      of Section 2 / Section 3 is `visible`), matching the exact pattern
 *      already used by every other scrollable page in this app --
 *      Pages/PlaylistPage.qml, Pages/MonitorPage.qml,
 *      Pages/PerformancePage.qml, Pages/SettingsPage.qml all wrap their
 *      content ColumnLayout in `Flickable { contentHeight:
 *      content.implicitHeight; clip: true; boundsBehavior:
 *      Flickable.StopAtBounds }`. This page was the one page that never
 *      got that treatment (it just anchor.fill'd a bare ColumnLayout
 *      inside ManagerWindow.qml's `clip: true` page container -- see
 *      that file), so once two full dock settings panels were visible
 *      at once its content could exceed the viewport with no way to
 *      scroll to the rest -- ManagerWindow.qml itself is untouched.
 *
 *   2. Section 2 (MusicDockPanel) and Section 3 (PeaclockCavaDockPanel)
 *      each get a `visible: ...` binding off their OWN dock's enabled
 *      setting below, so each panel's visibility tracks its own dock --
 *      and, since Qt Quick Layouts already excludes
 *      `visible: false` children from space allocation (same convention
 *      already relied on elsewhere in this app, e.g.
 *      the performance panel's visibility
 *      `visible: root.boostOpen` sections), the hidden panel no longer
 *      contributes to contentHeight either -- so Fix 1 and Fix 2 close
 *      the same root cause together for the "always some content
 *      clipped" symptom.
 *
 * FIX (independent presets) -- "Cava" and "Cava + Peaclock" are no longer
 * mutually exclusive. Each preset now writes ONLY its own dock's enable
 * setting (music_dock_enabled / pcdock_enabled respectively) -- neither
 * write ever touches the other setting -- so both docks can be enabled
 * at once, either alone, or neither. CavaPresetSwitcher.qml's control
 * mechanism changed to match (independent per-segment toggles instead of
 * a single-select switch; see that file's header). Both Section 2 and
 * Section 3 below are now visible/hidden purely off their OWN dock's
 * enabled setting, not off a single shared "which preset is active"
 * flag -- so both settings panels can be visible at once, matching
 * what's actually running.
 */
Flickable {
    id: root
    anchors.fill: parent
    contentWidth: width
    contentHeight: content.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    // ── Independent per-preset state ──────────────────────────────────────
    // Each preset is driven purely by its own dock's enable setting -- no
    // shared "which one is active" flag, no forced exclusivity between
    // them. Both can be true, both can be false, either can be true alone.
    readonly property bool cavaOn: SettingsService.settings.music_dock_enabled === true
    readonly property bool peaclockOn: SettingsService.settings.pcdock_enabled === true

    ColumnLayout {
        id: content
        width: root.width
        spacing: Theme.spacingLg

        // ── Section 0: Preset switcher (NEW, additive) ───────────────────
        // Segmented "Cava | Cava + Peaclock" control, visually matching
        // the existing Wallpapers/Streaming/Web pill
        // (Components/ModeSwitcher.qml) via the new
        // Components/CavaPresetSwitcher.qml -- see that file's header for
        // why it's a separate component rather than a change to
        // ModeSwitcher itself, and for why it's now an independent-toggle
        // control rather than a single-select switch.
        //
        // Toggling a preset writes ONLY that preset's own dock enable
        // setting (the same "music_dock_enabled" / "pcdock_enabled" keys
        // their own panels' "Enable ..." toggles already use) -- never
        // the other one:
        //   "Cava"            -> music_dock_enabled = <on/off>
        //   "Cava + Peaclock" -> pcdock_enabled     = <on/off>
        // Panels/PeaclockCavaDockOverlay.qml's and Panels/
        // MusicDockOverlay.qml's own _syncBackends() (both unmodified)
        // already start/stop Peaclock/Cava gracefully off these exact
        // keys -- and now register/release their own consumer id with
        // CavaService (see that file's "Multi-consumer reference
        // counting" header), so the shared Cava pipeline stays running
        // for as long as EITHER dock still wants it, and there is still
        // only ever one cava process no matter which combination of
        // presets is on.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingMd

            Text {
                text: "Preset"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeLg
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            CavaPresetSwitcher {
                activePresets: {
                    const active = [];
                    if (root.cavaOn) active.push("cava");
                    if (root.peaclockOn) active.push("cava_peaclock");
                    return active;
                }
                onPresetToggled: (preset, enabled) => {
                    if (preset === "cava_peaclock") {
                        SettingsService.set("pcdock_enabled", enabled);
                    } else {
                        SettingsService.set("music_dock_enabled", enabled);
                    }
                }
            }
        }

        // ── Section 1: Visualizer ─────────────────────────────────────────
        // Shown for BOTH presets (per the fix spec) -- unaffected by
        // either dock's enabled state.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingMd

            Text {
                text: "Visualizer"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeLg
                font.bold: true
            }

            Text {
                Layout.fillWidth: true
                text: "Live preview of the Cava audio visualizer used by the Music Dock below -- both share the same settings service, so there's one control surface for the whole feature."
                color: Theme.subtext0
                font.family: Theme.fontFamilyUi
                font.pixelSize: Theme.fontSizeSm
                wrapMode: Text.WordWrap
            }

            VisualizerPreview {
                Layout.fillWidth: true
            }
        }

        // ── Section 2: Music Dock ──────────────────────────────────────────
        // No separate outer heading here -- MusicDockPanel draws its own
        // "🎵 Music Dock" title + enabled/disabled status in its fixed
        // header row, so an extra "Music Dock" Text above it would just
        // duplicate that label.
        //
        // visible: purely off this dock's OWN enabled setting (FIX 1) --
        // an invisible Layout child takes no space, so this also removes
        // it from `content.implicitHeight` (FIX 2) when off. Independent
        // of Section 3 below -- both can be visible at once now that the
        // two presets aren't exclusive. Component itself, its settings,
        // and its own "Enable Music Dock" toggle are completely
        // unmodified.
        MusicDockPanel {
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            visible: root.cavaOn
            // Page is the container now; the panel's own ✕ is a no-op
            // here (matches PlaylistPage.qml's own note on the same
            // pattern).
            onCloseRequested: {}
        }

        // ── Section 3: Peaclock + Cava Dock (NEW, additive) ────────────────
        // A second, fully independent dock -- own overlay window, own
        // "pcdock_*" settings, own enable/disable -- placed here purely
        // for settings-surface convenience (same page Music Dock's
        // settings live on). Does not read or affect any music_dock_*
        // setting.
        //
        // visible: purely off this dock's OWN enabled setting (FIX 1),
        // same space-collapsing effect as Section 2 above (FIX 2), and
        // just as independent of it. Component itself is completely
        // unmodified.
        PeaclockCavaDockPanel {
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            visible: root.peaclockOn
        }

        // Bottom padding -- ensures the active panel's last row/control
        // is fully reachable above the window edge (and, in the embedded
        // case, above the compositor's own status bar) instead of ending
        // flush with the last pixel of scrollable content. Fixed height,
        // not Layout.fillHeight: true -- the old trailing spacer relied
        // on this ColumnLayout having a bounded height from
        // `anchors.fill: parent` (fillHeight has no effect now that the
        // layout's height is intrinsic/content-driven inside a
        // Flickable).
        Item { Layout.preferredHeight: Theme.spacingXl }
    }
}
