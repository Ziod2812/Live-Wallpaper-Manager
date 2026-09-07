import QtQuick
import Quickshell
import Quickshell.Io
import "Services"
import "Panels"
import "Manager"

// Live Wallpaper Manager v2.9 - Debian/Wayland startup-safe entry point.
//
// Important: do NOT instantiate PanelWindow/FloatingWindow objects directly
// from ShellRoot on startup. On some Debian + Wayland/Qt combinations a
// hidden native window can trigger a native Qt/Wayland crash before the QML
// UI is actually needed. Quickshell provides LazyLoader specifically for
// deferring window construction.
ShellRoot {
    id: root

    property bool triggerDockVisible: false

    // BUGFIX -- "Exit Application" doesn't close the app / leaves it
    // running: LiveWallpaperPanel.qml's own onReadyToClose only calls
    // Qt.quit() when panel.standalone is true, but that Connections block
    // only exists once panelLoader.item has actually been created. If the
    // user only ever opens the Manager window (Settings page) and never
    // opens the small panel, panelLoader stays inactive, so nothing in
    // the whole process ever calls Qt.quit() -- ApplicationService still
    // kills mpvpaper/the tray helper/awww-daemon correctly, but this
    // `quickshell -c livewallpaper` process itself keeps running in the
    // background forever. This is the one entry point guaranteed to be
    // alive for the process's entire lifetime (see the "always-live
    // objects" comment below), so it's the only safe place to guarantee
    // a real exit regardless of which windows were ever loaded.
    Connections {
        target: ApplicationService
        function onReadyToClose() {
            Qt.quit();
        }
    }

    // The only always-live objects in this root are IPC handlers and lazy
    // loaders. No native Wayland/XDG toplevel is created until requested.
    LazyLoader {
        id: panelLoader
        active: false
        component: Component {
            LiveWallpaperPanel {
                standalone: true
                ipcEnabled: false
            }
        }
    }

    LazyLoader {
        id: triggerLoader
        active: root.triggerDockVisible
        component: Component {
            TriggerDock {
                targetPanel: panelLoader.item
            }
        }
    }

    LazyLoader {
        id: managerLoader
        active: false
        component: Component {
            ManagerWindow {
                ipcEnabled: false
            }
        }
    }

    // Dock overlays are fully independent of the main panel -- see the
    // overlays' own headers: each visibility ALWAYS depends only on its
    // own settings key (+ auto-hide), never on LiveWallpaperPanel.visible.
    // Gate them on their settings alone so Music Dock / Peaclock+Cava
    // construct (and their Cava/MPRIS backends start) even when the main
    // panel itself has never been summoned.
    LazyLoader {
        id: musicDockLoader
        active: SettingsService.settings.music_dock_enabled === true
        component: Component { MusicDockOverlay { } }
    }

    LazyLoader {
        id: peaclockDockLoader
        active: SettingsService.settings.pcdock_enabled === true
        component: Component { PeaclockCavaDockOverlay { } }
    }

    // Root-owned IPC keeps the daemon usable even when the actual windows
    // are unloaded. This avoids duplicate IpcHandler targets when the lazy
    // child components are created.
    IpcHandler {
        target: "livewallpaper"

        function ensurePanel(): void {
            panelLoader.active = true
            if (panelLoader.item)
                panelLoader.item.open()
        }
        function toggle(): void {
            panelLoader.active = true
            if (panelLoader.item)
                panelLoader.item.toggle()
        }
        function open(): void {
            ensurePanel()
        }
        function close(): void {
            if (panelLoader.item)
                panelLoader.item.close()
        }
        function isOpen(): bool {
            return panelLoader.item ? panelLoader.item.visible : false
        }
        function togglePlayback(): void {
            PlaybackService.toggle()
        }
        function next(): void {
            PlaybackService.next()
        }
        function previous(): void {
            PlaybackService.previous()
        }
        function random(): void {
            PlaybackService.random()
        }
        function exitApplication(): void {
            ApplicationService.exit()
        }
        function restartApplication(): void {
            ApplicationService.restart()
        }
    }

    IpcHandler {
        target: "livewallpapermanager"

        function open(): void {
            managerLoader.active = true
            if (managerLoader.item)
                managerLoader.item.focusOrShow()
        }
        function close(): void {
            if (managerLoader.item)
                managerLoader.item.close()
        }
        function toggle(): void {
            managerLoader.active = true
            if (!managerLoader.item)
                return
            if (managerLoader.item.visible)
                managerLoader.item.close()
            else
                managerLoader.item.focusOrShow()
        }
        function isOpen(): bool {
            return managerLoader.item ? managerLoader.item.visible : false
        }
        function show(): void {
            managerLoader.active = true
            if (managerLoader.item)
                managerLoader.item.focusOrShow()
        }
        function hide(): void {
            if (managerLoader.item)
                managerLoader.item.close()
        }
    }

    // Wire the panel's UI requests after the panel has been created.
    Connections {
        target: panelLoader.item

        function onOpenManagerRequested() {
            managerLoader.active = true
            if (!managerLoader.item)
                return
            if (managerLoader.item.visible)
                managerLoader.item.close()
            else {
                if (panelLoader.item)
                    panelLoader.item.close()
                managerLoader.item.focusOrShow()
            }
        }

        function onToggleTriggerDockRequested() {
            root.triggerDockVisible = !root.triggerDockVisible
            triggerLoader.active = root.triggerDockVisible
        }
    }
}
