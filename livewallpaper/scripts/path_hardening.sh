#!/usr/bin/env bash
#
# path_hardening.sh
# -----------------------------------------------------------------------------
# Sanitize + authorize wallpaper path.
#
# API:
#   lw_harden_wallpaper_path <candidate> [allowed_root]
#
# realpath -e is a mandatory primitive: candidate and allowed_root must
# both exist before comparing canonical paths. NixOS dynamic symlinks are
# accepted if the final target remains inside the wallpaper root; symlinks
# pointing outside are rejected. Do not use realpath -m because it can
# legitimize non-existent targets.

set -uo pipefail

lw_ph_detect_distro() {
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        printf '%s\n' "${ID:-unknown}"
    else
        printf '%s\n' "unknown"
    fi
}

lw_ph_is_nix() {
    command -v nix-store >/dev/null 2>&1 ||
    [ -d /nix/store ] ||
    [ -n "${IN_NIX_SHELL:-}" ]
}

lw_ph_wallpaper_root() {
    local root="${LW_WALLPAPER_DIR:-}"

    if [ -z "$root" ] && [ -n "${LW_SETTINGS_FILE:-}" ] && [ -s "$LW_SETTINGS_FILE" ] && command -v jq >/dev/null 2>&1; then
        root="$(jq -r '.wallpaper_directory // empty' "$LW_SETTINGS_FILE" 2>/dev/null || true)"
    fi

    if [ -z "$root" ] && [ -n "${LW_DATA_DIR:-}" ]; then
        local settings="$LW_DATA_DIR/settings.json"
        if [ -s "$settings" ] && command -v jq >/dev/null 2>&1; then
            root="$(jq -r '.wallpaper_directory // empty' "$settings" 2>/dev/null || true)"
        fi
    fi

    root="${root:-$HOME/Pictures/Live Wallpaper}"

    case "$root" in
        "~") root="$HOME" ;;
        "~/"*) root="$HOME/${root#~/}" ;;
    esac

    printf '%s\n' "$root"
}

lw_ph_canonical_existing() {
    command -v realpath >/dev/null 2>&1 || return 127
    realpath -e -- "$1" 2>/dev/null
}

lw_harden_wallpaper_path() {
    local candidate="${1:-}"
    local allowed_root="${2:-}"
    local canonical_candidate canonical_root relative

    [ -n "$candidate" ] || return 2

    if [ -z "$allowed_root" ]; then
        allowed_root="$(lw_ph_wallpaper_root)"
    fi

    # ~ expansion only applies after path is taken from config; no shell eval.
    case "$candidate" in
        "~") candidate="$HOME" ;;
        "~/"*) candidate="$HOME/${candidate#~/}" ;;
    esac

    case "$allowed_root" in
        "~") allowed_root="$HOME" ;;
        "~/"*) allowed_root="$HOME/${allowed_root#~/}" ;;
    esac

    canonical_root="$(lw_ph_canonical_existing "$allowed_root")" || return 3
    canonical_candidate="$(lw_ph_canonical_existing "$candidate")" || return 4

    [ -f "$canonical_candidate" ] || return 5
    [ -r "$canonical_candidate" ] || return 6

    # To avoid prefix bypass (e.g. /wallpaper vs /wallpaper-evil), use a
    # boundary component check via case instead of startswith.
    case "$canonical_candidate" in
        "$canonical_root"/*)
            ;;
        *)
            return 7
            ;;
    esac

    relative="${canonical_candidate#"$canonical_root"/}"
    [ "$relative" != "$canonical_candidate" ] || return 8
    [ -n "$relative" ] || return 9

    # realpath already strips ../, but keep defense-in-depth check if caller
    # supplies a weird path from an old data file.
    case "/$relative/" in
        */../*|*/./*) return 10 ;;
    esac

    printf '%s\n' "$canonical_candidate"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
        echo "Usage: $0 <wallpaper-path> [allowed-root]" >&2
        exit 2
    fi

    if result="$(lw_harden_wallpaper_path "$1" "${2:-}" 2>/dev/null)"; then
        printf '%s\n' "$result"
        exit 0
    fi

    echo "Rejected wallpaper path: $1" >&2
    exit 1
fi
