import QtQuick
import "../Config"
import "../Services"

/*
 * TagFilterBar.qml
 * -------------------
 * PHASE 3 -- "Tags" from the Wallpaper Library requirement. Reads
 * WallpaperService.allTags (derived from the existing wp.tags field,
 * already written by the backend) and sets WallpaperService.selectedTag
 * on click, same one-property-drives-the-filter shape FilterTabs.qml
 * already uses for filterMode. Hidden entirely when no wallpaper has
 * any tags, so it never shows an empty row.
 */
Flow {
    id: root
    spacing: Theme.spacingSm
    visible: WallpaperService.allTags.length > 0

    IconButton {
        text: "🏷 All tags"
        active: WallpaperService.selectedTag === ""
        onClicked: WallpaperService.selectedTag = ""
    }

    Repeater {
        model: WallpaperService.allTags
        delegate: IconButton {
            text: modelData
            fontSize: Theme.fontSizeSm
            active: WallpaperService.selectedTag === modelData
            onClicked: WallpaperService.selectedTag = (WallpaperService.selectedTag === modelData) ? "" : modelData
        }
    }
}
