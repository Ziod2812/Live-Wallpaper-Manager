import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../Config"
import "../Services"
import "../Components"
import "../Pages"

/*
 * ManagerWindow.qml
 * -------------------
 * PHASE 1 -- Desktop Application Foundation.
 * PHASE 2 -- Move Configuration UI: this window is now the app's actual
 * settings surface (Wallpaper/Streaming/Web mode + browsing, Playlist,
 * Music Dock, Visualizer, per-monitor target, Smart Playback
 * performance tuning, and General/directory/cache/exit settings all
 * live in Pages/ now -- see each page file's header for exactly which
 * existing Component it reuses).
 * PHASE 4 -- Production polish: keyboard shortcuts, window state
 * restore (position/size/last page, persisted via the existing generic
 * SettingsService.set() key/value store -- no new persistence
 * mechanism), a responsive sidebar collapse, and a page fade
 * transition. See each addition's own comment below.
 *
 * BUGFIX -- "Open Manager can't reopen after closing via the titlebar
 * X": corrected. The previous fix here assumed Quickshell exposes Qt
 * Quick Window's cancelable `closing(CloseEvent)` signal (the one with
 * `close.accepted`) and tried to redirect it through close(). Quickshell
 * does NOT expose that signal on FloatingWindow/QsWindow -- there is no
 * "closing" signal and no accept/reject mechanism at all, which is why
 * `onClosing:` failed to parse ("Cannot assign to non-existent
 * property"). See https://quickshell.org/docs/v0.3.0/types/Quickshell/QsWindow/ .
 *
 * What Quickshell exposes instead is QsWindow.closed() -- an
 * *informational*, non-cancelable signal fired after the window has
 * already been closed by the user, the display server, or an error.
 * There is nothing to intercept or veto.
 *
 * The reopen bug turned out not to need interception at all. Quickshell's
 * own docs recommend controlling a window purely through its `visible`
 * property, and a native titlebar close only ever flips that property to
 * false -- it does not destroy the underlying QML item. Since
 * ManagerWindow is instantiated directly in this file (not behind a
 * Loader/LazyLoader), the singleton lives for the lifetime of the shell
 * regardless of how it was closed; `visible` simply goes false, exactly
 * as if close() had been called, so Open Manager setting `visible = true`
 * again always has something to show. The onClosed handler below just
 * keeps every close path (titlebar X, Ctrl+W, IPC, onReadyToClose)
 * funneled through the same close() function for consistency -- see its
 * own comment.
 *
 * Kept entirely separate from the existing LiveWallpaperPanel
 * (Panels/LiveWallpaperPanel.qml):
 *
 *   - LiveWallpaperPanel is a Quickshell PanelWindow: a layer-shell
 *     surface, centered, no window decorations, toggled via IPC target
 *     "livewallpaper". It is UNTOUCHED by this file.
 *   - ManagerWindow is a Quickshell FloatingWindow: a normal, WM-managed
 *     desktop window with a title bar, resizing and an app-switcher/
 *     taskbar entry -- Quickshell's equivalent of QtQuick Controls'
 *     ApplicationWindow for windows that should NOT be layer-shell
 *     surfaces. It is toggled via its own IPC target,
 *     "livewallpapermanager", so it can never collide with the panel's
 *     "livewallpaper" target.
 *
 * Layout: Toolbar (top) / Toast / [Sidebar | page Loader] (middle) /
 * StatusBar (bottom). Navigation.qml (a singleton -- see
 * Manager/qmldir) is the single source of truth for the page list;
 * Sidebar just renders it and the Loader just follows it.
 *
 * No Service is rewritten or duplicated here -- pages import the same
 * Services/ singletons the panel always used.
 */
FloatingWindow {
    id: managerWindow

    title: "Live Wallpaper Manager"

    // ── PHASE 4: window state restore ──────────────────────────────────
    // Seeded once from settings on first paint (Component.onCompleted
    // below, not here -- reading `x`/`y`/`width`/`height` directly as
    // property initializers races FloatingWindow's own initial
    // placement on some window managers). Falls back to the original
    // Phase 1 defaults when nothing's been saved yet.
    implicitWidth: 1180
    implicitHeight: 760
    minimumSize: Qt.size(900, 600)
    visible: false
    color: Theme.base

    readonly property bool responsiveCollapsed: width < 760
    property real sidebarWidth: responsiveCollapsed ? 60 : 220
    Behavior on sidebarWidth {
        NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutCubic }
    }

    function open() {
        managerWindow.visible = true;
    }
    function close() {
        managerWindow.visible = false;
    }
    function toggle() {
        managerWindow.visible = !managerWindow.visible;
    }
    // PHASE 4 -- system tray left-click / "Show / Open": open() alone
    // only ever sets visible = true, which is a no-op (no raise, no
    // focus) if the window is already visible but sitting behind
    // something else -- exactly the case a tray left-click needs to
    // handle. raise()/requestActivate() are the standard QtQuick Window
    // calls for "bring to front and give it keyboard focus", available
    // here since FloatingWindow is a real WM-managed top-level window
    // (see this file's header). Safe to call whether the window was
    // already visible or hidden.
    function focusOrShow() {
        console.log("[IPC] managerWindow.focusOrShow() called");
        managerWindow.visible = true;
        console.log("[IPC] visible changed -> true");
        managerWindow.raise();
        managerWindow.requestActivate();
        console.log("[IPC] activation requested (raise + requestActivate)");
    }

    // ── WM titlebar X button ─────────────────────────────────────────────
    // FloatingWindow is a real, WM-decorated top-level window (unlike
    // LiveWallpaperPanel's layer-shell PanelWindow, which has no titlebar
    // and so was never exposed to this). Every *in-app* path that closes
    // this window (close()/toggle() above, the Ctrl+W shortcut, the
    // "livewallpapermanager" IPC target, and ApplicationService's
    // onReadyToClose below) already went through managerWindow.visible =
    // false, which just hides the existing QML item -- it is never
    // destroyed by any of that code.
    //
    // Quickshell does not give FloatingWindow a cancelable "closing"
    // signal (that's a QtQuick.Window/ApplicationWindow API Quickshell
    // doesn't implement -- see the file header comment above), so there
    // is no accept/reject step to hook for the native X button, and none
    // is needed: clicking it drives `visible` to false the same way
    // close() does, without destroying this item. QsWindow.closed() is
    // Quickshell's only signal here, fired *after* that has already
    // happened, purely informational. We still hook it -- calling the
    // same close() every other path uses keeps any future close-time
    // bookkeeping (e.g. persisting state) in one place instead of
    // duplicated across every trigger.
    onClosed: managerWindow.close()

    // Exposes: quickshell -c livewallpaper ipc call livewallpapermanager open|close|toggle
    // Deliberately a different target name than LiveWallpaperPanel's
    // "livewallpaper" IPC target so the two windows can never be
    // confused or accidentally cross-wired.
    //
    // IPC-LIFECYCLE FIX: `open`/`toggle` used to route through
    // managerWindow.open()/toggle() (plain `visible = true`, see those
    // functions above). That is fine for the "Open Manager" button in
    // LiveWallpaperPanel (shell.qml's onOpenManagerRequested), which
    // runs on a WM-focused click and so the WM already gives the newly
    // -mapped window focus/stacking on its own. An `ipc call` arrives
    // from an *external* process (a terminal, a compositor keybind)
    // with no window of its own focused, so on several window managers
    // a bare `visible = true` transition maps the window without
    // raising or focusing it -- it can end up open but stacked behind
    // whatever already has focus, which reads as "the command did
    // nothing". `focusOrShow()` (defined above, already used by the
    // system tray's `show` below) additionally calls raise() and
    // requestActivate(), which is exactly the "reuse the existing
    // window, show it, raise it, activate it" sequence this needs --
    // so `open`/`toggle` now use it too. `close`/`isOpen` are unchanged.
    // Temporary console.log calls below trace each step during testing
    // -- see the project notes for removal before final release.
    IpcHandler {
        target: "livewallpapermanager"

        function open(): void {
            console.log("[IPC] livewallpapermanager.open received");
            managerWindow.focusOrShow();
            console.log("[IPC] managerWindow.open() -> focusOrShow(): visible =", managerWindow.visible, "activation requested");
        }
        function close(): void {
            console.log("[IPC] livewallpapermanager.close received");
            managerWindow.close();
            console.log("[IPC] visible =", managerWindow.visible);
        }
        function toggle(): void {
            console.log("[IPC] livewallpapermanager.toggle received, visible was", managerWindow.visible);
            if (managerWindow.visible) {
                managerWindow.close();
            } else {
                managerWindow.focusOrShow();
            }
            console.log("[IPC] visible =", managerWindow.visible);
        }
        function isOpen(): bool { return managerWindow.visible; }

        // PHASE 4 -- system tray. `show`/`hide` are the tray's own verbs
        // (see scripts/_tray_icon.py's menu) kept distinct from
        // open()/close() above: `show` additionally raises/focuses (see
        // focusOrShow()), and `hide` is just close() under the name the
        // tray menu actually presents to the user, so the IPC surface
        // reads the same as the menu it's driving. No existing target/
        // method above is renamed or removed.
        function show(): void { managerWindow.focusOrShow(); }
        function hide(): void { managerWindow.close(); }
    }

    // Matches LiveWallpaperPanel.qml's own Connections block -- each
    // window is responsible for closing itself once ApplicationService
    // confirms playback has actually stopped. See ApplicationService.qml
    // and the panel's header comment for why this waits for
    // onReadyToClose instead of closing immediately on the Exit click.
    Connections {
        target: ApplicationService
        function onReadyToClose() {
            managerWindow.close();
        }
    }

    // ── PHASE 4: window state restore ──────────────────────────────────
    // Debounced (400ms) so dragging/resizing doesn't spam
    // SettingsService.set() on every intermediate frame -- same
    // "wait for the gesture to actually stop" idea as
    // SearchBar.qml's existing 150ms debounce.
    Timer {
        id: saveGeometryTimer
        interval: 400
        onTriggered: {
            SettingsService.set("manager_window_width", managerWindow.width);
            SettingsService.set("manager_window_height", managerWindow.height);
        }
    }
    onWidthChanged: if (_restored) saveGeometryTimer.restart()
    onHeightChanged: if (_restored) saveGeometryTimer.restart()

    // Guards against the restore step itself (below) re-triggering the
    // save timer, and against saving the transient geometry FloatingWindow
    // reports before its first real layout pass.
    property bool _restored: false

    Component.onCompleted: {
        const s = SettingsService.settings;
        if (typeof s.manager_window_width === "number" && s.manager_window_width > 0) {
            managerWindow.width = s.manager_window_width;
            managerWindow.height = s.manager_window_height;
        }
        if (typeof s.manager_last_page === "string" && s.manager_last_page.length > 0) {
            Navigation.navigate(s.manager_last_page);
        }
        _restored = true;
    }

    property string pendingSettingsSearch: ""

    function handleSettingsSearch(query) {
        const q = String(query || "").trim().toLowerCase();
        pendingSettingsSearch = q;
        if (!q.length)
            return;

        // Search the actual settings-bearing Manager pages instead of always
        // forcing the user onto Settings.  Keep this deliberately small and
        // deterministic: the existing header/search UI stays unchanged.
        const routes = [
            { page: "settings", terms: ["wallpaper", "directory", "folder", "path", "cache", "login", "autostart", "notification", "tray", "system tray"] },
            { page: "performance", terms: ["gpu", "graphics", "hardware decoding", "hwdec", "performance", "battery", "smart playback", "fps", "resolution", "cpu", "ram"] },
            { page: "visualizer", terms: ["cava", "visualizer", "music dock", "peaclock", "audio", "mpris"] },
            { page: "playlist", terms: ["playlist", "shuffle", "loop", "sequential", "random", "favorites", "interval"] },
            { page: "monitor", terms: ["monitor", "display", "resolution", "output"] }
        ];

        for (let i = 0; i < routes.length; i++) {
            const route = routes[i];
            if (route.terms.some(term => term.indexOf(q) !== -1 || q.indexOf(term) !== -1)) {
                if (Navigation.currentId !== route.page) {
                    Navigation.navigate(route.page);
                    return;
                }
                if (pageLoader.item && typeof pageLoader.item.focusSettingSearch === "function") {
                    pageLoader.item.focusSettingSearch(q);
                    pendingSettingsSearch = "";
                }
                return;
            }
        }

        // Unknown query: keep the current page untouched rather than
        // unexpectedly navigating somewhere unrelated.
        if (pageLoader.item && typeof pageLoader.item.focusSettingSearch === "function") {
            pageLoader.item.focusSettingSearch(q);
        }
    }

    // Persist last-viewed page so reopening the app returns to it.
    Connections {
        target: Navigation
        function onCurrentIdChanged() {
            SettingsService.set("manager_last_page", Navigation.currentId);
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Toolbar {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            windowTitle: managerWindow.title
            currentPageLabel: Navigation.currentItem ? Navigation.currentItem.label : ""
            onSettingsSearchRequested: function(query) {
                managerWindow.handleSettingsSearch(query)
            }
        }

        Toast {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacingLg
            Layout.rightMargin: Theme.spacingLg
            Layout.topMargin: Theme.spacingSm
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Sidebar {
                id: sidebar
                Layout.fillHeight: true
                // PHASE 4 -- responsive collapse: icon rail under 760px wide.
                Layout.preferredWidth: sidebarWidth
                collapsed: managerWindow.responsiveCollapsed
                model: Navigation.items
                currentId: Navigation.currentId
                onNavigate: id => Navigation.navigate(id)
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.mantle
                clip: true

                // ── Page Loader ──────────────────────────────────────────
                // Swaps in whichever page Navigation.currentItem points at.
                // `asynchronous: true` (PHASE 4 / "Optimize -> lazy
                // loading") lets a heavier page (Wallpapers' grid) load
                // without blocking the UI thread the way a synchronous
                // Loader would.
                Loader {
                    id: pageLoader
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLg
                    asynchronous: true
                    source: Navigation.currentItem ? Navigation.currentItem.source : ""

                    // PHASE 4 -- page transition: fade in each time a new
                    // page finishes loading. Deliberately fade-in only
                    // (no fade-out of the outgoing page first) -- with an
                    // asynchronous Loader the outgoing item is already
                    // gone by the time the new one starts loading, so
                    // there's nothing to cross-fade against.
                    opacity: 0
                    onLoaded: {
                        fadeIn.restart()
                        if (Navigation.currentId === "settings"
                                && managerWindow.pendingSettingsSearch.length > 0
                                && pageLoader.item
                                && typeof pageLoader.item.focusSettingSearch === "function") {
                            pageLoader.item.focusSettingSearch(managerWindow.pendingSettingsSearch)
                            managerWindow.pendingSettingsSearch = ""
                        }
                    }
                    NumberAnimation {
                        id: fadeIn
                        target: pageLoader
                        property: "opacity"
                        from: 0; to: 1
                        duration: Theme.durationNormal
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        StatusBar {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            statusText: "Ready"
            pageLabel: Navigation.currentItem ? Navigation.currentItem.label : ""
        }
    }

    // ── PHASE 4: keyboard shortcuts ─────────────────────────────────────
    // Ctrl+1..7 jump directly to a page (one Shortcut per current
    // Navigation.items entry -- see that file; the standalone Music page
    // was removed there, so there are 7 pages now, not 8, and the old
    // Ctrl+8 binding below was removed to match); Ctrl+Tab/Ctrl+Shift+Tab step
    // through them in order; Ctrl+F focuses the Wallpapers page's search
    // field (switching to that page first if needed); Ctrl+W closes the
    // window (same as the titlebar close button -- NOT "Exit
    // Application", which stays a deliberate, confirmed action on the
    // Settings page).
    Shortcut {
        sequence: "Ctrl+W"
        onActivated: managerWindow.close()
    }
    Shortcut {
        sequence: "Ctrl+F"
        onActivated: {
            if (Navigation.currentId !== "wallpapers") {
                Navigation.navigate("wallpapers");
            } else if (pageLoader.item && pageLoader.item.focusSearch) {
                pageLoader.item.focusSearch();
            }
        }
    }
    Shortcut {
        sequence: "Ctrl+Tab"
        onActivated: {
            const items = Navigation.items;
            const i = items.findIndex(p => p.id === Navigation.currentId);
            Navigation.navigate(items[(i + 1) % items.length].id);
        }
    }
    Shortcut {
        sequence: "Ctrl+Shift+Tab"
        onActivated: {
            const items = Navigation.items;
            const i = items.findIndex(p => p.id === Navigation.currentId);
            Navigation.navigate(items[(i - 1 + items.length) % items.length].id);
        }
    }
    Shortcut { sequence: "Ctrl+1"; onActivated: if (Navigation.items.length > 0) Navigation.navigate(Navigation.items[0].id) }
    Shortcut { sequence: "Ctrl+2"; onActivated: if (Navigation.items.length > 1) Navigation.navigate(Navigation.items[1].id) }
    Shortcut { sequence: "Ctrl+3"; onActivated: if (Navigation.items.length > 2) Navigation.navigate(Navigation.items[2].id) }
    Shortcut { sequence: "Ctrl+4"; onActivated: if (Navigation.items.length > 3) Navigation.navigate(Navigation.items[3].id) }
    Shortcut { sequence: "Ctrl+5"; onActivated: if (Navigation.items.length > 4) Navigation.navigate(Navigation.items[4].id) }
    Shortcut { sequence: "Ctrl+6"; onActivated: if (Navigation.items.length > 5) Navigation.navigate(Navigation.items[5].id) }
    Shortcut { sequence: "Ctrl+7"; onActivated: if (Navigation.items.length > 6) Navigation.navigate(Navigation.items[6].id) }
}
