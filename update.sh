#!/usr/bin/env bash
#
# update.sh — Live Wallpaper Manager Updater (v2.1.6 — NixOS support)
# NOTE (v2.1.6): recognizes DISTRO_ID=nixos when picking APP_SRC_DIR (same
# livewallpaper-nixos/ override convention as -arch/-fedora/-debian, see
# install.sh). No dependency-install logic lives in this script, so
# nothing else needed to change here.
# NOTE (v2.1.5.54): kept in sync with install.sh's same-version fix --
# scripts/utils.sh's new lw_ensure_wayland_env() recovers a missing
# WAYLAND_DISPLAY (icon/menu-launched processes don't always get it, even
# when a terminal on the same machine does) from the real wayland-N socket
# on disk, used by launch_quickshell.sh, launch_debian_wayland_safe.sh and
# open_app.sh. No special handling needed in this script itself -- Step 2's
# plain scripts/ directory copy already picks up utils.sh's new function.
# NOTE: scripts/ copy is now a plain "every file, not just *.sh" copy (see
# Step 2 below) instead of *.sh + a hardcoded .py allowlist -- the old
# allowlist silently dropped newly-added non-.sh helper scripts
# (_mpv_ipc.py, _hypr_fullscreen_watch.py) on every update until someone
# remembered to add them here by name.
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
    CYAN='\033[1;33m'; DIM='\033[2m'; BOLD='\033[1m'; RESET='\033[0m'
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

# ─── App source directory ───────────────────────────────────────────────────
# Normally a single shared livewallpaper/ directory for every distro, since
# the app code itself has no distro-specific content. If distro-specific
# copies (livewallpaper-arch/, livewallpaper-fedora/, livewallpaper-debian/)
# are ever reintroduced alongside this archive, this autodetects the
# distro the same way install.sh's detect_distro() does (update.sh stays
# non-interactive by design, so it never prompts) and prefers the
# matching copy automatically.
DISTRO_ID=""
DISTRO_ID_LIKE=""
if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO_ID="${ID:-}"
    DISTRO_ID_LIKE="${ID_LIKE:-}"
fi
APP_SRC_DIR="$SCRIPT_DIR/livewallpaper"
case "$DISTRO_ID $DISTRO_ID_LIKE" in
    *arch*|*cachyos*|*endeavouros*|*manjaro*|*garuda*)
        [ -d "$SCRIPT_DIR/livewallpaper-arch" ] && APP_SRC_DIR="$SCRIPT_DIR/livewallpaper-arch" ;;
    *fedora*|*rhel*)
        [ -d "$SCRIPT_DIR/livewallpaper-fedora" ] && APP_SRC_DIR="$SCRIPT_DIR/livewallpaper-fedora" ;;
    *debian*|*ubuntu*)
        [ -d "$SCRIPT_DIR/livewallpaper-debian" ] && APP_SRC_DIR="$SCRIPT_DIR/livewallpaper-debian" ;;
    *nixos*)
        [ -d "$SCRIPT_DIR/livewallpaper-nixos" ] && APP_SRC_DIR="$SCRIPT_DIR/livewallpaper-nixos" ;;
esac

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
cp -rf "$APP_SRC_DIR/Config"      "$LWM_DEST/"
cp -rf "$APP_SRC_DIR/Services"    "$LWM_DEST/"
cp -rf "$APP_SRC_DIR/Components"  "$LWM_DEST/"
cp -rf "$APP_SRC_DIR/Panels"      "$LWM_DEST/"
[ -d "$APP_SRC_DIR/Manager" ] && cp -rf "$APP_SRC_DIR/Manager" "$LWM_DEST/"
[ -d "$APP_SRC_DIR/Pages" ]   && cp -rf "$APP_SRC_DIR/Pages"   "$LWM_DEST/"
cp -f  "$APP_SRC_DIR/shell.qml"   "$LWM_DEST/"
[ -d "$APP_SRC_DIR/assets" ] && cp -rf "$APP_SRC_DIR/assets" "$LWM_DEST/"
[ -d "$SCRIPT_DIR/assets" ]               && cp -rf "$SCRIPT_DIR/assets/."             "$LWM_DEST/assets/"

mkdir -p "$LWM_DEST/scripts"
# Copy every file in scripts/ -- NOT just *.sh + a hardcoded .py allowlist.
# That allowlist approach silently dropped newly-added helper scripts
# (e.g. _mpv_ipc.py, _hypr_fullscreen_watch.py) on every update until
# someone remembered to add them here by name, which is exactly the kind
# of bug that surfaces as "works after a fresh ./install.sh, breaks again
# after ./update.sh" days/weeks later. A plain directory copy can never
# go stale like that again.
#
# The ONLY exclusions are editor/tool backup suffixes (".orig", ".check",
# ".crossdistro", ".backup"): those are never runtime files, and a couple
# of stale pre-hardening backups shipped inside scripts/ already
# propagated straight into every installed copy via this exact loop until
# they were removed -- this guard keeps that class of regression from
# ever coming back without reintroducing the allowlist's fetch-it-by-name
# fragility.
find "$APP_SRC_DIR/scripts" -maxdepth 1 -type f \
    ! -name '*.orig' ! -name '*.crossdistro' ! -name '*.check' ! -name '*.backup' \
    ! -name '*.tmp' ! -name '*.old' ! -name '*~' ! -name '~*' \
    -exec cp -f {} "$LWM_DEST/scripts/" \;
chmod +x "$LWM_DEST/scripts/"*.sh 2>/dev/null || true
find "$LWM_DEST/scripts" -maxdepth 1 -name "*.py" -exec chmod +x {} \; 2>/dev/null || true

# Same stale-backup guard for the QML module tree copied above (Config/,
# Services/, Components/, Panels/, Manager/, Pages/). `cp -rf dir/ dest/`
# merges files in and never removes what's already there, so a legacy
# "X.qml.orig"/"X.qml.check" sitting in a subdirectory would otherwise
# ride along into every user's install on every update (the Components/
# copy has shipped at least one). Sweep the whole destination once here.
find "$LWM_DEST" -type f \( -name '*.orig' -o -name '*.crossdistro' -o -name '*.check' \
    -o -name '*.backup' -o -name '*.tmp' -o -name '*.old' -o -name '*~' -o -name '~*' \) \
    -delete 2>/dev/null || true

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
if [ -f "$APP_SRC_DIR/assets/icons/app-icon.png" ]; then
    for sz in 16x16 22x22 24x24 32x32 48x48 64x64 96x96 128x128 192x192 256x256 512x512; do
        ICON_DIR="$HOME/.local/share/icons/hicolor/$sz/apps"
        mkdir -p "$ICON_DIR"
        cp -f "$APP_SRC_DIR/assets/icons/app-icon.png" "$ICON_DIR/live-wallpaper-manager-app.png"
    done
    mkdir -p "$HOME/.local/share/pixmaps"
    cp -f "$APP_SRC_DIR/assets/icons/app-icon.png" \
        "$HOME/.local/share/pixmaps/live-wallpaper-manager-app.png"
    rm -f "$HOME/.local/share/icons/hicolor/scalable/apps/live-wallpaper-manager-app.svg"
    command -v gtk-update-icon-cache >/dev/null 2>&1 && \
        gtk-update-icon-cache -f -q "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
    APP_ICON_INSTALLED="$HOME/.local/share/icons/hicolor/512x512/apps/live-wallpaper-manager-app.png"
fi

mkdir -p "$HOME/.local/share/applications"
ICON_FOR_DESKTOP="${APP_ICON_INSTALLED:-video-x-generic}"
# __OPEN_APP_SH__ -- same fix as install.sh: filled in with the real,
# already-expanded absolute path to open_app.sh instead of leaving the
# old `bash -c "\"$HOME/...\" ..."` form, whose nested quoting was
# fragile across different desktop environments' Exec= parsers and
# could make icon clicks silently do nothing. Must stay in sync with
# install.sh's "Installing desktop entries" step.
OPEN_APP_SH="$LWM_DEST/scripts/open_app.sh"
if [ -f "$APP_SRC_DIR/live-wallpaper-manager.desktop" ]; then
    sed -e "s|__QS_CONFIG_DIR__|$LWM_DEST|g" \
        -e "s|__OPEN_APP_SH__|$OPEN_APP_SH|g" \
        -e "s|__APP_ICON_PATH__|$ICON_FOR_DESKTOP|g" \
        "$APP_SRC_DIR/live-wallpaper-manager.desktop" \
        > "$HOME/.local/share/applications/live-wallpaper-manager.desktop"
fi
if [ -f "$APP_SRC_DIR/live-wallpaper-manager-app.desktop" ]; then
    sed -e "s|__OPEN_APP_SH__|$OPEN_APP_SH|g" \
        -e "s|__APP_ICON_PATH__|$ICON_FOR_DESKTOP|g" \
        "$APP_SRC_DIR/live-wallpaper-manager-app.desktop" \
        > "$HOME/.local/share/applications/live-wallpaper-manager-app.desktop"
fi
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

# Refresh the KDE Plasma wallpaper plugin's code IF it's already
# installed (i.e. the user opted into it during a previous ./install.sh
# or via scripts/install_kde_plasma_wallpaper.sh) -- same treatment as
# the icon/desktop entries just above: code gets refreshed
# unconditionally, but the decision to have it installed at all is a
# user preference/registration, same as autostart, and is never made
# here. A no-op if it was never installed.
KDE_PLUGIN_DEST="$HOME/.local/share/plasma/wallpapers/com.livewallpapermanager.plasmawallpaper"
if [ -d "$KDE_PLUGIN_DEST" ] && [ -f "$SCRIPT_DIR/kde-plasma-wallpaper/metadata.json" ]; then
    cp -rf "$SCRIPT_DIR/kde-plasma-wallpaper/." "$KDE_PLUGIN_DEST/"
    ok "KDE Plasma wallpaper plugin refreshed → $KDE_PLUGIN_DEST"
fi

# ─── Step 2.5: Refresh yt-dlp (non-pacman distros) ────────────────────────
# yt-dlp needs to stay current or YouTube stream extraction breaks with an
# opaque "HTTP error 403 Forbidden" from googlevideo.com -- the exact same
# reason install.sh's install_ytdlp_latest() documents. update.sh used to
# leave this stale: the old "# v2.1.3 yt-dlp workflow" comment sat here
# with NO code under it, so after every ./update.sh the installed yt-dlp
# stayed at whatever version was left from install time and eventually
# started failing. This step defines its own copy of the exact same
# install_ytdlp_latest() function install.sh uses -- the two files no
# longer share a single file, so if this function ever needs to change,
# update the copy in install.sh to match.
#
# Only applies to yt-dlp managed the way install.sh manages it -- the latest
# GitHub release binary. Arch's pacman-managed yt-dlp is deliberately NOT
# touched (pacman tracks upstream closely enough to trust as-is; install.sh
# skips install_ytdlp_latest() for pacman for the same reason). A failed
# refresh (offline / GitHub unreachable) only warns -- it must never block
# or roll back the code update itself.
install_ytdlp_latest() {
    info "Installing yt-dlp (latest release binary -- distro packages of yt-dlp" \
         "routinely lag behind YouTube's changes and cause 403 stream errors)..."

    if ! command -v curl >/dev/null 2>&1; then
        info "curl not found -- installing it first (needed to fetch yt-dlp)..."
        case "$PKG_MANAGER" in
            apt)    sudo apt-get install -y curl               >/dev/null 2>&1 ;;
            dnf)    sudo dnf install -y curl                   >/dev/null 2>&1 ;;
            zypper) sudo zypper --non-interactive install curl >/dev/null 2>&1 ;;
            nix)    if declare -F lw_nix_install >/dev/null 2>&1; then
                        # install.sh provides this helper; update.sh has no
                        # equivalent, so fall through to nix itself below.
                        lw_nix_install curl >/dev/null 2>&1
                    else
                        nix profile install --extra-experimental-features 'nix-command flakes' \
                            nixpkgs#curl >/dev/null 2>&1 || true
                    fi ;;
        esac
        if ! command -v curl >/dev/null 2>&1; then
            fail "curl is required to install yt-dlp and could not be installed automatically."
            return 1
        fi
    fi

    # Remove a stale distro package first, if any, so it can't shadow
    # /usr/local/bin/yt-dlp on PATH.
    case "$PKG_MANAGER" in
        apt)    sudo apt-get remove -y yt-dlp   >/dev/null 2>&1 || true ;;
        dnf)    sudo dnf remove -y yt-dlp        >/dev/null 2>&1 || true ;;
        zypper) sudo zypper --non-interactive remove yt-dlp >/dev/null 2>&1 || true ;;
        nix)    nix profile remove yt-dlp >/dev/null 2>&1 || true ;;
    esac

    if ! sudo curl -fL --retry 3 \
        https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
        -o /usr/local/bin/yt-dlp; then
        fail "Failed to download yt-dlp from GitHub (network unavailable or GitHub unreachable)"
        fail "Manual install: sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp && sudo chmod a+rx /usr/local/bin/yt-dlp"
        return 1
    fi
    sudo chmod a+rx /usr/local/bin/yt-dlp
    ok "yt-dlp installed ($(/usr/local/bin/yt-dlp --version 2>/dev/null || echo "latest"), /usr/local/bin/yt-dlp)"
    return 0
}

step "Refreshing yt-dlp (non-pacman distros only)"
PKG_MANAGER=""
case "$DISTRO_ID" in
    arch|cachyos|endeavouros|manjaro|garuda) PKG_MANAGER="pacman" ;;
    ubuntu|debian|pop|linuxmint|elementary|zorin) PKG_MANAGER="apt" ;;
    fedora|rhel|rocky|almalinux|centos) PKG_MANAGER="dnf" ;;
    opensuse*|suse|sles) PKG_MANAGER="zypper" ;;
    nixos) PKG_MANAGER="nix" ;;
    *) PKG_MANAGER="" ;;
esac
if [ -z "$PKG_MANAGER" ] && [ -n "$DISTRO_ID_LIKE" ]; then
    case "$DISTRO_ID_LIKE" in
        *arch*)          PKG_MANAGER="pacman" ;;
        *debian*)        PKG_MANAGER="apt" ;;
        *fedora*|*rhel*) PKG_MANAGER="dnf" ;;
        *suse*)          PKG_MANAGER="zypper" ;;
        *nixos*)         PKG_MANAGER="nix" ;;
    esac
fi
if [ "$PKG_MANAGER" = "pacman" ]; then
    info "Skipping yt-dlp refresh (managed by pacman, which tracks upstream closely)"
else
    if install_ytdlp_latest; then
        ok "yt-dlp refreshed to the latest release"
    else
        warn "yt-dlp could not be refreshed (offline or GitHub unreachable) -- leaving the current one in place; re-run ./install.sh later to retry"
    fi
fi

# ─── Step 3: Restart Quickshell if it was running ──────────────────────────
if $WAS_RUNNING; then
    step "Restarting Live Wallpaper Manager"
    # restart_app.sh polls for the new process for several seconds instead
    # of a single fixed sleep + one-shot check, so a cold start that's a
    # little slow (no warm cache right after an update) doesn't print a
    # false "may not have restarted" warning. Quickshell was already fully
    # stopped in Step 1, so this is a plain fresh start, not a handoff --
    # no old PID is passed.
    if bash "$LWM_DEST/scripts/restart_app.sh" >/dev/null 2>&1; then
        ok "Quickshell restarted"
    else
        warn "Quickshell may not have restarted — start it manually: $LWM_DEST/scripts/launch_quickshell.sh -c livewallpaper"
    fi
else
    info "Quickshell was not running before the update — not starting it now"
fi

echo ""
ok "Update complete. All settings, favorites, history, playlists, and wallpapers were preserved."

# v2.1.3 yt-dlp workflow (now implemented as Step 2.5 above -- this comment
# used to be the ONLY trace of that feature, with no code under it: after
# every update.sh the installed yt-dlp stayed stale and eventually broke
# YouTube streams with 403 errors. Step 2.5 defines its own copy of the
# same install_ytdlp_latest() function install.sh uses, so non-pacman
# yt-dlp is now refreshed on every update.)

# Keep default log directory after updates
mkdir -p "$HOME/LiveWallpaperLogs"

# Ensure helper scripts stay executable
find "$(dirname "$0")" -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
