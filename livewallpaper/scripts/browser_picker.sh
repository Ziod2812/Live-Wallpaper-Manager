#!/usr/bin/env bash
#
# browser_picker.sh <list|launch> [args...]
# -------------------------------------------
# Backend for the "choose a browser" popup on Performance > File Converter
# (Services/BrowserPickerService.qml -> Components/FileConverterPanel.qml).
# Previously "Open File Converter" always went straight through
# Qt.openUrlExternally(), i.e. whatever the desktop's single default
# browser happened to be. This lets the user pick which installed browser
# opens the link instead.
#
#   browser_picker.sh list
#       Scans the standard XDG application directories for installed
#       browser .desktop entries -- matched via Categories=...WebBrowser...,
#       falling back to an allow-list of common browser desktop-file
#       basenames for the handful of real-world browsers that ship
#       incomplete Categories -- and prints a JSON array:
#         [{"id":"firefox.desktop","name":"Firefox","exec":"firefox %u","icon":"firefox"}, ...]
#       Deduplicated by desktop id (first match wins, and
#       _lw_browser_app_dirs lists user-level dirs before system-level
#       ones, so a user override shadows the system entry same as any
#       XDG_DATA_DIRS lookup would). NoDisplay=true / Hidden=true entries
#       are skipped. When `xdg-settings` is available, the system default
#       browser (if it's actually in the detected list) is moved to the
#       front purely as a display-order nicety -- never required for
#       correctness.
#
#   browser_picker.sh launch <desktop-id> <url>
#       Re-resolves <desktop-id> the same way `list` does (never trusts a
#       stale Exec= string handed back from the QML side) and launches it
#       detached (setsid ... & disown), same pattern open_app.sh already
#       uses for the shell itself. %u/%U in Exec= is substituted with
#       <url>; every other field code (%f %F %d %D %n %N %i %c %k %v %m)
#       is dropped since a browser launched this way never has a
#       file/desktop-file/tracker id to hand it; if Exec= has no %u/%U at
#       all, <url> is simply appended. Exits non-zero with no side effects
#       if <desktop-id> can't be found any more (e.g. uninstalled between
#       list and launch).
#
# NOTE ON Exec= PARSING: this does a plain whitespace split, not full
# Desktop Entry Spec quote/backslash handling -- sufficient for every
# real-world browser Exec= line (a bare binary name or absolute path plus
# %u/%U and the odd fixed flag), but a hand-edited Exec= using quoted
# arguments with embedded spaces is not something this script attempts to
# parse correctly.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Matched against a .desktop file's basename (without ".desktop") ONLY
# when its Categories doesn't already declare WebBrowser.
_LW_BROWSER_FALLBACK_RE='^(firefox|firefox-esr|librewolf|waterfox|floorp|zen|chromium|chromium-browser|google-chrome|google-chrome-stable|google-chrome-beta|google-chrome-unstable|brave-browser|brave|vivaldi-stable|vivaldi|opera|opera-stable|opera-beta|microsoft-edge|microsoft-edge-stable|microsoft-edge-beta|microsoft-edge-dev|epiphany|org\.gnome\.Epiphany|falkon|qutebrowser|midori|konqueror|thorium-browser|ungoogled-chromium|io\.gitlab\.librewolf-community)$'

# Lowest-to-highest precedence is NOT what this prints -- it prints
# user-level dirs FIRST so the dedup loop in _lw_browser_list_json (first
# id seen wins) lets a user-level override shadow a system-level entry of
# the same desktop id, matching normal XDG app-dir shadowing semantics.
_lw_browser_app_dirs() {
    local dirs=()
    [ -n "${XDG_DATA_HOME:-}" ] && dirs+=("$XDG_DATA_HOME/applications")
    dirs+=("$HOME/.local/share/applications")
    dirs+=("$HOME/.local/share/flatpak/exports/share/applications")
    if [ -n "${XDG_DATA_DIRS:-}" ]; then
        local dir
        local IFS=:
        for dir in $XDG_DATA_DIRS; do dirs+=("$dir/applications"); done
    else
        dirs+=("/usr/local/share/applications" "/usr/share/applications")
    fi
    dirs+=("/var/lib/flatpak/exports/share/applications")
    printf '%s\n' "${dirs[@]}"
}

# _lw_browser_desktop_entry_json <file> <id> -> one JSON object, or
# nothing if <file> isn't a displayable browser entry.
_lw_browser_desktop_entry_json() {
    local file="$1" id="$2"
    [ -r "$file" ] || return 0

    local in_entry=0 name="" exec="" icon="" categories="" nodisplay="false" hidden="false" line
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            "[Desktop Entry]") in_entry=1; continue ;;
            "["*"]") in_entry=0; continue ;;
        esac
        [ "$in_entry" -eq 1 ] || continue
        case "$line" in
            Name=*) [ -z "$name" ] && name="${line#Name=}" ;;
            Exec=*) exec="${line#Exec=}" ;;
            Icon=*) icon="${line#Icon=}" ;;
            Categories=*) categories="${line#Categories=}" ;;
            NoDisplay=*) nodisplay="${line#NoDisplay=}" ;;
            Hidden=*) hidden="${line#Hidden=}" ;;
        esac
    done < "$file"

    [ -n "$name" ] && [ -n "$exec" ] || return 0
    [ "$nodisplay" = "true" ] && return 0
    [ "$hidden" = "true" ] && return 0

    local base="${id%.desktop}"
    case "$categories" in
        *WebBrowser*) : ;;
        *) echo "$base" | grep -Eq "$_LW_BROWSER_FALLBACK_RE" || return 0 ;;
    esac

    jq -cn --arg id "$id" --arg name "$name" --arg exec "$exec" --arg icon "$icon" \
        '{id:$id, name:$name, exec:$exec, icon:$icon}'
}

_lw_browser_list_json() {
    local -A seen=()
    local items=() dir file id entry list_json default_id

    while IFS= read -r dir; do
        [ -d "$dir" ] || continue
        while IFS= read -r -d '' file; do
            id="$(basename "$file")"
            [ -n "${seen[$id]:-}" ] && continue
            entry="$(_lw_browser_desktop_entry_json "$file" "$id")"
            [ -n "$entry" ] || continue
            seen[$id]=1
            items+=("$entry")
        done < <(find "$dir" -maxdepth 1 -name '*.desktop' -print0 2>/dev/null)
    done < <(_lw_browser_app_dirs)

    list_json="[]"
    if [ "${#items[@]}" -gt 0 ]; then
        list_json="$(IFS=,; echo "[${items[*]}]")"
    fi

    default_id=""
    if command -v xdg-settings >/dev/null 2>&1; then
        default_id="$(xdg-settings get default-web-browser 2>/dev/null | tr -d '[:space:]')"
    fi

    if [ -n "$default_id" ]; then
        jq -c --arg d "$default_id" \
            '(map(select(.id == $d)) + map(select(.id != $d)))' \
            <<< "$list_json"
    else
        echo "$list_json"
    fi
}

# _lw_browser_resolve_exec <desktop-id> -> prints its Exec= value, or
# nothing if <desktop-id> can't be found / isn't a browser entry.
_lw_browser_resolve_exec() {
    local target_id="$1" dir file
    while IFS= read -r dir; do
        [ -d "$dir" ] || continue
        file="$dir/$target_id"
        [ -r "$file" ] || continue
        _lw_browser_desktop_entry_json "$file" "$target_id" | jq -r '.exec // empty'
        return 0
    done < <(_lw_browser_app_dirs)
}

# _lw_browser_build_argv <exec-line> <url> -> one argv token per line,
# suitable for `mapfile -t argv < <(...)`. See header's "NOTE ON Exec="
# for the whitespace-split limitation.
_lw_browser_build_argv() {
    local exec_line="$1" url="$2" tok used=0
    local -a toks out=()
    read -ra toks <<< "$exec_line"
    for tok in "${toks[@]}"; do
        case "$tok" in
            %u|%U) out+=("$url"); used=1 ;;
            %f|%F|%d|%D|%n|%N|%i|%c|%k|%v|%m) continue ;;
            %%) out+=("%") ;;
            *) out+=("$tok") ;;
        esac
    done
    [ "$used" -eq 1 ] || out+=("$url")
    printf '%s\n' "${out[@]}"
}

cmd="${1:-list}"
case "$cmd" in
    list)
        _lw_browser_list_json
        ;;
    launch)
        target_id="${2:-}"
        url="${3:-}"
        if [ -z "$target_id" ] || [ -z "$url" ]; then
            lw_log_error "browser_picker.sh launch: missing <desktop-id> or <url>"
            exit 1
        fi
        exec_line="$(_lw_browser_resolve_exec "$target_id")"
        if [ -z "$exec_line" ]; then
            lw_log_error "browser_picker.sh launch: '$target_id' not found (uninstalled since list?)"
            exit 1
        fi
        mapfile -t argv < <(_lw_browser_build_argv "$exec_line" "$url")
        if [ "${#argv[@]}" -eq 0 ]; then
            lw_log_error "browser_picker.sh launch: empty Exec= for '$target_id'"
            exit 1
        fi
        lw_log_info "browser_picker.sh: launching ${argv[*]}"
        setsid "${argv[@]}" < /dev/null > /dev/null 2>&1 &
        disown
        ;;
    *)
        lw_log_error "browser_picker.sh: unknown command '$cmd' (expected list|launch)"
        exit 1
        ;;
esac
