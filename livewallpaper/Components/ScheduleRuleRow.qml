import QtQuick
import QtQuick.Layouts
import "../Config"

/*
 * ScheduleRuleRow.qml
 * ----------------------
 * One row in PlaylistPage.qml's "Time-of-day rules" list (formerly on SchedulePage.qml): label, start/
 * end (HH:MM or "sunrise"/"sunset"), and which collection to pick a
 * random wallpaper from. Purely a dumb editor -- it emits the whole
 * updated rule object via changed(), the page owns writing it back to
 * settings.schedule_rules.
 */
Rectangle {
    id: root

    property var ruleData: ({})
    property bool isActive: false
    property var collectionNames: []

    signal changed(var updatedRule)
    signal removeRequested()

    implicitHeight: row.implicitHeight + Theme.spacingSm * 2
    radius: Theme.radiusMd
    color: root.isActive ? Qt.rgba(0.6510, 0.9059, 0.6314, 0.14) : Theme.cardBg
    border.width: root.isActive ? 1 : 0
    border.color: Theme.success

    function _emit(patch) {
        const next = Object.assign({}, root.ruleData, patch);
        root.changed(next);
    }

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.margins: Theme.spacingSm
        spacing: Theme.spacingSm

        Rectangle {
            width: 8; height: 8; radius: 4
            visible: root.isActive
            color: Theme.success
        }

        Rectangle {
            width: 110; height: 30
            radius: Theme.radiusSm
            color: Theme.base
            TextInput {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingSm
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                text: root.ruleData.label || ""
                onEditingFinished: root._emit({ label: text })
            }
        }

        Text { text: "from"; color: Theme.subtext0; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm }

        Rectangle {
            width: 78; height: 30
            radius: Theme.radiusSm
            color: Theme.base
            TextInput {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingSm
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                text: root.ruleData.start || ""
                onEditingFinished: root._emit({ start: text })
            }
        }

        Text { text: "to"; color: Theme.subtext0; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm }

        Rectangle {
            width: 78; height: 30
            radius: Theme.radiusSm
            color: Theme.base
            TextInput {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingSm
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                text: root.ruleData.end || ""
                onEditingFinished: root._emit({ end: text })
            }
        }

        Text { text: "→"; color: Theme.subtext0; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm }

        // Collection picker -- cycles through collectionNames on click
        // (kept as a simple tap-to-cycle chip rather than pulling in a
        // ComboBox dependency for one field).
        Rectangle {
            Layout.preferredWidth: 130
            height: 30
            radius: Theme.radiusSm
            color: Theme.surface0
            Text {
                anchors.centerIn: parent
                text: root.ruleData.source || "(none)"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                elide: Text.ElideRight
                width: parent.width - 8
                horizontalAlignment: Text.AlignHCenter
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.collectionNames.length === 0) return;
                    const cur = root.collectionNames.indexOf(root.ruleData.source);
                    const next = root.collectionNames[(cur + 1) % root.collectionNames.length];
                    root._emit({ source: next, source_type: "collection" });
                }
            }
        }

        Item { Layout.fillWidth: true }

        IconButton {
            text: "✕"
            danger: true
            fontSize: Theme.fontSizeSm
            implicitWidth: 30
            onClicked: root.removeRequested()
        }
    }
}
