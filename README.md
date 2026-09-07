# Live Wallpaper Manager v2.9

A Quickshell-based live wallpaper manager for Linux desktops, primarily targeting **Hyprland + Wayland**, with `mpvpaper` as the main video wallpaper backend.

## Features

- Local video wallpapers with search, favorites, tags, and history
- Streaming and web wallpaper modes
- Web wallpaper browser and download manager with pause/resume and bandwidth limits
- Multi-monitor support
- GPU selection and performance controls
- Wallpaper transitions for MP4/GIF (fade, crossfade-style fade, slide, wipe, zoom, grow, random)
- Smart Playback
- Playlist scheduling
- Music Dock, Cava, and Peaclock + Cava
- Cache management
- Performance profiles and performance history
- Optional system tray and login autostart
- AWWW-based compositor-side transitions for image/GIF wallpapers

> **Weather backend note:** v2.9 contains `WeatherService.qml`, `weather.sh`, and `weather_tick.sh`, but the current release does **not** expose a Weather Wallpapers configuration page in the UI. Weather is therefore not listed above as a user-facing feature. The backend can be extended later without changing the main wallpaper architecture.

## Requirements

- Linux with a Wayland session
- Hyprland for the primary supported desktop environment
- Quickshell
- `mpv` and `mpvpaper`
- `jq`
- `ffmpeg` / `ffprobe`
- Python 3 for the optional system tray helper

### Optional dependencies

- `grim` — screenshot support and transition-related functionality
- `awww` / `awww-daemon` — compositor-side image/GIF wallpaper backend and transitions
- `yt-dlp` — stream/page URL resolution where required
- `cava` — audio visualizer
- `playerctl` — media controls / MPRIS integration
- `peaclock` — clock integration
- `zenity`, `yad`, `kdialog`, or an available desktop portal — optional dialogs

## Supported distributions

The installer supports dependency handling for the following distribution families:

| Distribution | Status |
|---|---|
| Arch Linux / CachyOS / EndeavourOS / Manjaro | Supported |
| Fedora / RHEL-based | Supported |
| Debian / Ubuntu-based | Supported |
| NixOS | Supported |
| Other Linux distributions | Manual dependency installation may be required |

The application itself uses the same `livewallpaper/` source tree across supported distributions. `install.sh` only changes its dependency-installation strategy according to the selected distribution.

## Install

```bash
chmod +x install.sh
./install.sh
```

The application is installed under:

```text
~/.config/quickshell/livewallpaper
```

Default wallpaper directory:

```text
~/Pictures/Live Wallpaper
```

The wallpaper directory can be changed from the Settings page.

### Wayland startup

The v2.9 launcher includes Wayland environment recovery for cases where `WAYLAND_DISPLAY` is missing from the environment inherited by a launcher or autostart process. The application still requires an actual Wayland session.

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

## NixOS

Missing dependencies are installed imperatively into the user's Nix profile with `nix profile install nixpkgs#<pkg>` when possible, falling back to `nix-env` on older setups. The installer does not modify `configuration.nix` or `home.nix` and does not require `sudo` for profile-managed dependencies.

If you prefer declarative management, install the required packages yourself through your NixOS configuration before running the application installer. Anything already available on `PATH` is left alone.

## Wallpaper transitions

Image and animated GIF wallpapers can use AWWW for compositor-side fade transitions. MP4/video wallpapers remain on the MPV/mpvpaper backend.

Transition enable/disable and duration are available under:

```text
Playlist → Wallpaper Transitions
```

## Performance

v2.x includes the following performance infrastructure:

- Adaptive FPS based on GPU utilization
- Thermal protection with warning FPS caps and critical pause/resume behavior
- Battery-aware FPS profiles
- Runtime performance overrides without changing the saved user FPS preference
- Wallpaper and monitor performance profiles
- Performance history service and UI integration

## Streaming and web wallpapers

Streaming and web wallpaper support is separate from the normal local-video playback path. Some page URLs require `yt-dlp` to resolve a playable media source before MPV can consume them.

Web wallpaper mode may use a browser/kiosk-based renderer where supported by the implementation and installed dependencies.

## Weather backend status

The current v2.9 source contains weather-related backend components:

```text
livewallpaper/Services/WeatherService.qml
livewallpaper/scripts/weather.sh
livewallpaper/scripts/weather_tick.sh
```

These components are retained for backend capability and future integration, but **there is currently no Weather Wallpapers page or weather-rule editor in the main UI**. Do not treat Weather Wallpapers as an exposed v2.9 UI feature.

## Debian / Wayland startup hardening

The standalone `shell.qml` uses Quickshell `LazyLoader` for native windows so hidden `PanelWindow` / `FloatingWindow` surfaces are not constructed during process startup. This reduces startup failures caused by Wayland window surfaces being created before the session environment is ready.

See:

```text
livewallpaper/docs/DEBIAN_WAYLAND_STARTUP.md
```

## v2.9 release notes

v2.9 consolidates the current Quickshell/QML architecture with the hardened wallpaper lifecycle, multi-monitor handling, performance infrastructure, scheduling, transition support, and distribution-aware installation logic.

The release also includes reliability work around:

- Wayland environment handling
- Quickshell startup
- Wallpaper start/stop/restart lifecycle
- Stale `mpvpaper` processes
- MPV IPC switching
- Watcher/process cleanup
- Tray lifecycle
- Cava positioning and process handling
- GPU detection/statistics
- File/path handling
- NixOS installation behavior

## Testing and validation

The v2.9 release was validated on a CachyOS + Hyprland + Wayland environment with the required runtime dependencies available.

Validation covered:

- Bash syntax checks
- Python compilation/import checks
- QML/qmldir structure checks
- Dependency validation
- Installer audit
- UI/IPC startup checks
- Wallpaper lifecycle checks
- File operation checks
- Stop/cleanup checks
- Wayland and Hyprland compatibility checks
- Security regression checks
- Performance/resource checks
- Logging and documentation checks

A known non-blocking `qmllint` false positive involving `void` in Qt6/QML was observed during validation and does not indicate a runtime failure.

## Security

The project does not intentionally hide downloads, execute arbitrary remote commands, or embed credentials. Installation scripts that use third-party bootstrap installers are documented in the project's security documentation.

Do not run installation scripts as root unless the installation method explicitly requires it.

## License

See `LICENSE`.

## Historical release notes

### v2.1.0 — Advanced Performance

- Adaptive FPS driven by GPU utilization
- Thermal Protection with warning FPS cap and critical pause/resume
- Battery Profiles with normal/low-battery FPS caps
- Runtime performance overrides keep the saved user FPS preference intact

### v2.1.1

- Added performance profile infrastructure for wallpapers and monitors.

### v2.1.2

- Added Performance History service scaffold and UI card.

### v2.1.3 Stable

- Streaming improvements.

### v2.1.6 — NixOS support

- `install.sh` / `uninstall.sh` treat NixOS as a first-class distribution alongside Arch, Fedora, and Debian.
- Missing dependencies can be installed into and removed from the user's Nix profile without editing `configuration.nix` or `home.nix`.
- `update.sh` supports an optional `livewallpaper-nixos/` application-source override in the same way as the existing distribution-specific source overrides.
