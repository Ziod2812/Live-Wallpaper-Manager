import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQCB
import "../Config"

/*
 * Sidebar.qml
 * -------------
 * Left-hand navigation column for the Manager app window. Purely
 * presentational: it renders whatever `model` it's given (an array of
 * { id, label, icon } like Navigation.items) and reports clicks via
 * `navigate(id)`. ManagerWindow owns the actual current-page state.
 *
 * PHASE 4 -- `collapsed` (set by ManagerWindow based on window width)
 * hides the text labels and narrows the column to an icon rail, for
 * "Responsive layout". Labels are still available as a tooltip so
 * nothing is actually lost, just given less permanent screen space.
 */
Rectangle {
    id: sidebar

    property var model: []
    property string currentId: ""
    property bool collapsed: false

    signal navigate(string id)

    color: Theme.crust

    Rectangle {
        anchors.right: parent.right
        width: 1
        height: parent.height
        color: Theme.panelBorder
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingMd
        spacing: Theme.spacingXs

        Repeater {
            model: sidebar.model

            delegate: Rectangle {
                id: navItem

                readonly property bool active: modelData.id === sidebar.currentId

                Layout.fillWidth: true
                Layout.preferredHeight: 40
                radius: Theme.radiusSm
                color: active ? Theme.segmentActiveBg
                             : (hoverArea.containsMouse ? Theme.segmentHoverBg : "transparent")

                Behavior on color {
                    ColorAnimation { duration: Theme.durationFast }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingMd
                    anchors.rightMargin: Theme.spacingMd
                    spacing: Theme.spacingSm

                    Text {
                        text: modelData.icon
                        font.pixelSize: Theme.fontSizeMd
                        color: navItem.active ? Theme.accent : Theme.subtext0
                    }

                    Text {
                        visible: !sidebar.collapsed
                        text: modelData.label
                        font.family: Theme.fontFamilyUi
                        font.pixelSize: Theme.fontSizeMd
                        color: navItem.active ? Theme.text : Theme.subtext0
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: hoverArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: sidebar.navigate(modelData.id)
                    QQCB.ToolTip.visible: sidebar.collapsed && containsMouse
                    QQCB.ToolTip.text: modelData.label
                    QQCB.ToolTip.delay: 400
                }

                // ── Smart Accent Color: thanh gạch đứng (indicator) ──────
                // Chỉ báo dạng thanh dọc sát biên phải của mục điều hướng
                // đang Active, đồng bộ theo Theme.accent (tức
                // SmartAccentService.accentColor khi tính năng được bật).
                // Ẩn hoàn toàn khi không Active thay vì chỉ đổi màu, để
                // không vẽ thêm một cạnh mờ trên các mục chưa được chọn.
                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3
                    radius: 1.5
                    height: navItem.active ? parent.height * 0.6 : 0
                    color: Theme.accent
                    opacity: navItem.active ? 1.0 : 0.0

                    Behavior on height {
                        NumberAnimation { duration: Theme.durationAccentGlow; easing.type: Easing.InOutQuad }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: Theme.durationAccentGlow; easing.type: Easing.InOutQuad }
                    }
                    Behavior on color {
                        ColorAnimation { duration: Theme.durationAccentGlow; easing.type: Easing.InOutQuad }
                    }
                }
            }
        }

        // Spacer pushes nav items to the top, leaving room to grow.
        Item { Layout.fillHeight: true }
    }
}
