import QtQuick
import "../Config"
import "../Services"

Row {
    id: root
    spacing: Theme.spacingSm

    // ── Smart Accent Color: underline indicator for the selected tab ─────
    // Internal component wrapping the existing IconButton, does NOT change
    // the original button's behavior or size -- just adds a small underline
    // below it, synced to the current accent colour (Theme.accent, i.e.
    // SmartAccentService when enabled) with a 450ms animation so QA can
    // easily visually verify synchronisation between filter tabs and the
    // applied background colour.
    component FilterTab: Column {
        id: tabRoot
        property alias text: btn.text
        property alias active: btn.active
        property alias accentColor: btn.accentColor
        signal clicked()

        spacing: 3

        IconButton {
            id: btn
            onClicked: tabRoot.clicked()
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: btn.implicitWidth * 0.5
            height: 3
            radius: 1.5
            color: btn.accentColor
            opacity: tabRoot.active ? 1.0 : 0.0

            Behavior on opacity {
                NumberAnimation { duration: Theme.durationAccentGlow; easing.type: Easing.InOutQuad }
            }
            Behavior on color {
                ColorAnimation { duration: Theme.durationAccentGlow; easing.type: Easing.InOutQuad }
            }
        }
    }

    FilterTab {
        text: "All"
        active: WallpaperService.filterMode === "all"
        onClicked: WallpaperService.filterMode = "all"
    }
    FilterTab {
        text: "★ Favorites"
        active: WallpaperService.filterMode === "favorites"
        accentColor: Theme.yellow
        onClicked: WallpaperService.filterMode = "favorites"
    }
    FilterTab {
        text: "Recent"
        active: WallpaperService.filterMode === "recent"
        onClicked: WallpaperService.filterMode = "recent"
    }
    // PHASE 4 -- #24 Duplicate detection. Hidden when the library has no
    // duplicates so it never shows an always-empty tab.
    FilterTab {
        visible: WallpaperService.duplicateGroups.length > 0
        text: "⧉ Duplicates" + (WallpaperService.duplicateCount > 0 ? " (" + WallpaperService.duplicateCount + ")" : "")
        active: WallpaperService.filterMode === "duplicates"
        accentColor: Theme.danger
        onClicked: WallpaperService.filterMode = "duplicates"
    }
}
