import QtQuick
import "../Config"
import "../Services"

Row {
    id: root
    spacing: Theme.spacingSm

    IconButton {
        text: "All"
        active: WallpaperService.filterMode === "all"
        onClicked: WallpaperService.filterMode = "all"
    }
    IconButton {
        text: "★ Favorites"
        active: WallpaperService.filterMode === "favorites"
        accentColor: Theme.yellow
        onClicked: WallpaperService.filterMode = "favorites"
    }
    IconButton {
        text: "Recent"
        active: WallpaperService.filterMode === "recent"
        onClicked: WallpaperService.filterMode = "recent"
    }
}
