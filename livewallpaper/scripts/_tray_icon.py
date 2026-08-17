#!/usr/bin/env python3
"""
_tray_icon.py
---------------
PHASE 4 -- "System tray" requirement.

REWRITE NOTE (tray-not-appearing fix): this used to shell out to
`pystray`. On this runtime pystray has no AppIndicator3/AyatanaAppIndicator3
GObject-introspection typelib available (that's a *system* package --
e.g. `gir1.2-ayatanaappindicator3-0.1` -- not something pip can install),
so pystray silently fell back to its Xorg/GtkStatusIcon backends. Those
speak the legacy XEmbed tray protocol, NOT the freedesktop
StatusNotifierItem (SNI) D-Bus protocol -- and Wayland tray hosts
(waybar's `tray` module, swaync, etc -- what a Hyprland session
actually has) only implement an SNI *host*, not an XEmbed tray manager.
That mismatch is the root cause of "icon doesn't appear": the process
was running, but never speaking the protocol the host understands.

Fix: talk raw StatusNotifierItem D-Bus directly (spec:
https://www.freedesktop.org/wiki/Specifications/StatusNotifierItem/),
via `dbus-next` -- a pure-Python asyncio D-Bus client/service library
with no GI/system-typelib dependency, so it works regardless of which
optional GTK/AppIndicator bindings happen to be installed. This process:

  1. Requests its own well-known bus name
     `org.kde.StatusNotifierItem-<pid>-1` on the session bus (the name
     itself is also this tray's single-instance guard -- see main()).
  2. Exports a real `org.kde.StatusNotifierItem` object at
     `/StatusNotifierItem` (icon, title, status, Activate/ContextMenu).
  3. Exports a real `com.canonical.dbusmenu` object at `/MenuBar`
     (Open/Close / Change Wallpaper / Restart / Quit) -- the standard way
     SNI hosts render a tray icon's right-click menu.
  4. Calls `org.kde.StatusNotifierWatcher.RegisterStatusNotifierItem`
     with that bus name, and re-registers automatically if the watcher
     (re)starts after we do (NameOwnerChanged), so load order with the
     bar/tray host doesn't matter.

Every menu/click action still just shells out to the EXACT SAME
`quickshell -c livewallpaper ipc call ...` commands the .desktop files
and keybinds already use -- no access to Quickshell's QML state from
here, unchanged from before.

Soft dependency: requires `dbus-next` + `Pillow` (both pip-installable,
NOT in the hard-dependency table -- see install.sh Step 1c). If either
import fails, or no session D-Bus is reachable, this exits immediately
(code 0, not an error) and TrayService.qml simply reports the tray as
unavailable -- same degrade-gracefully contract as before.

Usage: _tray_icon.py <path-to-app-icon.svg-or-png>
Stops on SIGTERM/SIGINT (sent by TrayService.qml's Process.stop()) or
stdin close.
"""
import asyncio
import os
import shlex
import subprocess
import sys

try:
    from dbus_next import BusType, Variant, RequestNameReply
    from dbus_next.aio import MessageBus
    from dbus_next.service import ServiceInterface, method, dbus_property, signal
    from dbus_next.constants import PropertyAccess, NameFlag
    from dbus_next.errors import DBusError
    from PIL import Image
except ImportError:
    # Soft dependency missing -- exit quietly, TrayService.qml treats
    # this as "tray unavailable", not an error.
    sys.exit(0)

WATCHER_BUS = "org.kde.StatusNotifierWatcher"
WATCHER_PATH = "/StatusNotifierWatcher"
WATCHER_IFACE = "org.kde.StatusNotifierWatcher"

APP_ID = "live-wallpaper-manager"
APP_TITLE = "Live Wallpaper Manager"


def ipc(target, method_name):
    """Fire-and-forget: same `quickshell -c livewallpaper ipc call ...`
    the .desktop launchers and keybinds already use. `target` is one of
    the module's two IPC targets -- "livewallpapermanager" (the Manager
    window, ManagerWindow.qml) or "livewallpaper" (the panel /
    application-lifecycle target, LiveWallpaperPanel.qml).

    ROOT-CAUSE FIX -- "Open doesn't reliably work": this tray process can
    outlive the Quickshell instance that spawned it (TrayService.qml's own
    comment already anticipates this: "Kills any orphaned instance from a
    previous Quickshell session" -- e.g. Quickshell was force-killed or
    crashed but this dbus-next process, a separate PID, kept running). In
    that state a plain `ipc call` has no running instance to reach and
    previously just failed silently -- the tray icon looked alive, but
    clicking Open did nothing.

    Mirrors the EXACT same "try ipc call; if that fails, start exactly one
    instance and retry" shape already used by the .desktop launchers
    (live-wallpaper-manager.desktop / live-wallpaper-manager-app.desktop),
    for consistency. The fallback launch uses -n/--no-duplicate (Quickshell
    CLI flag: "Exit immediately if another instance of the given config is
    running") so if the ipc call actually failed for some OTHER transient
    reason while an instance genuinely was still running, this fallback is
    a harmless no-op instead of spawning a duplicate Quickshell process --
    duplicates are exactly what would make subsequent `ipc call`s
    ambiguous/unreliable, the thing this fix is trying to prevent.

    Entirely non-blocking: the retry logic runs inside a detached shell
    (same as the .desktop pattern), so this function returns immediately
    either way and never blocks the asyncio/D-Bus event loop handling the
    Activate()/menu click that called it.
    """
    t = shlex.quote(target)
    m = shlex.quote(method_name)
    cmd = (
        "quickshell -c livewallpaper ipc call {t} {m} 2>/dev/null "
        "|| (quickshell -c livewallpaper -n >/dev/null 2>&1 & sleep 1.5; "
        "quickshell -c livewallpaper ipc call {t} {m} 2>/dev/null)"
    ).format(t=t, m=m)
    try:
        subprocess.Popen(
            ["bash", "-c", cmd],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    except FileNotFoundError:
        pass


def show_manager():
    # ManagerWindow.qml's show() -> focusOrShow(): restores it if hidden
    # and raises/focuses it if it's already open but behind something
    # else -- the left-click / primary-activation behavior (unchanged,
    # not part of the "Open/Close" menu-item fix below).
    ipc("livewallpapermanager", "show")


def toggle_manager():
    # Tray menu "Open / Close". Reuses ManagerWindow.qml's own toggle()
    # via the *existing* "livewallpapermanager" IPC target's `toggle`
    # method (already exposed for `quickshell ipc call`, see
    # ManagerWindow.qml) -- first click opens it, second click closes
    # it, repeated clicks keep flipping it. toggle() only ever sets
    # ManagerWindow's `visible` property; it never touches
    # ApplicationService.exit()/restart(), so "closing" here can never
    # quit the app or take the tray icon down with it.
    ipc("livewallpapermanager", "toggle")


def change_wallpaper():
    # Tray menu "Change Wallpaper" is explicitly RANDOM.
    # Use the same existing IPC target as the application's Random control.
    ipc("livewallpaper", "random")


def ipc_terminal(target, method_name):
    """Fire-and-forget, single attempt -- NO "start a new instance if this
    fails" fallback. Deliberately separate from ipc() above: that
    function's fallback exists for "no instance is running to reach"
    (a truly dead/never-started app), but restartApplication and
    exitApplication both intentionally end the running instance as part
    of what they do. The moment we call either, `quickshell ipc call`
    can legitimately return non-zero simply because the target hung up
    while shutting down -- not because no instance was ever there. Using
    ipc()'s fallback for these two would misread that as "no instance
    running" and launch a brand-new `quickshell -c livewallpaper -n`
    right in the middle of an in-progress exit/restart, racing (and
    potentially duplicating) the very teardown/relaunch already under
    way in the QML side (ApplicationService.exit()/restart() +
    scripts/restart_app.sh) -- exactly the "duplicate instance" /
    "Restart doesn't reliably come back" failure this project must not
    have. restart_app.sh already owns retrying/verifying the relaunch on
    its own (see that script), so this just needs to deliver the
    request once.
    """
    t = shlex.quote(target)
    m = shlex.quote(method_name)
    cmd = "quickshell -c livewallpaper ipc call {t} {m} 2>/dev/null".format(t=t, m=m)
    try:
        subprocess.Popen(
            ["bash", "-c", cmd],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    except FileNotFoundError:
        pass


def _find_livewallpaper_pid():
    """Return the PID of the running `quickshell -c livewallpaper` instance."""
    try:
        proc = subprocess.run(
            [
                "ps", "-eo", "pid=,args="
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
        )
        for line in proc.stdout.splitlines():
            parts = line.strip().split()
            if len(parts) >= 4 and parts[1:4] == ["quickshell", "-c", "livewallpaper"]:
                return parts[0]
    except Exception:
        pass
    return ""


def restart_app():
    # The tray helper is a separate process from Quickshell, so it can own the
    # restart watchdog safely. It captures the exact old PID BEFORE asking the
    # Quickshell instance to shut down, then waits for that PID to disappear
    # before starting the replacement. This avoids the race where a watchdog
    # launched from inside the dying Quickshell process gets terminated too.
    old_pid = _find_livewallpaper_pid()
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "restart_app.sh")

    try:
        subprocess.Popen(
            ["bash", script, old_pid] if old_pid else ["bash", script],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except Exception:
        return

    # Ask the current instance to perform its normal teardown. The detached
    # watchdog above remains alive and performs the actual relaunch.
    ipc_terminal("livewallpaper", "restartApplication")


def quit_app():
    # See ipc_terminal()'s docstring -- the same "ipc call failing
    # because the target is exiting looks identical to no instance
    # being there" hazard applies here too, and would be worse: a Quit
    # that raced its own fallback could silently relaunch the app it
    # was just asked to close.
    ipc_terminal("livewallpaper", "exitApplication")


def _load_icon_pixmap(icon_path):
    """Loads the existing app icon (Paths.appIcon is always a PNG in
    this repo, see Services/Paths.qml) and converts it to the
    `a(iiay)` ARGB32/network-byte-order format the SNI spec's
    IconPixmap property requires. Falls back to a small solid square
    (same fallback color the old pystray build used) so the tray still
    shows *something* rather than failing to start over a missing or
    unreadable icon file.
    """
    try:
        img = Image.open(icon_path).convert("RGBA") if icon_path else None
    except Exception:
        img = None
    if img is None:
        img = Image.new("RGBA", (32, 32), (203, 166, 247, 255))

    # Keep the tray icon at a sane pixel size -- hosts scale down anyway,
    # but sending a huge source PNG as an uncompressed pixmap is wasteful.
    if img.width > 128 or img.height > 128:
        img = img.copy()
        img.thumbnail((128, 128), Image.LANCZOS)

    w, h = img.size
    raw = img.tobytes("raw", "RGBA")
    # Spec: 32-bit ARGB, network (big-endian) byte order -> per-pixel
    # byte sequence is A, R, G, B.
    argb = bytearray(len(raw))
    argb[0::4] = raw[3::4]  # A
    argb[1::4] = raw[0::4]  # R
    argb[2::4] = raw[1::4]  # G
    argb[3::4] = raw[2::4]  # B
    # dbus-next requires DBus STRUCT members to be Python `list`, not
    # `tuple` -- see signature.py's _verify_struct.
    return [[w, h, bytes(argb)]]


class StatusNotifierItem(ServiceInterface):
    """org.kde.StatusNotifierItem -- the de-facto standard tray-icon
    protocol (KDE-authored, adopted by GNOME/Ayatana/every SNI host
    including waybar's `tray` module). See freedesktop spec linked in
    the module docstring."""

    def __init__(self, icon_pixmap):
        super().__init__("org.kde.StatusNotifierItem")
        self._icon_pixmap = icon_pixmap
        self._status = "Active"

    @method()
    def Activate(self, x: "i", y: "i"):
        # Left-click / primary activation -- same default action the
        # old pystray menu marked `default=True`.
        show_manager()

    @method()
    def SecondaryActivate(self, x: "i", y: "i"):
        show_manager()

    @method()
    def ContextMenu(self, x: "i", y: "i"):
        # Hosts render the Menu object themselves (see DBusMenu below);
        # nothing else required here.
        pass

    @method()
    def Scroll(self, delta: "i", orientation: "s"):
        pass

    @dbus_property(access=PropertyAccess.READ)
    def Category(self) -> "s":
        return "ApplicationStatus"

    @dbus_property(access=PropertyAccess.READ)
    def Id(self) -> "s":
        return APP_ID

    @dbus_property(access=PropertyAccess.READ)
    def Title(self) -> "s":
        return APP_TITLE

    @dbus_property(access=PropertyAccess.READ)
    def Status(self) -> "s":
        return self._status

    @dbus_property(access=PropertyAccess.READ)
    def WindowId(self) -> "i":
        return 0

    @dbus_property(access=PropertyAccess.READ)
    def IconName(self) -> "s":
        return ""  # we supply pixel data directly instead

    @dbus_property(access=PropertyAccess.READ)
    def IconPixmap(self) -> "a(iiay)":
        return self._icon_pixmap

    @dbus_property(access=PropertyAccess.READ)
    def OverlayIconName(self) -> "s":
        return ""

    @dbus_property(access=PropertyAccess.READ)
    def AttentionIconName(self) -> "s":
        return ""

    @dbus_property(access=PropertyAccess.READ)
    def ToolTip(self) -> "(sa(iiay)ss)":
        return ["", [], APP_TITLE, ""]

    @dbus_property(access=PropertyAccess.READ)
    def ItemIsMenu(self) -> "b":
        return False

    @dbus_property(access=PropertyAccess.READ)
    def Menu(self) -> "o":
        return "/MenuBar"


class DBusMenu(ServiceInterface):
    """com.canonical.dbusmenu -- minimal static menu (Open/Close/
    Change Wallpaper/separator/Restart/Quit) exposed at /MenuBar and
    referenced by StatusNotifierItem.Menu above. This is the standard
    companion protocol SNI hosts use to render a tray icon's
    right-click menu.

    Item behavior (see the action functions above for what each one
    actually calls):
      Open/Close      -- toggle_manager(): ManagerWindow.qml's own
                          toggle() via the existing "livewallpapermanager"
                          IPC target. First click opens the window,
                          second click closes it, and so on -- closing
                          it never quits the app or touches the tray
                          helper (that's ApplicationService.exit()'s
                          job, wired to Quit only, below).
      Change Wallpaper -- change_wallpaper(): PlaybackService.random()
                          via the existing "livewallpaper" IPC target --
                          the same wallpaper-change logic the app's own
                          Random button already uses.
      Restart          -- restart_app(): ApplicationService.restart()
                          via the existing "livewallpaper" IPC target --
                          full teardown, then relaunches the process
                          (see LiveWallpaperPanel.qml's
                          restartApplication(), which launches
                          scripts/restart_app.sh via
                          Quickshell.execDetached() so it survives this
                          process's own exit).
      Quit             -- quit_app(): ApplicationService.exit() via the
                          existing "livewallpaper" IPC target -- the
                          only item that actually terminates the app.
    """

    # (id, label, is_separator)
    _ITEMS = [
        (1, "Open / Close", False),
        (2, "Change Wallpaper", False),
        (3, "", True),
        (4, "Restart", False),
        (5, "Quit", False),
    ]
    _ACTIONS = {
        1: toggle_manager,
        2: change_wallpaper,
        4: restart_app,
        5: quit_app,
    }

    def __init__(self):
        super().__init__("com.canonical.dbusmenu")
        self._revision = 1

    def _item_props(self, item_id, label, is_separator):
        props = {
            "enabled": Variant("b", True),
            "visible": Variant("b", True),
        }
        if is_separator:
            props["type"] = Variant("s", "separator")
        else:
            props["label"] = Variant("s", label)
        return props

    @method()
    def GetLayout(self, parentId: "i", recursionDepth: "i", propertyNames: "as") -> "u(ia{sv}av)":
        children = [
            Variant("(ia{sv}av)", [item_id, self._item_props(item_id, label, sep), []])
            for item_id, label, sep in self._ITEMS
        ]
        root = [0, {"children-display": Variant("s", "submenu")}, children]
        return [self._revision, root]

    @method()
    def GetGroupProperties(self, ids: "ai", propertyNames: "as") -> "a(ia{sv})":
        by_id = {i: (label, sep) for i, label, sep in self._ITEMS}
        out = []
        for item_id in ids:
            if item_id in by_id:
                label, sep = by_id[item_id]
                out.append([item_id, self._item_props(item_id, label, sep)])
        return out

    @method()
    def GetProperty(self, id: "i", name: "s") -> "v":
        by_id = {i: (label, sep) for i, label, sep in self._ITEMS}
        label, sep = by_id.get(id, ("", False))
        return self._item_props(id, label, sep).get(name, Variant("s", ""))

    @method()
    def Event(self, id: "i", eventId: "s", data: "v", timestamp: "u"):
        if eventId == "clicked":
            action = self._ACTIONS.get(id)
            if action:
                action()

    @method()
    def EventGroup(self, events: "a(isvu)") -> "ai":
        for item_id, eventId, data, timestamp in events:
            if eventId == "clicked":
                action = self._ACTIONS.get(item_id)
                if action:
                    action()
        return []

    @method()
    def AboutToShow(self, id: "i") -> "b":
        return False

    @method()
    def AboutToShowGroup(self, ids: "ai") -> "(aiai)":
        return [[], []]

    @dbus_property(access=PropertyAccess.READ)
    def Version(self) -> "u":
        return 3

    @dbus_property(access=PropertyAccess.READ)
    def TextDirection(self) -> "s":
        return "ltr"

    @dbus_property(access=PropertyAccess.READ)
    def Status(self) -> "s":
        return "normal"

    @dbus_property(access=PropertyAccess.READ)
    def IconThemePath(self) -> "as":
        return []


async def _register_with_watcher(bus, own_name):
    """Calls StatusNotifierWatcher.RegisterStatusNotifierItem(own_name).
    Returns True on success. Doesn't raise on "watcher not running yet"
    -- that's a normal, common state (many tray hosts start the watcher
    lazily, or the bar hasn't started yet) that main_async()'s
    NameOwnerChanged listener recovers from once the watcher does show
    up, rather than something to treat as a hard failure.
    """
    try:
        introspection = await bus.introspect(WATCHER_BUS, WATCHER_PATH)
    except (DBusError, Exception):
        return False
    proxy = bus.get_proxy_object(WATCHER_BUS, WATCHER_PATH, introspection)
    watcher = proxy.get_interface(WATCHER_IFACE)
    try:
        await watcher.call_register_status_notifier_item(own_name)
        return True
    except DBusError:
        return False


async def main_async(icon_path):
    try:
        bus = await MessageBus(bus_type=BusType.SESSION).connect()
    except Exception:
        # No session D-Bus reachable -- degrade exactly like a missing
        # dependency (see module docstring).
        return

    # Single-instance guard. The SNI item's own bus name below is
    # deliberately per-PID (org.kde.StatusNotifierItem-<pid>-1, the
    # conventional SNI naming pattern), so it can't double as a dedup
    # lock -- two concurrent processes would each just get their own
    # unique name and both register. Instead, claim a separate *fixed*
    # name with DO_NOT_QUEUE first: if a previous instance (e.g. an
    # orphan from a force-killed Quickshell session) already owns it,
    # this returns IN_QUEUE/EXISTS instead of PRIMARY_OWNER and we exit
    # immediately rather than spawning a second tray icon -- matches
    # the "No duplicate tray items" requirement without needing a
    # separate pgrep/pidfile.
    lock_reply = await bus.request_name("io.github.livewallpapermanager.TrayIcon", NameFlag.DO_NOT_QUEUE)
    if lock_reply not in (RequestNameReply.PRIMARY_OWNER, RequestNameReply.ALREADY_OWNER):
        return

    own_name = f"org.kde.StatusNotifierItem-{os.getpid()}-1"
    reply = await bus.request_name(own_name)
    if reply not in (RequestNameReply.PRIMARY_OWNER, RequestNameReply.ALREADY_OWNER):
        return

    icon_pixmap = _load_icon_pixmap(icon_path)
    sni = StatusNotifierItem(icon_pixmap)
    menu = DBusMenu()
    bus.export("/StatusNotifierItem", sni)
    bus.export("/MenuBar", menu)

    await _register_with_watcher(bus, own_name)

    # Re-register whenever the watcher (re)appears on the bus -- covers
    # both "tray host starts after us" (very common: waybar/the bar
    # often starts asynchronously relative to Quickshell) and "tray
    # host restarts while we're already running".
    try:
        dbus_intro = await bus.introspect("org.freedesktop.DBus", "/org/freedesktop/DBus")
        dbus_proxy = bus.get_proxy_object("org.freedesktop.DBus", "/org/freedesktop/DBus", dbus_intro)
        dbus_iface = dbus_proxy.get_interface("org.freedesktop.DBus")

        def _on_name_owner_changed(name, old_owner, new_owner):
            if name == WATCHER_BUS and new_owner:
                asyncio.ensure_future(_register_with_watcher(bus, own_name))

        dbus_iface.on_name_owner_changed(_on_name_owner_changed)
    except Exception:
        pass  # not fatal -- we're already registered if the watcher was up

    await bus.wait_for_disconnect()


def main():
    icon_path = sys.argv[1] if len(sys.argv) > 1 else None
    try:
        asyncio.run(main_async(icon_path))
    except (KeyboardInterrupt, SystemExit):
        pass


if __name__ == "__main__":
    main()
