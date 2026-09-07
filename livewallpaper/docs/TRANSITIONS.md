# Wallpaper transitions

Live Wallpaper Manager uses **AWWW** for compositor-side transitions on image and animated-GIF wallpapers. AWWW currently supports: `none`, `simple`, `fade`, `left`, `right`, `top`, `bottom`, `wipe`, `wave`, `grow`, `center`, `any`, `outer`, and `random`. The Playlist page exposes these choices plus a duration control.

The application maps the UI to AWWW's transition type:

```text
Fade        -> fade
Simple      -> simple
Slide Left  -> left
Slide Right -> right
Slide Up    -> top
Slide Down  -> bottom
Wipe        -> wipe
Wave        -> wave
Grow        -> grow
Center      -> center
Any         -> any
Outer       -> outer
Random      -> random
None        -> none
```

For duration-based effects the command is equivalent to:

```bash
awww img --outputs <monitor> --transition-type <type> --transition-duration <seconds> --transition-fps 60 --transition-step 90 <wallpaper>
```

`simple` does not use `--transition-duration`; it uses AWWW's own step-based simple transition. `none` switches instantly.

MP4/video wallpapers continue to use the existing persistent `mpvpaper` backend. AWWW does not render MP4 video, so it is not used for video playback.

## Requirements

- Wayland compositor with layer-shell support (for example Hyprland/Sway).
- `awww` and `awww-daemon` on `PATH` for image/GIF transitions.
- `mpvpaper` + MPV for MP4/video wallpapers.

The daemon is health-checked with `awww query`; when needed the app starts one user-level `awww-daemon` and reuses it.

## MP4 / live video switching

Local live/video wallpapers are switched directly on the existing mpvpaper instance through MPV IPC. The process and compositor surface are kept alive; there is no full-output screenshot, no Quickshell transition overlay, and no stop/relaunch cycle during a normal wallpaper change. AWWW transitions remain for image/GIF backends.


## Live MP4/video transitions

Live video wallpapers use the existing single mpvpaper/libmpv surface. No desktop
screenshot, Quickshell overlay, AWWW overlay, or second video decoder is created.
The selected transition is executed inside MPV over IPC before and after `loadfile`.

Supported live-video mappings:

- `fade`: MPV libavfilter fade-out/fade-in.
- `left`, `right`, `top`, `bottom`: pan + zoom slide.
- `wipe`, `wave`: motion reveal variants.
- `grow`, `center`, `any`, `outer`: zoom reveal variants.
- `simple`, `none`: immediate switch.
- `random`: chooses one of the animated variants.

The transition menu is shared with AWWW so the UI stays consistent. The exact visual
implementation for video is native to MPV rather than AWWW because AWWW does not render
the mpvpaper video surface.
