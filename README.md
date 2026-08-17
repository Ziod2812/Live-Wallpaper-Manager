# Live Wallpaper Manager

**A modern Quickshell-based live wallpaper manager for Hyprland.**

Play local videos, streams, and web content as live wallpapers with
multi-monitor support, GPU selection, Smart Playback, Music Dock,
and playlists.

[Repository](https://github.com/Ziod1395/Live-Wallpaper-Manager) ·
[MIT License](LICENSE) ·
[Report an Issue](https://github.com/Ziod1395/Live-Wallpaper-Manager/issues)

---

## ✨ Highlights

| Feature | Description |
|---|---|
| 🎞️ **Wallpapers** | Play local video wallpapers with search, favorites, history, resolution, and FPS controls. |
| 🌐 **Streaming & Web** | Use supported video URLs, websites, or local HTML in kiosk mode. |
| 🖥️ **Multi-monitor** | Run an independent wallpaper on each display. |
| 🎮 **GPU Control** | Select or pin the GPU used by `mpvpaper` on multi-GPU systems. |
| ⚡ **Smart Playback** | React to battery state, fullscreen apps, lock state, sleep, and games. |
| 🎵 **Music Dock** | Floating now-playing controls with MPRIS and a live `cava` visualizer. |
| 🕒 **Peaclock + Cava** | Independent clock/date and visualizer overlay using the shared Cava pipeline. |
| 🔁 **Playlist** | Automatic wallpaper rotation with Sequential, Random, or Favorites modes. |
| 🖥️ **Manager** | Full control from Wallpapers, Playlist, Visualizer, Monitor, Performance, Settings, and About pages. |
| 🔔 **System Tray** | Quick Open/Close, Change Wallpaper, Restart, and Quit controls. |

---

## 📋 Requirements

### Core

| Package | Required | Purpose |
|---|:---:|---|
| `quickshell` | ✅ | QML shell runtime |
| `mpvpaper` | ✅ | Wallpaper renderer |
| `ffmpeg` / `ffprobe` | ✅ | Media processing |
| `jq` | ✅ | JSON handling |
| `hyprctl` | ✅ | Hyprland integration |
| `python3` | ✅ | Tray helper |

### Optional

| Package | Used for |
|---|---|
| `yt-dlp` | Streaming platforms |
| `chromium` / `firefox` | Local HTML mode |
| `inotify-tools` | Automatic wallpaper-folder refresh |
| `cava` / `playerctl` / `pipewire` | Music Dock and media detection |
| `peaclock` | Peaclock + Cava Dock |
| `zenity`, `yad`, `kdialog`, or `xdg-desktop-portal` | Folder picker backend |

### Dependency Safety

The dependency manager distinguishes between:

- **Protected / system packages**
- **Shared dependencies**
- **Optional application-owned dependencies**

Protected and shared packages are not removed automatically.

Uninstall only allows removal of optional dependencies when Live Wallpaper
Manager can safely verify that the application owns them.

If ownership cannot be established, the package is left installed.

---

## 🚀 Installation

Choose your distribution.

### Debian / Ubuntu

```bash
git clone https://github.com/Ziod1395/Live-Wallpaper-Manager.git
cd Live-Wallpaper-Manager

chmod +x install.sh uninstall.sh update.sh
./install.sh
```

### Fedora

```bash
git clone https://github.com/Ziod1395/Live-Wallpaper-Manager.git
cd Live-Wallpaper-Manager

chmod +x install.sh uninstall.sh update.sh
./install.sh
```

### Arch Linux

```bash
git clone https://github.com/Ziod1395/Live-Wallpaper-Manager.git
cd Live-Wallpaper-Manager

chmod +x install.sh uninstall.sh update.sh
./install.sh
```

> **Arch / AUR:** `quickshell` and `mpvpaper` may be installed through
> [`yay`](https://github.com/Jguer/yay) or
> [`paru`](https://github.com/Morganamilo/paru) when available.

### NixOS

There is no dedicated NixOS installer yet.

Install the required dependencies using your Nix configuration, then follow
the project setup compatible with your Quickshell and Hyprland environment.

> Do not use `pacman`, `apt`, or `dnf` commands on NixOS.

### After installation

The installer can set up:

- application files and desktop entries
- system tray helper
- default wallpaper data
- login autostart

### Verify the installation

```bash
test -f ~/.config/quickshell/livewallpaper/shell.qml && \
echo "Live Wallpaper Manager installed"

quickshell -c livewallpaper
```

---

## ▶️ Launch

### Start the application

```bash
quickshell -c livewallpaper
```

### Toggle the main panel

```bash
quickshell -c livewallpaper ipc call livewallpaper toggle
```

### Toggle the Manager window

```bash
quickshell -c livewallpaper ipc call livewallpapermanager toggle
```

---

## 🎞️ Wallpaper Management

Place your video wallpapers in:

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

`inotify-tools` enables automatic folder refresh. Manual **Refresh** remains
available without it.

### Multi-monitor

Each display can have its own wallpaper.

The Manager's **Monitor** page shows detected outputs and what is currently
playing on each display.

### GPU selection

The **Performance** page can choose how `mpvpaper` uses available GPUs,
including automatic, vendor-specific, power-saving, and high-performance
profiles.

---

## 🔁 Playlist

The Playlist page can automatically advance wallpapers on a timer.

Available modes:

- **Sequential** — follow the current order
- **Random** — choose a random wallpaper
- **Favorites** — cycle through favorites, falling back to Random when there
  are none

Playlist timing and behavior are controlled from the Manager window.

---

## 🌐 Streaming & Web

The panel supports three playback modes:

**Wallpapers · Streaming · Web**

### Streaming

Paste a supported URL, such as:

- YouTube
- Twitch
- Vimeo
- Bilibili
- Niconico
- direct `.m3u8`, `.mp4`, or `.webm` URLs

`yt-dlp` is required for supported platform extraction.
Direct media URLs can work without it.

### Web

Web mode provides:

- **Website** — play a web URL through the existing playback engine
- **Local HTML** — open an `.html` / `.htm` file in kiosk mode using Chromium
  or Firefox

---

## 🎵 Music Dock & Peaclock + Cava

### Music Dock

A floating now-playing overlay with:

- album artwork
- title and artist
- seekable progress
- playback controls
- MPRIS media detection
- live Cava visualization

### Peaclock + Cava Dock

A separate floating overlay combining:

- clock
- date
- live Cava visualization

Both overlays are independent and can be configured from the
**Visualizer** page.

When both are enabled, they share the existing Cava pipeline instead of
starting unnecessary duplicate Cava processes.

---

## ⚡ Smart Playback & Performance

The **Performance** page combines playback quality controls with Smart
Playback rules.

Depending on your settings, playback can react to:

- battery state
- fullscreen applications
- screen lock
- monitor sleep
- game detection

Performance controls can also manage resolution/FPS behavior and GPU
selection.

---

## ⚙️ Autostart

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

## 🗂️ Configuration & Data

| Purpose | Location |
|---|---|
| Wallpaper library | `~/Pictures/Live Wallpaper` |
| Wallpaper database | `~/.config/quickshell/livewallpaper/data/wallpapers.json` |
| Settings | `~/.config/quickshell/livewallpaper/data/settings.json` |
| Recent history | `~/.config/quickshell/livewallpaper/data/history.json` |
| Thumbnails | `~/.cache/livewallpaper/thumbs/` |
| Runtime state | `~/.cache/livewallpaper/state/` |
| Logs | `~/.cache/livewallpaper/logs/` |

CLI settings are handled by:

```bash
scripts/settings.sh <get|set|reset> [key] [value]
```

---

## 🔄 Update

Update an existing installation with:

```bash
cd Live-Wallpaper-Manager
./update.sh
```

The update script refreshes the installed application code while preserving
user data such as:

- settings
- favorites
- history
- playlists
- wallpaper files

You can also update directly from a fresh clone:

```bash
git clone https://github.com/Ziod1395/Live-Wallpaper-Manager.git
cd Live-Wallpaper-Manager
chmod +x update.sh
./update.sh
```

---

## 🗑️ Uninstall

From the project directory:

```bash
cd Live-Wallpaper-Manager
./uninstall.sh
```

The uninstaller removes the application's own registrations and program
files, then asks before deleting configuration and data directories.

Dependency cleanup is safety-first:

- protected/system dependencies are never removed
- shared dependencies are not removed just because they are installed
- only verified optional application-owned dependencies may be removed
- unknown ownership means the package stays installed

---

## 🛠️ Troubleshooting

### Manager or panel does not appear

Run:

```bash
quickshell -c livewallpaper
```

Then check the QML/runtime errors printed in the terminal.

Verify:

```bash
test -f ~/.config/quickshell/livewallpaper/shell.qml
```

### mpvpaper does not start / black screen

Check:

```bash
command -v mpvpaper
mpvpaper --help
hyprctl monitors
```

Make sure you are running inside an active Hyprland session.

### Streaming does not connect

Check:

```bash
yt-dlp --version
```

For supported platforms, keep `yt-dlp` up to date.

Direct `.m3u8`, `.mp4`, and `.webm` URLs do not necessarily require
`yt-dlp`.

### System tray icon is missing

The tray helper uses `dbus-next` and `Pillow` in the project's local Python
environment.

Re-run:

```bash
./install.sh
```

to restore missing dependencies.

---

## 🧠 Advanced

### Architecture

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

### CLI scripts

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

## 🌿 Caelestia Integration

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
consume live playback state directly without an extra IPC layer.

---

## 🧪 Development

Run the bundled backend tests:

```bash
bash tests/run_gpu_manager_tests.sh
```

---

## 📄 License

Live Wallpaper Manager is licensed under the
[MIT License](LICENSE).

---

## 🙌 Credits & References

Live Wallpaper Manager is an independent project. During development,
several open-source projects and public resources were reviewed for ideas,
implementation approaches, architecture references, compatibility patterns,
and general technical learning.

Third-party projects remain under their respective licenses and copyrights.

Where attribution is required by a third-party license, the applicable
attribution and license terms should be preserved.

---

## 🧪 Testers

Thanks to everyone who helped test Live Wallpaper Manager:

| Tester | Platform | Contribution |
|---|---|---|
| [minh23102011](https://github.com/minh23102011) | GitHub | General testing and feedback |
| [@prodepxser](https://www.youtube.com/@prodepxser) | YouTube | General testing and feedback |
| [Trypezz](https://github.com/Trypezz) | GitHub | General testing and feedback |
| A real-life friend | Private | General testing and feedback |

---

<div align="center">

**Live Wallpaper Manager** · built for Hyprland · powered by Quickshell + mpvpaper

</div>
