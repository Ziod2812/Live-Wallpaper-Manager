import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Components"

/*
 * MonitorPage.qml
 * ------------------
 * PHASE 2 -- "Monitor settings" moved here: MonitorSelector.qml (the
 * per-monitor wallpaper-target picker), lifted out of
 * WallpapersModeContent.qml (see that file's updated header) into its
 * own page. Same MultiMonitorService wiring as before, unmodified.
 *
 * PHASE 3 -- added MonitorLayoutPreview.qml ("Preview layout" -- see
 * that file's header for its schematic-not-exact-position scope note)
 * and PerMonitorStatus.qml ("Per-monitor wallpaper" visibility --
 * what's actually playing on each monitor right now). "Per-monitor
 * visualizer" was already covered by MusicDockPanel's existing
 * "Monitor" section (music_dock_monitor) on the Music/Visualizer pages.
 */
Flickable {
    id: root
    anchors.fill: parent
    contentWidth: width
    contentHeight: content.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
        id: content
        width: root.width
        spacing: Theme.spacingMd

        MonitorLayoutPreview {
            Layout.fillWidth: true
        }

        MonitorSelector {
            Layout.fillWidth: true
        }

        PerMonitorStatus {
            Layout.fillWidth: true
        }
    }
}
