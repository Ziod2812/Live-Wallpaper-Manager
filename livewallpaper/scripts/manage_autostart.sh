#!/usr/bin/env bash
#
# manage_autostart.sh
# ----------------------
# PHASE 4 -- "Autostart" (launch the Quickshell shell itself on login).
#
# Manages TWO autostart mechanisms together so the Settings toggle
# actually survives a reboot regardless of desktop environment:
#
#   1. A standard XDG autostart entry at
#      ~/.config/autostart/live-wallpaper-manager.desktop -- picked up
#      automatically by every DE/session manager that follows the
#      freedesktop autostart spec.
#
#   2. A Hyprland-native autostart line, because Hyprland itself does
#      NOT read ~/.config/autostart -- (1) alone is a silent no-op on a
#      bare Hyprland session. Written into whichever of these the user
#      actually has, preferring the newer Lua config if both exist:
#        ~/.config/hypr/hyprland.lua   -> hl.on("hyprland.start", ...) wrapper
#        ~/.config/hypr/hyprland.conf  -> legacy `exec-once = ...` line
#      Neither file is required to exist -- if the user isn't on
#      Hyprland (or hasn't set up hypr/ yet), this step is skipped
#      entirely and only the XDG entry above is written.
#
# Usage:
#   manage_autostart.sh status            -> prints "enabled" or "disabled"
#   manage_autostart.sh enable
#   manage_autostart.sh disable
#
# Idempotent: re-running enable/disable never produces duplicate lines
# or duplicate markers, and only ever touches text between this
# script's own markers -- the rest of hyprland.conf/hyprland.lua is
# left byte-for-byte alone. A one-time ".lwm-bak" copy of each Hyprland
# config file is made before its first edit, so the original is always
# recoverable.
#
# -n/--no-duplicate on the generated Exec/exec-once/hl.exec_cmd lines
# below: since both mechanisms are now written together, both can fire
# at login on setups where something else also reads ~/.config/autostart
# under Hyprland. Without -n, quickshell has no default single-instance
# guard of its own and would happily start a second, independent
# process -- two ManagerWindows, two tray icons, and `ipc call`
# becoming ambiguous between them. -n makes the loser of that race exit
# immediately instead, which is a correct no-op since the other
# instance is already up.

set -uo pipefail

AUTOSTART_DIR="$HOME/.config/autostart"
AUTOSTART_FILE="$AUTOSTART_DIR/live-wallpaper-manager.desktop"

HYPR_CONF="$HOME/.config/hypr/hyprland.conf"
HYPR_LUA="$HOME/.config/hypr/hyprland.lua"

MARK_TAG="live-wallpaper-manager autostart"
MARK_BEGIN_RE="^[[:space:]]*(#|--) >>> $MARK_TAG >>>"
MARK_END_RE="^[[:space:]]*(#|--) <<< $MARK_TAG <<<"

# One-time backup of a Hyprland config file before this script edits it
# for the first time, so `enable`/`disable` can never be the only copy
# of the user's original config.
_backup_once() {
    local f="$1"
    local bak="${f}.lwm-bak"
    [ -f "$f" ] && [ ! -f "$bak" ] && cp "$f" "$bak"
}

# Strip any existing managed block (idempotent -- safe even if absent).
_strip_block() {
    local f="$1"
    [ -f "$f" ] || return 0
    grep -Eq "$MARK_BEGIN_RE" "$f" || return 0
    local tmp
    tmp="$(mktemp)" || return 1
    awk -v begin="$MARK_BEGIN_RE" -v end="$MARK_END_RE" '
        $0 ~ begin { skip = 1; next }
        $0 ~ end   { skip = 0; next }
        !skip      { print }
    ' "$f" > "$tmp" && mv "$tmp" "$f"
}

# Add the managed block to a Hyprland config file, but only if:
#   - the file exists (we never create hypr/ config files ourselves), and
#   - it doesn't already mention livewallpaper in some other form (e.g.
#     a line the user added by hand from the old manual instructions --
#     don't create a second, competing entry).
_hypr_add() {
    local f="$1" kind="$2"   # kind: conf | lua
    [ -f "$f" ] || return 0
    _strip_block "$f"
    grep -qi "livewallpaper" "$f" && return 0
    _backup_once "$f"
    {
        echo ""
        if [ "$kind" = "lua" ]; then
            echo "-- >>> $MARK_TAG >>>"
            echo "hl.on(\"hyprland.start\", function() hl.exec_cmd(\"$HOME/.config/quickshell/livewallpaper/scripts/launch_quickshell.sh -c livewallpaper -n\") end)"
            echo "-- <<< $MARK_TAG <<<"
        else
            echo "# >>> $MARK_TAG >>>"
            echo "exec-once = $HOME/.config/quickshell/livewallpaper/scripts/launch_quickshell.sh -c livewallpaper -n"
            echo "# <<< $MARK_TAG <<<"
        fi
    } >> "$f"
}

_hypr_remove() {
    local f="$1"
    _strip_block "$f"
}

# Self-heal a totally separate, pre-existing problem: editing
# hyprland.conf (enable or disable, above) makes Hyprland's own
# file-watcher reload the config immediately. If the user's
# hyprland.conf already has (independent of this project) a
# `source = .../hyprland.lua` line pointing at a file that doesn't
# exist, that reload fails with "cannot open .../hyprland.lua: No such
# file or directory" -- a latent breakage this script's edit merely
# surfaces, not one it caused. Since an empty file satisfies Hyprland's
# `source` directive, create it (and its parent dir) if missing so the
# reload this script triggers can never fail on that account. Only
# acts on a target that (a) is actually named hyprland.lua and (b)
# lives under this same hypr/ config directory -- never touches an
# unrelated sourced path.
# Self-heal a totally separate, pre-existing problem: editing
# hyprland.conf (enable or disable, above) makes Hyprland's own
# file-watcher reload the config immediately. If somewhere under the
# user's hypr/ config (independent of this project -- hyprland.conf
# itself, or any *.conf it includes) there's already a `source = ...`
# line pointing at a hyprland.lua that doesn't exist, that reload fails
# with "cannot open .../hyprland.lua: No such file or directory" -- a
# latent breakage this script's edit merely surfaces, not one it
# caused. Since an empty file satisfies Hyprland's `source` directive,
# create it (and its parent dir) if missing so the reload this script
# triggers can never fail on that account.
#
# Tolerates the source-line variations Hyprland configs actually use:
# quoted paths ("...", '...'), trailing inline comments, $HOME/~
# expansion, and paths relative to hypr_dir -- and looks in every
# *.conf file under hypr/ (not just hyprland.conf itself), since a
# modular setup may source hyprland.lua from an included file instead.
_ensure_sourced_hyprland_lua_exists() {
    local hypr_dir="$HOME/.config/hypr"
    [ -d "$hypr_dir" ] || return 0

    local conf
    while IFS= read -r -d '' conf; do
        local line stripped raw target
        while IFS= read -r line || [ -n "$line" ]; do
            stripped="${line%%#*}"
            [[ "$stripped" =~ ^[[:space:]]*source[[:space:]]*=[[:space:]]*(.+)$ ]] || continue
            raw="${BASH_REMATCH[1]}"
            raw="$(printf '%s' "$raw" | sed -E 's/[[:space:]]+$//; s/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/')"
            case "$raw" in
                *hyprland.lua) : ;;
                *) continue ;;
            esac
            raw="${raw/#\~/$HOME}"
            raw="${raw//\$HOME/$HOME}"
            case "$raw" in
                /*) target="$raw" ;;
                *)  target="$hypr_dir/$raw" ;;
            esac
            if [ ! -f "$target" ]; then
                mkdir -p "$(dirname "$target")" 2>/dev/null
                : > "$target"
            fi
        done < "$conf"
    done < <(find "$hypr_dir" -maxdepth 3 -type f -name "*.conf" -print0 2>/dev/null)
}

# Force an authoritative reload right after we're done editing, instead
# of relying on Hyprland's own file-watcher to notice and reload on its
# own timing. This is what actually clears a stale error banner --
# without it, the banner can persist even after the underlying file is
# fixed, until something else (e.g. the user manually opening and
# saving a config file) triggers the next reload. No-op if hyprctl
# isn't installed or we're not actually inside a running Hyprland
# session (HYPRLAND_INSTANCE_SIGNATURE unset) -- e.g. GNOME/KDE users,
# or Hyprland not started yet.
_hyprctl_reload_if_running() {
    command -v hyprctl >/dev/null 2>&1 || return 0
    [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || return 0
    hyprctl reload >/dev/null 2>&1 || true
}

cmd="${1:-status}"

case "$cmd" in
    status)
        if [ -f "$AUTOSTART_FILE" ]; then
            echo "enabled"
        else
            echo "disabled"
        fi
        ;;
    enable)
        mkdir -p "$AUTOSTART_DIR"
        # NOTE: unquoted heredoc delimiter (DESKTOP, not 'DESKTOP') is
        # deliberate here -- it lets $HOME below expand to a real absolute
        # path at write time, since XDG autostart Exec= values are NOT
        # shell-expanded when read back by the session/DE. No other line
        # in this block contains a "$" that could be mis-expanded.
        cat > "$AUTOSTART_FILE" << DESKTOP
[Desktop Entry]
Type=Application
Name=Live Wallpaper Manager
Comment=Start the Live Wallpaper Manager background shell on login
Exec=$HOME/.config/quickshell/livewallpaper/scripts/launch_quickshell.sh -c livewallpaper -n
Icon=video-x-generic
Terminal=false
X-GNOME-Autostart-enabled=true
NoDisplay=true
DESKTOP

        # Create any missing sourced hyprland.lua FIRST -- before
        # touching hyprland.conf below. Hyprland's own file-watcher
        # reloads the config the instant hyprland.conf changes, so if
        # the sourced file were created afterwards, that first
        # reload would still hit "No such file or directory" and the
        # error banner would stick around until something else
        # triggered a second reload (this is why it previously only
        # cleared once the user manually opened+saved the file).
        _ensure_sourced_hyprland_lua_exists

        # Hyprland-native side: prefer hyprland.lua if present (newer
        # config style already documented in Settings/README), else
        # fall back to legacy hyprland.conf. Only touch whichever
        # actually exists on this machine.
        if [ -f "$HYPR_LUA" ]; then
            _hypr_add "$HYPR_LUA" "lua"
        elif [ -f "$HYPR_CONF" ]; then
            _hypr_add "$HYPR_CONF" "conf"
        fi

        _hyprctl_reload_if_running

        echo "enabled"
        ;;
    disable)
        rm -f "$AUTOSTART_FILE"
        _ensure_sourced_hyprland_lua_exists
        [ -f "$HYPR_LUA" ] && _hypr_remove "$HYPR_LUA"
        [ -f "$HYPR_CONF" ] && _hypr_remove "$HYPR_CONF"
        _hyprctl_reload_if_running
        echo "disabled"
        ;;
    *)
        echo "Usage: manage_autostart.sh {status|enable|disable}" >&2
        exit 1
        ;;
esac
