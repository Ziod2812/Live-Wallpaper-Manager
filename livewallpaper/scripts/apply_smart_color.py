#!/usr/bin/env python3
"""
apply_smart_color.py <media_path> [--monitor <name>]
==========================================================================
Feature: Auto-generate Smart Accent Color palette
--------------------------------------------------------------------------
Extract the dominant colour from Wallpaper (static image), GIF
(first frame) or Live Wallpaper/Video (cover/thumbnail), then
synchronise the resulting HEX colour code to:

    1. livewallpaper/data/settings.json  (key "active_accent_color"),
       written via settings.sh mset — REUSES the existing file-locking
       (lw_lock_or_skip) + atomic-overwrite (lw_atomic_commit) mechanisms
       already present in the project, so there is never a race condition
       with other QML processes writing settings.json concurrently.
    2. /tmp/livewallpaper_color.current — for child processes (Cava
       reader, Web Wallpaper script, etc.) to read at runtime without
       parsing JSON or waiting for Quickshell's FileView to reload.
    3. (best-effort) Waybar (style.css), Kitty (colors.conf), Rofi
       (colors.rasi), SwayNC — only when the corresponding config
       directories already exist on the user's machine; silently skip
       if missing, never crash due to a missing desktop app.

 DEFENSIVE CODING
--------------------------------------------------------------------------
- Called ASYNCHRONOUSLY (background, `&` + disown) immediately after a
  wallpaper is successfully applied (_apply_worker.sh / _web_worker.sh),
  NEVER on the main thread -> does not freeze UI or slow down wallpaper
  changes.
- Race-condition protection when the user rapidly switches Wallpaper/GIF/
  Live Wallpaper: each call writes its own PID to a SHARED "generation
  file". Before committing any external changes (the time-consuming I/O
  step above), the process re-checks the generation file — if a NEWER
  call has already overwritten the PID (i.e. the user switched to a
  different wallpaper while this process is still extracting colour),
  this process BAILS OUT without writing anything, avoiding the "old
  colour overwrites new colour" problem when a slower process finishes
  after. This is similar to lw_cancel_inflight_apply_worker in
  utils.sh, but applied to the Python child process instead of bash
  workers.
- Does NOT spawn long-running child processes (no ffmpeg/subprocess kept
  running in background) -> no zombie processes. subprocess.run(...)
  always has `wait()` (run()'s default) with timeout, and all temp files
  are deleted in the `finally` block.
- Never raises outside main(): all errors (corrupt/empty files, missing
  libraries, ffmpeg not present, etc.) are caught and lead to
  FALLBACK_COLOR so the app doesn't crash or the script exits with a
  dirty traceback.
- Exit code is always 0 when something was written (even if fallback
  colour), ONLY returns !=0 for bad command-line args (config error,
  not runtime error) — because this script is called "fire-and-forget"
  from bash, no calling script checks its exit code in a blocking way.

 USAGE
--------------------------------------------------------------------------
    python3 apply_smart_color.py /path/to/wallpaper.png
    python3 apply_smart_color.py /path/to/anim.gif
    python3 apply_smart_color.py /path/to/video.mp4 --monitor eDP-1

Called from _apply_worker.sh / _web_worker.sh after a wallpaper is
successfully applied, e.g.:

    setsid python3 "$SCRIPT_DIR/apply_smart_color.py" "$VIDEO" \\
        > /dev/null 2>&1 < /dev/null &
    disown
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Optional

# ── Constants / paths (mirror utils.sh's LW_* to stay consistent) ──
SCRIPT_DIR = Path(__file__).resolve().parent
HOME = Path(os.environ.get("HOME", str(Path.home())))

CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", str(HOME / ".cache"))) / "livewallpaper"
DATA_DIR = HOME / ".config" / "quickshell" / "livewallpaper" / "data"
SETTINGS_FILE = DATA_DIR / "settings.json"
SETTINGS_SCRIPT = SCRIPT_DIR / "settings.sh"

# Runtime colour file shared by all child processes (Cava, Web wallpaper...).
TMP_COLOR_FILE = Path("/tmp/livewallpaper_color.current")
# "Generation file" for race-condition protection — see docstring above.
TMP_GENERATION_FILE = Path("/tmp/livewallpaper_color.generation")

# System dark colour used as safe fallback on any error.
FALLBACK_COLOR = "#353446"

GIF_EXTS = {".gif"}
IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".bmp"}
VIDEO_EXTS = {
    ".mp4", ".webm", ".mkv", ".mov", ".avi", ".m4v",
    ".mpeg", ".mpg", ".wmv", ".flv", ".ts", ".mts", ".m2ts", ".3gp", ".ogv",
}

HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")


# ──────────────────────────────────────────────────────────────────────────
# Step 1: Format detection & representative image extraction
# ──────────────────────────────────────────────────────────────────────────

def _ext_of(path: Path) -> str:
    return path.suffix.lower()


def _extract_gif_first_frame(gif_path: Path, tmp_dir: Path) -> Optional[Path]:
    """Extract the first frame of a GIF using Pillow, save as temporary PNG."""
    try:
        from PIL import Image
    except ImportError:
        return None

    try:
        with Image.open(gif_path) as im:
            im.seek(0)
            frame = im.convert("RGB")
            out_path = tmp_dir / "gif_first_frame.png"
            frame.save(out_path, format="PNG")
            return out_path
    except Exception:
        # Corrupt/empty GIF file, or no valid frame available.
        return None


def _extract_video_thumbnail(video_path: Path, tmp_dir: Path) -> Optional[Path]:
    """Use ffmpeg to grab a single frame as cover image (like scripts/thumbnail.sh)."""
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        return None

    out_path = tmp_dir / "video_thumb.png"

    def _grab(seek: Optional[str]) -> bool:
        cmd = [ffmpeg, "-y"]
        if seek:
            cmd += ["-ss", seek]
        cmd += [
            "-i", str(video_path),
            "-frames:v", "1",
            "-vf", "scale=400:225:force_original_aspect_ratio=increase,crop=400:225",
            "-loglevel", "error",
            str(out_path),
        ]
        try:
            subprocess.run(cmd, timeout=20, check=False,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except (subprocess.TimeoutExpired, OSError):
            return False
        return out_path.exists() and out_path.stat().st_size > 0

    # Like thumbnail.sh: try at second 3 first, shorter videos fall back to the first frame.
    if _grab("00:00:03"):
        return out_path
    if _grab(None):
        return out_path
    return None


def _resolve_source_image(media_path: Path, tmp_dir: Path) -> Optional[Path]:
    """Return the PNG/JPEG image path used for colour extraction, or None on error."""
    if not media_path.is_file():
        return None
    if media_path.stat().st_size == 0:
        return None

    ext = _ext_of(media_path)

    if ext in GIF_EXTS:
        return _extract_gif_first_frame(media_path, tmp_dir)

    if ext in VIDEO_EXTS:
        return _extract_video_thumbnail(media_path, tmp_dir)

    if ext in IMAGE_EXTS:
        return media_path

    # Unknown format: try treating as static image first (some wallpapers
    # lack a standard extension); if Pillow can't open it, give up and
    # let main() fall through to the fallback branch.
    return media_path


# ──────────────────────────────────────────────────────────────────────────
# Step 2: Extract dominant colour from representative image
# ──────────────────────────────────────────────────────────────────────────

def _dominant_color_via_colorthief(image_path: Path) -> Optional[tuple[int, int, int]]:
    try:
        from colorthief import ColorThief
    except ImportError:
        return None
    try:
        ct = ColorThief(str(image_path))
        return ct.get_color(quality=4)
    except Exception:
        return None


def _dominant_color_via_pillow_fallback(image_path: Path) -> Optional[tuple[int, int, int]]:
    """Fallback when ColorThief is not available: quantise using Pillow.

    Not as good as ColorThief's dedicated median-cut algorithm, but
    good enough to avoid a hard dependency on a package that isn't
    always available on every distro (Arch/Fedora/Debian/Ubuntu/NixOS).
    """
    try:
        from PIL import Image
    except ImportError:
        return None
    try:
        with Image.open(image_path) as im:
            im = im.convert("RGB")
            im.thumbnail((150, 150))
            # 16 colours, Pillow's default median-cut method.
            quantized = im.quantize(colors=16, method=Image.Quantize.MEDIANCUT)
            palette = quantized.getpalette() or []
            color_counts = sorted(quantized.getcolors(), reverse=True)
            if not color_counts:
                return None
            _, dominant_index = color_counts[0]
            r = palette[dominant_index * 3]
            g = palette[dominant_index * 3 + 1]
            b = palette[dominant_index * 3 + 2]
            return (r, g, b)
    except Exception:
        return None


def _rgb_to_hex(rgb: tuple[int, int, int]) -> str:
    r, g, b = (max(0, min(255, int(c))) for c in rgb)
    return "#{:02X}{:02X}{:02X}".format(r, g, b)


def extract_accent_hex(media_path: Path, tmp_dir: Path) -> str:
    """Main entry point for colour extraction. Always returns a valid HEX
    code — never raises; any error falls back to FALLBACK_COLOR."""
    try:
        source_image = _resolve_source_image(media_path, tmp_dir)
        if source_image is None:
            return FALLBACK_COLOR

        rgb = _dominant_color_via_colorthief(source_image)
        if rgb is None:
            rgb = _dominant_color_via_pillow_fallback(source_image)
        if rgb is None:
            return FALLBACK_COLOR

        hex_color = _rgb_to_hex(rgb)
        return hex_color if HEX_RE.match(hex_color) else FALLBACK_COLOR
    except Exception:
        # Last-resort safety net: any unforeseen error (image corrupted
        # in an unusual way, out of memory, etc.) must not let this
        # background process exit with a traceback.
        return FALLBACK_COLOR


# ──────────────────────────────────────────────────────────────────────────
# Step 3: Race-condition protection via generation file
# ──────────────────────────────────────────────────────────────────────────

def _claim_generation() -> str:
    """Write THIS call's PID+timestamp into the generation file and return
    a "token" string to re-check later. Written directly (no locking)
    because overwriting one short line is near-atomic on all common Linux
    filesystems at this size, and if a rare collision occurs the worst
    outcome is one extra run self-bailing-out needlessly — never data
    corruption."""
    token = f"{os.getpid()}:{time.time_ns()}"
    try:
        TMP_GENERATION_FILE.write_text(token, encoding="utf-8")
    except OSError:
        pass
    return token


def _still_latest(token: str) -> bool:
    """True if no NEWER call has overwritten the generation file since we
    claimed it. If the file can't be read for any reason, treat it as
    still-latest (fail-open) — better to write once extra than to never
    update the colour because of an unrelated transient I/O error."""
    try:
        return TMP_GENERATION_FILE.read_text(encoding="utf-8").strip() == token
    except OSError:
        return True


# ──────────────────────────────────────────────────────────────────────────
# Step 4: Write result — settings.json (via settings.sh), tmp file, dotfiles
# ──────────────────────────────────────────────────────────────────────────

def _atomic_write_text(path: Path, content: str) -> None:
    """Atomic write: write to a temp file in the same directory then
    os.replace() — never let a reader see a partial write."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
        os.replace(tmp_name, path)
    except Exception:
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        raise


def _write_settings_json(hex_color: str) -> bool:
    """Write "active_accent_color" into settings.json via settings.sh
    mset — ABSOLUTELY never parse/overwrite settings.json directly from
    Python, to avoid conflicting with lw_lock_or_skip/lw_atomic_commit
    that every other writer (from QML SettingsService) already goes
    through."""
    if not SETTINGS_SCRIPT.is_file():
        return False
    patch = json.dumps({"active_accent_color": hex_color})
    try:
        result = subprocess.run(
            ["bash", str(SETTINGS_SCRIPT), "mset", patch],
            timeout=10, check=False,
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        )
        return result.returncode == 0
    except (subprocess.TimeoutExpired, OSError):
        return False


def _write_tmp_color_file(hex_color: str) -> None:
    try:
        _atomic_write_text(TMP_COLOR_FILE, hex_color + "\n")
    except Exception:
        pass


# ── Dotfiles sync (best-effort — silently skip if the app doesn't exist) ──
#
# Each function below ONLY edits a BLOCK marked by Live Wallpaper Manager's
# own marker comment inside the user's original config file — never
# overwrites the whole file, so it won't destroy the other manual config
# the user already has in that same file.

_MARKER_BEGIN = "/* LIVEWALLPAPER-SMART-ACCENT:BEGIN */"
_MARKER_END = "/* LIVEWALLPAPER-SMART-ACCENT:END */"


def _replace_marked_block(path: Path, block_body: str,
                           marker_begin: str = _MARKER_BEGIN,
                           marker_end: str = _MARKER_END) -> bool:
    """Insert/replace the `marker_begin...marker_end` block inside `path`.
    If no marker exists, the block is appended to the end of the file.
    Returns False (does nothing) if the file doesn't exist — best-effort,
    never creates another app's config file."""
    if not path.is_file():
        return False
    try:
        original = path.read_text(encoding="utf-8")
    except OSError:
        return False

    new_block = f"{marker_begin}\n{block_body}\n{marker_end}"

    if marker_begin in original and marker_end in original:
        pattern = re.compile(
            re.escape(marker_begin) + r".*?" + re.escape(marker_end),
            re.DOTALL,
        )
        updated = pattern.sub(new_block, original, count=1)
    else:
        sep = "\n" if original and not original.endswith("\n") else ""
        updated = f"{original}{sep}\n{new_block}\n"

    try:
        _atomic_write_text(path, updated)
        return True
    except OSError:
        return False


def _sync_waybar(hex_color: str) -> None:
    style_css = HOME / ".config" / "waybar" / "style.css"
    css = (
        "@define-color lw_smart_accent " + hex_color + ";\n"
        "window#waybar, #workspaces button.active, #clock {\n"
        "    border-color: @lw_smart_accent;\n"
        "}"
    )
    if _replace_marked_block(style_css, css):
        # Waybar reloads style.css on SIGUSR2 — no need to restart the
        # whole process.
        try:
            subprocess.run(["pkill", "-SIGUSR2", "waybar"], timeout=3,
                            check=False, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL)
        except (subprocess.TimeoutExpired, OSError):
            pass


def _sync_kitty(hex_color: str) -> None:
    colors_conf = HOME / ".config" / "kitty" / "colors.conf"
    body = f"cursor {hex_color}\nselection_background {hex_color}\nurl_color {hex_color}"
    if not _replace_marked_block(colors_conf, body, "# LIVEWALLPAPER-SMART-ACCENT:BEGIN",
                                  "# LIVEWALLPAPER-SMART-ACCENT:END"):
        return
    # kitty remote control applies colours immediately if a socket is
    # available, NO need to restart the open terminal (best-effort, silent if off).
    kitten = shutil.which("kitten") or shutil.which("kitty")
    if not kitten:
        return
    try:
        subprocess.run(
            [kitten, "@", "set-colors", "--all", "--configured", str(colors_conf)],
            timeout=3, check=False,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    except (subprocess.TimeoutExpired, OSError):
        pass


def _sync_rofi(hex_color: str) -> None:
    colors_rasi = HOME / ".config" / "rofi" / "colors.rasi"
    body = (
        "* {\n"
        f"    lw-smart-accent: {hex_color};\n"
        "    selected-normal-background: @lw-smart-accent;\n"
        "    selected-active-background: @lw-smart-accent;\n"
        "}"
    )
    # Rofi has no persistent process (each invocation reads config fresh),
    # so no reload signal is needed.
    _replace_marked_block(colors_rasi, body)


def _sync_swaync(hex_color: str) -> None:
    style_css = HOME / ".config" / "swaync" / "style.css"
    css = (
        "@define-color lw_smart_accent " + hex_color + ";\n"
        ".notification-row .notification-background .notification-content,\n"
        ".control-center {\n"
        "    border-color: @lw_smart_accent;\n"
        "}"
    )
    if _replace_marked_block(style_css, css):
        client = shutil.which("swaync-client")
        if client:
            try:
                subprocess.run([client, "--reload-css"], timeout=3, check=False,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except (subprocess.TimeoutExpired, OSError):
                pass


def sync_desktop_components(hex_color: str) -> None:
    """Synchronise to Waybar/Kitty/Rofi/SwayNC. Each function is independent,
    a failure in one must not block the others (no shared exception
    scope)."""
    for fn in (_sync_waybar, _sync_kitty, _sync_rofi, _sync_swaync):
        try:
            fn(hex_color)
        except Exception:
            # A desktop component error (permissions, file locked by
            # another app, etc.) must not break the remaining steps.
            continue


# ──────────────────────────────────────────────────────────────────────────
# main
# ──────────────────────────────────────────────────────────────────────────

def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract and synchronise Smart Accent Color for Live Wallpaper Manager.")
    parser.add_argument("media_path", help="Path to the wallpaper image/GIF/video just applied")
    parser.add_argument("--monitor", default="", help="Output/monitor name (for logging only)")
    return parser.parse_args(argv)


def main(argv: Optional[list[str]] = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    media_path = Path(os.path.expanduser(args.media_path)).resolve() if args.media_path else None

    if not args.media_path:
        print("Usage: apply_smart_color.py <media_path> [--monitor <name>]", file=sys.stderr)
        return 2

    # Claim generation IMMEDIATELY, before any time-consuming I/O — a newer
    # call appearing while we are processing will overwrite the generation
    # file and cause the commit step at the end to auto bail-out.
    token = _claim_generation()

    tmp_dir = Path(tempfile.mkdtemp(prefix="lw-smart-color-"))
    try:
        hex_color = extract_accent_hex(media_path, tmp_dir) if media_path else FALLBACK_COLOR
    finally:
        # Clean up temp directory immediately — don't leave garbage in /tmp
        # across multiple wallpaper switches (no child processes need this
        # directory to outlive extract_accent_hex()).
        shutil.rmtree(tmp_dir, ignore_errors=True)

    # ── Race Condition Check ──────────────────────────────────────────────
    # If a NEWER call has already started (user switched to a different
    # wallpaper while we were extracting colour above), skip the entire
    # write to avoid the OLD colour (from this call) overwriting the NEW
    # colour that the other call may have already (or is about to) write.
    if not _still_latest(token):
        return 0

    _write_settings_json(hex_color)
    _write_tmp_color_file(hex_color)
    sync_desktop_components(hex_color)

    return 0


if __name__ == "__main__":
    sys.exit(main())
