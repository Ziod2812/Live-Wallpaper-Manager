# Debian / Wayland startup hardening

This v2.9 build uses `Quickshell.LazyLoader` for every native `PanelWindow` / `FloatingWindow` surface in the standalone root. The initial `ShellRoot` therefore starts with only IPC handlers and lazy loaders; native windows are not created until an IPC command requests them.

## Diagnostic sequence

Start the root without opening a native window:

```bash
~/.config/quickshell/livewallpaper/scripts/launch_quickshell.sh -c livewallpaper -d
```

(this wraps the same call with a check that corrects `QT_QPA_PLATFORM=xcb` leaking into a real Wayland session -- a common cause of an immediate crash that looks like a ShellRoot/native-surface bug but isn't; see the script's own header comment)

From a second terminal, request the panel:

```bash
quickshell -c livewallpaper ipc call livewallpaper open
```

Then request the desktop manager:

```bash
quickshell -c livewallpaper ipc call livewallpapermanager open
```

If the first command stays alive but opening the panel crashes the process, the crash is in the panel's native Wayland surface/dependencies rather than ShellRoot construction. If the panel opens but the manager crashes, the issue is isolated to the `FloatingWindow` path.

For a configuration/environment sanity check:

```bash
printf 'WAYLAND_DISPLAY=%s\nXDG_SESSION_TYPE=%s\nQT_QPA_PLATFORM=%s\n' "${WAYLAND_DISPLAY-}" "${XDG_SESSION_TYPE-}" "${QT_QPA_PLATFORM-}"
quickshell --version
```

Known Quickshell documentation recommends `LazyLoader` for windows that are not needed immediately, and documents that it can defer window creation. See https://quickshell.org/docs/v0.3.0/types/Quickshell/LazyLoader/ .
