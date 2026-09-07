import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Services"

/*
 * RecolorCollectionDialog.qml
 * ------------------------------
 * Tiny modal: change a collection's color dot. Opened by tapping the dot
 * itself on Pages/PlaylistPage.qml (formerly the standalone CollectionsPage.qml). CollectionService.setColor(name, color)
 * already existed on the backend (collections.sh set_color) -- this is
 * just the UI that was missing to reach it.
 *
 * Offers a row of theme-palette swatches for a quick pick, plus a "#RRGGBB"
 * text field for any custom hex color.
 */
Item {
    id: root

    property bool open: false
    property string targetName: ""
    // Read as the dialog opens, purely to preselect/preview -- the actual
    // current color always comes live from CollectionService.collections.
    property string currentColor: ""

    readonly property var swatches: [
        Theme.red, Theme.maroon, Theme.peach, Theme.yellow, Theme.green,
        Theme.teal, Theme.sky, Theme.blue, Theme.lavender, Theme.mauve, Theme.pink
    ]

    function normalizeHex(text) {
        var t = text.trim();
        if (t.length > 0 && t.charAt(0) !== "#") t = "#" + t;
        return t;
    }

    function isValidHex(text) {
        return /^#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})$/.test(text);
    }

    // Swatches in `swatches` are QML `color` values (e.g. Theme.red), not
    // strings -- they have no .toLowerCase()/.trim(), which is what was
    // throwing "Property 'toLowerCase' of object #f38ba8 is not a
    // function". Convert explicitly to a clean "#rrggbb" string instead of
    // relying on implicit color->string coercion (which yields an 8-digit
    // "#aarrggbb" form that fails isValidHex and would save the wrong hex).
    function hexOfColor(c) {
        function ch(v) {
            var h = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16);
            return h.length < 2 ? "0" + h : h;
        }
        return "#" + ch(c.r) + ch(c.g) + ch(c.b);
    }

    onOpenChanged: if (open) hexInput.text = root.currentColor

    visible: opacity > 0
    opacity: open ? 1 : 0
    z: 1000

    Behavior on opacity {
        NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutCubic }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        MouseArea { anchors.fill: parent; onClicked: root.open = false }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(360, root.width - Theme.spacingXl * 2)
        implicitHeight: col.implicitHeight + Theme.spacingLg * 2
        height: implicitHeight
        radius: Theme.radiusLg
        color: Theme.panelBg
        border.width: 1
        border.color: Theme.panelBorder

        scale: root.open ? 1.0 : 0.94
        Behavior on scale {
            NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: Theme.spacingLg
            spacing: Theme.spacingMd

            Text {
                text: "Recolor \u201c" + root.targetName + "\u201d"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeLg
                font.bold: true
            }

            Flow {
                Layout.fillWidth: true
                spacing: Theme.spacingSm

                Repeater {
                    model: root.swatches
                    delegate: Rectangle {
                        width: 26; height: 26; radius: 13
                        color: modelData
                        border.width: root.isValidHex(root.normalizeHex(hexInput.text)) && Qt.colorEqual(modelData, root.normalizeHex(hexInput.text)) ? 2 : 1
                        border.color: root.isValidHex(root.normalizeHex(hexInput.text)) && Qt.colorEqual(modelData, root.normalizeHex(hexInput.text)) ? Theme.text : Theme.panelBorder

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var hex = root.hexOfColor(modelData);
                                hexInput.text = hex;
                                CollectionService.setColor(root.targetName, hex);
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSm

                Rectangle {
                    width: 34; height: 34; radius: 17
                    color: root.isValidHex(root.normalizeHex(hexInput.text)) ? root.normalizeHex(hexInput.text) : Theme.surface0
                    border.width: 1
                    border.color: Theme.panelBorder
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 38
                    radius: Theme.radiusMd
                    color: Theme.cardBg
                    border.width: hexInput.activeFocus ? 1 : 0
                    border.color: Theme.accent

                    TextInput {
                        id: hexInput
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingMd
                        anchors.rightMargin: Theme.spacingMd
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeMd
                        clip: true
                        onAccepted: {
                            const hex = root.normalizeHex(text);
                            if (root.isValidHex(hex)) CollectionService.setColor(root.targetName, hex);
                        }
                    }
                    Text {
                        visible: hexInput.text.length === 0
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingMd
                        anchors.verticalCenter: parent.verticalCenter
                        text: "#89b4fa"
                        color: Theme.subtext0
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeMd
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: hexInput.text.length > 0 && !root.isValidHex(root.normalizeHex(hexInput.text))
                text: "Not a valid hex color -- use 3 or 6 digits, e.g. #f38ba8."
                color: Theme.danger
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSm
                Item { Layout.fillWidth: true }
                IconButton {
                    text: "Close"
                    fontSize: Theme.fontSizeSm
                    onClicked: root.open = false
                }
                IconButton {
                    text: "Apply"
                    bold: true
                    fontSize: Theme.fontSizeSm
                    enabled: root.isValidHex(root.normalizeHex(hexInput.text))
                    onClicked: hexInput.accepted()
                }
            }
        }
    }
}
