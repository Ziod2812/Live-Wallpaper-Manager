# Live Wallpaper Manager — KDE Plasma bridge

## Why this exists

Live Wallpaper Manager's normal playback path is `mpvpaper`, which renders
through Wayland's `wlr-layer-shell` protocol — it needs a Wayland session
and cannot connect to an X11 display at all. Under **KDE Plasma** this
means two different problems depending on the session type:

- **Plasma Wayland (KWin Wayland)**: mpvpaper does run, but KWin doesn't
  support `wlr-layer-shell` the way wlroots compositors (Hyprland, Sway,
  ...) do. In practice, the video wallpaper goes blank the moment the
  desktop regains input (e.g. on a click) — a known upstream limitation
  of that combination, not something fixable by changing `mpvpaper`'s
  launch flags.
- **Plasma X11 (KWin X11)**: mpvpaper cannot start at all — there is no
  Wayland socket for it to connect to.

This directory is a real **Plasma Wallpaper KPackage plugin**, loaded by
`plasmashell` itself through KDE's own wallpaper plugin system — the same
mechanism the built-in "Image"/"Slideshow" wallpapers use. It never
touches `wlr-layer-shell` or `mpvpaper`, so it works identically on
**both Plasma Wayland and Plasma X11**: it fixes the blanking-on-click
bug on Wayland, and it's the only way to get video wallpaper at all on
X11.

## What it does

It reads the same state files `scripts/utils.sh` already writes (the
per-monitor `current` file, plus `settings.json`) and plays whatever is
there using Qt's own `QtMultimedia`, matched to the real output name of
the screen it's running on. It does not launch or control `mpvpaper` —
it's a read-only mirror of whatever Live Wallpaper Manager already has
applied.

## What it does **not** do

- **Streaming mode**: only a direct, already-playable URL works (a raw
  `.mp4`/HLS link, e.g. from Twitch). A YouTube/Twitch/etc. *page* URL
  needs `yt-dlp` to resolve first — that happens in
  `scripts/_stream_worker.sh` (a shell script); plain QML in a Plasma
  wallpaper plugin has no way to shell out to `yt-dlp` itself. Those URLs
  are simply left unplayed here until this bridge is extended.
- **Web wallpaper mode** (kiosk browser / arbitrary HTML) — not a video
  source, out of scope.
- The Manager window's playback controls (next/previous/pause/seek) only
  affect the process they were built for. This bridge doesn't expose any
  controls of its own — it just mirrors state.

## What happens if you *don't* install this on Plasma X11

Applying a video wallpaper or stream through the normal Live Wallpaper
Manager window will fail with a clear error ("mpvpaper needs a Wayland
session...") pointing back here, instead of an opaque `mpvpaper` crash —
this bridge is what actually renders the video in that case.

## Install

```bash
./scripts/install_kde_plasma_wallpaper.sh
```

Then: right-click the desktop → **Configure Desktop and Wallpaper…** (or
System Settings → Appearance → Wallpaper), change the wallpaper type to
**"Live Wallpaper Manager"**, and apply a video wallpaper as usual from
the Live Wallpaper Manager window.

If it doesn't show up in the wallpaper type list, KDE may need
`plasmashell` restarted to notice the new package:

```bash
plasmashell --replace &
```

## Uninstall

```bash
./scripts/install_kde_plasma_wallpaper.sh --remove
```

## Status

This was written from KDE/Qt6/Plasma6 documentation and established QML
patterns, but has **not** been exercised against a live `plasmashell`
session — there was no KDE Plasma environment available to test against
while writing it. Please report the exact behavior (including anything
`plasmashell --replace` prints in a terminal) so it can be corrected
against reality.
