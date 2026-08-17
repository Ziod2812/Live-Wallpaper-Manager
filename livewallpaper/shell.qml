import Quickshell
import "Panels"
import "Manager"
import "Services"

// shell.qml
// -----------
// Standalone entry point: `quickshell -c livewallpaper` (or -p <path to
// this file>) runs Live Wallpaper Manager on its own, independent of any
// other Caelestia modules.
//
// To embed it INTO an existing Caelestia shell.qml instead (recommended,
// so it shares Caelestia's single Quickshell process), just instantiate
// LiveWallpaperPanel, TriggerDock, and MusicDockOverlay from Caelestia's
// own ShellRoot, e.g.:
//
//   import "modules/livewallpaper/Panels" as LiveWallpaper
//   ...
//   LiveWallpaper.LiveWallpaperPanel { id: liveWallpaperPanel }
//   LiveWallpaper.TriggerDock { targetPanel: liveWallpaperPanel }
//   LiveWallpaper.MusicDockOverlay { }
//
// and wire your own bar button / keybind to `liveWallpaperPanel.toggle()`
// instead of using TriggerDock at all. MusicDockOverlay is independent
// of both -- it's a standalone desktop overlay gated purely by the
// "Enable Music Dock" setting, so it stays up even if the panel/trigger
// dock above are never shown.
ShellRoot {
    id: root

    // ── TriggerDock's single shared visibility flag ──────────────────────
    // Starts hidden. This is the ONE piece of state controlling whether
    // TriggerDock (the "LW" corner shortcut) is shown -- toggled only by
    // the panel's ▼ button (MiniTitleBar -> LiveWallpaperPanel's
    // toggleTriggerDockRequested() -> flipped here) and read directly by
    // TriggerDock's own `visible` binding below. Deliberately NOT derived
    // from liveWallpaperPanel.visible or managerWindow.visible in either
    // direction any more (that inverse-of-the-panel relationship was the
    // previous, incorrect behavior -- see LiveWallpaperPanel.qml's NOTE
    // for why it only ever let ▼ fire once). TriggerDock itself is still
    // the same single instance declared once below, plain child of
    // ShellRoot, never behind a Loader/LazyLoader -- this flag only ever
    // shows or hides it, never destroys or recreates it.
    property bool triggerDockVisible: false

    // PHASE 4 -- system tray (see Services/TrayService.qml). Singletons
    // are lazily instantiated on first access, so this property binding
    // is what actually brings TrayService to life for this process --
    // without touching one of its properties somewhere that's evaluated
    // at startup, the singleton would never be created until something
    // else (previously only SettingsPage.qml's toggle) happened to read
    // from it, meaning the tray icon would silently fail to appear on
    // launch unless the user opened Settings first. It's not a window,
    // so it doesn't fit LiveWallpaperPanel/ManagerWindow's pattern
    // above. Runs for the whole process lifetime, independent of
    // whether the panel or Manager window are open.
    readonly property bool _trayServiceKeepAlive: TrayService.enabledSetting

    LiveWallpaperPanel {
        id: liveWallpaperPanel
        // This entry point runs Live Wallpaper Manager as the only thing
        // in the process (see the file header) -- Exit Application is
        // safe to quit the whole Quickshell process here. Leave this
        // unset (defaults to false) when embedding into a shared shell.
        standalone: true
        // PHASE 2: the panel's "Open Manager" button only emits a
        // signal (it has no reference to managerWindow, a sibling
        // below) -- shell.qml is what wires the two together.
        //
        // BUGFIX #1 (panel/Manager overlap): this used to be
        // `onOpenManagerRequested: managerWindow.open()`, which opened the
        // Manager without ever hiding the panel, so the two centered
        // windows overlapped and covered the panel's own controls.
        //
        // BUGFIX #2: unconditionally calling managerWindow.open() also
        // meant a second click did nothing -- open() just re-sets
        // visible = true, which is already true, so there was no way to
        // close the Manager from this button. The fix is to branch on
        // managerWindow.visible (ManagerWindow's own FloatingWindow.visible
        // -- see ManagerWindow.qml, which already exposes
        // toggle()/open()/close() around that single property, and whose
        // IPC handler and the WM titlebar close button all funnel through
        // it too) so this becomes a real toggle instead of an "open only"
        // action:
        //   - Manager currently open  -> close it, leave the panel as-is.
        //   - Manager currently closed -> close the panel (if it's not
        //     already closed -- close() is idempotent) so the two windows
        //     never overlap, then open the *same* managerWindow instance
        //     (it's a plain child of ShellRoot below, never
        //     Loader-instantiated or recreated, so there is only ever one
        //     Manager window to reuse). TriggerDock is untouched by any of
        //     this -- its visibility is its own independent flag
        //     (triggerDockVisible above), not derived from
        //     liveWallpaperPanel.visible, so it stays exactly as shown or
        //     hidden as it was before this button was clicked.
        // liveWallpaperPanel.visible and managerWindow.visible each remain
        // the single source of truth for their own window -- no new flags
        // are introduced, and nothing here can drift out of sync with the
        // WM close button, the IPC handlers, or TriggerDock.
        onOpenManagerRequested: {
            if (managerWindow.visible) {
                managerWindow.close();
            } else {
                liveWallpaperPanel.close();
                managerWindow.open();
            }
        }

        // Live feed for MiniTitleBar's ▼ button toggle-switch look
        // (relayed through LiveWallpaperPanel.qml -> MiniTitleBar.qml).
        triggerDockVisible: root.triggerDockVisible
        // ▼ button (MiniTitleBar) asking to flip TriggerDock. This is the
        // ONLY place triggerDockVisible is ever written -- see that
        // property's own comment above for why nothing else touches it.
        onToggleTriggerDockRequested: root.triggerDockVisible = !root.triggerDockVisible
    }

    // The panel's ▼ button now drives TriggerDock's visibility completely
    // independently of the panel's own show/hide state -- see
    // triggerDockVisible above and LiveWallpaperPanel.qml's NOTE for why
    // the previous "exact inverse of liveWallpaperPanel.visible" binding
    // was wrong (it let ▼ fire only once, since hiding the panel also hid
    // the button). This dock's "LW" button (TriggerDock.qml ->
    // targetPanel.toggle()) is unchanged and still only ever toggles the
    // panel -- it has no effect on this binding either. TriggerDock stays
    // the single instance declared here for the process lifetime; this
    // binding only ever shows or hides it, never destroys or recreates it.
    TriggerDock {
        targetPanel: liveWallpaperPanel
        visible: root.triggerDockVisible
    }

    // Standalone desktop overlay -- deliberately NOT parented to or
    // gated by liveWallpaperPanel; see MusicDockOverlay.qml's header for
    // why that's what makes it survive the panel being closed.
    MusicDockOverlay { }

    // NEW -- Peaclock + Cava Dock. A second, fully independent standalone
    // overlay (own PanelWindow, own settings, own enable/disable/lifecycle
    // -- see PeaclockCavaDockOverlay.qml's header). Declaring it here,
    // alongside MusicDockOverlay, does not touch or depend on that dock in
    // any way; either can be enabled/disabled without affecting the other.
    PeaclockCavaDockOverlay { }

    // PHASE 1 -- Desktop Application Foundation (see Manager/ManagerWindow.qml).
    // PHASE 2 -- now the app's actual settings surface (see Pages/) and
    // reachable from the panel's "Open Manager" button (wired above).
    // Still a separate, normal (non-layer-shell) desktop window with its
    // own "livewallpapermanager" IPC target -- entirely independent of
    // liveWallpaperPanel's own "livewallpaper" IPC target.
    ManagerWindow {
        id: managerWindow
    }
}
