import QtQuick
import QtQuick.Layouts
import "../Config"

/*
 * PeaclockClock.qml
 * ---------------------
 * Standalone clock/date/day component, inspired by the "Peaclock" desktop
 * clock widget used by the Peaclock + Cava Dock. Deliberately
 * self-contained: reads nothing but the system clock (QML's own Date
 * object via a 1s Timer) and Theme colors.
 *
 * INDEPENDENCE CONTRACT:
 *   - Owns clock/date/day rendering ONLY.
 *   - Never imports, reads, or manages CavaService, MprisService,
 *     SystemStatsService, GPUManagerService, or any other audio-
 *     visualizer / now-playing / stats state.
 *   - Safe to drop into any layout on its own -- Components/
 *     PeaclockCavaDock.qml is just one consumer, not a dependency.
 */
ColumnLayout {
    id: root
    spacing: 2

    // Only cosmetic knobs -- caller-supplied, no SettingsService reads
    // here so this stays fully standalone.
    property color accentColor: Theme.mauve
    property color textColor: Theme.text
    property color subColor: Theme.subtext0
    // Optional small trailing glyph next to the day label (the reference
    // image shows a small icon top-right of the clock block). Purely
    // decorative; set to "" to hide it entirely.
    property string glyph: "\u25CF" // ●

    property date _now: new Date()

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root._now = new Date()
    }

    readonly property var _dayNames: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    readonly property var _monthNames: ["January", "February", "March", "April", "May", "June", "July",
                                         "August", "September", "October", "November", "December"]

    readonly property string dayLabel: root._dayNames[root._now.getDay()]
    readonly property string dateLabel: root._now.getDate() + " " + root._monthNames[root._now.getMonth()] + " " + root._now.getFullYear()
    readonly property int _h24: root._now.getHours()
    readonly property int hour12: {
        const h = root._h24 % 12;
        return h === 0 ? 12 : h;
    }
    readonly property string minuteLabel: (root._now.getMinutes() < 10 ? "0" : "") + root._now.getMinutes()
    readonly property string ampmLabel: root._h24 >= 12 ? "PM" : "AM"

    // ── Day row ─────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingSm

        Text {
            text: root.dayLabel
            color: root.textColor
            font.family: Theme.fontFamilyUi
            font.pixelSize: Theme.fontSizeMd
        }
        Item { Layout.fillWidth: true }
        Text {
            visible: root.glyph.length > 0
            text: root.glyph
            color: root.accentColor
            font.pixelSize: Theme.fontSizeSm
            opacity: 0.85
        }
    }

    // ── Time row ────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 4

        Text {
            text: root.hour12 + ":" + root.minuteLabel
            color: root.textColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXl + 10
            font.bold: true
        }
        Text {
            text: root.ampmLabel
            color: root.accentColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            font.bold: true
            Layout.alignment: Qt.AlignBottom
            Layout.bottomMargin: 6
        }
    }

    // ── Date row ────────────────────────────────────────────────────────
    Text {
        text: root.dateLabel
        color: root.subColor
        font.family: Theme.fontFamilyUi
        font.pixelSize: Theme.fontSizeSm
    }
}
