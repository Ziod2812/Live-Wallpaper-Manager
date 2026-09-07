# Live Wallpaper Manager

A Quickshell-based live wallpaper manager for Hyprland using `mpvpaper`.

## Features

- Local video wallpapers with search, favorites, tags, and history
- Streaming and web wallpaper modes
- Web wallpaper browser, download manager (pause/resume, bandwidth limit),
  and auto-update checks for new results (see `docs/NEW_FEATURES.md`)
- Multi-monitor support
- GPU selection and performance controls
- Wallpaper transitions for MP4/GIF (fade, crossfade-style fade, slide, wipe, zoom, grow, random)
- Smart Playback
- Playlist scheduling
- Music Dock, Cava, and Peaclock + Cava
- Cache management
- Optional system tray and login autostart

## Requirements

- Linux with Hyprland
- Quickshell
- `mpv` and `mpvpaper`
- `grim` (optional; enables animated transitions between live wallpapers)
- `awww` / `awww-daemon` (optional; prepared for Wayland image wallpaper backend)
- `jq`
- `ffmpeg`
- Python 3 for the optional system tray helper

## Install

```bash
chmod +x install.sh
./install.sh
```

The application is installed under `~/.config/quickshell/livewallpaper`.

Default wallpaper directory:

```text
~/Pictures/Live Wallpaper
```

The wallpaper directory can be changed from the Settings page.

## Update

```bash
./update.sh
```

## Uninstall

```bash
./uninstall.sh
```

The uninstaller removes program files and asks before removing project configuration/data directories.

## Project layout

```text
livewallpaper/
├── Components/
├── Config/
├── Manager/
├── Pages/
├── Panels/
├── Services/
├── scripts/
└── data/
```

`install.sh` asks which distro you're on (Arch / Fedora / Debian / NixOS /
Other) purely to decide how to auto-install missing dependencies
(pacman+AUR, dnf+COPR/source build, apt+backports/source build, or on
NixOS `nix profile install` into your user profile); every distro shares
this same `livewallpaper/` app code.

### NixOS

Missing dependencies (quickshell, mpvpaper, Node.js, ...) are installed
imperatively into your own Nix profile with `nix profile install
nixpkgs#<pkg>` (falling back to `nix-env` on an older Nix without flakes
enabled). This needs no `sudo` and never edits `configuration.nix` or
`home.nix` -- nothing here will be undone by a later `nixos-rebuild
switch`. If you'd rather manage these declaratively yourself, add
`quickshell`, `mpvpaper`, and (optionally) `hyprland`/`nodejs_22` to
`environment.systemPackages` or `home.packages` before running
`./install.sh`; anything already on `PATH` is left alone. AWWW and
peaclock aren't (yet) packaged in nixpkgs, so those fall back to a Rust
source build the same way they do on Debian/Fedora/openSUSE.

## License

See `LICENSE`.

## v2.1.0 — Advanced Performance

- Adaptive FPS driven by GPU utilization
- Thermal Protection with warning FPS cap and critical pause/resume
- Battery Profiles with normal/low-battery FPS caps
- Runtime performance overrides keep the saved user FPS preference intact


## v2.1.1
- Added performance profile infrastructure (wallpaper and monitor).


## v2.1.2
- Added Performance History service scaffold and UI card.


## v2.1.3 Stable
- Streaming improvements.


### AWWW transitions
Image and animated GIF wallpapers use AWWW for compositor-side Fade transitions. MP4/video wallpapers remain on the existing MPV/mpvpaper backend. Transition enable/disable and duration are available under Playlist → Wallpaper Transitions.

## v2.1.6 — NixOS support

- `install.sh`/`uninstall.sh` now treat NixOS as a fourth first-class
  distro (alongside Arch/Fedora/Debian): missing dependencies are
  installed into (and removed from) your own Nix profile with `nix
  profile install`/`nix profile remove nixpkgs#<pkg>` -- no sudo, no
  `configuration.nix`/`home.nix` edits.
- `update.sh` picks up an optional `livewallpaper-nixos/` app-source
  override the same way it already does for `-arch`/`-fedora`/`-debian`.

### Debian / Wayland startup hardening

The standalone `shell.qml` uses Quickshell `LazyLoader` for native windows so hidden PanelWindow/FloatingWindow surfaces are not constructed during process startup. See `livewallpaper/docs/DEBIAN_WAYLAND_STARTUP.md` for the diagnostic sequence.
