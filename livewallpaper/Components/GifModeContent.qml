import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import "../Config"
import "../Services"

/*
 * GIF mode body.
 * UI intentionally follows WallpapersModeContent.qml:
 * search + mode filters + large/compact toggle + grid + current/action bars.
 * Only the data source is different: SettingsService.gifWallpaperDirectory.
 *
 * Also mirrors WallpaperCard.qml's "+" add-to-collection button (GIFs can
 * be filed into the same named collections as regular wallpapers) and its
 * fix for the click-to-apply MouseArea stealing that button's clicks.
 */
Item {
    id: root

    property bool zenMode: false
    property bool largeThumbs: SettingsService.settings.gif_large_thumbnails === true

    implicitHeight: content.implicitHeight

    // -------------------- Local GIF state --------------------
    property string directoryPath: ""
    property string searchText: ""
    property string filterMode: "all"
    property string currentGif: ""
    property var gifs: []
    property var favorites: []
    property bool refreshing: false
    property bool advSearchOpen: false

    // GIF owns its filter state. AdvancedSearchPanel is provider-driven, so
    // moving the panel here does not accidentally mutate WallpaperService.
    QtObject {
        id: gifFilterProvider

        property string advResolution: ""
        property int advMinFps: 0
        property int advMinDurationSeconds: 0
        property bool advFavoriteOnly: false

        readonly property bool advFiltersActive:
            advResolution.length > 0 || advMinFps > 0 ||
            advMinDurationSeconds > 0 || advFavoriteOnly

        readonly property var allResolutions: {
            var set = {}
            for (var i = 0; i < root.gifs.length; ++i) {
                var resolution = root.gifs[i].resolution || ""
                if (resolution.length > 0)
                    set[resolution] = true
            }
            return Object.keys(set).sort()
        }

        function clearAdvancedFilters() {
            advResolution = ""
            advMinFps = 0
            advMinDurationSeconds = 0
            advFavoriteOnly = false
        }
    }

    function formatFps(rate) {
        if (!rate) return 0
        var parts = String(rate).split("/")
        var value = parts.length === 2
            ? Number(parts[0]) / Number(parts[1])
            : Number(rate)
        if (!isFinite(value) || value <= 0) return 0
        return Math.round(value * 100) / 100
    }

    function formatDuration(seconds) {
        var value = Number(seconds)
        if (!isFinite(value) || value < 0) return ""
        var total = Math.round(value)
        var minutes = Math.floor(total / 60)
        var secs = total % 60
        return minutes + ":" + (secs < 10 ? "0" : "") + secs
    }

    function expandedDirectory() {
        var p = String(SettingsService.gifWallpaperDirectory || "").trim()
        var home = Quickshell.env("HOME") || ""
        if (p === "~") return home
        if (p.indexOf("~/") === 0) return home + p.substring(1)
        return p
    }

    function refresh() {
        directoryPath = expandedDirectory()
        refreshing = true

        scanProc.command = [
            "bash", "-lc",
            'd="$1"; if [ -d "$d" ]; then find "$d" -maxdepth 1 -type f -iname "*.gif" -print0 | sort -z -f | while IFS= read -r -d "" f; do width=""; height=""; rate=""; duration=""; if command -v ffprobe >/dev/null 2>&1; then meta=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate,duration -of csv=p=0:s="|" "$f" 2>/dev/null | head -n 1); IFS="|" read -r width height rate duration <<< "$meta"; fi; printf "%s\\t%s\\t%s\\t%s\\t%s\\n" "$f" "$width" "$height" "$rate" "$duration"; done; fi',
            "gif-scan", directoryPath
        ]
        scanProc.running = true
    }

    function applyGif(path) {
        if (!path) return
        currentGif = path
        PlaybackService.apply(path)
    }

    function isFavorite(path) {
        return favorites.indexOf(path) >= 0
    }

    function toggleFavorite(path) {
        var next = favorites.slice()
        var i = next.indexOf(path)
        if (i >= 0)
            next.splice(i, 1)
        else
            next.unshift(path)

        favorites = next
        SettingsService.set("gif_favorites", JSON.stringify(favorites))
    }

    function matches(item) {
        if (filterMode === "favorites" && favorites.indexOf(item.path) < 0)
            return false

        if (searchText.length > 0 &&
            item.name.toLowerCase().indexOf(searchText.toLowerCase()) < 0)
            return false

        if (gifFilterProvider.advResolution.length > 0 &&
            item.resolution !== gifFilterProvider.advResolution)
            return false


        if (gifFilterProvider.advFavoriteOnly && !isFavorite(item.path))
            return false

        return true
    }

    readonly property var visibleGifs: {
        var filtered = gifs.filter(matches)

        if (filterMode !== "recent")
            return filtered

        var recentPaths = HistoryService.recentPaths
        var recentOut = []
        for (var i = 0; i < recentPaths.length; ++i) {
            for (var j = 0; j < filtered.length; ++j) {
                if (filtered[j].path === recentPaths[i]) {
                    recentOut.push(filtered[j])
                    break
                }
            }
        }
        return recentOut
    }

    Component.onCompleted: {
        try {
            var f = JSON.parse(SettingsService.settings.gif_favorites || "[]")
            if (Array.isArray(f)) favorites = f
        } catch (e) {}

        refresh()
    }

    Connections {
        target: SettingsService

        function onSettingsChanged() {
            try {
                var f = JSON.parse(SettingsService.settings.gif_favorites || "[]")
                if (Array.isArray(f)) root.favorites = f
            } catch (e) {}

            root.largeThumbs = SettingsService.settings.gif_large_thumbnails === true
            root.refresh()
        }
    }

    Process {
        id: scanProc

        stdout: StdioCollector { id: scanOut }
        stderr: StdioCollector { id: scanErr }

        onExited: (exitCode, exitStatus) => {
            root.refreshing = false

            if (exitCode !== 0) {
                root.gifs = []
                console.warn("GIF scan failed:", scanErr.text.trim())
                return
            }

            var found = []
            var lines = scanOut.text.split("\n")

            for (var i = 0; i < lines.length; ++i) {
                var line = lines[i]
                if (!line.length)
                    continue

                var fields = line.split("\t")
                var path = fields[0] || ""
                if (!path.length)
                    continue

                var slash = path.lastIndexOf("/")
                var width = Number(fields[1] || 0)
                var height = Number(fields[2] || 0)
                var fps = root.formatFps(fields[3] || "")
                var durationSeconds = Number(fields[4] || 0)
                if (!isFinite(durationSeconds) || durationSeconds < 0)
                    durationSeconds = 0

                found.push({
                    path: path,
                    isGif: true,
                    name: slash >= 0 ? path.substring(slash + 1) : path,
                    resolution: width > 0 && height > 0 ? width + "x" + height : "",
                    fps: fps,
                    duration_seconds: durationSeconds,
                    duration: root.formatDuration(durationSeconds),
                    favorite: root.isFavorite(path),
                    tags: []
                })
            }

            root.gifs = found
        }
    }

    // -------------------- Wallpaper-like layout --------------------
    ColumnLayout {
        id: content

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: Theme.spacingLg

        // Search + Compact/Large (same row as Wallpapers)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingLg
            visible: !root.zenMode
            opacity: root.zenMode ? 0 : 1

            Behavior on opacity {
                NumberAnimation { duration: Theme.durationNormal }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingMd

                Rectangle {
                    id: searchBox
                    Layout.fillWidth: true
                    height: 42
                    radius: Theme.radiusMd
                    color: Theme.cardBg
                    border.width: gifSearch.activeFocus ? 1 : 0
                    border.color: Theme.accent

                    Behavior on border.width {
                        NumberAnimation { duration: Theme.durationFast }
                    }

                    Item {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingMd
                        anchors.rightMargin: Theme.spacingMd

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "🔍"
                            font.pixelSize: Theme.fontSizeMd
                            color: Theme.subtext0
                        }

                        Text {
                            id: placeholder
                            anchors.left: parent.left
                            anchors.leftMargin: 28
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Search GIF wallpapers…"
                            color: Theme.subtext0
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeMd
                            visible: gifSearch.length === 0
                        }

                        TextInput {
                            id: gifSearch
                            anchors.left: parent.left
                            anchors.leftMargin: 28
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeMd
                            selectByMouse: true
                            clip: true

                            Component.onCompleted: text = root.searchText
                            onTextEdited: searchDebounce.restart()

                            Timer {
                                id: searchDebounce
                                interval: 150
                                onTriggered: root.searchText = gifSearch.text
                            }
                        }
                    }
                }

                IconButton {
                    text: root.largeThumbs ? "▦ Large" : "▤ Compact"
                    fontSize: Theme.fontSizeSm
                    active: root.largeThumbs

                    onClicked: {
                        root.largeThumbs = !root.largeThumbs
                        SettingsService.set("gif_large_thumbnails", root.largeThumbs)
                    }
                }

                IconButton {
                    text: "⚗ Filters"
                    fontSize: Theme.fontSizeSm
                    active: root.advSearchOpen || gifFilterProvider.advFiltersActive
                    onClicked: root.advSearchOpen = !root.advSearchOpen
                }
            }

            AdvancedSearchPanel {
                Layout.fillWidth: true
                visible: root.advSearchOpen
                filterProvider: gifFilterProvider
                supportsMotionFilters: false
            }

            // Same visual filter tabs as Wallpapers.
            Row {
                spacing: Theme.spacingSm

                IconButton {
                    text: "All"
                    active: root.filterMode === "all"
                    onClicked: root.filterMode = "all"
                }

                IconButton {
                    text: "★ Favorites"
                    active: root.filterMode === "favorites"
                    accentColor: Theme.yellow
                    onClicked: root.filterMode = "favorites"
                }

                IconButton {
                    text: "Recent"
                    active: root.filterMode === "recent"
                    onClicked: root.filterMode = "recent"
                }
            }
        }

        // Same grid geometry as WallpaperGrid.
        GridView {
            id: gifGrid
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            cellWidth: root.largeThumbs ? 306 : 206
            cellHeight: root.largeThumbs ? 300 : 210
            boundsBehavior: Flickable.StopAtBounds
            model: root.visibleGifs

            delegate: Item {
                required property var modelData

                width: gifGrid.cellWidth
                height: gifGrid.cellHeight

                WallpaperCard {
                    anchors.centerIn: parent
                    wp: modelData
                    large: root.largeThumbs
                    gifAsset: true
                    showPreviewButton: false

                    opacity: 0
                    Component.onCompleted: opacity = 1
                    Behavior on opacity {
                        NumberAnimation { duration: Theme.durationNormal }
                    }

                    onFavoriteToggled: root.toggleFavorite(path)
                    onCollectionRequested: {
                        gifCollectionDialog.wp = wp
                        gifCollectionDialog.open = true
                    }
                }
            }
            add: Transition {
                NumberAnimation {
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: Theme.durationNormal
                }
                NumberAnimation {
                    property: "scale"
                    from: 0.92
                    to: 1
                    duration: Theme.durationNormal
                    easing.type: Easing.OutBack
                }
            }

            Column {
                anchors.centerIn: parent
                visible: root.visibleGifs.length === 0 && !root.refreshing
                spacing: Theme.spacingSm

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.filterMode === "recent" ? "󰃰" : "󰸉"
                    font.family: Theme.fontFamily
                    font.pixelSize: 34
                    color: Theme.overlay0
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.filterMode === "recent"
                        ? "No GIF wallpapers switched yet."
                        : (root.gifs.length === 0
                           ? "No GIF wallpapers found. Add GIFs to your GIF wallpaper folder and hit Refresh."
                           : "No matches.")
                    width: 320
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: Theme.subtext0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }
            }
        }

        // Same bottom section structure as WallpapersModeContent.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingLg
            visible: !root.zenMode
            opacity: root.zenMode ? 0 : 1

            Behavior on opacity {
                NumberAnimation { duration: Theme.durationNormal }
            }

            // CurrentBar-like row + exact progress geometry.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingXs

                Row {
                    spacing: Theme.spacingSm
                    Layout.fillWidth: true

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "●"
                        color: PlaybackService.running ? Theme.success : Theme.overlay0
                        font.pixelSize: 10

                        SequentialAnimation on opacity {
                            running: PlaybackService.running
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.4; duration: 900; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Current:"
                        color: Theme.subtext0
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: PlaybackService.currentName
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        font.bold: true
                        elide: Text.ElideRight
                        width: 580
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: PlaybackService.running && PlaybackService.playDuration > 0
                        text: PlaybackService.playPercent + "%"
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        font.bold: true
                    }
                }

                Item {
                    Layout.fillWidth: true
                    height: 5
                    visible: PlaybackService.running && PlaybackService.playDuration > 0

                    Rectangle {
                        anchors.fill: parent
                        radius: 2
                        color: Theme.surface0
                    }

                    Rectangle {
                        width: Math.max(4,
                            parent.width * Math.min(PlaybackService.playPercent / 100.0, 1.0))
                        height: parent.height
                        radius: 2
                        color: Theme.accent

                        Behavior on width {
                            NumberAnimation { duration: 800; easing.type: Easing.OutCubic }
                        }
                    }
                }
            }

            // Same ActionBar row as Wallpapers.
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingMd

                TransportButtons {}

                Item { Layout.fillWidth: true }

                IconButton {
                    text: root.refreshing ? "Refreshing…" : " Refresh"
                    onClicked: root.refresh()
                }

                PlayPauseButton {}
            }
        }
    }

    // Collections (GIF card's "+" button) -- overlay sibling of `content`
    // for the same reason as WallpapersModeContent.qml's collectionDialog:
    // its anchors.fill would conflict with ColumnLayout if nested inside.
    // AddToCollectionDialog only needs wp.path/wp.name, which GIF entries
    // already have, so the exact same dialog component is reused here.
    AddToCollectionDialog {
        id: gifCollectionDialog
        anchors.fill: parent
    }

    function focusSearch() {
        gifSearch.forceActiveFocus()
    }
}
