#!/usr/bin/env bash
#
# update.sh — Live Wallpaper Manager Updater
# =====================================================
# Refreshes the installed code (QML module and scripts) from
# this extracted folder, in place, over an existing installation.
#
# Never touches:
#   - $LWM_DEST/data (favorites.json, history.json, settings.json,
#     wallpapers.json — your favorites, history, playlists, and settings)
#   - Your wallpaper video files (wherever wallpaper_directory points,
#     default ~/Pictures/Live Wallpaper)
#   - ~/.cache/livewallpaper (regenerable, but there's no reason to wipe
#     it just for a code update — thumbnails you already have stay valid)
#
# This is intentionally NOT "just run install.sh again": install.sh also
# re-runs the full interactive dependency-check/prompt flow and the
# Music Dock/system-tray dependency prompts, which is more than a
# routine code update needs. update.sh is the quiet, non-interactive
# path — if something IS newly missing, it tells you to run install.sh
# instead of trying to install it itself.
#
# Usage:
#   ./update.sh
#
set -euo pipefail

# ─── Terminal capability detection ─────────────────────────────────────────
# Colour and Unicode glyphs are only used on an interactive TTY (and, for
# colour, only when NO_COLOR isn't set) with a UTF-8 locale. Anything else —
# redirected to a file, piped through tee, a dumb terminal — falls back to
# plain ASCII with no ANSI escapes, so `./update.sh > update.log` and
# `./update.sh | tee update.log` stay clean and readable.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then USE_COLOR=1; else USE_COLOR=0; fi
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *UTF-8*|*UTF8*|*utf8*) USE_UNICODE=1 ;;
    *)                     USE_UNICODE=0 ;;
esac

# ─── Colours ──────────────────────────────────────────────────────────────
if [ "$USE_COLOR" = 1 ]; then
    RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
    CYAN='\033[0;36m'; DIM='\033[2m'; BOLD='\033[1m'; RESET='\033[0m'
else
    RED=''; YELLOW=''; GREEN=''; CYAN=''; DIM=''; BOLD=''; RESET=''
fi

# ─── Status symbols ─────────────────────────────────────────────────────────
if [ "$USE_UNICODE" = 1 ]; then
    SYM_OK='✓'; SYM_INFO='→'; SYM_WARN='⚠'; SYM_ERR='✕'; SYM_BULLET='•'
else
    SYM_OK='[OK]'; SYM_INFO='->'; SYM_WARN='[!]'; SYM_ERR='[X]'; SYM_BULLET='*'
fi

# ─── Presentation helpers ───────────────────────────────────────────────────
ok()      { printf "${GREEN}  %s %s${RESET}\n" "$SYM_OK" "$*"; }
info()    { printf "${CYAN}  %s %s${RESET}\n" "$SYM_INFO" "$*"; }
warn()    { printf "${YELLOW}  %s %s${RESET}\n" "$SYM_WARN" "$*"; }
fail()    { printf "${RED}  %s %s${RESET}\n" "$SYM_ERR" "$*"; }
step()    { echo ""; printf "${BOLD}${CYAN}%s${RESET}\n" "$*"; }
divider() { if [ "$USE_UNICODE" = 1 ]; then printf "${DIM}%s${RESET}\n" "────────────────────────────────────"; else printf -- "${DIM}%s${RESET}\n" "----------------------------------------"; fi; }
banner() {
    echo ""
    printf "${BOLD}${CYAN}"
    cat <<'LWM_LOGO'
██╗     ██╗██╗   ██╗███████╗
██║     ██║██║   ██║██╔════╝
██║     ██║██║   ██║█████╗  
██║     ██║╚██╗ ██╔╝██╔══╝  
███████╗██║ ╚████╔╝ ███████╗
╚══════╝╚═╝  ╚═══╝  ╚══════╝
██╗    ██╗ █████╗ ██╗     ██╗     ██████╗  █████╗ ██████╗ ███████╗██████╗ 
██║    ██║██╔══██╗██║     ██║     ██╔══██╗██╔══██╗██╔══██╗██╔════╝██╔══██╗
██║ █╗ ██║███████║██║     ██║     ██████╔╝███████║██████╔╝█████╗  ██████╔╝
██║███╗██║██╔══██║██║     ██║     ██╔═══╝ ██╔══██║██╔═══╝ ██╔══╝  ██╔══██╗
╚███╔███╔╝██║  ██║███████╗███████╗██║     ██║  ██║██║     ███████╗██║  ██║
 ╚══╝╚══╝ ╚═╝  ╚═╝╚══════╝╚══════╝╚═╝     ╚═╝  ╚═╝╚═╝     ╚══════╝╚═╝  ╚═╝
███╗   ███╗ █████╗ ███╗   ██╗ █████╗  ██████╗ ███████╗██████╗ 
████╗ ████║██╔══██╗████╗  ██║██╔══██╗██╔════╝ ██╔════╝██╔══██╗
██╔████╔██║███████║██╔██╗ ██║███████║██║  ███╗█████╗  ██████╔╝
██║╚██╔╝██║██╔══██║██║╚██╗██║██╔══██║██║   ██║██╔══╝  ██╔══██╗
██║ ╚═╝ ██║██║  ██║██║ ╚████║██║  ██║╚██████╔╝███████╗██║  ██║
╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝
LWM_LOGO
    printf "${RESET}\n"
    printf "${BOLD}%s${RESET}\n" "$1"
    divider
    echo ""
}

quickshell_running() { pgrep quickshell >/dev/null 2>&1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LWM_DEST="$HOME/.config/quickshell/livewallpaper"

banner "Update"

if [ ! -d "$LWM_DEST" ]; then
    fail "No existing installation found at $LWM_DEST"
    fail "Run ./install.sh first."
    exit 1
fi

# ─── Step 1: Remember + stop Quickshell ────────────────────────────────────
step "Checking for a running Live Wallpaper Manager"
WAS_RUNNING=false
if quickshell_running; then
    WAS_RUNNING=true
    info "Stopping Quickshell so the module files can be safely replaced..."
    pkill quickshell 2>/dev/null || true
    waited=0
    while quickshell_running && [ "$waited" -lt 5 ]; do sleep 1; waited=$((waited + 1)); done
    if quickshell_running; then
        warn "Quickshell did not exit within 5s — forcing (pkill -9)..."
        pkill -9 quickshell 2>/dev/null || true
        sleep 1
    fi
    if quickshell_running; then
        fail "Could not stop Quickshell. Aborting update so no files are replaced out from under a running instance."
        exit 1
    fi
    ok "Quickshell stopped"
else
    info "Quickshell is not running"
fi

# ─── Step 2: Refresh the QML module + scripts ──────────────────────────────
step "Updating Live Wallpaper Manager code → $LWM_DEST"
cp -rf "$SCRIPT_DIR/livewallpaper/Config"      "$LWM_DEST/"
cp -rf "$SCRIPT_DIR/livewallpaper/Services"    "$LWM_DEST/"
cp -rf "$SCRIPT_DIR/livewallpaper/Components"  "$LWM_DEST/"
cp -rf "$SCRIPT_DIR/livewallpaper/Panels"      "$LWM_DEST/"
[ -d "$SCRIPT_DIR/livewallpaper/Manager" ] && cp -rf "$SCRIPT_DIR/livewallpaper/Manager" "$LWM_DEST/"
[ -d "$SCRIPT_DIR/livewallpaper/Pages" ]   && cp -rf "$SCRIPT_DIR/livewallpaper/Pages"   "$LWM_DEST/"
cp -f  "$SCRIPT_DIR/livewallpaper/shell.qml"   "$LWM_DEST/"
[ -d "$SCRIPT_DIR/livewallpaper/assets" ] && cp -rf "$SCRIPT_DIR/livewallpaper/assets" "$LWM_DEST/"
[ -d "$SCRIPT_DIR/assets" ]               && cp -rf "$SCRIPT_DIR/assets/."             "$LWM_DEST/assets/"

mkdir -p "$LWM_DEST/scripts"
cp -f "$SCRIPT_DIR/livewallpaper/scripts/"*.sh "$LWM_DEST/scripts/"
[ -f "$SCRIPT_DIR/livewallpaper/scripts/_cava_reader.py" ] && \
    cp -f "$SCRIPT_DIR/livewallpaper/scripts/_cava_reader.py" "$LWM_DEST/scripts/"
[ -f "$SCRIPT_DIR/livewallpaper/scripts/_tray_icon.py" ] && \
    cp -f "$SCRIPT_DIR/livewallpaper/scripts/_tray_icon.py" "$LWM_DEST/scripts/"
[ -f "$SCRIPT_DIR/livewallpaper/scripts/cava.conf" ] && \
    cp -f "$SCRIPT_DIR/livewallpaper/scripts/cava.conf" "$LWM_DEST/scripts/"
chmod +x "$LWM_DEST/scripts/"*.sh
[ -f "$LWM_DEST/scripts/_cava_reader.py" ] && chmod +x "$LWM_DEST/scripts/_cava_reader.py"
[ -f "$LWM_DEST/scripts/_tray_icon.py" ] && chmod +x "$LWM_DEST/scripts/_tray_icon.py"

# Data (favorites/history/settings/wallpapers catalog) is DELIBERATELY
# untouched here — same seed-only-if-missing files exist already, no
# copy step at all for data/ in this script (unlike install.sh, which
# only ever seeds missing defaults too, but this makes the guarantee
# explicit and unconditional for an update).
ok "Code updated ($LWM_DEST/data left untouched)"

# Re-install icon + desktop entries in case they changed. Never touches
# autostart registration (that's a user preference, not code). Icon goes
# into every conventional hicolor size plus the legacy pixmaps fallback
# (see install.sh's "Installing app icon" step for why), and the
# .desktop files get that absolute path baked into Icon= directly rather
# than relying on icon-theme name lookup.
APP_ICON_INSTALLED=""
if [ -f "$SCRIPT_DIR/livewallpaper/assets/icons/app-icon.png" ]; then
    for sz in 16x16 22x22 24x24 32x32 48x48 64x64 96x96 128x128 192x192 256x256 512x512; do
        ICON_DIR="$HOME/.local/share/icons/hicolor/$sz/apps"
        mkdir -p "$ICON_DIR"
        cp -f "$SCRIPT_DIR/livewallpaper/assets/icons/app-icon.png" "$ICON_DIR/live-wallpaper-manager-app.png"
    done
    mkdir -p "$HOME/.local/share/pixmaps"
    cp -f "$SCRIPT_DIR/livewallpaper/assets/icons/app-icon.png" \
        "$HOME/.local/share/pixmaps/live-wallpaper-manager-app.png"
    rm -f "$HOME/.local/share/icons/hicolor/scalable/apps/live-wallpaper-manager-app.svg"
    command -v gtk-update-icon-cache >/dev/null 2>&1 && \
        gtk-update-icon-cache -f -q "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
    APP_ICON_INSTALLED="$HOME/.local/share/icons/hicolor/512x512/apps/live-wallpaper-manager-app.png"
fi

mkdir -p "$HOME/.local/share/applications"
ICON_FOR_DESKTOP="${APP_ICON_INSTALLED:-video-x-generic}"
if [ -f "$SCRIPT_DIR/livewallpaper/live-wallpaper-manager.desktop" ]; then
    sed -e "s|__QS_CONFIG_DIR__|$LWM_DEST|g" \
        -e "s|__APP_ICON_PATH__|$ICON_FOR_DESKTOP|g" \
        "$SCRIPT_DIR/livewallpaper/live-wallpaper-manager.desktop" \
        > "$HOME/.local/share/applications/live-wallpaper-manager.desktop"
fi
if [ -f "$SCRIPT_DIR/livewallpaper/live-wallpaper-manager-app.desktop" ]; then
    sed -e "s|__APP_ICON_PATH__|$ICON_FOR_DESKTOP|g" \
        "$SCRIPT_DIR/livewallpaper/live-wallpaper-manager-app.desktop" \
        > "$HOME/.local/share/applications/live-wallpaper-manager-app.desktop"
fi
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

# ─── Step 3: Restart Quickshell if it was running ──────────────────────────
if $WAS_RUNNING; then
    step "Restarting Live Wallpaper Manager"
    (nohup quickshell -c livewallpaper >/dev/null 2>&1 &) 
    disown 2>/dev/null || true
    sleep 1
    if quickshell_running; then
        ok "Quickshell restarted"
    else
        warn "Quickshell may not have restarted — start it manually: quickshell -c livewallpaper"
    fi
else
    info "Quickshell was not running before the update — not starting it now"
fi

echo ""
ok "Update complete. All settings, favorites, history, playlists, and wallpapers were preserved."
