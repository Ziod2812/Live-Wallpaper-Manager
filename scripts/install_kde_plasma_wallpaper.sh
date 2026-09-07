#!/usr/bin/env bash
#
# install_kde_plasma_wallpaper.sh
# --------------------------------------------------------------------
# OPTIONAL, separate from install.sh on purpose (that installer's own
# rule is "stay functionally stable unless explicitly requested" --
# this is a distinct opt-in feature for KDE Plasma users, not something
# that should silently change what install.sh does for every distro/
# compositor).
#
# Installs kde-plasma-wallpaper/ as a real Plasma Wallpaper KPackage
# plugin under the current user's ~/.local/share/plasma/wallpapers/,
# so it shows up in System Settings > Appearance > Wallpaper (or
# right-click Desktop > Configure Desktop) as "Live Wallpaper Manager".
# See kde-plasma-wallpaper/contents/ui/main.qml for exactly what it
# does and does not support.
#
# Usage:
#   ./scripts/install_kde_plasma_wallpaper.sh          # install
#   ./scripts/install_kde_plasma_wallpaper.sh --remove # uninstall

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$PROJECT_ROOT/kde-plasma-wallpaper"
PLUGIN_ID="com.livewallpapermanager.plasmawallpaper"
DEST_DIR="$HOME/.local/share/plasma/wallpapers/$PLUGIN_ID"

if [ "${1:-}" = "--remove" ]; then
    if [ -e "$DEST_DIR" ] || [ -L "$DEST_DIR" ]; then
        rm -rf "$DEST_DIR"
        echo "Removed $DEST_DIR"
    else
        echo "Nothing installed at $DEST_DIR"
    fi
    exit 0
fi

if [ ! -f "$SRC_DIR/metadata.json" ]; then
    echo "Error: $SRC_DIR/metadata.json not found -- run this from the extracted project directory." >&2
    exit 1
fi

if ! command -v plasmashell >/dev/null 2>&1 && ! command -v kpackagetool6 >/dev/null 2>&1; then
    echo "Warning: neither plasmashell nor kpackagetool6 was found on PATH." >&2
    echo "This doesn't look like a KDE Plasma system -- continuing anyway," >&2
    echo "but the plugin will only do something under Plasma." >&2
fi

mkdir -p "$(dirname "$DEST_DIR")"

if [ -e "$DEST_DIR" ] || [ -L "$DEST_DIR" ]; then
    rm -rf "$DEST_DIR"
fi

# A real copy (not a symlink) so kpackagetool6/plasmashell's own package
# validation -- which can be picky about symlinked KPackage roots on some
# versions -- never has anything unusual to trip over.
cp -r "$SRC_DIR" "$DEST_DIR"

echo "Installed to: $DEST_DIR"
echo ""
echo "Next steps:"
echo "  1. Right-click the desktop -> Configure Desktop and Wallpaper..."
echo "     (or System Settings > Appearance > Wallpaper)"
echo "  2. Change the wallpaper type to \"Live Wallpaper Manager\"."
echo "  3. Apply a video wallpaper as usual from the Live Wallpaper Manager"
echo "     window -- this plugin mirrors whatever it currently has applied."
echo ""
echo "If it doesn't show up in the wallpaper type list, KDE may need"
echo "plasmashell restarted to notice the new package:"
echo "  plasmashell --replace &"
echo ""
echo "To remove it later: $0 --remove"
