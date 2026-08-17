#!/usr/bin/env bash
#
# install.sh — Live Wallpaper Manager Installer
# =============================================================
# Installs BOTH Live Wallpaper Manager (Quickshell module) and
# directory. Run from the extracted folder:
#
#   cd Live-Wallpaper-Manager
#   chmod +x install.sh uninstall.sh
#   ./install.sh
#
# IDEMPOTENT: safe to run multiple times — existing user config/data is
# never overwritten, an existing venv is reused (not rebuilt from scratch),
# an existing systemd unit is updated but not double-started.
#
set -euo pipefail

# ─── Signal handling ────────────────────────────────────────────────────────
trap 'echo; fail "Installation cancelled by user (Ctrl+C)."; exit 130' INT

# ─── Terminal capability detection ─────────────────────────────────────────
# Colour and Unicode glyphs are only used on an interactive TTY (and, for
# colour, only when NO_COLOR isn't set) with a UTF-8 locale. Anything else —
# redirected to a file, piped through tee, a dumb terminal — falls back to
# plain ASCII with no ANSI escapes, so `./install.sh > install.log` and
# `./install.sh | tee install.log` stay clean and readable.
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
    # Widened to match the "Wallpaper" content column in the reference
    # design (banner-only — the shared divider() used by prompt_install()
    # and the closing summary section is untouched).
    if [ "$USE_UNICODE" = 1 ]; then
        printf "${DIM}%s${RESET}\n" "─────────────────────────────────────────"
    else
        printf -- "${DIM}%s${RESET}\n" "-------------------------------------------"
    fi
    echo ""
}

# ─── Dependency auto-install ────────────────────────────────────────────────
# Table of checked dependencies: display_name|check_command|hard|soft|pkg_key
# "hard" deps block installation; "soft" deps only warn. pkg_key is the key
# used to look up the actual package name per distro below (several commands
# — ffmpeg/ffprobe, hyprctl — share one pkg_key because they ship in the same
# package).
DEP_TABLE="quickshell|quickshell|hard|quickshell
mpvpaper|mpvpaper|hard|mpvpaper
ffmpeg|ffmpeg|hard|ffmpeg
ffprobe|ffprobe|hard|ffmpeg
jq|jq|hard|jq
hyprctl|hyprctl|hard|hyprland
python3|python3|hard|python3
curl|curl|soft|curl
inotifywait|inotifywait|soft|inotify-tools
yt-dlp|yt-dlp|soft|yt-dlp
zenity|zenity|soft|zenity
yad|yad|soft|yad
kdialog|kdialog|soft|kdialog
cava|cava|soft|cava
playerctl|playerctl|soft|playerctl
pipewire|pipewire|soft|pipewire
peaclock|peaclock|soft|peaclock"

# Package name per distro family. Empty string = no known native package on
# that distro (installer will say so and ask for manual install). "AUR:name"
# = Arch-only, installed via an AUR helper (yay/paru) rather than pacman.
declare -A PKG_PACMAN=(
    [quickshell]="AUR:quickshell"   [mpvpaper]="AUR:mpvpaper"
    [ffmpeg]="ffmpeg"               [jq]="jq"
    [hyprland]="hyprland"           [python3]="python"
    [curl]="curl"                   [inotify-tools]="inotify-tools"
    [yt-dlp]="yt-dlp"
    [xdg-desktop-portal]="xdg-desktop-portal"
    [zenity]="zenity"               [yad]="yad"
    [kdialog]="kdialog"
    [cava]="cava"                   [playerctl]="playerctl"
    [pipewire]="pipewire"
    [peaclock]="AUR:peaclock"
)
declare -A PKG_APT=(
    [quickshell]=""                 [mpvpaper]=""
    [ffmpeg]="ffmpeg"                [jq]="jq"
    [hyprland]="hyprland"           [python3]="python3"
    [curl]="curl"                   [inotify-tools]="inotify-tools"
    [yt-dlp]="yt-dlp"
    [xdg-desktop-portal]="xdg-desktop-portal"
    [zenity]="zenity"               [yad]="yad"
    [kdialog]="kdialog"
    [cava]="cava"                   [playerctl]="playerctl"
    [pipewire]="pipewire"
    [peaclock]=""
)
declare -A PKG_DNF=(
    [quickshell]=""                 [mpvpaper]=""
    [ffmpeg]="ffmpeg"                [jq]="jq"
    [hyprland]="hyprland"           [python3]="python3"
    [curl]="curl"                   [inotify-tools]="inotify-tools"
    [yt-dlp]="yt-dlp"
    [xdg-desktop-portal]="xdg-desktop-portal"
    [zenity]="zenity"               [yad]="yad"
    [kdialog]="kdialog"
    [cava]="cava"                   [playerctl]="playerctl"
    [pipewire]="pipewire"
    [peaclock]=""
)
declare -A PKG_ZYPPER=(
    [quickshell]=""                 [mpvpaper]=""
    [ffmpeg]="ffmpeg"                [jq]="jq"
    [hyprland]="hyprland"           [python3]="python3"
    [curl]="curl"                   [inotify-tools]="inotify-tools"
    [yt-dlp]="yt-dlp"
    [xdg-desktop-portal]="xdg-desktop-portal"
    [zenity]="zenity"               [yad]="yad"
    [kdialog]="kdialog"
    [cava]="cava"                   [playerctl]="playerctl"
    [pipewire]="pipewire"
    [peaclock]=""
)

PKG_MANAGER=""       # pacman | apt | dnf | zypper | ""
DISTRO_ID=""
DISTRO_ID_LIKE=""
AUR_HELPER=""         # yay | paru | ""
declare -A MISSING_PKGS=()    # pkg_key -> hard|soft
declare -A MISSING_LABELS=()  # pkg_key -> comma-separated command names

detect_distro() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO_ID="${ID:-unknown}"
        DISTRO_ID_LIKE="${ID_LIKE:-}"
    else
        DISTRO_ID="unknown"
        DISTRO_ID_LIKE=""
    fi
}

detect_package_manager() {
    case "$DISTRO_ID" in
        arch|cachyos|endeavouros|manjaro|garuda) PKG_MANAGER="pacman" ;;
        ubuntu|debian|pop|linuxmint|elementary|zorin) PKG_MANAGER="apt" ;;
        fedora|rhel|rocky|almalinux|centos) PKG_MANAGER="dnf" ;;
        opensuse*|suse|sles) PKG_MANAGER="zypper" ;;
        *) PKG_MANAGER="" ;;
    esac

    if [ -z "$PKG_MANAGER" ] && [ -n "$DISTRO_ID_LIKE" ]; then
        case "$DISTRO_ID_LIKE" in
            *arch*)          PKG_MANAGER="pacman" ;;
            *debian*)        PKG_MANAGER="apt" ;;
            *fedora*|*rhel*) PKG_MANAGER="dnf" ;;
            *suse*)          PKG_MANAGER="zypper" ;;
        esac
    fi

    # Last resort: whichever package-manager binary actually exists.
    if [ -z "$PKG_MANAGER" ]; then
        if command -v pacman   >/dev/null 2>&1; then PKG_MANAGER="pacman"
        elif command -v apt-get >/dev/null 2>&1; then PKG_MANAGER="apt"
        elif command -v dnf     >/dev/null 2>&1; then PKG_MANAGER="dnf"
        elif command -v zypper  >/dev/null 2>&1; then PKG_MANAGER="zypper"
        fi
    fi
}

detect_aur_helper() {
    if command -v yay >/dev/null 2>&1; then
        AUR_HELPER="yay"
    elif command -v paru >/dev/null 2>&1; then
        AUR_HELPER="paru"
    else
        AUR_HELPER=""
    fi
}

get_package_name() {
    local key="$1"
    case "$PKG_MANAGER" in
        pacman) printf '%s' "${PKG_PACMAN[$key]:-}" ;;
        apt)    printf '%s' "${PKG_APT[$key]:-}"    ;;
        dnf)    printf '%s' "${PKG_DNF[$key]:-}"    ;;
        zypper) printf '%s' "${PKG_ZYPPER[$key]:-}" ;;
        *)      printf '%s' ""                      ;;
    esac
}

# Runs the dependency checks, printing ok/fail/warn per item (same style as
# before), and (re)populates MISSING_PKGS / MISSING_LABELS. Safe to call
# more than once (used for the initial check and the post-install re-check).
collect_missing_dependencies() {
    MISSING_PKGS=()
    MISSING_LABELS=()

    local label cmd req pkgkey
    while IFS='|' read -r label cmd req pkgkey; do
        [ -z "$label" ] && continue
        if command -v "$cmd" >/dev/null 2>&1; then
            ok "$label"
            continue
        fi
        if [ "$req" = "hard" ]; then
            fail "$label — REQUIRED, not found on PATH"
            MISSING_PKGS[$pkgkey]="hard"
        else
            warn "$label — optional, not found"
            if [ "${MISSING_PKGS[$pkgkey]:-}" != "hard" ]; then
                MISSING_PKGS[$pkgkey]="soft"
            fi
        fi
        if [ -n "${MISSING_LABELS[$pkgkey]:-}" ]; then
            MISSING_LABELS[$pkgkey]="${MISSING_LABELS[$pkgkey]}, $label"
        else
            MISSING_LABELS[$pkgkey]="$label"
        fi
    done <<< "$DEP_TABLE"

    # xdg-desktop-portal: checked live over D-Bus rather than just
    # "is gdbus on PATH", since gdbus itself ships with glib2 (present on
    # nearly every desktop system) regardless of whether a portal
    # service is actually installed/running. Soft/optional, like
    # zenity/yad/kdialog above -- Browse only needs ONE working backend.
    if command -v gdbus >/dev/null 2>&1 && \
       timeout 3 gdbus call --session --dest org.freedesktop.DBus \
           --object-path /org/freedesktop/DBus \
           --method org.freedesktop.DBus.GetNameOwner \
           org.freedesktop.portal.Desktop >/dev/null 2>&1; then
        ok "xdg-desktop-portal (folder picker backend)"
    else
        warn "xdg-desktop-portal — optional, not found or no portal backend running"
        MISSING_PKGS[xdg-desktop-portal]="soft"
        MISSING_LABELS[xdg-desktop-portal]="xdg-desktop-portal"
    fi

    # Browser is an either/or choice (chromium OR firefox) and isn't a single
    # installable package, so it stays informational-only, same as before.
    if command -v chromium >/dev/null 2>&1 || command -v chromium-browser >/dev/null 2>&1 || command -v firefox >/dev/null 2>&1; then
        ok "browser (for Web mode Local HTML)"
    else
        warn "no chromium/firefox found — Web mode's Local HTML source will fail until one is installed (Web-URL source is unaffected, it uses mpvpaper)"
    fi

    # The "Browse..." folder picker only needs ONE of the four backends
    # above (portal / zenity / yad / kdialog) to work -- flag it clearly
    # only when ALL FOUR are missing, rather than nagging about each one
    # individually when e.g. zenity alone is already enough.
    if [ -n "${MISSING_PKGS[xdg-desktop-portal]:-}" ] && [ -n "${MISSING_PKGS[zenity]:-}" ] && \
       [ -n "${MISSING_PKGS[yad]:-}" ] && [ -n "${MISSING_PKGS[kdialog]:-}" ]; then
        warn "No folder-picker backend found at all -- the Browse... button will show an error until at least one of xdg-desktop-portal, zenity, yad, or kdialog is installed."
    fi
}

# Shows the missing-dependency summary and asks the user whether to install
# them automatically. Returns 0 for yes, 1 for no. Defaults to yes.
prompt_install() {
    echo ""
    divider
    echo "Missing dependencies:"
    echo ""
    local k tag
    for k in "${!MISSING_PKGS[@]}"; do
        tag="Optional"
        [ "${MISSING_PKGS[$k]}" = "hard" ] && tag="Required"
        echo "  $SYM_BULLET ${MISSING_LABELS[$k]} ($tag)"
    done
    echo ""
    echo "Would you like the installer to install them automatically?"
    echo ""
    echo "  [Y] Yes"
    echo "  [N] No"
    echo ""
    divider

    if [ ! -t 0 ]; then
        info "Non-interactive shell detected — defaulting to Yes"
        return 0
    fi

    local choice=""
    read -rp "Choice [Y/n]: " choice || choice=""
    choice="${choice:-Y}"
    case "$choice" in
        [Yy]*) return 0 ;;
        *)     return 1 ;;
    esac
}

# Installs a single dependency by its pkg_key. Handles pacman/apt/dnf/zypper
# plus the Arch-only AUR case. Returns 1 (without killing the shell, thanks
# to the caller checking the return value) on any failure, with a message
# covering the common causes: sudo cancelled, no network, unknown package,
# missing AUR helper, or an unsupported package manager.
install_dependency() {
    local key="$1" label="$2" pkg
    pkg="$(get_package_name "$key")"

    if [ -z "$pkg" ]; then
        warn "No known package for $label on this distro — please install it manually."
        return 1
    fi

    if [[ "$pkg" == AUR:* ]]; then
        pkg="${pkg#AUR:}"
        if [ -z "$AUR_HELPER" ]; then
            fail "$label requires an AUR helper (yay or paru), none found."
            return 1
        fi
        info "Installing $label ($pkg) via $AUR_HELPER..."
        if ! "$AUR_HELPER" -S --needed --noconfirm "$pkg"; then
            fail "Failed to install $label via $AUR_HELPER (network unavailable, prompt cancelled, or package not found)"
            return 1
        fi
        ok "$label installed"
        return 0
    fi

    info "Installing $label ($pkg)..."
    local install_status=0
    case "$PKG_MANAGER" in
        pacman) sudo pacman -S --needed --noconfirm "$pkg" || install_status=$? ;;
        apt)    sudo apt-get install -y "$pkg"             || install_status=$? ;;
        dnf)    sudo dnf install -y "$pkg"                 || install_status=$? ;;
        zypper) sudo zypper --non-interactive install "$pkg" || install_status=$? ;;
        *)
            fail "No supported package manager detected — cannot install $label automatically."
            return 1
            ;;
    esac
    if [ "$install_status" -ne 0 ]; then
        fail "Failed to install $label (sudo cancelled, network unavailable, or package not found)"
        return 1
    fi
    ok "$label installed"
    return 0
}

# Installs everything currently in MISSING_PKGS, one at a time (so failures
# are attributable to a single package). Stops the installer immediately on
# the first failure of a HARD/required dependency, per project requirements.
# A failed SOFT/optional dependency (e.g. peaclock has no native apt/dnf/
# zypper package -- AUR only, see PKG_PACMAN/PKG_APT/PKG_DNF/PKG_ZYPPER
# above) only warns and continues -- it was never supposed to be able to
# block installation of the rest of the app, and optional features already
# degrade gracefully at runtime when their dependency is missing (see e.g.
# CavaService.qml/MprisService.qml/PeaclockCavaDockPanel.qml).
install_missing_dependencies() {
    local k
    for k in "${!MISSING_PKGS[@]}"; do
        if ! install_dependency "$k" "${MISSING_LABELS[$k]}"; then
            if [ "${MISSING_PKGS[$k]}" = "hard" ]; then
                echo ""
                fail "Dependency installation failed on: ${MISSING_LABELS[$k]}"
                fail "Installer stopped. Please install it manually and re-run ./install.sh"
                exit 1
            else
                warn "Optional dependency failed to install: ${MISSING_LABELS[$k]} — continuing without it."
            fi
        fi
    done
    echo ""
    ok "All requested dependencies processed."
}

# Re-runs the dependency checker after an install pass. Continues silently
# if everything required is now present; exits cleanly, listing whatever is
# still missing, if any REQUIRED dependency is still absent.
verify_dependencies() {
    step "Re-checking dependencies"
    collect_missing_dependencies

    local still_missing=() k
    for k in "${!MISSING_PKGS[@]}"; do
        [ "${MISSING_PKGS[$k]}" = "hard" ] && still_missing+=("${MISSING_LABELS[$k]}")
    done

    if [ "${#still_missing[@]}" -gt 0 ]; then
        echo ""
        fail "Still missing required dependencies: ${still_missing[*]}"
        fail "Please install them manually and re-run ./install.sh"
        exit 1
    fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Paths ─────────────────────────────────────────────────────────────────
LWM_DEST="$HOME/.config/quickshell/livewallpaper"

# ─── Banner ────────────────────────────────────────────────────────────────
banner "Installation"

# ─── Step 1: Check dependencies ────────────────────────────────────────────
step "Checking dependencies"

detect_distro
detect_package_manager
[ "$PKG_MANAGER" = "pacman" ] && detect_aur_helper

collect_missing_dependencies

if [ "${#MISSING_PKGS[@]}" -gt 0 ]; then
    if [ -n "$PKG_MANAGER" ] && prompt_install; then
        step "Installing missing dependencies"
        install_missing_dependencies
        verify_dependencies
        ok "All dependencies satisfied — continuing installation."
    else
        if [ -z "$PKG_MANAGER" ]; then
            echo ""
            warn "Could not detect a supported package manager (pacman/apt/dnf/zypper) — unsupported distro."
            warn "Automatic installation is unavailable; please install missing dependencies manually."
        else
            info "Skipping automatic installation."
        fi

        # Same strict behaviour as before: required deps still block install.
        STILL_HARD=()
        for k in "${!MISSING_PKGS[@]}"; do
            [ "${MISSING_PKGS[$k]}" = "hard" ] && STILL_HARD+=("${MISSING_LABELS[$k]}")
        done
        if [ "${#STILL_HARD[@]}" -gt 0 ]; then
            echo ""
            fail "Missing required dependencies: ${STILL_HARD[*]}"
            fail "Install them before running this installer."
            exit 1
        fi
    fi
fi

# ─── Step 1b: Music Dock dependencies (cava / playerctl / PipeWire) ────────
# These three are already covered by the generic soft-dependency pass
# above (same DEP_TABLE / install_dependency machinery -- nothing
# duplicated here), but Music Dock is a distinct, easily-skippable
# feature, so anything still missing after that pass gets its own
# focused prompt with the exact wording the feature spec calls for,
# rather than being silently lumped in with unrelated optional extras.
MUSIC_DOCK_MISSING=()
for k in cava playerctl pipewire; do
    [ -n "${MISSING_PKGS[$k]:-}" ] && MUSIC_DOCK_MISSING+=("$k")
done

if [ "${#MUSIC_DOCK_MISSING[@]}" -gt 0 ]; then
    step "Music Dock"
    echo "Music Dock requires additional packages."
    for k in "${MUSIC_DOCK_MISSING[@]}"; do
        echo "  • ${MISSING_LABELS[$k]}"
    done
    echo ""
    if [ -n "$PKG_MANAGER" ]; then
        echo "Install them now?"
        echo ""
        echo "  [Y] Yes"
        echo "  [N] No — Music Dock will run without the missing piece(s)"
        echo ""
        MD_CHOICE="Y"
        if [ -t 0 ]; then
            read -rp "Choice [Y/n]: " MD_CHOICE || MD_CHOICE=""
            MD_CHOICE="${MD_CHOICE:-Y}"
        else
            info "Non-interactive shell detected — defaulting to Yes"
        fi
        case "$MD_CHOICE" in
            [Yy]*)
                MD_FAILED=false
                for k in "${MUSIC_DOCK_MISSING[@]}"; do
                    install_dependency "$k" "${MISSING_LABELS[$k]}" || MD_FAILED=true
                done
                if $MD_FAILED; then
                    warn "Some Music Dock packages failed to install — the feature will still load, just with the visualizer and/or player detection disabled until you install them manually."
                else
                    ok "Music Dock dependencies installed."
                fi
                ;;
            *)
                info "Skipping Music Dock dependency install — the feature still works, just without cava/MPRIS until these are installed."
                ;;
        esac
    else
        warn "No supported package manager detected — install cava/playerctl/pipewire manually to enable Music Dock's visualizer and player detection."
    fi
    echo ""
fi

# ─── Step 1b-2: Peaclock + Cava Dock dependency (peaclock) ─────────────────
# Same "focused re-prompt after the generic pass" shape as Music Dock's
# Step 1b immediately above, reusing the identical install_dependency()
# call -- not a new/separate installer. Purely optional: the dock's clock
# face is self-contained QML (Components/PeaclockClock.qml) and never
# depends on this package, so declining or failing here never breaks the
# dock -- it only means the "peaclock" binary itself won't be on PATH
# (see PeaclockCavaDockPanel.qml's graceful missing-dependency notice).
PEACLOCK_MISSING=()
[ -n "${MISSING_PKGS[peaclock]:-}" ] && PEACLOCK_MISSING+=("peaclock")

if [ "${#PEACLOCK_MISSING[@]}" -gt 0 ]; then
    step "Peaclock + Cava Dock"
    echo "Peaclock + Cava Dock uses an additional optional package: peaclock."
    echo ""
    if [ -n "$AUR_HELPER" ] || [ "$PKG_MANAGER" != "pacman" ]; then
        echo "Install it now?"
        echo ""
        echo "  [Y] Yes"
        echo "  [N] No — Peaclock + Cava Dock will run without it"
        echo ""
        PC_CHOICE="Y"
        if [ -t 0 ]; then
            read -rp "Choice [Y/n]: " PC_CHOICE || PC_CHOICE=""
            PC_CHOICE="${PC_CHOICE:-Y}"
        else
            info "Non-interactive shell detected — defaulting to Yes"
        fi
        case "$PC_CHOICE" in
            [Yy]*)
                if install_dependency "peaclock" "${MISSING_LABELS[peaclock]}"; then
                    ok "Peaclock + Cava Dock dependency installed."
                else
                    warn "peaclock failed to install — the dock still works, just without this optional package."
                fi
                ;;
            *)
                info "Skipping peaclock install — the dock still works without it."
                ;;
        esac
    else
        warn "peaclock requires an AUR helper (yay or paru) on Arch — install one, or install peaclock manually, to add this optional package."
    fi
    echo ""
fi

# ─── Step 1c: System tray dependencies (dbus-next / Pillow) ────────────────
# Python packages, not commands, so they don't fit the DEP_TABLE/
# install_dependency machinery above -- checked and (optionally)
# installed here instead. Purely soft: TrayService.qml/_tray_icon.py
# already degrade gracefully (tray just stays unavailable) if these
# aren't present, same philosophy as cava/playerctl for Music Dock.
#
# dbus-next (not pystray) -- _tray_icon.py registers a real
# freedesktop StatusNotifierItem directly over session D-Bus. This is
# deliberately NOT pystray: pystray's Linux tray icon only actually
# speaks the modern SNI protocol via its AppIndicator3/
# AyatanaAppIndicator3 backend, which needs a *system* GObject-
# introspection typelib package (not pip-installable) -- without it,
# pystray silently falls back to a backend that Wayland tray hosts
# (waybar's `tray` module, etc.) don't support, so the icon never
# appears. dbus-next is pure Python with no such system dependency.
#
# INSTALL METHOD: a project-local venv at "$LWM_DEST/venv" (created here
# so it survives independently of any system/user pip policy), NOT
# `pip install --user` -- PEP 668 ("externally-managed-environment")
# makes `--user`/global pip installs fail outright on many current
# distros (Debian/Ubuntu, Fedora, Arch), which is exactly the class of
# failure this step used to hit ("Could not install dbus-next/Pillow").
# at $DWT_VENV_DIR below -- this mirrors that pattern) and needs no
# root/sudo. TrayService.qml's Process command is what actually
# consumes this: it launches "$LWM_DEST/venv/bin/python3" when present
# (see Paths.qml's trayVenvPython), falling back to plain `python3`
# only if the venv wasn't created (e.g. venv module unavailable).
TRAY_VENV_DIR="$LWM_DEST/venv"
TRAY_VENV_PY="$TRAY_VENV_DIR/bin/python3"

# Per-distro hint for the one system package this can't install itself
# (Debian/Ubuntu splits `venv` out of the base `python3` package).
_tray_venv_pkg_hint() {
    case "$PKG_MANAGER" in
        apt)    echo "sudo apt-get install -y python3-venv" ;;
        pacman) echo "sudo pacman -S --needed python" ;;
        dnf)    echo "sudo dnf install -y python3" ;;
        zypper) echo "sudo zypper install -y python3" ;;
        *)      echo "install your distro's python3-venv (or equivalent) package" ;;
    esac
}

# Idempotent check: only (re)install if the import actually fails in
# the venv's own interpreter -- never reinstalls an already-working env.
_tray_deps_ok() {
    [ -x "$TRAY_VENV_PY" ] && "$TRAY_VENV_PY" -c "import dbus_next, PIL" >/dev/null 2>&1
}

if ! command -v python3 >/dev/null 2>&1; then
    warn "python3 not found — system tray will be unavailable (needed for the optional system tray helper)"
elif _tray_deps_ok; then
    ok "System tray dependencies already installed ($TRAY_VENV_DIR)"
else
    step "System tray"
    if ! python3 -c "import venv" >/dev/null 2>&1; then
        warn "Python's venv module is unavailable — system tray needs it to install dbus-next/Pillow in isolation."
        warn "Install it, then re-run ./install.sh:  $(_tray_venv_pkg_hint)"
    else
        mkdir -p "$LWM_DEST"
        if [ -x "$TRAY_VENV_PY" ]; then
            info "Reusing existing venv at $TRAY_VENV_DIR"
        else
            info "Creating virtual environment at $TRAY_VENV_DIR ..."
            if ! python3 -m venv "$TRAY_VENV_DIR"; then
                warn "Could not create venv at $TRAY_VENV_DIR — system tray will stay unavailable."
            fi
        fi

        if [ -x "$TRAY_VENV_PY" ]; then
            info "Installing dbus-next + Pillow into the tray venv..."
            "$TRAY_VENV_PY" -m pip install --upgrade pip --quiet >/dev/null 2>&1 || true
            if "$TRAY_VENV_PY" -m pip install --quiet dbus-next Pillow; then
                # Verification step -- only ever report success once this
                # actually succeeds; never claim the tray is available on
                # a "the installer command exited 0" assumption alone.
                if VERIFY_OUT=$("$TRAY_VENV_PY" -c "import dbus_next; import PIL; print('System Tray dependencies OK')" 2>&1); then
                    ok "$VERIFY_OUT ($TRAY_VENV_DIR)"
                else
                    warn "dbus-next/Pillow installed but failed to import — system tray will stay unavailable:"
                    warn "$VERIFY_OUT"
                fi
            else
                warn "Could not install dbus-next/Pillow into $TRAY_VENV_DIR — system tray will stay unavailable."
            fi
        fi
    fi
    echo ""
fi

# ─── Step 2: Install Live Wallpaper Manager ────────────────────────────────
step "Installing Live Wallpaper Manager → $LWM_DEST"

mkdir -p "$LWM_DEST"
info "Copying QML module (Config/, Services/, Components/, Panels/, Manager/, Pages/, shell.qml)..."
cp -rf "$SCRIPT_DIR/livewallpaper/Config"      "$LWM_DEST/"
cp -rf "$SCRIPT_DIR/livewallpaper/Services"    "$LWM_DEST/"
cp -rf "$SCRIPT_DIR/livewallpaper/Components"  "$LWM_DEST/"
cp -rf "$SCRIPT_DIR/livewallpaper/Panels"      "$LWM_DEST/"
# Manager/ + Pages/ (the desktop-app window and its settings pages) --
# added after Components/Panels existed, so they're copied explicitly
# rather than being caught by an earlier glob.
[ -d "$SCRIPT_DIR/livewallpaper/Manager" ] && cp -rf "$SCRIPT_DIR/livewallpaper/Manager" "$LWM_DEST/"
[ -d "$SCRIPT_DIR/livewallpaper/Pages" ]   && cp -rf "$SCRIPT_DIR/livewallpaper/Pages"   "$LWM_DEST/"
cp -f  "$SCRIPT_DIR/livewallpaper/shell.qml"   "$LWM_DEST/"
[ -d "$SCRIPT_DIR/livewallpaper/assets" ] && cp -rf "$SCRIPT_DIR/livewallpaper/assets" "$LWM_DEST/"
[ -d "$SCRIPT_DIR/assets" ]               && cp -rf "$SCRIPT_DIR/assets/."             "$LWM_DEST/assets/"

info "Copying scripts..."
mkdir -p "$LWM_DEST/scripts"
cp -f "$SCRIPT_DIR/livewallpaper/scripts/"*.sh "$LWM_DEST/scripts/"
# Music Dock's FIFO reader (_cava_reader.py) and cava's config template
# (cava.conf) aren't shell scripts, so the *.sh glob above misses them —
# copy explicitly, tolerating either being absent (older archives / a
# stripped-down build without Music Dock still install fine).
[ -f "$SCRIPT_DIR/livewallpaper/scripts/_cava_reader.py" ] && \
    cp -f "$SCRIPT_DIR/livewallpaper/scripts/_cava_reader.py" "$LWM_DEST/scripts/"
[ -f "$SCRIPT_DIR/livewallpaper/scripts/cava.conf" ] && \
    cp -f "$SCRIPT_DIR/livewallpaper/scripts/cava.conf" "$LWM_DEST/scripts/"
# PHASE 4 -- system tray helper (Python, so missed by the *.sh glob above)
[ -f "$SCRIPT_DIR/livewallpaper/scripts/_tray_icon.py" ] && \
    cp -f "$SCRIPT_DIR/livewallpaper/scripts/_tray_icon.py" "$LWM_DEST/scripts/"
chmod +x "$LWM_DEST/scripts/"*.sh
[ -f "$LWM_DEST/scripts/_cava_reader.py" ] && chmod +x "$LWM_DEST/scripts/_cava_reader.py"
[ -f "$LWM_DEST/scripts/_tray_icon.py" ] && chmod +x "$LWM_DEST/scripts/_tray_icon.py"

info "Seeding default data (never overwrites existing favorites/settings/history)..."
mkdir -p "$LWM_DEST/data"
if [ -d "$SCRIPT_DIR/livewallpaper/data" ]; then
    for f in "$SCRIPT_DIR/livewallpaper/data/"*.json; do
        name="$(basename "$f")"
        if [ ! -s "$LWM_DEST/data/$name" ]; then
            cp "$f" "$LWM_DEST/data/$name"
            info "  Created default $name"
        else
            info "  Kept existing $name (user data preserved)"
        fi
    done
fi

info "Creating wallpaper folder (if missing)..."
mkdir -p "$HOME/Pictures/Live Wallpaper"

info "Installing app icon..."
# Installed into every conventional hicolor size (same source image in
# each -- exact pixel size doesn't matter, loaders scale it; what matters
# is that at least one of these directories is one a given launcher/bar
# actually scans) PLUS the legacy ~/.local/share/pixmaps fallback, which
# spec-compliant icon loaders check directly by filename with no
# icon-theme/index.theme involved at all. Icon= in the .desktop files
# below is then pointed at this exact absolute path rather than an icon
# *name*, sidestepping icon-theme lookup entirely -- the most reliable
# option across the range of launchers/bars/notification daemons used on
# Hyprland setups.
APP_ICON_INSTALLED=""
if [ -f "$SCRIPT_DIR/livewallpaper/assets/icons/app-icon.png" ]; then
    for sz in 16x16 22x22 24x24 32x32 48x48 64x64 96x96 128x128 192x192 256x256 512x512; do
        ICON_DIR="$HOME/.local/share/icons/hicolor/$sz/apps"
        mkdir -p "$ICON_DIR"
        cp -f "$SCRIPT_DIR/livewallpaper/assets/icons/app-icon.png" \
            "$ICON_DIR/live-wallpaper-manager-app.png"
    done
    mkdir -p "$HOME/.local/share/pixmaps"
    cp -f "$SCRIPT_DIR/livewallpaper/assets/icons/app-icon.png" \
        "$HOME/.local/share/pixmaps/live-wallpaper-manager-app.png"
    # Stale scalable/apps SVG from an older install -- remove so nothing
    # shadows the PNG above on lookups that do prefer scalable/.
    rm -f "$HOME/.local/share/icons/hicolor/scalable/apps/live-wallpaper-manager-app.svg"
    command -v gtk-update-icon-cache >/dev/null 2>&1 && \
        gtk-update-icon-cache -f -q "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
    APP_ICON_INSTALLED="$HOME/.local/share/icons/hicolor/512x512/apps/live-wallpaper-manager-app.png"
    ok "App icon installed"
else
    warn "App icon source not found -- desktop entries will fall back to a generic icon"
fi

info "Installing desktop entries..."
mkdir -p "$HOME/.local/share/applications"
# Icon= is a literal placeholder in the source .desktop files -- filled
# in here with the real installed path (falling back to a generic system
# icon name if the icon above didn't install for some reason) so it
# never ships as a broken/empty reference.
ICON_FOR_DESKTOP="${APP_ICON_INSTALLED:-video-x-generic}"
if [ -f "$SCRIPT_DIR/livewallpaper/live-wallpaper-manager.desktop" ]; then
    sed -e "s|__QS_CONFIG_DIR__|$LWM_DEST|g" \
        -e "s|__APP_ICON_PATH__|$ICON_FOR_DESKTOP|g" \
        "$SCRIPT_DIR/livewallpaper/live-wallpaper-manager.desktop" \
        > "$HOME/.local/share/applications/live-wallpaper-manager.desktop"
fi
# Manager app launcher (added in an earlier phase but never previously
# wired into the installer -- fixed here).
if [ -f "$SCRIPT_DIR/livewallpaper/live-wallpaper-manager-app.desktop" ]; then
    sed -e "s|__APP_ICON_PATH__|$ICON_FOR_DESKTOP|g" \
        "$SCRIPT_DIR/livewallpaper/live-wallpaper-manager-app.desktop" \
        > "$HOME/.local/share/applications/live-wallpaper-manager-app.desktop"
fi
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
ok "Desktop entries installed (panel + Manager app)"

# ─── Step 2b: Autostart (PHASE 4) ──────────────────────────────────────────
step "Autostart"
echo "Start Live Wallpaper Manager automatically when you log in?"
echo ""
echo "  [Y] Yes -- registers a standard login-session autostart entry"
echo "  [N] No  -- you can enable this later from Settings in the app,"
echo "             or add a Hyprland-native autostart yourself (see below)"
echo ""
AUTOSTART_CHOICE="N"
if [ -t 0 ]; then
    read -rp "Choice [y/N]: " AUTOSTART_CHOICE || AUTOSTART_CHOICE=""
    AUTOSTART_CHOICE="${AUTOSTART_CHOICE:-N}"
else
    info "Non-interactive shell detected — skipping (enable later from Settings)"
fi
case "$AUTOSTART_CHOICE" in
    [Yy]*)
        bash "$LWM_DEST/scripts/manage_autostart.sh" enable >/dev/null 2>&1 && \
            ok "Autostart enabled (~/.config/autostart/live-wallpaper-manager.desktop)" || \
            warn "Could not write the autostart entry (non-fatal — try again from Settings)"
        ;;
    *)
        info "Autostart skipped — enable anytime from Settings → Application"
        ;;
esac
if command -v hyprctl >/dev/null 2>&1; then
    info "On Hyprland, the entry above is NOT read automatically by Hyprland itself."
    info "For a Hyprland-native autostart, use the hyprland.start wrapper in"
    info "hyprland.lua instead of a bare one-liner (-n prevents duplicate instances"
    info "if the XDG entry above also fires):"
    info "  hl.on(\"hyprland.start\", function()"
    info "      hl.exec_cmd(\"quickshell -c livewallpaper -n\")"
    info "  end)"
    info "(Legacy hyprland.conf syntax: exec-once = quickshell -c livewallpaper -n)"
fi

ok "Live Wallpaper Manager installed at $LWM_DEST"

# ─── Step 3: Initial scan (only if wallpapers.json is empty/missing) ───────
step "Checking wallpaper catalog"

if [ ! -s "$HOME/.config/quickshell/livewallpaper/data/wallpapers.json" ] || \
   [ "$(cat "$HOME/.config/quickshell/livewallpaper/data/wallpapers.json" 2>/dev/null)" = "[]" ]; then
    info "No catalog yet — triggering initial scan of $HOME/Pictures/Live Wallpaper ..."
    # Only scan if there's actually something to scan
    VIDEO_COUNT=$(find "$HOME/Pictures/Live Wallpaper" -maxdepth 1 \
        \( -iname "*.mp4" -o -iname "*.webm" -o -iname "*.mkv" -o -iname "*.mov" \) 2>/dev/null | wc -l)
    if [ "$VIDEO_COUNT" -gt 0 ]; then
        bash "$LWM_DEST/scripts/refresh.sh" >/dev/null 2>&1 && \
            ok "Initial scan complete ($VIDEO_COUNT video(s) found)" || \
            warn "Initial scan encountered an error (non-fatal — use Refresh in the UI)"
    else
        info "No wallpaper videos found yet in ~/Pictures/Live Wallpaper — drop some .mp4/.webm/.mkv files there and press Refresh"
    fi
else
    info "Existing wallpaper catalog found — skipping initial scan"
fi

# ─── Step 5: PATH check ────────────────────────────────────────────────────
step "Checking PATH"

PATH_OK=false
if [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
    PATH_OK=true
else
    warn "~/.local/bin is NOT in your PATH"
    warn "Add this to your ~/.bashrc / ~/.zshrc / ~/.profile:"
    warn '  export PATH="$HOME/.local/bin:$PATH"'
    warn "Then run:  source ~/.bashrc"
fi

# ─── Step 6: Verification ──────────────────────────────────────────────────
step "Verifying installation"

VERIFY_PASS=0
VERIFY_FAIL=0

echo ""
printf "${BOLD}${CYAN}%s${RESET}\n" "Installation Summary"
divider
echo ""
ok "Live Wallpaper Manager → $LWM_DEST"
echo ""
info "Checks passed: $VERIFY_PASS | Warnings: $VERIFY_FAIL"
echo ""
printf "${BOLD}Next steps:${RESET}\n"
echo ""
echo "  1. Add your wallpaper videos to:  ~/Pictures/Live Wallpaper"
echo ""
echo "  2. Start the Quickshell module:"
echo "     Standalone:  quickshell -c livewallpaper"
echo "     Caelestia:   see livewallpaper/CAELESTIA_INTEGRATION.md"
echo "     (or just launch \"Live Wallpaper Manager\" from your app launcher)"
echo ""
echo "  3. (Optional) Add a Hyprland-native autostart on login, in"
echo "     hyprland.lua (don't use a bare one-liner):"
echo "     hl.on(\"hyprland.start\", function()"
echo "         hl.exec_cmd(\"quickshell -c livewallpaper -n\")"
echo "     end)"
echo "     (legacy hyprland.conf: exec-once = quickshell -c livewallpaper -n)"
echo "     (the installer already offered to register a login-session"
echo "      autostart entry above, but Hyprland doesn't read that on its"
echo "      own -- see the Autostart step)"
echo ""
echo "  4. Toggle the compact panel (play/pause/next/previous/random,"
echo "     current wallpaper + song):"
echo "     quickshell -c livewallpaper ipc call livewallpaper toggle"
echo ""
echo "  5. Open the full Manager app (library, playlist, music, visualizer,"
echo "     monitor, performance, and general settings):"
echo "     quickshell -c livewallpaper ipc call livewallpapermanager open"
echo "     (or click \"Open Manager\" in the panel's title bar, or launch"
echo "      \"Live Wallpaper Manager (App)\" from your app launcher)"
echo ""
echo "  6. Keyboard shortcuts (Manager app window): Ctrl+1-8 jump to a"
echo "     page, Ctrl+Tab/Ctrl+Shift+Tab cycle pages, Ctrl+F search,"
echo "     Ctrl+W close. Panel: Space play/pause, ←/→ previous/next,"
echo "     R random, Esc close."
echo ""
echo "  7. System tray + Music Dock (floating now-playing overlay + audio"
echo "     visualizer) are both configurable from the Manager app:"
echo "     Settings → Application (tray/notifications/autostart) and"
echo "     Music page (Music Dock) respectively."
echo ""
if ! $PATH_OK; then
    warn "Remember to add ~/.local/bin to PATH (see warning above)"
    echo ""
fi
ok "Done."
