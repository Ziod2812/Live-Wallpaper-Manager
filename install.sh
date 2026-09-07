#!/usr/bin/env bash
#
# install.sh — Live Wallpaper Manager Installer (v2.1.6 — NixOS support)
# NOTE (v2.1.6): added NixOS as a fourth first-class distro alongside
# Arch/Fedora/Debian. Missing dependencies (quickshell, mpvpaper, Node.js,
# AWWW build deps) are installed into the invoking user's own Nix profile
# via `nix profile install nixpkgs#<pkg>` (falling back to classic
# `nix-env -f '<nixpkgs>' -iA <pkg>` on a Nix without flakes enabled) --
# no sudo, no configuration.nix/home.nix edits. See detect_package_manager(),
# the PKG_NIX table, lw_nix_install(), and the "NixOS/nix-specific
# installers" block for details. AWWW and peaclock are now also packaged
# in nixpkgs (awww 0.12.1 / peaclock 0.4.3 as of nixos-unstable), so they
# install via `nix profile install` like the rest; the Rust source build
# remains as the fallback on nixpkgs channels that predate them.
# NOTE (v2.1.5.54): app-launcher icon clicks can be spawned by the desktop
# environment without WAYLAND_DISPLAY in their environment at all (this
# depends on the DE/session manager, not the distro) -- a plain terminal
# has it and works fine, but the icon-launched process doesn't, so
# quickshell can't connect to any compositor and exits with zero visible
# output. scripts/utils.sh now has lw_ensure_wayland_env(), which recovers
# WAYLAND_DISPLAY by finding the actual wayland-N socket under
# XDG_RUNTIME_DIR on disk instead of trusting the environment to have
# propagated it, and forces QT_QPA_PLATFORM=wayland once a real session is
# confirmed either way. launch_quickshell.sh, launch_debian_wayland_safe.sh
# and open_app.sh (v2.1.5.53) all use it now.
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
    # Distro brand colours (24-bit truecolor) used only for the
    # Arch/Fedora/Debian/Ubuntu labels in the Step 0 menu below --
    # everything else keeps the standard palette above.
    ARCH_COLOR='\033[38;2;23;147;209m'    # #1793D1
    FEDORA_COLOR='\033[38;2;60;110;180m'  # #3C6EB4
    DEBIAN_COLOR='\033[38;2;206;0;86m'    # #CE0056 (Debian swirl red)
    UBUNTU_COLOR='\033[38;2;233;84;32m'   # #E95420 (Ubuntu orange)
    NIXOS_COLOR='\033[38;2;82;115;196m'   # #5277C3 (Nix snowflake blue)
    APT_LABEL_COLOR='\033[38;2;200;42;40m' # #C82A28 (apt-based parenthetical)
else
    RED=''; YELLOW=''; GREEN=''; CYAN=''; DIM=''; BOLD=''; RESET=''
    ARCH_COLOR=''; FEDORA_COLOR=''; DEBIAN_COLOR=''; UBUNTU_COLOR=''; NIXOS_COLOR=''
    APT_LABEL_COLOR=''
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
step() {
    echo ""
    printf "${BOLD}${CYAN}%s${RESET}\n" "$*"
    if [ "$USE_UNICODE" = 1 ]; then
        printf "${DIM}%s${RESET}\n" "────────────────────────────────"
    else
        printf -- "${DIM}%s${RESET}\n" "--------------------------------"
    fi
}
divider() { if [ "$USE_UNICODE" = 1 ]; then printf "${DIM}%s${RESET}\n" "────────────────────────────────────"; else printf -- "${DIM}%s${RESET}\n" "----------------------------------------"; fi; }

# ─── Node.js minimum version ────────────────────────────────────────────────
# yt-dlp's EJS JavaScript-challenge solver (used to defeat YouTube's
# signature/n-parameter obfuscation so resolved stream URLs don't come back
# HTTP 403) refuses any Node build older than this, printing
# "JS runtimes: node-X.Y.Z (unsupported)" and silently falling back to
# storyboard-only formats -- which then fails streaming with an opaque
# "Requested format is not available" error that looks like a mpvpaper/
# Wayland problem, not a Node one. Debian/Ubuntu stable's apt package (and,
# less reliably, Fedora/RHEL's dnf package) routinely ships older than this.
NODE_MIN_MAJOR=22

# Prints node's major version number (e.g. "22"), or nothing if node isn't
# on PATH / --version couldn't be parsed.
lw_node_major_version() {
    local v
    v="$(node --version 2>/dev/null)" || { printf ''; return 1; }
    v="${v#v}"
    printf '%s' "${v%%.*}"
}
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
# NOTE: check_command must be the literal binary name (looked up with
# `command -v`), not a description -- the "node" row previously had
# "node (JS runtime for YouTube playback)" here, which made the presence
# check silently and permanently fail (`command -v` was looking for a
# binary literally named that whole phrase), so node was always reported
# missing even when a working install was on PATH.
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
node|node|soft|nodejs
cava|cava|soft|cava
playerctl|playerctl|soft|playerctl
pipewire|pipewire|soft|pipewire
grim|grim|soft|grim
awww|awww|soft|awww
awww-daemon|awww-daemon|soft|awww
peaclock|peaclock|soft|peaclock
zenity|zenity|soft|zenity
kdialog|kdialog|soft|kdialog
yad|yad|soft|yad
qarma|qarma|soft|qarma"

# Package name per distro family. Empty string = no known native package on
# that distro (installer will say so and ask for manual install). "AUR:name"
# = Arch-only, installed via an AUR helper (yay/paru) rather than pacman.
declare -A PKG_PACMAN=(
    # quickshell is packaged in Arch's official `extra` repo since 0.3.1
    # (verified on archlinux.org) -- no longer an AUR-only install; the
    # literal AUR package named `quickshell` doesn't exist either, only
    # `quickshell-git` does, so the old "AUR:quickshell" entry pointed at
    # a package that was never there.
    [quickshell]="quickshell"       [mpvpaper]="AUR:mpvpaper"
    [ffmpeg]="ffmpeg"                [jq]="jq"
    [hyprland]="hyprland"           [python3]="python"
    [curl]="curl"                   [inotify-tools]="inotify-tools"
    [yt-dlp]="yt-dlp"               [nodejs]="nodejs"
    [zenity]="zenity"               [yad]="yad"
    [kdialog]="kdialog"             [qarma]="AUR:qarma-git"
    [python3-tkinter]="tk"
    [cava]="cava"                   [playerctl]="playerctl"
    [pipewire]="pipewire"
    [grim]="grim"
    [awww]="awww" [peaclock]="AUR:peaclock"
)
declare -A PKG_APT=(
    [quickshell]=""                 [mpvpaper]=""
    [ffmpeg]="ffmpeg"                [jq]="jq"
    [hyprland]="hyprland"           [python3]="python3"
    [curl]="curl"                   [inotify-tools]="inotify-tools"
    [yt-dlp]="yt-dlp"               [nodejs]="nodejs"
    [zenity]="zenity"               [yad]="yad"
    [kdialog]="kdialog"             [qarma]=""
    [python3-tkinter]="python3-tk"
    [cava]="cava"                   [playerctl]="playerctl"
    [pipewire]="pipewire"
    [grim]="grim"
    [awww]=""
    [peaclock]=""
)
declare -A PKG_DNF=(
    [quickshell]=""                 [mpvpaper]=""
    [ffmpeg]="ffmpeg"                [jq]="jq"
    [hyprland]="hyprland"           [python3]="python3"
    [curl]="curl"                   [inotify-tools]="inotify-tools"
    [yt-dlp]="yt-dlp"               [nodejs]="nodejs"
    [zenity]="zenity"               [yad]="yad"
    [kdialog]="kdialog"             [qarma]=""
    [python3-tkinter]="python3-tkinter"
    [cava]="cava"                   [playerctl]="playerctl"
    [pipewire]="pipewire"
    [grim]="grim"
    [awww]=""
    [peaclock]=""
)
declare -A PKG_ZYPPER=(
    [quickshell]=""                 [mpvpaper]=""
    [ffmpeg]="ffmpeg"                [jq]="jq"
    [hyprland]="hyprland"           [python3]="python3"
    [curl]="curl"                   [inotify-tools]="inotify-tools"
    [yt-dlp]="yt-dlp"               [nodejs]="nodejs"
    [zenity]="zenity"               [yad]="yad"
    [kdialog]="kdialog"             [qarma]=""
    [python3-tkinter]="python3-tk"
    [cava]="cava"                   [playerctl]="playerctl"
    [pipewire]="pipewire"
    [grim]="grim"
    [awww]=""
    [peaclock]=""
)
# NixOS: attribute names inside nixpkgs, installed via `nix profile install
# nixpkgs#<attr>` (see lw_nix_install() below) rather than a system package
# manager -- no sudo, no configuration.nix edits. quickshell and mpvpaper
# are both packaged directly in nixpkgs, unlike on Fedora/Debian/openSUSE.
# Empty string = not (yet) packaged in nixpkgs under a simple top-level
# attribute; same "install manually" fallback as the other tables.
declare -A PKG_NIX=(
    [quickshell]="quickshell"       [mpvpaper]="mpvpaper"
    [ffmpeg]="ffmpeg"                [jq]="jq"
    [hyprland]="hyprland"           [python3]="python3"
    [curl]="curl"                   [inotify-tools]="inotify-tools"
    [yt-dlp]="yt-dlp"               [nodejs]="nodejs"
    [zenity]="zenity"               [yad]="yad"
    [kdialog]="kdialog"             [qarma]=""
    [python3-tkinter]=""
    [cava]="cava"                   [playerctl]="playerctl"
    [pipewire]="pipewire"
    [grim]="grim"
    # awww + peaclock are packaged in nixpkgs now (unstable carries awww
    # 0.12.1 / peaclock 0.4.3 as of this writing). awww's entry is mostly
    # documentary -- install_awww() routes nix installs through
    # `nix profile install nixpkgs#awww` itself -- while peaclock's is what
    # actually flips the generic install path from "install manually" to
    # `nix profile install nixpkgs#peaclock`.
    [awww]="awww" [peaclock]="peaclock"
)

PKG_MANAGER=""       # pacman | apt | dnf | zypper | nix | ""
DISTRO_ID=""
DISTRO_ID_LIKE=""
USE_HYPRLAND=""       # "true" | "false" -- set in Step 0.5, see hyprland_dep_req()
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

    # Last resort: whichever package-manager binary actually exists.
    # /etc/NIXOS is the canonical marker NixOS itself creates (present even
    # if /etc/os-release is ever missing/customized), checked ahead of the
    # command -v probes below since nix-env/nixos-rebuild can also exist on
    # a non-NixOS machine that merely has the Nix package manager installed.
    if [ -z "$PKG_MANAGER" ]; then
        if [ -e /etc/NIXOS ]; then PKG_MANAGER="nix"
        elif command -v pacman   >/dev/null 2>&1; then PKG_MANAGER="pacman"
        elif command -v apt-get >/dev/null 2>&1; then PKG_MANAGER="apt"
        elif command -v dnf     >/dev/null 2>&1; then PKG_MANAGER="dnf"
        elif command -v zypper  >/dev/null 2>&1; then PKG_MANAGER="zypper"
        elif command -v nixos-rebuild >/dev/null 2>&1; then PKG_MANAGER="nix"
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
        nix)    printf '%s' "${PKG_NIX[$key]:-}"    ;;
        *)      printf '%s' ""                      ;;
    esac
}

# Resolves how strict the hyprctl/hyprland check should be, based on the
# Hyprland question asked in Step 0.5 (USE_HYPRLAND) and the selected
# package manager:
#   - Not using Hyprland at all        -> "skip"  (don't check, don't install)
#   - Using Hyprland on Arch (pacman)  -> "hard"  (native package, block if missing)
#   - Using Hyprland elsewhere         -> "soft"  (install if available, never block --
#                                                   Fedora/other distros don't reliably
#                                                   ship a hyprland package)
hyprland_dep_req() {
    if [ "$USE_HYPRLAND" != "true" ]; then
        printf 'skip'
    elif [ "$PKG_MANAGER" = "pacman" ]; then
        printf 'hard'
    else
        printf 'soft'
    fi
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

        # qarma is a Qt clone of zenity, and on Arch its AUR package
        # declares provides=zenity/conflicts=zenity -- installing it
        # while zenity is already present forces pacman into "Remove
        # zenity to continue? [y/N]", which `yay -S --noconfirm` answers
        # N to and fails on. Since Browse only ever needs ONE working
        # backend, skip even checking for qarma once zenity, kdialog, or
        # yad is already installed -- there's nothing to gain and a real
        # risk of that conflict.
        # hyprctl/hyprland: requirement level depends on the Hyprland
        # question asked right after the distro step, not a fixed "hard"
        # entry -- users who don't run Hyprland shouldn't be forced to
        # compile/install it just to run LWM (Smart Playback's fullscreen
        # detection is the only thing that actually needs hyprctl, and it
        # already degrades gracefully without it).
        if [ "$pkgkey" = "hyprland" ]; then
            req="$(hyprland_dep_req)"
            if [ "$req" = "skip" ]; then
                ok "$label (skipped — not using Hyprland)"
                continue
            fi
        fi

        if [ "$pkgkey" = "qarma" ] && \
           { command -v zenity >/dev/null 2>&1 || command -v kdialog >/dev/null 2>&1 || command -v yad >/dev/null 2>&1; }; then
            ok "qarma (skipped — zenity/kdialog/yad already cover the folder picker)"
            continue
        fi

        # node: presence alone isn't enough -- a Node older than
        # NODE_MIN_MAJOR is on PATH but unusable by yt-dlp's EJS solver
        # (see NODE_MIN_MAJOR comment above), and yt-dlp fails silently
        # rather than with a clear "wrong Node version" error. Treat a
        # too-old Node the same as a missing one so install_dependency()
        # gets a chance to fetch a current build via NodeSource.
        if [ "$pkgkey" = "nodejs" ] && command -v "$cmd" >/dev/null 2>&1; then
            local node_major
            node_major="$(lw_node_major_version)"
            if [ -n "$node_major" ] && [ "$node_major" -ge "$NODE_MIN_MAJOR" ]; then
                ok "$label"
            else
                warn "$label — found (v${node_major:-?}) but too old; yt-dlp's YouTube JS-challenge solver needs Node >= $NODE_MIN_MAJOR"
                if [ "${MISSING_PKGS[$pkgkey]:-}" != "hard" ]; then
                    MISSING_PKGS[$pkgkey]="soft"
                fi
                if [ -n "${MISSING_LABELS[$pkgkey]:-}" ]; then
                    MISSING_LABELS[$pkgkey]="${MISSING_LABELS[$pkgkey]}, $label (too old)"
                else
                    MISSING_LABELS[$pkgkey]="$label (too old)"
                fi
            fi
            continue
        fi

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

    # python3/tkinter: folder_picker.sh's last-resort backend, tried only
    # once zenity/kdialog/yad/qarma are ALL missing. Checked as an
    # importable module, not a command -- there's no "tkinter" binary to
    # look up with command -v. Soft/optional, same as the four above:
    # Browse only needs ONE working backend to function.
    if python3 -c "import tkinter" >/dev/null 2>&1; then
        ok "python3-tkinter (folder picker fallback)"
    else
        warn "python3-tkinter — optional, not found (folder picker's last-resort fallback)"
        MISSING_PKGS[python3-tkinter]="soft"
        MISSING_LABELS[python3-tkinter]="python3-tkinter"
    fi

    # Browser is an either/or choice (chromium OR firefox) and isn't a single
    # installable package, so it stays informational-only, same as before.
    if command -v chromium >/dev/null 2>&1 || command -v chromium-browser >/dev/null 2>&1 || command -v firefox >/dev/null 2>&1; then
        ok "browser (for Web mode Local HTML)"
    else
        warn "no chromium/firefox found — Web mode's Local HTML source will fail until one is installed (Web-URL source is unaffected, it uses mpvpaper)"
    fi

    # The "Browse..." folder picker only needs ONE of these five backends
    # to work (see scripts/folder_picker.sh: zenity -> kdialog -> yad ->
    # qarma -> python3/tkinter) -- flag it clearly only when ALL FIVE are
    # missing, rather than nagging about each one individually when e.g.
    # zenity alone is already enough.
    if [ -n "${MISSING_PKGS[zenity]:-}" ] && [ -n "${MISSING_PKGS[kdialog]:-}" ] && \
       [ -n "${MISSING_PKGS[yad]:-}" ] && [ -n "${MISSING_PKGS[qarma]:-}" ] && \
       [ -n "${MISSING_PKGS[python3-tkinter]:-}" ]; then
        warn "No folder-picker dialog backend found at all -- the Browse... button will fall back to opening a plain file manager window (no auto-fill) until at least one of zenity, kdialog, yad, or qarma is installed."
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

# ─── Fedora-specific hard-dependency installers ────────────────────────────
# Neither quickshell nor mpvpaper have an official Fedora repo package on
# EVERY supported release: quickshell is packaged for Fedora 44+ and
# Rawhide as of this writing (see packages.fedoraproject.org), but Fedora 43
# and earlier have nothing, so both still need distro-specific handling:
#   - quickshell: try the official package name first (works on Fedora 44+ /
#     Rawhide), then fall back to the community-maintained
#     errornointernet/quickshell COPR -- still the path upstream's own docs
#     (v0.3.1 install-setup page) list for every release.
#   - mpvpaper: no COPR is reliable/maintained enough to depend on long
#     term, so it's built from source instead (this is also exactly what
#     the upstream README recommends — meson + ninja, no distro packaging
#     involved).

install_quickshell_fedora() {
    info "Installing quickshell (Fedora)..."

    # 1) Try the official Fedora package first (Rawhide today, may reach
    #    stable releases later).
    if sudo dnf install -y quickshell >/dev/null 2>&1; then
        ok "quickshell installed (official Fedora package)"
        return 0
    fi

    # 2) Fall back to the errornointernet/quickshell COPR.
    #    The package that provides the `copr` subcommand depends on which
    #    dnf generation is running: dnf5 (default on Fedora 41+, i.e. the
    #    common case today) gets it from `dnf5-plugins`, while classic
    #    dnf4 gets it from `dnf-plugins-core` -- installing the wrong one
    #    silently leaves `dnf copr` as an unrecognized command. Try both
    #    (whichever doesn't apply to this system is a harmless no-op/
    #    already-satisfied dependency) so this works on either generation
    #    without needing to detect dnf5 vs dnf4 explicitly.
    info "quickshell not in the official repos — enabling errornointernet/quickshell COPR..."
    sudo dnf install -y dnf5-plugins >/dev/null 2>&1 || true
    sudo dnf install -y dnf-plugins-core >/dev/null 2>&1 || true
    if ! sudo dnf copr enable -y errornointernet/quickshell >/dev/null 2>&1; then
        fail "Failed to enable the errornointernet/quickshell COPR (network unavailable or COPR unreachable)"
        fail "Manual install: sudo dnf copr enable errornointernet/quickshell && sudo dnf install quickshell"
        return 1
    fi
    if ! sudo dnf install -y quickshell; then
        fail "Failed to install quickshell from COPR (Qt version mismatch is a known issue on some Fedora releases — see https://github.com/errornointernet/quickshell)"
        fail "Manual install: sudo dnf install quickshell   (after: sudo dnf copr enable errornointernet/quickshell)"
        return 1
    fi
    ok "quickshell installed (errornointernet/quickshell COPR)"
    return 0
}

install_mpvpaper_fedora() {
    info "Building mpvpaper from source (no maintained Fedora package exists)..."

    # mesa-libEGL-devel (not mesa-libGL-devel) is what actually ships
    # egl.pc on Fedora -- mpvpaper's meson.build calls
    # dependency('egl'), and mesa-libGL-devel only provides gl.pc
    # (OpenGL), so without libEGL-devel `meson setup` fails with
    # "Dependency egl not found".
    local build_deps=(meson ninja-build gcc mpv-libs-devel wayland-devel wayland-protocols-devel mesa-libEGL-devel pkgconf-pkg-config git)
    info "Installing build dependencies: ${build_deps[*]}"
    if ! sudo dnf install -y "${build_deps[@]}"; then
        fail "Failed to install mpvpaper's build dependencies (network unavailable or a package name changed upstream)"
        return 1
    fi

    local build_dir
    build_dir="$(mktemp -d)"
    if ! git clone --single-branch --depth 1 https://github.com/GhostNaN/mpvpaper "$build_dir/mpvpaper" >/dev/null 2>&1; then
        fail "Failed to clone GhostNaN/mpvpaper (network unavailable or GitHub unreachable)"
        rm -rf "$build_dir"
        return 1
    fi

    if ! (
        cd "$build_dir/mpvpaper" && \
        meson setup build --prefix=/usr/local >/dev/null 2>&1 && \
        ninja -C build >/dev/null 2>&1
    ); then
        fail "mpvpaper failed to build (see https://github.com/GhostNaN/mpvpaper for build requirements)"
        rm -rf "$build_dir"
        return 1
    fi

    if ! sudo ninja -C "$build_dir/mpvpaper/build" install >/dev/null 2>&1; then
        fail "mpvpaper built successfully but failed to install to /usr/local (sudo cancelled?)"
        rm -rf "$build_dir"
        return 1
    fi

    rm -rf "$build_dir"
    ok "mpvpaper installed (built from source to /usr/local)"
    return 0
}

# ─── Debian/apt-specific hard-dependency installers ────────────────────────
# Neither quickshell nor mpvpaper has a Debian/Ubuntu package that can be
# resolved with a plain `apt-get install <pkg>` lookup on EVERY supported
# release, so both get dedicated handling below (same reasoning as the
# Fedora block above):
#   - quickshell: try the package directly (works on Debian testing/sid),
#     then fall back to enabling <codename>-backports on Debian stable,
#     then the community avengemedia/danklinux PPA that upstream's own
#     docs recommend for Ubuntu 24.04+.
#   - mpvpaper: no reliable apt package exists anywhere, so it's built
#     from source instead (meson + ninja, exactly what upstream recommends).

install_quickshell_apt() {
    info "Installing quickshell (apt)..."

    # 1) Try installing it directly first -- works out of the box on
    #    Debian testing/sid, or on Debian stable if the user already has
    #    a *-backports source enabled.
    if sudo apt-get install -y quickshell >/dev/null 2>&1; then
        ok "quickshell installed (apt)"
        return 0
    fi

    # 2) Debian stable ships quickshell via backports only. Enable
    #    <codename>-backports (an official, Debian-signed repo -- same
    #    "auto-enable a trusted extra repo" pattern as the Fedora COPR
    #    fallback above) and retry once.
    local codename=""
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
    fi
    if [ -n "$codename" ] && [ "$DISTRO_ID" = "debian" ]; then
        info "quickshell not found in your current apt sources -- trying ${codename}-backports..."
        if [ ! -f "/etc/apt/sources.list.d/${codename}-backports.list" ]; then
            echo "deb http://deb.debian.org/debian ${codename}-backports main" | \
                sudo tee "/etc/apt/sources.list.d/${codename}-backports.list" >/dev/null
        fi
        sudo apt-get update >/dev/null 2>&1 || true
        if sudo apt-get install -y -t "${codename}-backports" quickshell >/dev/null 2>&1; then
            ok "quickshell installed (${codename}-backports)"
            return 0
        fi
    fi

    # 3) Ubuntu family: quickshell is not in Ubuntu's own repos, but the
    #    official quickshell docs (v0.3.1 install-setup page) recommend the
    #    community-maintained avengemedia/danklinux PPA, which actively
    #    ships quickshell 0.3.1 for noble 24.04+ (verified on
    #    launchpad.net/~avengemedia/+archive/ubuntu/danklinux). Same
    #    "auto-enable an extra repo" pattern as the Fedora COPR and the
    #    Debian backports above. Non-fatal: no add-apt-repository, an
    #    unsupported release (e.g. jammy-based Mint 21), or a network
    #    failure all fall straight through to the manual instructions below.
    case "$DISTRO_ID" in
        ubuntu|pop|linuxmint|elementary|zorin)
            if command -v add-apt-repository >/dev/null 2>&1; then
                info "quickshell not in this release's repos -- trying the docs-recommended ppa:avengemedia/danklinux..."
                if sudo add-apt-repository -y ppa:avengemedia/danklinux >/dev/null 2>&1 && \
                   sudo apt-get update >/dev/null 2>&1 && \
                   sudo apt-get install -y quickshell >/dev/null 2>&1; then
                    ok "quickshell installed (avengemedia/danklinux PPA)"
                    return 0
                fi
                warn "The avengemedia/danklinux PPA install failed (unsupported release or network issue) -- falling back to the manual instructions below."
            fi
            ;;
    esac

    fail "quickshell isn't available via apt on this system."
    fail "Ubuntu 24.04+ users: the official quickshell docs recommend the PPA"
    fail "  sudo add-apt-repository ppa:avengemedia/danklinux && sudo apt install quickshell"
    fail "Build it from source (needs Qt 6.6+): https://quickshell.org/docs/v0.3.1/guide/install-setup/"
    fail "  sudo apt install cmake ninja-build pkg-config qt6-base-dev qt6-declarative-dev \\"
    fail "    qt6-shadertools-dev qt6-wayland qt6-svg-dev libdrm-dev wayland-protocols \\"
    fail "    libpipewire-0.3-dev libdbus-1-dev libxkbcommon-dev libcli11-dev \\"
    fail "    libjemalloc-dev libpam0g-dev spirv-tools"
    fail "  git clone https://git.outfoxxed.me/quickshell/quickshell && cd quickshell"
    fail "  cmake -GNinja -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCRASH_HANDLER=OFF"
    fail "  cmake --build build && sudo cmake --install build"
    return 1
}

install_mpvpaper_apt() {
    info "Building mpvpaper from source (no Debian/Ubuntu package exists)..."

    local build_deps=(meson ninja-build build-essential libmpv-dev libwayland-dev wayland-protocols libegl-dev pkg-config git)
    info "Installing build dependencies: ${build_deps[*]}"
    if ! sudo apt-get install -y "${build_deps[@]}"; then
        fail "Failed to install mpvpaper's build dependencies (network unavailable or a package name changed upstream)"
        return 1
    fi

    local build_dir
    build_dir="$(mktemp -d)"
    if ! git clone --single-branch --depth 1 https://github.com/GhostNaN/mpvpaper "$build_dir/mpvpaper" >/dev/null 2>&1; then
        fail "Failed to clone GhostNaN/mpvpaper (network unavailable or GitHub unreachable)"
        rm -rf "$build_dir"
        return 1
    fi

    if ! (
        cd "$build_dir/mpvpaper" && \
        meson setup build --prefix=/usr/local >/dev/null 2>&1 && \
        ninja -C build >/dev/null 2>&1
    ); then
        fail "mpvpaper failed to build (see https://github.com/GhostNaN/mpvpaper for build requirements)"
        rm -rf "$build_dir"
        return 1
    fi

    if ! sudo ninja -C "$build_dir/mpvpaper/build" install >/dev/null 2>&1; then
        fail "mpvpaper built successfully but failed to install to /usr/local (sudo cancelled?)"
        rm -rf "$build_dir"
        return 1
    fi

    rm -rf "$build_dir"
    ok "mpvpaper installed (built from source to /usr/local)"
    return 0
}

# ─── NixOS/nix-specific installers ──────────────────────────────────────────
# NixOS doesn't have a `sudo <pkgmgr> install <pkg>` in the apt/dnf/pacman
# sense -- packages normally get added to /etc/nixos/configuration.nix (or a
# home-manager config) and applied with `nixos-rebuild switch`, which this
# installer has no business editing unattended. Instead, every dependency
# below is installed IMPERATIVELY into the invoking user's own Nix profile
# via `nix profile install nixpkgs#<pkg>` (falling back to the older
# `nix-env -f '<nixpkgs>' -iA <pkg>` on a Nix without the new CLI/flakes
# enabled) -- this needs no sudo at all (the Nix daemon owns /nix/store, not
# the user's profile) and never touches configuration.nix, so a later
# `nixos-rebuild switch` won't undo anything this installer did. Quickshell
# and mpvpaper are both packaged directly in nixpkgs (unstable), so --
# unlike Fedora/Debian above -- neither needs a COPR/backports/source-build
# fallback chain here.
lw_nix_install() {
    # Installs one or more nixpkgs attributes (by their unqualified
    # attribute name, e.g. "quickshell") into the user profile. Returns 1
    # if `nix` isn't on PATH at all, or if every install method fails for
    # every requested attribute.
    command -v nix >/dev/null 2>&1 || return 1

    local pkg installables=()
    for pkg in "$@"; do
        installables+=("nixpkgs#${pkg}")
    done

    # 1) Modern Nix CLI (`nix profile install`), flakes enabled explicitly
    #    on the command line so this works even when the user's nix.conf
    #    hasn't turned on the nix-command/flakes experimental features.
    if nix profile install --extra-experimental-features 'nix-command flakes' \
        "${installables[@]}" >/dev/null 2>&1; then
        return 0
    fi

    # 2) Classic nix-env, one attribute at a time, resolved against
    #    whatever <nixpkgs> currently points to in NIX_PATH -- works on any
    #    Nix install regardless of channel name (avoids assuming the
    #    channel is called "nixos" vs "nixpkgs") and needs no experimental
    #    features at all.
    local any_failed=0 any_succeeded=0
    for pkg in "$@"; do
        if nix-env -f '<nixpkgs>' -iA "$pkg" >/dev/null 2>&1; then
            any_succeeded=1
        else
            any_failed=1
        fi
    done
    # Callers (install_quickshell_nixos/install_mpvpaper_nixos, both
    # single-package) only ever cared about all-or-nothing, but
    # install_node_nixos and any future multi-package caller need "did
    # at least the fallback attribute succeed" -- returning failure only
    # when EVERY attribute failed (instead of when ANY one did) stops a
    # single missing/renamed attribute in one call from masking a
    # genuinely successful install of the others.
    [ "$any_succeeded" -eq 1 ] && return 0
    [ "$any_failed" -eq 1 ] && return 1
    return 0
}

install_quickshell_nixos() {
    info "Installing quickshell (nix profile install, nixpkgs#quickshell)..."
    if lw_nix_install quickshell; then
        ok "quickshell installed into your Nix profile"
        return 0
    fi
    fail "quickshell isn't resolvable from your current nixpkgs channel (needs a reasonably recent nixos-unstable/25.05+)."
    fail "Manual install: nix profile install nixpkgs#quickshell"
    fail "  or add it to environment.systemPackages / home.packages and run nixos-rebuild switch / home-manager switch."
    return 1
}

install_mpvpaper_nixos() {
    info "Installing mpvpaper (nix profile install, nixpkgs#mpvpaper)..."
    if lw_nix_install mpvpaper; then
        ok "mpvpaper installed into your Nix profile"
        return 0
    fi
    fail "mpvpaper isn't resolvable from your current nixpkgs channel."
    fail "Manual install: nix profile install nixpkgs#mpvpaper"
    fail "  or add it to environment.systemPackages / home.packages and run nixos-rebuild switch / home-manager switch."
    return 1
}

# node/nodejs: see the NODE_MIN_MAJOR comment above for why presence alone
# isn't enough. nixpkgs' generic `nodejs` attribute tracks whichever major
# is the current default in that nixpkgs revision (usually recent enough on
# nixos-unstable), but try the explicitly-versioned `nodejs_<major>`
# attribute first for a guarantee, falling back to plain `nodejs` on older
# nixpkgs revisions that don't have it yet.
install_node_nixos() {
    info "Installing Node.js (nix profile install, nixpkgs#nodejs_${NODE_MIN_MAJOR}, falling back to nixpkgs#nodejs)..."
    if ! lw_nix_install "nodejs_${NODE_MIN_MAJOR}"; then
        lw_nix_install nodejs
    fi

    local got_major
    got_major="$(lw_node_major_version)"
    if [ -z "$got_major" ] || [ "$got_major" -lt "$NODE_MIN_MAJOR" ]; then
        fail "Node.js installed but is still older than $NODE_MIN_MAJOR (got: $(node --version 2>/dev/null || echo unknown))"
        fail "Manual install: nix profile install nixpkgs#nodejs_${NODE_MIN_MAJOR}"
        return 1
    fi
    ok "Node.js installed ($(node --version 2>/dev/null), nixpkgs#nodejs_${NODE_MIN_MAJOR})"
    return 0
}

# yt-dlp needs to stay current: YouTube changes its signature/PO-token
# scheme often enough that a yt-dlp even a few weeks stale starts failing
# stream extraction with an opaque "HTTP error 403 Forbidden" from
# googlevideo.com (mpv/ytdl_hook surfaces this, not yt-dlp itself, so it's
# easy to mistake for a Wayland/mpvpaper problem). Arch's official pacman
# package tracks upstream closely enough to trust as-is, but Fedora/
# Debian/openSUSE's yt-dlp packages routinely lag behind by weeks to
# months -- so for every non-Arch distro, install the latest standalone
# binary release directly from GitHub instead of going through dnf/apt/
# zypper. It's a single self-contained executable (yt-dlp bundles its own
# Python runtime), so this has no extra dependencies and matches what the
# yt-dlp project itself recommends for staying up to date.
#
# update.sh defines its own identical copy of this function (Step 2.5) so
# it can refresh yt-dlp on existing installs too -- the two are no longer
# a single shared file, so if this function ever needs to change, update
# the copy in update.sh to match.
install_ytdlp_latest() {
    info "Installing yt-dlp (latest release binary -- distro packages of yt-dlp" \
         "routinely lag behind YouTube's changes and cause 403 stream errors)..."

    # curl is what actually fetches the binary below -- MISSING_PKGS is an
    # associative array, so install order across dependencies isn't
    # guaranteed; make sure curl itself is present first rather than
    # assuming its own DEP_TABLE entry has already been processed.
    if ! command -v curl >/dev/null 2>&1; then
        info "curl not found -- installing it first (needed to fetch yt-dlp)..."
        case "$PKG_MANAGER" in
            apt)    sudo apt-get install -y curl               >/dev/null 2>&1 ;;
            dnf)    sudo dnf install -y curl                   >/dev/null 2>&1 ;;
            zypper) sudo zypper --non-interactive install curl >/dev/null 2>&1 ;;
            nix)    if declare -F lw_nix_install >/dev/null 2>&1; then
                        # install.sh provides this helper; use it verbatim.
                        lw_nix_install curl >/dev/null 2>&1
                    else
                        # update.sh has no lw_nix_install -- nix itself is
                        # the fallback (matches lw_nix_install's own logic).
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
    # /usr/local/bin/yt-dlp on PATH (distro package managers usually
    # install to /usr/bin, which some distros place before /usr/local/bin
    # in PATH -- not worth relying on ordering here). On nix this is a
    # user-profile removal, harmless no-op if yt-dlp was never installed
    # that way (this installer never puts it there in the first place --
    # see the plain-binary download below -- but a user may have).
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

# node/nodejs: see the NODE_MIN_MAJOR comment above for why presence alone
# isn't enough. On apt (Debian/Ubuntu) and dnf (Fedora/RHEL family) the
# distro-packaged Node can lag behind current LTS by one or more major
# versions, so fetch a current major straight from NodeSource instead of
# trusting whatever the distro repo happens to carry -- same reasoning as
# install_ytdlp_latest() above, just for Node instead of yt-dlp itself.
# Arch/openSUSE track a recent Node closely enough on their own that this
# hasn't been observed there, so pacman/zypper fall through to the generic
# per-distro package install below instead of getting a special case here.
install_node_latest() {
    local setup_url manual_install_cmd
    case "$PKG_MANAGER" in
        apt)
            setup_url="https://deb.nodesource.com/setup_${NODE_MIN_MAJOR}.x"
            manual_install_cmd="sudo apt-get install -y nodejs"
            ;;
        dnf)
            setup_url="https://rpm.nodesource.com/setup_${NODE_MIN_MAJOR}.x"
            manual_install_cmd="sudo dnf install -y nodejs"
            ;;
        *)
            return 1
            ;;
    esac

    info "Installing Node.js ${NODE_MIN_MAJOR}.x via NodeSource (this distro's own" \
         "package can be too old for yt-dlp's YouTube JS-challenge solver)..."

    # curl is what actually fetches NodeSource's setup script -- MISSING_PKGS
    # is an associative array, so install order across dependencies isn't
    # guaranteed; make sure curl itself is present first rather than
    # assuming its own DEP_TABLE entry has already been processed.
    if ! command -v curl >/dev/null 2>&1; then
        info "curl not found -- installing it first (needed for NodeSource's setup script)..."
        case "$PKG_MANAGER" in
            apt) sudo apt-get install -y curl >/dev/null 2>&1 ;;
            dnf) sudo dnf install -y curl      >/dev/null 2>&1 ;;
        esac
        if ! command -v curl >/dev/null 2>&1; then
            fail "curl is required to install Node.js via NodeSource and could not be installed automatically."
            return 1
        fi
    fi

    # SECURITY: This step downloads and executes NodeSource's official
    # repository setup script over HTTPS. The script adds the NodeSource
    # apt/dnf repository to your system so Node.js ${NODE_MIN_MAJOR}.x
    # can be installed via your package manager. This is NodeSource's
    # recommended installation method (see nodesource.com). The URL is
    # pinned above and uses HTTPS. For manual/air-gapped installation,
    # cancel now and see: https://github.com/nodesource/distributions
    info "Executing NodeSource repository setup script..."
    info "(source: $setup_url)"
    if ! curl -fsSL "$setup_url" | sudo -E bash - >/dev/null 2>&1; then
        fail "Failed to configure the NodeSource repository (network unavailable or nodesource.com unreachable)"
        fail "Manual install: curl -fsSL $setup_url | sudo -E bash - && $manual_install_cmd"
        return 1
    fi

    local install_status=0
    case "$PKG_MANAGER" in
        apt) sudo apt-get install -y nodejs || install_status=$? ;;
        dnf) sudo dnf install -y nodejs      || install_status=$? ;;
    esac
    if [ "$install_status" -ne 0 ]; then
        fail "Failed to install nodejs from the NodeSource repository"
        return 1
    fi

    local got_major
    got_major="$(lw_node_major_version)"
    if [ -z "$got_major" ] || [ "$got_major" -lt "$NODE_MIN_MAJOR" ]; then
        fail "Node.js installed but is still older than $NODE_MIN_MAJOR (got: $(node --version 2>/dev/null || echo unknown))"
        return 1
    fi

    ok "Node.js installed ($(node --version 2>/dev/null), NodeSource ${NODE_MIN_MAJOR}.x)"
    return 0
}

# Installs a single dependency by its pkg_key. Handles pacman/apt/dnf/zypper
# plus the Arch-only AUR case. Returns 1 (without killing the shell, thanks
# to the caller checking the return value) on any failure, with a message
# covering the common causes: sudo cancelled, no network, unknown package,
# missing AUR helper, or an unsupported package manager.
# AWWW (successor to swww). Prefer a native package when the distro
# provides one (Arch/CachyOS/EndeavourOS/etc.), because that is faster and
# avoids rebuilding Rust dependencies. Fall back to the upstream Codeberg
# source build on distros without a known native package. A small ownership
# marker records when this installer actually installed AWWW, so uninstall.sh
# never removes a user-installed copy.
LWM_AWWW_MARKER="$HOME/.local/share/live-wallpaper-manager/.awww-installed-by-lwm"

install_awww() {
    local cargo_cmd=""
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.nix-profile/bin:$PATH"

    # 1) If both commands already exist, do nothing and never claim ownership.
    if command -v awww >/dev/null 2>&1 && command -v awww-daemon >/dev/null 2>&1 && [ ! -f "$LWM_AWWW_MARKER" ]; then
        info "AWWW is already installed; keeping the existing installation."
        ok "AWWW available: $(command -v awww)"
        return 0
    fi

    # 2) Arch-family: AWWW is available as the official `awww` package in
    #    Extra. Install it directly instead of compiling it from source.
    if [ "$PKG_MANAGER" = "pacman" ]; then
        if pacman -Q awww >/dev/null 2>&1; then
            info "AWWW package is already installed; keeping it."
            return 0
        fi
        info "Installing AWWW from the Arch package repository..."
        if sudo pacman -S --needed --noconfirm awww; then
            mkdir -p "$HOME/.local/share/live-wallpaper-manager"
            printf '%s\n' 'method=pacman' 'package=awww' > "$LWM_AWWW_MARKER"
            ok "AWWW installed from pacman (awww + awww-daemon)"
            return 0
        fi
        warn "Native AWWW package installation failed; falling back to source build."
    fi

    # 3) Try the distro package on the other three supported families too.
    #    Not every release exposes AWWW, so a failed lookup is non-fatal and
    #    falls through to the existing source-build path below.
    case "$PKG_MANAGER" in
        apt)
            if apt-cache show awww >/dev/null 2>&1; then
                info "AWWW package found in apt repositories; installing it..."
                if sudo apt-get update -qq >/dev/null 2>&1 && sudo apt-get install -y awww >/dev/null 2>&1; then
                    mkdir -p "$HOME/.local/share/live-wallpaper-manager"
                    printf '%s\n' 'method=apt' 'package=awww' > "$LWM_AWWW_MARKER"
                    ok "AWWW installed from apt (awww + awww-daemon)"
                    return 0
                fi
                warn "apt knows about AWWW, but installation failed; falling back to source build."
            else
                info "AWWW is not available in the current apt repositories; using source build."
            fi
            info "Preparing AWWW build dependencies..."
            sudo apt-get update -qq >/dev/null 2>&1 || true
            sudo apt-get install -y cargo rustc pkg-config libwayland-dev liblz4-dev git curl >/dev/null 2>&1 || true
            ;;
        dnf)
            if dnf list --available awww >/dev/null 2>&1; then
                info "AWWW package found in dnf repositories; installing it..."
                if sudo dnf install -y awww >/dev/null 2>&1; then
                    mkdir -p "$HOME/.local/share/live-wallpaper-manager"
                    printf '%s\n' 'method=dnf' 'package=awww' > "$LWM_AWWW_MARKER"
                    ok "AWWW installed from dnf (awww + awww-daemon)"
                    return 0
                fi
                warn "dnf knows about AWWW, but installation failed; falling back to source build."
            else
                info "AWWW is not available in the enabled dnf repositories; using source build."
            fi
            info "Preparing AWWW build dependencies..."
            sudo dnf install -y rust cargo pkgconf-pkg-config wayland-devel lz4-devel git curl >/dev/null 2>&1 || true
            ;;
        zypper)
            if zypper --non-interactive info awww >/dev/null 2>&1; then
                info "AWWW package found in zypper repositories; installing it..."
                if sudo zypper --non-interactive install -y awww >/dev/null 2>&1; then
                    mkdir -p "$HOME/.local/share/live-wallpaper-manager"
                    printf '%s\n' 'method=zypper' 'package=awww' > "$LWM_AWWW_MARKER"
                    ok "AWWW installed from zypper (awww + awww-daemon)"
                    return 0
                fi
                warn "zypper knows about AWWW, but installation failed; falling back to source build."
            else
                info "AWWW is not available in the enabled zypper repositories; using source build."
            fi
            info "Preparing AWWW build dependencies..."
            sudo zypper --non-interactive install rust cargo pkg-config wayland-devel lz4-devel git curl >/dev/null 2>&1 || true
            ;;
        pacman)
            info "Preparing AWWW source-build dependencies..."
            sudo pacman -S --needed --noconfirm rust cargo pkgconf wayland lz4 git curl >/dev/null 2>&1 || true
            ;;
        nix)
            if lw_nix_install awww; then
                mkdir -p "$HOME/.local/share/live-wallpaper-manager"
                printf '%s\n' 'method=nix' 'package=awww' > "$LWM_AWWW_MARKER"
                ok "AWWW installed via nix profile install (nixpkgs#awww)"
                return 0
            fi
            info "AWWW is packaged in nixpkgs but not resolvable on this channel (try a newer nixos-unstable) -- using source build."
            info "Preparing AWWW source-build dependencies..."
            lw_nix_install cargo rustc pkg-config wayland lz4 git curl >/dev/null 2>&1 || true
            ;;
    esac

    if command -v cargo >/dev/null 2>&1; then
        cargo_cmd="$(command -v cargo)"
    fi

    local rust_ok=0 rust_ver rust_major rust_minor
    if command -v rustc >/dev/null 2>&1; then
        rust_ver="$(rustc --version | awk '{print $2}')"
        rust_major="${rust_ver%%.*}"
        rust_minor="${rust_ver#*.}"; rust_minor="${rust_minor%%.*}"
        if [ "${rust_major:-0}" -gt 1 ] || { [ "${rust_major:-0}" -eq 1 ] && [ "${rust_minor:-0}" -ge 87 ]; }; then
            rust_ok=1
        fi
    fi

    if [ "$rust_ok" -ne 1 ]; then
        if [ -x "$HOME/.cargo/bin/rustup" ]; then
            "$HOME/.cargo/bin/rustup" default stable >/dev/null 2>&1 || true
            export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
            cargo_cmd="$HOME/.cargo/bin/cargo"
        elif command -v curl >/dev/null 2>&1; then
            # SECURITY: This step downloads and executes rustup's official
            # installer over HTTPS. The script installs Rust into
            # ~/.cargo (user-local, no root). This is rustup's
            # recommended installation method (see rustup.rs). The URL
            # is pinned and uses TLS with certificate verification. For
            # manual/air-gapped installation, cancel and run:
            #   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
            info "System Rust is missing or too old; installing user-local stable Rust via rustup..."
            if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal >/dev/null 2>&1; then
                export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
                "$HOME/.cargo/bin/rustup" default stable >/dev/null 2>&1 || true
                cargo_cmd="$HOME/.cargo/bin/cargo"
                rust_ok=1
            else
                warn "Could not install rustup automatically; AWWW will remain unavailable."
                return 1
            fi
        fi
    fi

    [ -x "$cargo_cmd" ] || { warn "AWWW requires Cargo/Rust >= 1.87."; return 1; }

    mkdir -p "$HOME/.local/bin" "$HOME/.local/share/live-wallpaper-manager"
    if [ -x "$HOME/.local/bin/awww" ] && [ ! -f "$LWM_AWWW_MARKER" ]; then
        if [ -x "$HOME/.local/bin/awww-daemon" ]; then
            info "AWWW is already installed at ~/.local/bin; keeping the existing installation."
            return 0
        fi
        warn "awww exists but awww-daemon is missing; not overwriting the existing AWWW installation."
        return 1
    fi

    local build_dir cli daemon
    build_dir="$(mktemp -d)"
    if ! git clone --depth 1 https://codeberg.org/LGFae/awww.git "$build_dir/awww" >/dev/null 2>&1; then
        rm -rf "$build_dir"
        warn "Failed to download AWWW source from Codeberg."
        return 1
    fi
    if ! (cd "$build_dir/awww" && "$cargo_cmd" build --release --locked >/dev/null 2>&1); then
        rm -rf "$build_dir"
        warn "AWWW build failed; existing wallpaper backends remain unchanged."
        return 1
    fi

    cli="$build_dir/awww/target/release/awww"
    daemon="$build_dir/awww/target/release/awww-daemon"
    if [ ! -x "$cli" ] || [ ! -x "$daemon" ]; then
        rm -rf "$build_dir"
        warn "AWWW build did not produce both required binaries."
        return 1
    fi

    install -m 755 "$cli" "$HOME/.local/bin/awww"
    install -m 755 "$daemon" "$HOME/.local/bin/awww-daemon"
    printf '%s\n' 'method=local' > "$LWM_AWWW_MARKER"
    rm -rf "$build_dir"
    ok "AWWW installed to ~/.local/bin (awww + awww-daemon)"
    return 0
}

install_dependency() {
    local key="$1" label="$2" pkg

    # Fedora/dnf special cases -- see install_quickshell_fedora() and
    # install_mpvpaper_fedora() above for why these two can't go through
    # the generic per-distro package table.
    if [ "$PKG_MANAGER" = "dnf" ]; then
        case "$key" in
            quickshell) install_quickshell_fedora && return 0 || return 1 ;;
            mpvpaper)   install_mpvpaper_fedora   && return 0 || return 1 ;;
            nodejs)     install_node_latest       && return 0 || return 1 ;;
            awww)       install_awww               && return 0 || return 1 ;;
        esac
    fi

    # apt (Debian/Ubuntu/derivatives): same reasoning as the dnf block
    # above -- neither quickshell nor mpvpaper has a package apt can
    # reliably resolve on every apt-based distro, so both get dedicated
    # handling instead of a plain `apt-get install <pkg>` lookup.
    if [ "$PKG_MANAGER" = "apt" ]; then
        case "$key" in
            quickshell) install_quickshell_apt && return 0 || return 1 ;;
            mpvpaper)   install_mpvpaper_apt   && return 0 || return 1 ;;
            nodejs)     install_node_latest    && return 0 || return 1 ;;
            awww)       install_awww            && return 0 || return 1 ;;
        esac
    fi

    # NixOS/nix -- see the "NixOS/nix-specific installers" block above for
    # why these go through nix profile install / nix-env instead of the
    # generic per-distro package table below.
    if [ "$PKG_MANAGER" = "nix" ]; then
        case "$key" in
            quickshell) install_quickshell_nixos && return 0 || return 1 ;;
            mpvpaper)   install_mpvpaper_nixos   && return 0 || return 1 ;;
            nodejs)     install_node_nixos       && return 0 || return 1 ;;
            awww)       install_awww              && return 0 || return 1 ;;
        esac
    fi

    if [ "$key" = "awww" ]; then
        install_awww && return 0 || return 1
    fi

    # yt-dlp on any non-Arch distro: always the latest GitHub release
    # binary, never the distro package -- see install_ytdlp_latest() above
    # for why (stale distro packages cause opaque 403 stream errors).
    if [ "$key" = "yt-dlp" ] && [ "$PKG_MANAGER" != "pacman" ]; then
        install_ytdlp_latest && return 0 || return 1
    fi

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
        nix)    lw_nix_install "$pkg"                      || install_status=1  ;;
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

# ─── Step 0: Distro ─────────────────────────────────────────────────────────
# Arch, Fedora and Debian are the three distros with fully automatic
# dependency installation (pacman+AUR, dnf+COPR/source-build, and
# apt+backports/source-build respectively) -- everything else still
# auto-detects normally but doesn't get a dedicated menu entry here yet.
detect_distro
detect_package_manager

# Resolve the brand colour/label/qualifier once so the big ASCII "DISTRO"
# logo below and the "Detected: ..." line right after it both use the
# same colour -- e.g. an Arch machine gets a blue logo + "Arch Linux" in
# blue, an Ubuntu machine gets an orange logo + "Ubuntu" in orange.
DISTRO_BRAND_COLOR="$CYAN"
DISTRO_BRAND_LABEL="Unknown / unsupported"
DISTRO_BRAND_QUALIFIER="(no pacman, apt, dnf, zypper, or nix found)"
case "$PKG_MANAGER" in
    pacman) DISTRO_BRAND_COLOR="$ARCH_COLOR";   DISTRO_BRAND_LABEL="Arch Linux"; DISTRO_BRAND_QUALIFIER="(or an Arch-based distro)" ;;
    dnf)    DISTRO_BRAND_COLOR="$FEDORA_COLOR"; DISTRO_BRAND_LABEL="Fedora";     DISTRO_BRAND_QUALIFIER="(or an RHEL-based distro)" ;;
    apt)
        # Same apt-family package manager either way -- only the brand
        # colour/name differs, based on the exact distro ID
        # detect_distro() already read from /etc/os-release. Ubuntu and
        # its own derivatives (Pop!_OS, Mint, elementary, Zorin) get
        # Ubuntu's orange; Debian and everything else on apt gets
        # Debian's red.
        case "$DISTRO_ID" in
            ubuntu|pop|linuxmint|elementary|zorin)
                DISTRO_BRAND_COLOR="$UBUNTU_COLOR"; DISTRO_BRAND_LABEL="Ubuntu"; DISTRO_BRAND_QUALIFIER="(or an Ubuntu-based distro)" ;;
            *)
                DISTRO_BRAND_COLOR="$DEBIAN_COLOR"; DISTRO_BRAND_LABEL="Debian"; DISTRO_BRAND_QUALIFIER="(or a Debian-based distro)" ;;
        esac
        ;;
    nix)    DISTRO_BRAND_COLOR="$NIXOS_COLOR"; DISTRO_BRAND_LABEL="NixOS"; DISTRO_BRAND_QUALIFIER="" ;;
    zypper) DISTRO_BRAND_COLOR="$CYAN";        DISTRO_BRAND_LABEL="openSUSE"; DISTRO_BRAND_QUALIFIER="" ;;
esac

echo ""
printf "${BOLD}${DISTRO_BRAND_COLOR}"
cat <<'DISTRO_LOGO'
 ____ ___ ____ _____ ____   ___  
|  _ \_ _/ ___|_   _|  _ \ / _ \ 
| | | | |\___ \ | | | |_) | | | |
| |_| | | ___) || | |  _ <| |_| |
|____/___|____/ |_| |_| \_\\___/ 
DISTRO_LOGO
printf "${RESET}\n"

if [ -n "$DISTRO_BRAND_QUALIFIER" ]; then
    printf "${CYAN}  %s Detected: ${DISTRO_BRAND_COLOR}%s${CYAN} %s${RESET}\n" "$SYM_INFO" "$DISTRO_BRAND_LABEL" "$DISTRO_BRAND_QUALIFIER"
else
    printf "${CYAN}  %s Detected: ${DISTRO_BRAND_COLOR}%s${RESET}\n" "$SYM_INFO" "$DISTRO_BRAND_LABEL"
fi
echo ""
echo "Which distro are you installing on? This decides how missing"
echo "dependencies (quickshell, mpvpaper, ...) get installed automatically."
echo ""

# ─── Distro choice menu (boxed) ─────────────────────────────────────────
# Drawn at runtime rather than as fixed printf lines because line [5]'s
# text embeds the live-detected ${PKG_MANAGER} value, whose length isn't
# known ahead of time -- the box has to size itself to whatever actually
# gets printed. Padding widths below are computed from each line's PLAIN
# (uncoloured) text; the colour escape codes layered on top are invisible
# and take up no terminal columns, so they never throw the alignment off
# as long as the visible characters match the plain version exactly.
if [ "$USE_UNICODE" = 1 ]; then
    BOX_TL='┌'; BOX_TR='┐'; BOX_BL='└'; BOX_BR='┘'; BOX_H='─'; BOX_V='│'; BOX_TC='┬'; BOX_BC='┴'
else
    BOX_TL='+'; BOX_TR='+'; BOX_BL='+'; BOX_BR='+'; BOX_H='-'; BOX_V='|'; BOX_TC='+'; BOX_BC='+'
fi

MENU_NUM=(1 2 3 4 5)
MENU_LABEL_PLAIN=(
    "Arch Linux / Arch-based"
    "Fedora / RHEL-based"
    "Debian / Ubuntu (apt-based)"
    "NixOS"
    "Other"
)
MENU_DESC_PLAIN=(
    "pacman + AUR helper (yay/paru)"
    "dnf + COPR / build from source"
    "apt + backports / build from source"
    "nix profile install (user profile, no sudo)"
    "keep the autodetected package manager (${PKG_MANAGER:-none})"
)
# Same visible text as MENU_LABEL_PLAIN above, just with colour codes
# layered on -- must stay character-for-character identical once the
# escape sequences are stripped out, or the padding math breaks.
MENU_LABEL_COLOR=(
    "${ARCH_COLOR}Arch Linux / Arch-based${RESET}"
    "${FEDORA_COLOR}Fedora / RHEL-based${RESET}"
    "${DEBIAN_COLOR}Debian${RESET} / ${UBUNTU_COLOR}Ubuntu${RESET} ${APT_LABEL_COLOR}(apt-based)${RESET}"
    "${NIXOS_COLOR}NixOS${RESET}"
    "Other"
)

LABEL_WIDTH=0
for s in "${MENU_LABEL_PLAIN[@]}"; do
    [ "${#s}" -gt "$LABEL_WIDTH" ] && LABEL_WIDTH="${#s}"
done
DESC_WIDTH=0
for s in "${MENU_DESC_PLAIN[@]}"; do
    [ "${#s}" -gt "$DESC_WIDTH" ] && DESC_WIDTH="${#s}"
done

# Row layout: "  [N] " (6 cols) + label + " " (1) + divider (1) + " " (1) + desc + "  " (2).
# LEFT_SEG is the column index (0-based, inside the box) where the vertical
# divider sits -- the border-drawing function below punches a ┬/┴ through
# the top/bottom rules at that same index so the divider lines up into a
# proper two-column table instead of a floating bar.
LEFT_SEG=$((6 + LABEL_WIDTH + 1))
MENU_INNER_WIDTH=$((LEFT_SEG + 1 + 1 + DESC_WIDTH + 2))

menu_box_border() {
    local corner_l="$1" corner_r="$2" mid="$3" i line=""
    for ((i = 0; i < MENU_INNER_WIDTH; i++)); do
        if [ "$i" -eq "$LEFT_SEG" ]; then
            line+="$mid"
        else
            line+="$BOX_H"
        fi
    done
    printf "%s%s%s\n" "$corner_l" "$line" "$corner_r"
}

menu_box_border "$BOX_TL" "$BOX_TR" "$BOX_TC"
for i in "${!MENU_NUM[@]}"; do
    label_pad="$(printf '%*s' "$((LABEL_WIDTH - ${#MENU_LABEL_PLAIN[$i]}))" '')"
    desc_pad="$(printf '%*s' "$((DESC_WIDTH - ${#MENU_DESC_PLAIN[$i]}))" '')"
    # Colour codes must be interpolated directly into printf's format
    # string (not passed as %s arguments) -- printf only expands \033
    # backslash escapes in the format string itself, so a colour code
    # handed in via %s would print as the literal text "\033[...m"
    # instead of an actual escape sequence.
    printf "${BOX_V}  [${MENU_NUM[$i]}] ${MENU_LABEL_COLOR[$i]}${label_pad} ${BOX_V} ${MENU_DESC_PLAIN[$i]}${desc_pad}  ${BOX_V}\n"
done
menu_box_border "$BOX_BL" "$BOX_BR" "$BOX_BC"
echo ""
DISTRO_CHOICE=""
if [ -t 0 ]; then
    read -rp "Choice [1/2/3/4/5, Enter = autodetected]: " DISTRO_CHOICE || DISTRO_CHOICE=""
else
    info "Non-interactive shell detected — using the autodetected package manager"
fi
case "$DISTRO_CHOICE" in
    1) PKG_MANAGER="pacman" ;;
    2) PKG_MANAGER="dnf" ;;
    3) PKG_MANAGER="apt" ;;
    4) PKG_MANAGER="nix" ;;
    5|"") ;; # keep autodetected PKG_MANAGER as-is
    *) warn "Unrecognized choice '$DISTRO_CHOICE' — keeping the autodetected package manager" ;;
esac

if [ "$PKG_MANAGER" = "pacman" ]; then
    detect_aur_helper
    ok "Arch Linux selected — quickshell/awww install from the official repositories, mpvpaper/peaclock/qarma via AUR (${AUR_HELPER:-no yay/paru found})"
elif [ "$PKG_MANAGER" = "dnf" ]; then
    ok "Fedora selected — quickshell via the errornointernet COPR (falling back from the official package), mpvpaper built from source"
elif [ "$PKG_MANAGER" = "apt" ]; then
    ok "Debian/Ubuntu selected — quickshell via apt (or ${DISTRO_ID}-backports on Debian) if available, mpvpaper built from source"
elif [ "$PKG_MANAGER" = "nix" ]; then
    ok "NixOS selected — quickshell/mpvpaper/nodejs install via 'nix profile install' into your user profile (no sudo, no configuration.nix changes); AWWW/peaclock fall back to a Rust source build if not packaged in nixpkgs."
fi

# App source directory: normally a single shared livewallpaper/ directory
# for every distro, since the app code itself has no distro-specific
# content. If distro-specific copies (livewallpaper-arch/,
# livewallpaper-fedora/, livewallpaper-debian/) are ever reintroduced
# alongside this archive, they take priority automatically here -- no
# other change needed.
APP_SRC_DIR="$SCRIPT_DIR/livewallpaper"
if [ "$PKG_MANAGER" = "pacman" ] && [ -d "$SCRIPT_DIR/livewallpaper-arch" ]; then
    APP_SRC_DIR="$SCRIPT_DIR/livewallpaper-arch"
elif [ "$PKG_MANAGER" = "dnf" ] && [ -d "$SCRIPT_DIR/livewallpaper-fedora" ]; then
    APP_SRC_DIR="$SCRIPT_DIR/livewallpaper-fedora"
elif [ "$PKG_MANAGER" = "apt" ] && [ -d "$SCRIPT_DIR/livewallpaper-debian" ]; then
    APP_SRC_DIR="$SCRIPT_DIR/livewallpaper-debian"
elif [ "$PKG_MANAGER" = "nix" ] && [ -d "$SCRIPT_DIR/livewallpaper-nixos" ]; then
    APP_SRC_DIR="$SCRIPT_DIR/livewallpaper-nixos"
fi

# ─── Step 0.5: Hyprland ─────────────────────────────────────────────────────
# hyprctl is only needed for Smart Playback's fullscreen/lock/gaming
# detection via the Hyprland event socket -- everything else in LWM runs
# fine on any Wayland compositor. Asking up front means non-Hyprland users
# are never forced to compile/install Hyprland just to run the installer.
step "Hyprland"

HYPRLAND_DEFAULT="n"
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || command -v hyprctl >/dev/null 2>&1; then
    HYPRLAND_DEFAULT="y"
fi

echo "Do you use Hyprland (or plan to)? This decides whether hyprctl gets"
echo "installed/required -- Smart Playback's fullscreen/lock detection is"
echo "the only feature that needs it; everything else works without it."
echo ""
HYPRLAND_CHOICE=""
if [ -t 0 ]; then
    read -rp "Use Hyprland? [Y/n, Enter = ${HYPRLAND_DEFAULT}]: " HYPRLAND_CHOICE || HYPRLAND_CHOICE=""
    [ -z "$HYPRLAND_CHOICE" ] && HYPRLAND_CHOICE="$HYPRLAND_DEFAULT"
else
    HYPRLAND_CHOICE="$HYPRLAND_DEFAULT"
    info "Non-interactive shell detected — assuming '${HYPRLAND_DEFAULT}' (autodetected)"
fi
case "$HYPRLAND_CHOICE" in
    y|Y|yes|Yes|YES) USE_HYPRLAND="true" ;;
    *)                USE_HYPRLAND="false" ;;
esac

if [ "$USE_HYPRLAND" = "true" ]; then
    if [ "$PKG_MANAGER" = "pacman" ]; then
        ok "Hyprland: yes — hyprctl required, will install via pacman if missing"
    else
        ok "Hyprland: yes — hyprctl will be installed if available for this distro (not blocking if missing)"
    fi
else
    ok "Hyprland: no — hyprctl will not be checked or installed"
fi

# ─── Step 0.6: KDE Plasma ───────────────────────────────────────────────────
# mpvpaper (the normal video-wallpaper backend) needs a Wayland session --
# it's built entirely on the wlr-layer-shell protocol and can't connect to
# an X11 display at all. On Plasma Wayland it does run, but KWin doesn't
# support wlr-layer-shell the way wlroots compositors (Hyprland, Sway,
# ...) do, so the video wallpaper can go blank on a desktop click. On
# Plasma X11 mpvpaper cannot start at all -- there's no Wayland socket to
# hand it. kde-plasma-wallpaper/ is a genuine Plasma Wallpaper KPackage
# plugin that sidesteps mpvpaper entirely and renders through KDE's own
# wallpaper plugin system instead, which works identically on both
# session types (see kde-plasma-wallpaper/README.md for exactly what it
# does and does not support -- local video wallpaper only, not
# streaming/web modes yet). Entirely optional and additive: skipping this
# changes nothing else about the install.
step "KDE Plasma wallpaper plugin"

KDE_PLASMA_DETECTED="false"
if [ "${XDG_CURRENT_DESKTOP:-}" = "KDE" ] || [ -n "${KDE_FULL_SESSION:-}" ] || command -v plasmashell >/dev/null 2>&1; then
    KDE_PLASMA_DETECTED="true"
fi
IS_X11_SESSION="false"
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ "${XDG_SESSION_TYPE:-}" != "wayland" ]; then
    IS_X11_SESSION="true"
fi

KDE_PLASMA_DEFAULT="n"
[ "$KDE_PLASMA_DETECTED" = "true" ] && KDE_PLASMA_DEFAULT="y"

echo "Are you running KDE Plasma? mpvpaper's usual rendering path needs"
echo "Wayland: on Plasma Wayland it can go blank on a desktop click (KWin"
echo "doesn't fully support the protocol it relies on); on Plasma X11 it"
echo "can't run AT ALL. This installs a native Plasma wallpaper plugin that"
echo "sidesteps mpvpaper and works the same on both session types --"
echo "required for video wallpaper on Plasma X11, and fixes the blanking"
echo "on Plasma Wayland. Local video wallpaper only for now, not"
echo "streaming/web wallpaper. See kde-plasma-wallpaper/README.md."
if [ "$KDE_PLASMA_DETECTED" = "true" ] && [ "$IS_X11_SESSION" = "true" ]; then
    echo ""
    echo "Detected: KDE Plasma on an X11 session -- mpvpaper-based video"
    echo "wallpaper/streaming will not work at all without this plugin."
fi
echo ""
KDE_PLASMA_CHOICE=""
if [ -t 0 ]; then
    read -rp "Install KDE Plasma wallpaper plugin? [y/N, Enter = ${KDE_PLASMA_DEFAULT}]: " KDE_PLASMA_CHOICE || KDE_PLASMA_CHOICE=""
    [ -z "$KDE_PLASMA_CHOICE" ] && KDE_PLASMA_CHOICE="$KDE_PLASMA_DEFAULT"
else
    KDE_PLASMA_CHOICE="$KDE_PLASMA_DEFAULT"
    info "Non-interactive shell detected — assuming '${KDE_PLASMA_DEFAULT}' (autodetected)"
fi
case "$KDE_PLASMA_CHOICE" in
    y|Y|yes|Yes|YES) USE_KDE_PLASMA_WALLPAPER="true" ;;
    *)                USE_KDE_PLASMA_WALLPAPER="false" ;;
esac

if [ "$USE_KDE_PLASMA_WALLPAPER" = "true" ]; then
    ok "KDE Plasma wallpaper plugin: yes — will install to ~/.local/share/plasma/wallpapers/"
else
    ok "KDE Plasma wallpaper plugin: no — skipping (install later with ./scripts/install_kde_plasma_wallpaper.sh)"
fi

# ─── Step 0b: lw-cli (optional standalone terminal control tool) ──────────
# Pure CLI, no UI/QML involvement either way -- entirely optional and
# additive, same "skip changes nothing else" guarantee as the KDE Plasma
# plugin above. Needs socat; asked about separately below when chosen.
step "lw-cli (terminal control tool)"

echo "lw-cli is a standalone command-line tool (next/prev/toggle/status/file)"
echo "for controlling the running wallpaper from a terminal or keybind --"
echo "independent of the Manager app/panel UI. Requires 'socat'."
echo ""
LW_CLI_CHOICE=""
if [ -t 0 ]; then
    read -rp "Install lw-cli? [Y/n]: " LW_CLI_CHOICE || LW_CLI_CHOICE=""
    [ -z "$LW_CLI_CHOICE" ] && LW_CLI_CHOICE="y"
else
    LW_CLI_CHOICE="y"
    info "Non-interactive shell detected — assuming 'y'"
fi
case "$LW_CLI_CHOICE" in
    n|N|no|No|NO) INSTALL_LW_CLI="false" ;;
    *)            INSTALL_LW_CLI="true" ;;
esac

if [ "$INSTALL_LW_CLI" = "true" ]; then
    ok "lw-cli: yes — will install to ~/.local/bin/lw-cli"
else
    ok "lw-cli: no — skipping (install later by re-running ./install.sh, or remove with ./uninstall.sh --remove-lw-cli)"
fi

# ─── Step 1: Check dependencies ────────────────────────────────────────────
step "Checking dependencies"

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
            warn "Could not detect a supported package manager (pacman/apt/dnf/zypper/nix) — unsupported distro."
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
        nix)    echo "nix profile install nixpkgs#python3 (the venv module is already bundled, no separate package needed)" ;;
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
cp -rf "$APP_SRC_DIR/Config"      "$LWM_DEST/"
cp -rf "$APP_SRC_DIR/Services"    "$LWM_DEST/"
cp -rf "$APP_SRC_DIR/Components"  "$LWM_DEST/"
cp -rf "$APP_SRC_DIR/Panels"      "$LWM_DEST/"
# Manager/ + Pages/ (the desktop-app window and its settings pages) --
# added after Components/Panels existed, so they're copied explicitly
# rather than being caught by an earlier glob.
[ -d "$APP_SRC_DIR/Manager" ] && cp -rf "$APP_SRC_DIR/Manager" "$LWM_DEST/"
[ -d "$APP_SRC_DIR/Pages" ]   && cp -rf "$APP_SRC_DIR/Pages"   "$LWM_DEST/"
cp -f  "$APP_SRC_DIR/shell.qml"   "$LWM_DEST/"
[ -d "$APP_SRC_DIR/assets" ] && cp -rf "$APP_SRC_DIR/assets" "$LWM_DEST/"
[ -d "$SCRIPT_DIR/assets" ]               && cp -rf "$SCRIPT_DIR/assets/."             "$LWM_DEST/assets/"

info "Copying scripts..."
mkdir -p "$LWM_DEST/scripts"
cp -f "$APP_SRC_DIR/scripts/"*.sh "$LWM_DEST/scripts/"
# Music Dock's FIFO reader (_cava_reader.py) and cava's config template
# (cava.conf) aren't shell scripts, so the *.sh glob above misses them —
# copy explicitly, tolerating either being absent (older archives / a
# stripped-down build without Music Dock still install fine).
[ -f "$APP_SRC_DIR/scripts/_cava_reader.py" ] && \
    cp -f "$APP_SRC_DIR/scripts/_cava_reader.py" "$LWM_DEST/scripts/"
[ -f "$APP_SRC_DIR/scripts/cava.conf" ] && \
    cp -f "$APP_SRC_DIR/scripts/cava.conf" "$LWM_DEST/scripts/"
# PHASE 4 -- system tray helper (Python, so missed by the *.sh glob above)
[ -f "$APP_SRC_DIR/scripts/_tray_icon.py" ] && \
    cp -f "$APP_SRC_DIR/scripts/_tray_icon.py" "$LWM_DEST/scripts/"
# _sun_times.py: the offline sunrise/sunset calculator sun_times.sh shells
# out to (Schedule page's "sunrise"/"sunset" rule tokens) -- same "*.sh glob
# misses it" reasoning as _cava_reader.py/_tray_icon.py above.
[ -f "$APP_SRC_DIR/scripts/_sun_times.py" ] && \
    cp -f "$APP_SRC_DIR/scripts/_sun_times.py" "$LWM_DEST/scripts/"
chmod +x "$LWM_DEST/scripts/"*.sh
[ -f "$LWM_DEST/scripts/_cava_reader.py" ] && chmod +x "$LWM_DEST/scripts/_cava_reader.py"
[ -f "$LWM_DEST/scripts/_tray_icon.py" ] && chmod +x "$LWM_DEST/scripts/_tray_icon.py"
[ -f "$LWM_DEST/scripts/_sun_times.py" ] && chmod +x "$LWM_DEST/scripts/_sun_times.py"

# ─── lw-cli (standalone terminal control tool) ──────────────────────────────
# Extensionless, so it's missed by the "*.sh" glob above -- copied and
# chmod'd explicitly. It is pure Bash/CLI and has no connection to any
# .qml file; nothing about the UI changes by installing it.
# Gated on the Step 0b choice above -- "no" there means skip entirely
# (don't even drop the file into $LWM_DEST/scripts).
LW_CLI_INSTALLED=false
if [ "${INSTALL_LW_CLI:-true}" = "true" ] && [ -f "$APP_SRC_DIR/scripts/lw-cli" ]; then
    info "Installing lw-cli (terminal control tool)..."

    # socat is lw-cli's only runtime dependency beyond what's already
    # required (utils.sh/jq). Checked here rather than folded into the
    # big MISSING_PKGS dependency system above, since it's optional
    # (only lw-cli needs it -- the Quickshell module never does).
    if ! command -v socat >/dev/null 2>&1; then
        case "$PKG_MANAGER" in
            pacman)
                warn "socat not found -- installing it (required by lw-cli)..."
                if sudo pacman -S --needed --noconfirm socat; then
                    ok "socat installed."
                else
                    warn "Failed to install socat automatically -- install it manually (sudo pacman -S socat) for lw-cli to work."
                fi
                ;;
            apt)
                warn "socat not found -- installing it (required by lw-cli)..."
                if sudo apt-get install -y socat; then
                    ok "socat installed."
                else
                    warn "Failed to install socat automatically -- install it manually (sudo apt install socat) for lw-cli to work."
                fi
                ;;
            dnf)
                warn "socat not found -- installing it (required by lw-cli)..."
                if sudo dnf install -y socat; then
                    ok "socat installed."
                else
                    warn "Failed to install socat automatically -- install it manually (sudo dnf install socat) for lw-cli to work."
                fi
                ;;
            zypper)
                warn "socat not found -- installing it (required by lw-cli)..."
                if sudo zypper --non-interactive install socat; then
                    ok "socat installed."
                else
                    warn "Failed to install socat automatically -- install it manually (sudo zypper install socat) for lw-cli to work."
                fi
                ;;
            nix)
                warn "socat not found -- installing it (required by lw-cli)..."
                if lw_nix_install socat; then
                    ok "socat installed."
                else
                    warn "Failed to install socat automatically -- install it manually (nix profile install nixpkgs#socat) for lw-cli to work."
                fi
                ;;
            *)
                warn "socat not found -- lw-cli (terminal control tool) needs it to work."
                warn "Install it manually, e.g.: sudo apt install socat / sudo dnf install socat / sudo zypper install socat / nix profile install nixpkgs#socat"
                ;;
        esac
    fi

    cp -f "$APP_SRC_DIR/scripts/lw-cli" "$LWM_DEST/scripts/lw-cli"
    chmod +x "$LWM_DEST/scripts/lw-cli"

    mkdir -p "$HOME/.local/bin"
    install -m 755 "$LWM_DEST/scripts/lw-cli" "$HOME/.local/bin/lw-cli"
    LW_CLI_INSTALLED=true
    ok "lw-cli installed → ~/.local/bin/lw-cli"
elif [ "${INSTALL_LW_CLI:-true}" = "false" ]; then
    # Opted out -- if this is a re-run over a previous install that had
    # lw-cli, clean up the leftovers instead of leaving a stale copy
    # around that the user just said they don't want.
    if [ -f "$LWM_DEST/scripts/lw-cli" ] || [ -f "$HOME/.local/bin/lw-cli" ]; then
        info "Removing previously installed lw-cli (opted out this run)..."
        rm -f "$LWM_DEST/scripts/lw-cli" "$HOME/.local/bin/lw-cli"
        ok "lw-cli removed."
    fi
fi

info "Seeding default data (never overwrites existing favorites/settings/history)..."
mkdir -p "$LWM_DEST/data"
if [ -d "$APP_SRC_DIR/data" ]; then
    for f in "$APP_SRC_DIR/data/"*.json; do
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
if [ -f "$APP_SRC_DIR/assets/icons/app-icon.png" ]; then
    for sz in 16x16 22x22 24x24 32x32 48x48 64x64 96x96 128x128 192x192 256x256 512x512; do
        ICON_DIR="$HOME/.local/share/icons/hicolor/$sz/apps"
        mkdir -p "$ICON_DIR"
        cp -f "$APP_SRC_DIR/assets/icons/app-icon.png" \
            "$ICON_DIR/live-wallpaper-manager-app.png"
    done
    mkdir -p "$HOME/.local/share/pixmaps"
    cp -f "$APP_SRC_DIR/assets/icons/app-icon.png" \
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
# __OPEN_APP_SH__ is filled in with the real, already-expanded absolute
# path to open_app.sh (not left as "$HOME/..." for bash to expand at
# click-time) because XDG .desktop Exec= values are not guaranteed to be
# run through a shell that expands "$HOME" -- some launchers exec the
# tokens directly, and the previous `bash -c "\"$HOME/...\" ..."` form's
# nested quoting was also fragile across different desktop
# environments' Exec= parsers, causing icon clicks to silently do
# nothing on some setups even though the exact same command worked fine
# typed in a terminal. See manage_autostart.sh's autostart entry, which
# already used this same "resolve the path now, no bash -c" approach.
OPEN_APP_SH="$LWM_DEST/scripts/open_app.sh"
if [ -f "$APP_SRC_DIR/live-wallpaper-manager.desktop" ]; then
    sed -e "s|__QS_CONFIG_DIR__|$LWM_DEST|g" \
        -e "s|__OPEN_APP_SH__|$OPEN_APP_SH|g" \
        -e "s|__APP_ICON_PATH__|$ICON_FOR_DESKTOP|g" \
        "$APP_SRC_DIR/live-wallpaper-manager.desktop" \
        > "$HOME/.local/share/applications/live-wallpaper-manager.desktop"
fi
# Manager app launcher (added in an earlier phase but never previously
# wired into the installer -- fixed here).
if [ -f "$APP_SRC_DIR/live-wallpaper-manager-app.desktop" ]; then
    sed -e "s|__OPEN_APP_SH__|$OPEN_APP_SH|g" \
        -e "s|__APP_ICON_PATH__|$ICON_FOR_DESKTOP|g" \
        "$APP_SRC_DIR/live-wallpaper-manager-app.desktop" \
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
        if bash "$LWM_DEST/scripts/manage_autostart.sh" enable >/dev/null 2>&1; then
            ok "Autostart enabled (~/.config/autostart/live-wallpaper-manager.desktop)"
            if [ -f "$HOME/.config/hypr/hyprland.lua" ] && grep -qi "live-wallpaper-manager autostart" "$HOME/.config/hypr/hyprland.lua" 2>/dev/null; then
                ok "Hyprland-native autostart added to hyprland.lua (Hyprland doesn't read the XDG entry above on its own)"
            elif [ -f "$HOME/.config/hypr/hyprland.conf" ] && grep -qi "live-wallpaper-manager autostart" "$HOME/.config/hypr/hyprland.conf" 2>/dev/null; then
                ok "Hyprland-native autostart added to hyprland.conf (Hyprland doesn't read the XDG entry above on its own)"
            elif command -v hyprctl >/dev/null 2>&1; then
                info "Hyprland detected but no ~/.config/hypr/hyprland.lua or hyprland.conf found yet"
                info "  — once you have one, toggle Autostart off/on in Settings to add the entry"
            fi
        else
            warn "Could not write the autostart entry (non-fatal — try again from Settings)"
        fi
        ;;
    *)
        info "Autostart skipped — enable anytime from Settings → Application"
        info "  (on Hyprland, enabling it there also writes the Hyprland-native entry"
        info "   into hyprland.lua/hyprland.conf automatically — no manual editing needed)"
        ;;
esac

ok "Live Wallpaper Manager installed at $LWM_DEST"

# ─── Step 2c: KDE Plasma wallpaper plugin ──────────────────────────────────
# Choice captured in Step 0.6. Copied (not symlinked) into place, same as
# scripts/install_kde_plasma_wallpaper.sh does standalone -- a real copy
# so kpackagetool6/plasmashell's own package validation, which can be
# picky about symlinked KPackage roots on some versions, never has
# anything unusual to trip over. Kept as its own step so re-running
# install.sh always re-syncs it from $SCRIPT_DIR, same as every other
# installed file here.
if [ "$USE_KDE_PLASMA_WALLPAPER" = "true" ]; then
    step "KDE Plasma wallpaper plugin"
    KDE_PLUGIN_SRC="$SCRIPT_DIR/kde-plasma-wallpaper"
    KDE_PLUGIN_ID="com.livewallpapermanager.plasmawallpaper"
    KDE_PLUGIN_DEST="$HOME/.local/share/plasma/wallpapers/$KDE_PLUGIN_ID"
    if [ -f "$KDE_PLUGIN_SRC/metadata.json" ]; then
        mkdir -p "$(dirname "$KDE_PLUGIN_DEST")"
        rm -rf "$KDE_PLUGIN_DEST"
        cp -r "$KDE_PLUGIN_SRC" "$KDE_PLUGIN_DEST"
        ok "Installed to $KDE_PLUGIN_DEST"
        info "Enable it: right-click Desktop → Configure Desktop and Wallpaper…"
        info "  → change wallpaper type to \"Live Wallpaper Manager\""
        info "If it's not listed yet, KDE may need: plasmashell --replace &"
    else
        warn "kde-plasma-wallpaper/ not found next to install.sh — skipping (non-fatal)"
    fi
fi

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
if [ "$USE_KDE_PLASMA_WALLPAPER" = "true" ]; then
    ok "KDE Plasma wallpaper plugin → $HOME/.local/share/plasma/wallpapers/com.livewallpapermanager.plasmawallpaper"
fi
echo ""
info "Checks passed: $VERIFY_PASS | Warnings: $VERIFY_FAIL"
echo ""
printf "${BOLD}Next steps:${RESET}\n"
echo ""
echo "  1. Add your wallpaper videos to:  ~/Pictures/Live Wallpaper"
echo ""
echo "  2. Start the Quickshell module:"
echo "     Standalone:  $LWM_DEST/scripts/launch_quickshell.sh -c livewallpaper"
echo "     Caelestia:   see livewallpaper/CAELESTIA_INTEGRATION.md"
echo "     (or just launch \"Live Wallpaper Manager\" from your app launcher)"
echo ""
echo "  3. (Optional) Enable \"Start on login\" from Settings → Application."
echo "     On Hyprland this automatically adds a matching entry to"
echo "     ~/.config/hypr/hyprland.lua (or hyprland.conf) too, since"
echo "     Hyprland doesn't read the plain XDG autostart entry on its own"
echo "     — no manual config editing needed."
echo ""
echo "  4. Toggle the compact panel (play/pause/next/previous/random,"
echo "     current wallpaper + song):"
echo "     $LWM_DEST/scripts/open_app.sh livewallpaper toggle"
echo ""
echo "  5. Open the full Manager app (library, playlist, music, visualizer,"
echo "     monitor, performance, and general settings):"
echo "     $LWM_DEST/scripts/open_app.sh livewallpapermanager open"
echo "     (or click \"Open Manager\" in the panel's title bar, or launch"
echo "      \"Live Wallpaper Manager (App)\" from your app launcher)"
echo ""
echo "     Both app launcher entries (and the two commands above) go"
echo "     through open_app.sh, which starts the shell if it isn't running"
echo "     yet and retries for up to ~15s instead of giving up after a"
echo "     single try -- prefer it over a raw"
echo "     \"quickshell -c livewallpaper ipc call ... open\" for anything"
echo "     that might run before the shell has finished starting (a"
echo "     keybind, a script, a cold-boot autostart race)."
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
if [ "${LW_CLI_INSTALLED:-false}" = "true" ]; then
    echo "  8. lw-cli (standalone terminal control, e.g. for keybinds):"
    echo "     lw-cli next | prev | toggle | status | file <path>"
    echo "     (installed to ~/.local/bin/lw-cli -- needs socat)"
    echo "     Remove it later without a full uninstall: ./uninstall.sh --remove-lw-cli"
    echo ""
fi
if ! $PATH_OK; then
    warn "Remember to add ~/.local/bin to PATH (see warning above)"
    echo ""
fi
ok "Done."

# Ensure default log directory exists
mkdir -p "$HOME/LiveWallpaperLogs"
chmod +x "$0" || true
