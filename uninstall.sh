#!/usr/bin/env bash
#
# uninstall.sh — Live Wallpaper Manager Uninstaller
# ================================================================
# Removes Live Wallpaper Manager.
#
# launcher) are removed automatically -- they're just registration
# files this project installed, not your data.
#
# Every actual CONFIG/DATA directory (Live Wallpaper Manager's own
# only ever removed after you explicitly confirm THAT directory, one at
# a time, with the default answer "no" -- press Enter (or say N) and it
# is kept. There is also a single "remove all of the above" shortcut,
# which still only ever touches the same approved, project-specific
# paths listed on screen -- nothing outside them.
#
# Usage:
#   ./uninstall.sh
#
set -euo pipefail

# ─── Terminal capability detection ─────────────────────────────────────────
# Colour and Unicode glyphs are only used on an interactive TTY (and, for
# colour, only when NO_COLOR isn't set) with a UTF-8 locale. Anything else —
# redirected to a file, piped through tee, a dumb terminal — falls back to
# plain ASCII with no ANSI escapes, so `./uninstall.sh > uninstall.log` and
# `./uninstall.sh | tee uninstall.log` stay clean and readable.
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
error()   { printf "${RED}  %s %s${RESET}\n" "$SYM_ERR" "$*" >&2; }
step()    { echo ""; printf "${BOLD}${RED}%s${RESET}\n" "$*"; }
divider() { if [ "$USE_UNICODE" = 1 ]; then printf "${DIM}%s${RESET}\n" "────────────────────────────────────"; else printf -- "${DIM}%s${RESET}\n" "----------------------------------------"; fi; }
banner() {
    echo ""
    printf "${BOLD}${RED}"
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

# Idempotent: true only while a quickshell process actually exists, so
# every caller below can just poll this instead of duplicating the pgrep
# invocation and its exit-code handling under `set -e`.
quickshell_running() {
    pgrep quickshell >/dev/null 2>&1
}

LWM_DEST="$HOME/.config/quickshell/livewallpaper"
LWM_CACHE_DIR="$HOME/.cache/livewallpaper"

banner "Uninstall"

# ═══════════════════════════════════════════════════════════════════════
# PATH SAFETY
# ═══════════════════════════════════════════════════════════════════════
# Every directory this script can ever remove is added, verbatim, to
# this allow-list below (see the "detect project directories" section) --
# nothing is ever passed to lw_safe_rmrf() that isn't one of those exact,
# already-known-safe paths. This function is still a hard second gate in
# front of every single rm -rf in the script: it re-resolves the path
# (so a symlink can't quietly redirect the deletion somewhere else),
# confirms it's actually still inside the project's own directories, and
# explicitly refuses a fixed list of paths that must never be touched --
# so a bug elsewhere in this script (a bad variable, a copy/paste
# mistake) can't turn into deleting the wrong thing.
lw_safe_rmrf() {
    local raw="$1" label="$2"
    local resolved
    resolved="$(realpath -m -- "$raw" 2>/dev/null || echo "$raw")"

    # Never these, no matter what.
    local forbidden=(
        "/" "/home" "/root" "/etc" "/usr" "/var" "/bin" "/boot" "/lib" "/lib64" "/sbin"
        "$HOME" "$HOME/.config" "$HOME/.cache" "$HOME/.local"
        "$HOME/.local/share" "$HOME/.local/bin" "$HOME/.config/systemd"
    )
    local f
    for f in "${forbidden[@]}"; do
        if [ "$resolved" = "$f" ]; then
            error "Refusing to remove '$resolved' ($label) -- this is a protected system/home directory, not a project-specific path. Skipping."
            return 1
        fi
    done

    # Must actually still be one of the exact paths this script knows
    # about -- catches the resolved (symlink-followed) path drifting
    # outside the project's own directories.
    case "$resolved" in
        "$HOME/.config/quickshell/livewallpaper"|"${HOME}/.cache/livewallpaper")
            ;;
        *)
            error "Refusing to remove '$resolved' ($label) -- not a recognized project-specific directory. Skipping."
            return 1
            ;;
    esac

    if [ ! -e "$resolved" ]; then
        info "$label ($resolved) not present -- nothing to remove."
        return 0
    fi

    rm -rf -- "$resolved"
    ok "$label removed ($resolved)"
}

# Prompts for one directory, default answer N (Enter keeps it).
# Returns 0 (true) only on an explicit y/yes.
lw_confirm() {
    local prompt="$1" ans
    read -r -p "  $prompt [y/N] " ans
    case "${ans,,}" in
        y|yes) return 0 ;;
        *) return 1 ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════
# DEPENDENCY CLEANUP (optional, additional stage -- see Step 5 below)
# ═══════════════════════════════════════════════════════════════════════
# Everything in this section mirrors install.sh's own dependency data
# (DEP_TABLE / PKG_PACMAN / PKG_APT / PKG_DNF / PKG_ZYPPER / distro+package-
# manager detection) verbatim -- no package name here is invented, every
# one of them is exactly what install.sh already knows how to install, so
# uninstall can offer to remove the same thing by the same name. The only
# thing added on top is DEP_CLASS, which decides what's ever safe to touch.

# label|check_cmd|hard|soft|pkg_key -- identical table to install.sh.
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

# Package name per distro family -- identical maps to install.sh. Empty
# string = no known native package on that distro. "AUR:name" = Arch-only
# package (removal still goes through pacman, see remove_dependency_pkg()).
declare -A PKG_PACMAN=(
    [quickshell]="AUR:quickshell"   [mpvpaper]="AUR:mpvpaper"
    [ffmpeg]="ffmpeg"               [jq]="jq"
    [hyprland]="hyprland"           [python3]="python"
    [curl]="curl"                   [inotify-tools]="inotify-tools"
    [yt-dlp]="yt-dlp"
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
    [zenity]="zenity"               [yad]="yad"
    [kdialog]="kdialog"
    [cava]="cava"                   [playerctl]="playerctl"
    [pipewire]="pipewire"
    [peaclock]=""
)

# ─── Safety classification ─────────────────────────────────────────────
# Two states only:
#   optional  = safe to offer for removal, subject to the same
#               ownership/package-manager checks as before (project's
#               own optional-feature dependencies -- dialog backends,
#               streaming/media helpers, the visualizer/MPRIS tools).
#               Still only ever removed after explicit user selection
#               and confirmation; still passed through the same
#               dep_get_package_name / remove_dependency_pkg path.
#   protected = core system/runtime components, general-purpose tools
#               other software commonly depends on, and this project's
#               own load-bearing runtime (quickshell, peaclock). Never
#               offered for removal, never selectable, never passed to
#               the uninstall command, by any menu action.
# Anything not explicitly listed as "optional" defaults to "protected" --
# the safe default, matching this feature's existing safety model.
declare -A DEP_CLASS=(
    [mpvpaper]="optional"       [zenity]="optional"       [yad]="optional"
    [kdialog]="optional"        [inotify-tools]="optional" [yt-dlp]="optional"
    [playerctl]="optional"      [cava]="optional"
    [quickshell]="protected"    [peaclock]="protected"
    [hyprland]="protected"      [pipewire]="protected"    [python3]="protected"
    [ffmpeg]="protected"        [curl]="protected"        [jq]="protected"
)

DEP_PKG_MANAGER=""   # pacman | apt | dnf | zypper | ""
DEP_DISTRO_ID=""
DEP_DISTRO_ID_LIKE=""
DEP_AUR_HELPER=""     # yay | paru | ""

# Same detection as install.sh's detect_distro/detect_package_manager,
# scoped to this script under a dep_ prefix so nothing here can collide
# with (or drift from) install.sh if the two are ever loaded together.
dep_detect_distro() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DEP_DISTRO_ID="${ID:-unknown}"
        DEP_DISTRO_ID_LIKE="${ID_LIKE:-}"
    else
        DEP_DISTRO_ID="unknown"
        DEP_DISTRO_ID_LIKE=""
    fi
}

dep_detect_package_manager() {
    case "$DEP_DISTRO_ID" in
        arch|cachyos|endeavouros|manjaro|garuda) DEP_PKG_MANAGER="pacman" ;;
        ubuntu|debian|pop|linuxmint|elementary|zorin) DEP_PKG_MANAGER="apt" ;;
        fedora|rhel|rocky|almalinux|centos) DEP_PKG_MANAGER="dnf" ;;
        opensuse*|suse|sles) DEP_PKG_MANAGER="zypper" ;;
        *) DEP_PKG_MANAGER="" ;;
    esac
    if [ -z "$DEP_PKG_MANAGER" ] && [ -n "$DEP_DISTRO_ID_LIKE" ]; then
        case "$DEP_DISTRO_ID_LIKE" in
            *arch*)          DEP_PKG_MANAGER="pacman" ;;
            *debian*)        DEP_PKG_MANAGER="apt" ;;
            *fedora*|*rhel*) DEP_PKG_MANAGER="dnf" ;;
            *suse*)          DEP_PKG_MANAGER="zypper" ;;
        esac
    fi
    if [ -z "$DEP_PKG_MANAGER" ]; then
        if command -v pacman   >/dev/null 2>&1; then DEP_PKG_MANAGER="pacman"
        elif command -v apt-get >/dev/null 2>&1; then DEP_PKG_MANAGER="apt"
        elif command -v dnf     >/dev/null 2>&1; then DEP_PKG_MANAGER="dnf"
        elif command -v zypper  >/dev/null 2>&1; then DEP_PKG_MANAGER="zypper"
        fi
    fi
}

dep_detect_aur_helper() {
    if command -v yay >/dev/null 2>&1; then
        DEP_AUR_HELPER="yay"
    elif command -v paru >/dev/null 2>&1; then
        DEP_AUR_HELPER="paru"
    else
        DEP_AUR_HELPER=""
    fi
}

dep_get_package_name() {
    local key="$1"
    case "$DEP_PKG_MANAGER" in
        pacman) printf '%s' "${PKG_PACMAN[$key]:-}" ;;
        apt)    printf '%s' "${PKG_APT[$key]:-}"    ;;
        dnf)    printf '%s' "${PKG_DNF[$key]:-}"    ;;
        zypper) printf '%s' "${PKG_ZYPPER[$key]:-}" ;;
        *)      printf '%s' ""                      ;;
    esac
}

# Ordered, de-duplicated list of pkg_keys from DEP_TABLE (two rows --
# ffmpeg/ffprobe -- share the "ffmpeg" key, so this collapses to one).
dep_all_keys() {
    local label cmd req pkgkey
    while IFS='|' read -r label cmd req pkgkey; do
        [ -z "$pkgkey" ] && continue
        case " ${DEP_SEEN_KEYS:-} " in
            *" $pkgkey "*) ;;
            *) DEP_SEEN_KEYS="${DEP_SEEN_KEYS:-} $pkgkey"; echo "$pkgkey" ;;
        esac
    done <<< "$DEP_TABLE"
}

# True if ANY check-command associated with this pkg_key is on PATH.
dep_pkg_installed() {
    local key="$1" label cmd req pkgkey
    while IFS='|' read -r label cmd req pkgkey; do
        [ "$pkgkey" = "$key" ] || continue
        command -v "$cmd" >/dev/null 2>&1 && return 0
    done <<< "$DEP_TABLE"
    return 1
}

# Actually removes one package via the detected package manager. Never
# called except after an explicit y/Y confirmation from one of the menu
# flows below, and never on a "protected" key -- callers filter those out
# before this is ever reached.
remove_dependency_pkg() {
    local key="$1" pkg
    pkg="$(dep_get_package_name "$key")"

    if [ -z "$pkg" ]; then
        warn "No known package for '$key' on this distro -- remove it manually if desired."
        return 1
    fi
    [[ "$pkg" == AUR:* ]] && pkg="${pkg#AUR:}"

    info "Removing $key ($pkg)..."
    local status=0
    case "$DEP_PKG_MANAGER" in
        pacman) sudo pacman -Rns --noconfirm "$pkg"        || status=$? ;;
        apt)    sudo apt-get remove -y "$pkg"               || status=$? ;;
        dnf)    sudo dnf remove -y "$pkg"                   || status=$? ;;
        zypper) sudo zypper --non-interactive remove "$pkg" || status=$? ;;
        *)
            warn "No supported package manager detected -- cannot remove $key automatically."
            return 1
            ;;
    esac
    if [ "$status" -ne 0 ]; then
        error "Failed to remove $key (sudo cancelled, package not found, or a dependency conflict)."
        return 1
    fi
    ok "$key removed"
}

# Splits "1 3 7" / "01 03 07" / "1,3,7" / "01,03,07" into clean 1-based
# indices, ignoring blanks. Duplicate/invalid entries are filtered by the
# caller (which knows the valid index range) rather than here.
dep_normalize_numbers() {
    local raw="$1" tok
    raw="${raw//,/ }"
    for tok in $raw; do
        [[ "$tok" =~ ^[0-9]+$ ]] || continue
        printf '%d\n' "$((10#$tok))"
    done
}

# Prints the "Installed dependencies" list grouped under "Optional
# (advanced)" and "Protected" headers, and fills the global DEP_NUM_KEYS
# array (index 1..N -> pkg_key) used to resolve the numbers a user types
# back in the select-remove / select-keep flows.
#
# Only "optional" packages get a [NN] number -- they're the only ones a
# user can ever type a selection for. "protected" packages are listed
# for visibility only, with no number attached, so they are structurally
# unselectable rather than merely rejected after the fact. (The class
# check in dep_action_select_remove/keep is kept anyway, as a second,
# belt-and-braces safeguard.)
DEP_NUM_KEYS=()
dep_print_numbered_list() {
    DEP_NUM_KEYS=()
    echo ""
    echo "Installed dependencies"
    divider
    echo ""

    local key n=0
    local -a optional_keys=() protected_keys=()
    for key in "${DEP_INSTALLED_KEYS[@]}"; do
        if [ "${DEP_CLASS[$key]:-protected}" = "optional" ]; then
            optional_keys+=("$key")
        else
            protected_keys+=("$key")
        fi
    done

    if [ "${#optional_keys[@]}" -gt 0 ]; then
        echo "Optional (advanced)"
        for key in "${optional_keys[@]}"; do
            n=$((n + 1))
            DEP_NUM_KEYS[$n]="$key"
            printf "  [%02d] %s %s\n" "$n" "$SYM_BULLET" "$key"
        done
        echo ""
    fi

    if [ "${#protected_keys[@]}" -gt 0 ]; then
        echo "Protected"
        for key in "${protected_keys[@]}"; do
            printf "       %s %s\n" "$SYM_BULLET" "$key"
        done
        echo ""
    fi
}

# ─── Menu actions ───────────────────────────────────────────────────────

dep_action_remove_all() {
    local key optional_keys=()
    for key in "${DEP_INSTALLED_KEYS[@]}"; do
        [ "${DEP_CLASS[$key]:-protected}" = "optional" ] && optional_keys+=("$key")
    done

    if [ "${#optional_keys[@]}" -eq 0 ]; then
        info "No optional packages installed -- nothing to do."
        return
    fi

    echo ""
    warn "Warning"
    echo "  The following optional packages will be removed:"
    for key in "${optional_keys[@]}"; do
        printf "    %s %s\n" "$SYM_ERR" "$key"
    done
    echo ""
    info "Protected packages will be kept."
    echo ""

    if ! lw_confirm "Continue?"; then
        info "Removal cancelled -- no changes made."
        return
    fi

    for key in "${optional_keys[@]}"; do
        remove_dependency_pkg "$key" || true
    done
}

dep_action_keep_all() {
    ok "All dependencies will be kept."
}

dep_action_select_remove() {
    local presupplied="$1" raw
    dep_print_numbered_list
    if [ -n "$presupplied" ]; then
        raw="$presupplied"
    else
        read -r -p "  Enter package numbers to remove:
  > " raw
    fi

    local -A seen=()
    local -a to_remove=()
    local num key cls
    while IFS= read -r num; do
        [ -z "$num" ] && continue
        if [ "$num" -lt 1 ] || [ "$num" -gt "${#DEP_NUM_KEYS[@]}" ]; then
            warn "Ignoring invalid selection: $num"
            continue
        fi
        [ -n "${seen[$num]:-}" ] && continue
        seen[$num]=1
        key="${DEP_NUM_KEYS[$num]}"
        cls="${DEP_CLASS[$key]:-protected}"
        if [ "$cls" != "optional" ]; then
            warn "$key is protected and will NOT be removed."
            continue
        fi
        to_remove+=("$key")
    done < <(dep_normalize_numbers "$raw")

    if [ "${#to_remove[@]}" -eq 0 ]; then
        info "No optional packages selected -- nothing to do."
        return
    fi

    echo ""
    echo "Removal plan"
    divider
    echo ""
    for key in "${to_remove[@]}"; do
        printf "  %s %s\n" "$SYM_ERR" "$key"
    done
    echo ""
    echo "All other packages will be kept."
    echo ""

    if ! lw_confirm "Continue?"; then
        info "Removal cancelled -- no changes made."
        return
    fi

    for key in "${to_remove[@]}"; do
        remove_dependency_pkg "$key" || true
    done
}

dep_action_select_keep() {
    local presupplied="$1" raw
    dep_print_numbered_list
    if [ -n "$presupplied" ]; then
        raw="$presupplied"
    else
        read -r -p "  Enter package numbers to keep:
  > " raw
    fi

    local -A seen=() keep_set=()
    local num key
    while IFS= read -r num; do
        [ -z "$num" ] && continue
        if [ "$num" -lt 1 ] || [ "$num" -gt "${#DEP_NUM_KEYS[@]}" ]; then
            warn "Ignoring invalid selection: $num"
            continue
        fi
        [ -n "${seen[$num]:-}" ] && continue
        seen[$num]=1
        keep_set["${DEP_NUM_KEYS[$num]}"]=1
    done < <(dep_normalize_numbers "$raw")

    local -a keep_list=() remove_list=()
    for key in "${DEP_INSTALLED_KEYS[@]}"; do
        if [ -n "${keep_set[$key]:-}" ]; then
            keep_list+=("$key")
        elif [ "${DEP_CLASS[$key]:-protected}" = "optional" ]; then
            remove_list+=("$key")
        fi
        # protected keys not explicitly kept are simply never added to
        # remove_list -- they are always kept, silently.
    done

    echo ""
    echo "Keep:"
    for key in "${keep_list[@]}"; do
        printf "  %s %s\n" "$SYM_OK" "$key"
    done
    echo ""
    echo "Remove:"
    if [ "${#remove_list[@]}" -eq 0 ]; then
        printf "  %s (none)\n" "$SYM_BULLET"
    else
        for key in "${remove_list[@]}"; do
            printf "  %s %s\n" "$SYM_ERR" "$key"
        done
    fi
    echo ""

    if [ "${#remove_list[@]}" -eq 0 ]; then
        info "Nothing to remove."
        return
    fi

    if ! lw_confirm "Continue?"; then
        info "Removal cancelled -- no changes made."
        return
    fi

    for key in "${remove_list[@]}"; do
        remove_dependency_pkg "$key" || true
    done
}

dep_action_cancel() {
    info "Cancelled -- no changes made."
}

# Top-level entry point for the optional dependency cleanup stage. Safe
# to skip entirely (non-TTY, or nothing tracked/installed) -- it never
# touches anything on its own.
dependency_cleanup_stage() {
    step "Dependency cleanup"

    if [ ! -t 0 ]; then
        info "Non-interactive shell detected -- skipping dependency cleanup (all kept)."
        return
    fi

    dep_detect_distro
    dep_detect_package_manager
    dep_detect_aur_helper

    DEP_INSTALLED_KEYS=()
    local key
    while IFS= read -r key; do
        dep_pkg_installed "$key" && DEP_INSTALLED_KEYS+=("$key")
    done < <(dep_all_keys)

    if [ "${#DEP_INSTALLED_KEYS[@]}" -eq 0 ]; then
        info "No tracked dependencies detected on this system -- nothing to clean up."
        return
    fi

    echo ""
    echo "Dependency Cleanup"
    divider
    echo ""
    echo "Choose what to do with installed dependencies."
    echo ""
    echo "  [a]  Remove all optional packages"
    echo "  [n]  Keep all packages"
    echo "  [s]  Select packages to remove"
    echo "  [k]  Select packages to keep"
    echo "  [q]  Cancel"
    echo ""

    local line choice rest
    read -r -p "  Choice [n]: " line
    line="${line:-n}"
    choice="${line%% *}"
    if [ "$line" != "$choice" ]; then rest="${line#* }"; else rest=""; fi

    echo ""
    case "$choice" in
        a|A) dep_action_remove_all ;;
        s|S) dep_action_select_remove "$rest" ;;
        k|K) dep_action_select_keep "$rest" ;;
        q|Q) dep_action_cancel ;;
        n|N|"") dep_action_keep_all ;;
        *)
            warn "Unrecognized choice '$choice' -- keeping all dependencies."
            dep_action_keep_all
            ;;
    esac
}

# ─── Step 0: Stop Quickshell (Live Wallpaper Manager UI) ──────────────────
# Must run first and before any file is touched: as long as Quickshell is
# alive it can be holding the panel/shortcut open, and mpvpaper
# can be re-spawned by LWM's own service code faster than we remove them.
# Stopping Quickshell first means every later step tears down an already-
# quiescent system instead of racing a live one.
step "Checking for a running Live Wallpaper Manager (Quickshell)"
if quickshell_running; then
    warn "Live Wallpaper Manager is currently running."
    read -r -p "  Stop Quickshell before uninstalling? [Y/n] " ans
    ans="${ans:-Y}"
    case "${ans,,}" in
        y|yes)
            info "Stopping Quickshell (pkill quickshell)..."
            pkill quickshell 2>/dev/null || true

            waited=0
            while quickshell_running && [ "$waited" -lt 5 ]; do
                sleep 1
                waited=$((waited + 1))
            done

            if quickshell_running; then
                warn "Quickshell did not exit within 5s — forcing (pkill -9 quickshell)..."
                pkill -9 quickshell 2>/dev/null || true
                sleep 1
            fi

            if quickshell_running; then
                error "Could not stop Quickshell. Aborting uninstall so no files are removed out from under a running instance."
                exit 1
            fi
            ok "Quickshell stopped"
            ;;
        *)
            warn "Uninstall aborted — Quickshell is still running."
            exit 1
            ;;
    esac
else
    info "Quickshell is not running — continuing"
fi

# ─── Step 1: Stop mpvpaper ─────────────────────────────────────────────────
step "Stopping mpvpaper (if running)"
pkill -x mpvpaper 2>/dev/null && ok "mpvpaper stopped" || info "mpvpaper was not running"

# ─── Step 1b: Stop Music Dock (cava + MPRIS listener) ──────────────────────
# Quickshell itself was already stopped in Step 0 (which is what actually
# owns Music Dock's overlay window and its CavaService/MprisService
# Process objects), but cava and the MPRIS worker are separate detached
# processes started via scripts/start_cava.sh / _mpris_worker.sh, so they
# need their own explicit stop here rather than assuming Quickshell
# exiting took them down too.
step "Stopping Music Dock (cava visualizer)"
if [ -f "$LWM_DEST/scripts/stop_cava.sh" ]; then
    bash "$LWM_DEST/scripts/stop_cava.sh" "$HOME/.cache/livewallpaper/musicdock/cava.fifo" >/dev/null 2>&1 \
        && ok "cava stopped" || warn "stop_cava.sh reported an issue (non-fatal)"
else
    pkill -x cava 2>/dev/null && ok "cava stopped" || info "cava was not running"
fi
pkill -f "playerctl --all-players --follow" 2>/dev/null || true
pkill -f "_mpris_worker.sh" 2>/dev/null || true

# Music Dock's own temporary files (FIFO, generated cava.conf, pid, log)
# are pure ephemeral runtime state -- regenerated fresh every time Music
# Dock starts, never anything the user would consider "data" -- so this
# one subdirectory is cleaned up unconditionally here, same as killing
# the processes above. This does NOT touch the rest of
# ~/.cache/livewallpaper (thumbnails, history-adjacent state, logs),
# which is real cache content and stays behind the confirmation prompt
# in Step 4 below like every other project directory.
rm -rf "$HOME/.cache/livewallpaper/musicdock" 2>/dev/null || true
ok "Music Dock temporary runtime files removed"

# ─── Step 1c: Stop system tray helper (PHASE 4) ────────────────────────────
# Quickshell (Step 0) stopping should already take TrayService's Process
# down with it, but the tray helper is a separate detached process (same
# reasoning as cava/MPRIS above), so it gets its own explicit stop too.
step "Stopping system tray helper"
pkill -f "_tray_icon.py" 2>/dev/null && ok "System tray helper stopped" || info "System tray helper was not running"

# ─── Step 2: Remove program files (desktop entries and icon) ───────────────
# None of this is user config/data -- it's registration files this
# project's own installer wrote (Step 0-2 above already made sure nothing
# is still running that would recreate them), so these are removed
# unconditionally, same as any normal uninstaller cleaning up after
# itself. Your actual config/data directories are handled separately
# below and always ask first.
step "Removing desktop entries, icon, and autostart entry"
rm -f "$HOME/.local/share/applications/live-wallpaper-manager.desktop"
rm -f "$HOME/.local/share/applications/live-wallpaper-manager-app.desktop"
rm -f "$HOME/.local/share/icons/hicolor/scalable/apps/live-wallpaper-manager-app.svg"
for sz in 16x16 22x22 24x24 32x32 48x48 64x64 96x96 128x128 192x192 256x256 512x512; do
    rm -f "$HOME/.local/share/icons/hicolor/$sz/apps/live-wallpaper-manager-app.png"
done
rm -f "$HOME/.local/share/pixmaps/live-wallpaper-manager-app.png"
command -v gtk-update-icon-cache >/dev/null 2>&1 && \
    gtk-update-icon-cache -f -q "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
rm -f "$HOME/.config/autostart/live-wallpaper-manager.desktop"
ok "Desktop entries, icon, and autostart entry removed"

# ═══════════════════════════════════════════════════════════════════════
# Step 4: Config/data directories -- confirmation required, one at a time
# ═══════════════════════════════════════════════════════════════════════
# Detect ONLY the project-specific directories this project actually
# creates/uses that still exist on disk -- nothing here is guessed or
# pattern-matched, and nothing outside this fixed list is ever
# considered. Directories that don't exist are simply left off the list
# (see UNINSTALL TEST case 4: a missing directory is not an error).
step "Configuration and data directories"

declare -a CANDIDATE_PATHS=()
declare -a CANDIDATE_LABELS=()

if [ -e "$LWM_DEST" ]; then
    CANDIDATE_PATHS+=("$LWM_DEST")
    CANDIDATE_LABELS+=("Live Wallpaper Manager config + data ($LWM_DEST)")
fi
if [ -e "$LWM_CACHE_DIR" ]; then
    CANDIDATE_PATHS+=("$LWM_CACHE_DIR")
    CANDIDATE_LABELS+=("Live Wallpaper Manager cache ($LWM_CACHE_DIR)")
fi

if [ "${#CANDIDATE_PATHS[@]}" -eq 0 ]; then
    info "No Live Wallpaper Manager config/data directories found — nothing to ask about."
else
    echo ""
    info "Found the following project directories:"
    for lbl in "${CANDIDATE_LABELS[@]}"; do
        info "  $SYM_BULLET $lbl"
    done
    echo ""
    warn "Nothing below is removed unless you explicitly say yes."
    echo ""

    remove_all=0
    if lw_confirm "Remove ALL of the directories listed above?"; then
        remove_all=1
    fi

    for i in "${!CANDIDATE_PATHS[@]}"; do
        path="${CANDIDATE_PATHS[$i]}"
        label="${CANDIDATE_LABELS[$i]}"
        if [ "$remove_all" -eq 1 ]; then
            do_remove=1
        elif lw_confirm "Remove $label?"; then
            do_remove=1
        else
            do_remove=0
        fi

        if [ "$do_remove" -eq 1 ]; then
            lw_safe_rmrf "$path" "$label"
        else
            info "Kept: $label"
        fi
    done
fi

# ═══════════════════════════════════════════════════════════════════════
# Step 5: Dependency cleanup -- optional, additional stage
# ═══════════════════════════════════════════════════════════════════════
# Entirely separate from Step 4 above: Step 4 only ever touches this
# project's own config/data directories; this step only ever touches
# system packages, and only the ones classified "optional" in
# DEP_CLASS -- protected packages are never removed by any path through
# this stage, no matter what's selected.
dependency_cleanup_stage

echo ""
warn "If you added a hyprland.start wrapper (hl.on(\"hyprland.start\", ...)"
warn "-> hl.exec_cmd(\"quickshell -c livewallpaper -n\")) to hyprland.lua, or the"
warn "legacy 'exec-once = quickshell -c livewallpaper' to hyprland.conf, or"
warn "embedded this module into a Caelestia shell.qml, remove those lines manually."
echo ""
ok "Uninstall complete."
