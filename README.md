# Live Wallpaper Manager

**A modern Quickshell-based live wallpaper manager for Hyprland.**

Play local videos, streams, and web content as live wallpapers with
multi-monitor support, GPU selection, Smart Playback, Music Dock,
playlists, performance profiles, scheduling, collections, and dynamic
wallpaper automation.

[Repository](https://github.com/Ziod2812/Live-Wallpaper-Manager) ·
[MIT License](https://github.com/Ziod2812/Live-Wallpaper-Manager/blob/main/LICENSE) ·
[Report an Issue](https://github.com/Ziod2812/Live-Wallpaper-Manager/issues)

> **Current release:** v2.9  
> **Primary target:** Hyprland + Wayland  
> **Supported installer families:** Arch-based, Fedora/RHEL-based,
> Debian/Ubuntu-based, and NixOS

---

## 🎥 Demo

Watch the original showcase:

[▶ Watch Demo](https://www.tiktok.com/@ziodenms/video/7666855041814318356)

---

## ✨ Highlights

| Feature | Description |
|---|---|
| 🎞️ **Wallpapers** | Play local video wallpapers with search, favorites, history, resolution, and FPS controls. |
| 🌐 **Streaming & Web** | Use supported video URLs, websites, direct media URLs, or local HTML in kiosk mode. |
| 🖥️ **Multi-monitor** | Run an independent wallpaper on each display. |
| 🎮 **GPU Control** | Select or pin the GPU used by `mpvpaper` on multi-GPU systems. |
| ⚡ **Smart Playback** | React to battery state, fullscreen applications, lock state, monitor sleep, and games. |
| 🎵 **Music Dock** | Floating now-playing controls with MPRIS and a live `cava` visualizer. |
| 🕒 **Peaclock + Cava** | Independent clock/date and visualizer overlay using the shared Cava pipeline. |
| 🔁 **Playlist** | Automatic wallpaper rotation with Sequential, Random, or Favorites modes. |
| 🗂️ **Collections** | Organize wallpapers into collections and use them with automation and playback rules. |
| 📅 **Scheduling** | Schedule wallpapers or collections by time, sunrise, and sunset. |
| 🌦️ **Weather Rules** | Select wallpapers based on locally evaluated weather conditions using Open-Meteo data. |
| 🎨 **Smart Accent** | Dynamically derive and apply accent colors from wallpaper/media content. |
| ✨ **AWWW Transitions** | Use compositor-side transitions for supported image/GIF wallpaper workflows. |
| 📊 **Performance** | GPU selection, performance profiles, playback quality controls, and performance history. |
| 🔔 **System Tray** | Quick Open/Close, Change Wallpaper, Restart, and Quit controls. |
| 🩺 **Diagnostics** | Built-in diagnostics and environment/dependency information for troubleshooting. |

---

# 📋 Requirements

## Core

| Package | Required | Purpose |
|---|:---:|---|
| `quickshell` | ✅ | QML shell runtime |
| `mpvpaper` | ✅ | Video wallpaper renderer |
| `ffmpeg` / `ffprobe` | ✅ | Media processing |
| `jq` | ✅ | JSON handling |
| `hyprctl` | ✅ | Hyprland integration |
| `python3` | ✅ | Runtime helpers and tray integration |

## Optional

| Package | Used for |
|---|---|
| `yt-dlp` | Streaming-platform extraction |
| `chromium` / `firefox` | Local HTML/web playback |
| `inotify-tools` | Automatic wallpaper-folder refresh |
| `cava` / `playerctl` / `pipewire` | Music Dock and media detection |
| `peaclock` | Peaclock + Cava Dock |
| `zenity`, `yad`, `kdialog`, or `xdg-desktop-portal` | Folder picker backend |
| `awww` | Image/GIF transition workflows |

The installer can handle required and optional dependencies according to the
detected Linux distribution and available package sources. Some packages may
fall back to a source build or standalone installation when no suitable
native package is available.

---

# 🐧 Supported Linux Distributions

The v2.9 installer detects the host package environment and provides
distribution-specific dependency handling for:

| Distribution family | Installer path | Status |
|---|---|:---:|
| Arch / CachyOS / EndeavourOS / Manjaro / similar | `pacman` + AUR where applicable | ✅ |
| Fedora / RHEL-based | `dnf` + COPR/source build where required | ✅ |
| Debian / Ubuntu-based | `apt` + backports/source build where required | ✅ |
| NixOS | `nix profile install` / user profile | ✅ |

### Important

"Supported" means the installer contains explicit handling for that package
family. Individual packages can still depend on the repositories, versions,
or build tools available on the host.

NixOS installation is designed to use the user's Nix profile and does not
require modifying `configuration.nix` or `home.nix`.

---

# 🚀 Installation

Clone the repository:

```bash
git clone https://github.com/Ziod2812/Live-Wallpaper-Manager.git
cd Live-Wallpaper-Manager
chmod +x install.sh uninstall.sh update.sh
```

Run:

```bash
./install.sh
```

The installer detects the available package manager and configures the
appropriate dependency path.

### Verify the installation

```bash
test -f ~/.config/quickshell/livewallpaper/shell.qml && \
echo "Live Wallpaper Manager installed"
```

Launch:

```bash
quickshell -c livewallpaper
```

---

# ▶️ Launch & IPC

## Start the application

```bash
quickshell -c livewallpaper
```

## Toggle the main panel

```bash
quickshell -c livewallpaper ipc call livewallpaper toggle
```

## Toggle the Manager window

```bash
quickshell -c livewallpaper ipc call livewallpapermanager toggle
```

The v2.9 release also contains hardened launcher paths for Wayland sessions
where a graphical launcher does not provide the same environment as an
interactive terminal.

---

# 🎞️ Wallpaper Management

Place video wallpapers in:

```text
~/Pictures/Live Wallpaper/
```

Supported formats include:

```text
.mp4  .webm  .mkv  .mov  .avi  .m4v  .mpeg  .mpg
.wmv  .flv   .ts   .mts  .m2ts .3gp .ogv
```

The Wallpapers page provides:

- live filename search
- Favorites and Recent history
- Apply / Start / Stop controls
- resolution and FPS selection
- Previous / Random / Next navigation
- wallpaper-directory selection
- Zen Mode
- monitor-specific playback
- supported transition workflows

`inotify-tools` enables automatic folder refresh. Manual **Refresh** remains
available without it.

## Multi-monitor

Each display can have its own wallpaper.

The Manager's **Monitor** page shows detected outputs and what is currently
playing on each display.

## GPU selection

The **Performance** page can choose how `mpvpaper` uses available GPUs,
including automatic, vendor-specific, power-saving, and high-performance
profiles.

---

# 🔁 Playlist

The Playlist page can automatically advance wallpapers on a timer.

Available modes:

- **Sequential** — follow the current order
- **Random** — choose a random wallpaper
- **Favorites** — cycle through favorites, falling back to Random when there
  are none

Playlist timing and behavior are controlled from the Manager window.

---

# 🗂️ Collections

Wallpapers can be organized into reusable collections.

Collections can be used for:

- manual playback
- random selection
- playlist workflows
- scheduling
- wallpaper automation

Collection data is stored locally and does not require a cloud service.

---

# 📅 Scheduling

Wallpaper automation can be scheduled using:

- specific times
- sunrise
- sunset
- specific wallpapers
- wallpaper collections

The scheduler avoids unnecessary wallpaper relaunches when the active rule has
not changed.

Sunrise/sunset calculations are performed locally.

---

# 🌦️ Weather Wallpapers

Weather-based rules use Open-Meteo data.

Supported categories include:

- Clear day/night
- Cloudy
- Fog
- Rain
- Snow
- Storm

Weather information is cached and polled periodically rather than requested
continuously.

---

# 🎨 Smart Accent Color

The Smart Accent system can derive accent colors from wallpaper/media content
and expose the resulting palette to the UI.

The objective is to keep the interface visually synchronized with the currently
selected wallpaper while preserving the existing UI/UX architecture.

---

# 🌐 Streaming & Web

The panel supports three playback modes:

**Wallpapers · Streaming · Web**

## Streaming

Paste a supported URL, such as:

- YouTube
- Twitch
- Vimeo
- Bilibili
- Niconico
- direct `.m3u8`
- direct `.mp4`
- direct `.webm`

`yt-dlp` is required for supported platform extraction.

Direct media URLs can work without `yt-dlp`.

## Web

Web mode provides:

- **Website** — play a web URL through the supported playback engine
- **Local HTML** — open an `.html` / `.htm` file in kiosk mode using Chromium
  or Firefox

---

# 🎵 Music Dock & Peaclock + Cava

## Music Dock

A floating now-playing overlay with:

- album artwork
- title and artist
- seekable progress
- playback controls
- MPRIS media detection
- live Cava visualization

## Peaclock + Cava Dock

A separate floating overlay combining:

- clock
- date
- live Cava visualization

Both overlays are independent and can be configured from the **Visualizer**
page.

When both are enabled, they share the existing Cava pipeline instead of
starting unnecessary duplicate Cava processes.

---

# ⚡ Smart Playback & Performance

The **Performance** page combines playback quality controls with Smart
Playback rules.

Depending on your settings, playback can react to:

- battery state
- fullscreen applications
- screen lock
- monitor sleep
- game detection

Performance controls can also manage:

- resolution
- FPS behavior
- GPU selection
- performance profiles
- performance history

---

# ✨ AWWW Transitions

AWWW is supported for image/GIF transition workflows where the environment
provides the required compositor integration.

Video wallpapers continue to use the MPV/mpvpaper playback path.

---

# ⚙️ Autostart

The installer can enable a standard XDG login-session autostart entry.

You can also manage it manually:

```bash
~/.config/quickshell/livewallpaper/scripts/manage_autostart.sh enable
```

For Hyprland-native startup:

```ini
exec-once = quickshell -c livewallpaper
```

After enabling **Start on Login**, verify your Hyprland configuration if your
setup does not consume XDG autostart entries directly.

---

# 🗂️ Configuration & Data

| Purpose | Location |
|---|---|
| Wallpaper library | `~/Pictures/Live Wallpaper` |
| Wallpaper database | `~/.config/quickshell/livewallpaper/data/wallpapers.json` |
| Settings | `~/.config/quickshell/livewallpaper/data/settings.json` |
| Recent history | `~/.config/quickshell/livewallpaper/data/history.json` |
| Collections | `~/.config/quickshell/livewallpaper/data/collections.json` |
| Thumbnails | `~/.cache/livewallpaper/thumbs/` |
| Runtime state | `~/.cache/livewallpaper/state/` |
| Logs | `~/.cache/livewallpaper/logs/` |

CLI settings are handled by:

```bash
scripts/settings.sh <get|set|reset> [key] [value]
```

---

# 🔄 Update

Update an existing installation with:

```bash
cd Live-Wallpaper-Manager
./update.sh
```

The update process preserves user data such as:

- settings
- favorites
- history
- playlists
- collections
- wallpaper files

You can also update directly from a fresh clone:

```bash
git clone https://github.com/Ziod2812/Live-Wallpaper-Manager.git
cd Live-Wallpaper-Manager
chmod +x update.sh
./update.sh
```

---

# 🗑️ Uninstall

From the project directory:

```bash
cd Live-Wallpaper-Manager
./uninstall.sh
```

The uninstaller removes the application's own registrations and program
files, then asks before deleting configuration and data directories.

Dependency cleanup is safety-first:

- protected/system dependencies are never removed
- shared dependencies are not removed merely because they are installed
- only verified optional application-owned dependencies may be removed
- unknown ownership means the package stays installed

---

# 🛠️ Troubleshooting

## Manager or panel does not appear

Run:

```bash
quickshell -c livewallpaper
```

Then inspect QML/runtime errors printed in the terminal.

Verify:

```bash
test -f ~/.config/quickshell/livewallpaper/shell.qml
```

## `quickshell` works in a terminal but not from a launcher

Check the Wayland session:

```bash
echo "$XDG_SESSION_TYPE"
echo "$WAYLAND_DISPLAY"
```

The v2.9 launcher path includes Wayland environment recovery for graphical
launch scenarios.

## mpvpaper does not start / black screen

Check:

```bash
command -v mpvpaper
mpvpaper --help
hyprctl monitors
```

Make sure you are running inside an active Hyprland session.

## Streaming does not connect

Check:

```bash
yt-dlp --version
```

For supported platforms, keep `yt-dlp` up to date.

Direct `.m3u8`, `.mp4`, and `.webm` URLs do not necessarily require
`yt-dlp`.

## System tray icon is missing

The tray helper uses the project's Python runtime and StatusNotifierItem/D-Bus
integration.

Re-run:

```bash
./install.sh
```

to restore missing dependencies.

## Cava visualizer does not start

Check:

```bash
command -v cava
command -v playerctl
```

If Cava is unavailable, the Music Dock and Cava visualizer features will not
be available until the optional dependency is installed.

---

# 🧠 Advanced

## Architecture

```text
livewallpaper/
├─ shell.qml
├─ Config/
├─ Services/
├─ Components/
├─ Panels/
├─ Manager/
├─ Pages/
├─ scripts/
├─ tests/
├─ data/
└─ assets/
```

Core responsibilities are split across services such as:

- `WallpaperService`
- `PlaybackService`
- `PlaylistService`
- `MultiMonitorService`
- `GPUManagerService`
- `SmartPlaybackService`
- `CavaService`
- `MprisService`
- `TrayService`
- `SettingsService`
- `PerformanceService`
- `SchedulerService`
- `CollectionService`
- `SmartAccentService`

## CLI scripts

Common standalone scripts include:

```text
scripts/apply_wallpaper.sh
scripts/start_wallpaper.sh
scripts/stop_wallpaper.sh
scripts/next_wallpaper.sh
scripts/previous_wallpaper.sh
scripts/random_wallpaper.sh
scripts/refresh.sh
scripts/favorite.sh
scripts/recent.sh
scripts/change_directory.sh
scripts/settings.sh
scripts/cache.sh
scripts/monitor.sh
scripts/gpu_manager.sh
```

---

# 🌿 Caelestia Integration

Live Wallpaper Manager can be embedded into another Quickshell shell such as
[Caelestia](https://github.com/caelestia-dots/shell).

At a high level:

1. Install or copy the `livewallpaper/` module.
2. Import the module in `shell.qml`.
3. Instantiate `LiveWallpaperPanel`.
4. Bind buttons or other UI to the exported services.

Example:

```qml
import "modules/livewallpaper/Panels" as LiveWallpaper

ShellRoot {
    LiveWallpaper.LiveWallpaperPanel {
        id: liveWallpaperPanel
    }
}
```

Because the project uses Quickshell singletons, other shell components can
consume live playback state directly without an additional external IPC layer.

---

# 🧪 Testing & QA

The project includes backend and regression tests.

Run the GPU Manager tests:

```bash
bash tests/run_gpu_manager_tests.sh
```

Additional release validation covers:

- Bash syntax
- Python compilation
- QML/qmldir integrity
- repository structure
- credential checks
- file permissions
- GPU detection
- GPU statistics
- performance profiles
- wallpaper lifecycle
- stop/cleanup behavior
- Wayland/Hyprland compatibility
- security/path handling

### Release validation status

**v2.9 Release Gate: PASS**

Previously reported regression suites:

- GPU Manager: **19/19 PASS**
- GPU Stats: **6/6 PASS**
- Performance Profiles: **10/10 PASS**

A known Qt6 `qmllint` `void` diagnostic was classified during validation as a
non-blocking false positive and did not indicate a runtime failure.

---

# 🔐 Security

Live Wallpaper Manager uses explicit path validation and safety checks for
file operations and dependency cleanup.

The project does not intentionally hide external installer behavior.

Some dependencies may use:

- distribution package repositories
- AUR
- COPR
- source builds
- standalone upstream binaries
- documented third-party installation scripts

Users should review installer behavior before running it on production
systems.

For security issues, use the repository's issue/security reporting process.

---

# 🐛 Bug Fixes & Release History

For a detailed old-vs-v2.9 comparison covering known bugs, fixes, hardening,
new functionality, regression testing, and removed components, see:

**`V2.9-RELEASE-CHANGELOG.md`**

The v2.9 release includes fixes/hardening for areas including:

- Wayland environment recovery
- Quickshell startup reliability
- wallpaper restart reliability
- stale `mpvpaper` handling
- MPV IPC switching reliability
- zombie/orphan wallpaper process handling
- system tray startup and lifecycle
- Cava positioning and process races
- visualizer clipping/layout
- Manager window IPC lifecycle
- GPU detection regressions
- GPU statistics regressions
- path/file safety
- multi-distro dependency handling
- NixOS installation behavior

---

# 📄 License

Live Wallpaper Manager is licensed under the
[MIT License](LICENSE).

---

# 🙌 Credits & References

Live Wallpaper Manager is an independent project.

During development, several open-source projects and public resources were
reviewed for ideas, implementation approaches, architecture references,
compatibility patterns, and general technical learning.

Third-party projects remain under their respective licenses and copyrights.

Where attribution is required by a third-party license, the applicable
attribution and license terms should be preserved.

---

# 🧪 Testers

Thanks to everyone who helped test Live Wallpaper Manager:

| Tester | Platform | Contribution |
|---|---|---|
| [minh23102011](https://github.com/minh23102011) | GitHub | General testing and feedback |
| [@prodepxser](https://www.youtube.com/@prodepxser) | YouTube | General testing and feedback |
| [Trypezz](https://github.com/Trypezz) | GitHub | General testing and feedback |
| A real-life friend | Private | General testing and feedback |

---

<div align="center">

**Live Wallpaper Manager v2.9** · built for Hyprland · powered by Quickshell + mpvpaper

</div>
