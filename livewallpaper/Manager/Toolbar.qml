import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Services"
import "../Components"

/*
 * Toolbar.qml
 * -------------
 * Existing Manager header with the current title/breadcrumb presentation.
 * The Settings search field is placed in the center of the existing header
 * without changing the surrounding UI structure.
 */
Rectangle {
    id: toolbar

    property string windowTitle: "Live Wallpaper Manager"
    property string currentPageLabel: ""
    signal settingsSearchRequested(string query)

    color: Theme.mantle

    // Existing title + breadcrumb stay anchored to the left.
    RowLayout {
        id: breadcrumbRow
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacingLg
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingSm

        Text {
            text: toolbar.windowTitle
            color: Theme.text
            font.family: Theme.fontFamilyUi
            font.pixelSize: Theme.fontSizeLg
            font.bold: true
        }

        Text {
            visible: toolbar.currentPageLabel.length > 0
            text: "/  " + toolbar.currentPageLabel
            color: Theme.subtext0
            font.family: Theme.fontFamilyUi
            font.pixelSize: Theme.fontSizeMd
        }
    }

    // Centered Settings search. It is intentionally independent of the
    // breadcrumb RowLayout so its position stays centered in the header.
    Rectangle {
        id: searchBox
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(280, Math.max(220, toolbar.width - 520))
        height: 34
        radius: Theme.radiusSm
        color: Theme.surface0
        border.width: searchInput.activeFocus ? 1 : 0
        border.color: Theme.accent

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingSm
            anchors.rightMargin: Theme.spacingSm
            spacing: Theme.spacingXs

            Text {
                text: "⌕"
                color: Theme.subtext0
                font.pixelSize: Theme.fontSizeMd
            }

            TextInput {
                id: searchInput
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.text
                font.family: Theme.fontFamilyUi
                font.pixelSize: Theme.fontSizeSm
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                selectByMouse: true

                // Keep the existing lightweight placeholder implementation.
                Text {
                    anchors.fill: parent
                    visible: !parent.text.length && !parent.activeFocus
                    text: "Search settings…"
                    color: Theme.overlay0
                    font.family: parent.font.family
                    font.pixelSize: parent.font.pixelSize
                    verticalAlignment: Text.AlignVCenter
                }

                onTextChanged: toolbar.settingsSearchRequested(text)
                Keys.onEscapePressed: {
                    text = "";
                    focus = false;
                }
                Keys.onReturnPressed: toolbar.settingsSearchRequested(text)
            }
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.panelBorder
    }
}
