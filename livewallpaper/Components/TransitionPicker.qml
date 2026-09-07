import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../Config"

/*
 * TransitionPicker.qml
 * --------------------
 * Project-styled replacement for the native ComboBox popup.
 * The native popup can ignore the application's Catppuccin/Fluent palette
 * and fall back to an opaque black platform menu. This keeps the selector,
 * popup, hover state, selected state and typography on the same design
 * tokens used by the rest of the UI.
 */
Control {
    id: root

    property var model: []
    property string currentValue: ""
    property string placeholder: "Select..."

    signal activated(string value)

    implicitWidth: 180
    implicitHeight: 36
    enabled: true

    background: Rectangle {
        radius: Theme.radiusMd
        color: root.enabled ? (selectorMouse.pressed ? Theme.surface1 :
                               selectorMouse.containsMouse ? Theme.cardHoverBg : Theme.panelBg)
                            : Theme.mantle
        border.width: 1
        border.color: root.enabled ? Theme.panelBorder : Theme.surface0
    }

    contentItem: RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacingMd
        anchors.rightMargin: Theme.spacingSm
        spacing: Theme.spacingSm

        Text {
            Layout.fillWidth: true
            text: root.selectedLabel
            color: root.enabled ? Theme.text : Theme.overlay0
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }

        Text {
            text: popup.opened ? "⌃" : "⌄"
            color: root.enabled ? Theme.subtext0 : Theme.overlay0
            font.family: Theme.fontFamilyUi
            font.pixelSize: Theme.fontSizeMd
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
        }
    }

    readonly property string selectedLabel: {
        for (let i = 0; i < root.model.length; ++i) {
            if (root.model[i].value === root.currentValue)
                return root.model[i].label;
        }
        return root.placeholder;
    }

    MouseArea {
        id: selectorMouse
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (popup.opened)
                popup.close();
            else
                popup.open();
        }
    }

    Popup {
        id: popup

        parent: Overlay.overlay
        x: root.mapToItem(Overlay.overlay, 0, 0).x
        y: root.mapToItem(Overlay.overlay, 0, root.height + Theme.spacingXs).y
        width: root.width
        padding: Theme.spacingXs
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

        background: Rectangle {
            radius: Theme.radiusMd
            color: Theme.panelBg
            border.width: 1
            border.color: Theme.panelBorder
        }

        contentItem: ListView {
            id: transitionList
            implicitHeight: Math.min(contentHeight, 14 * 36 + Theme.spacingSm)
            clip: true
            spacing: Theme.spacingXs
            model: root.model

            delegate: Item {
                id: option
                required property var modelData

                width: transitionList.width
                height: 34

                property bool hovered: optionMouse.containsMouse

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusSm
                    color: option.modelData.value === root.currentValue
                           ? Theme.segmentActiveBg
                           : option.hovered ? Theme.cardHoverBg : "transparent"
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingMd
                    anchors.right: check.left
                    anchors.rightMargin: Theme.spacingSm
                    anchors.verticalCenter: parent.verticalCenter
                    text: option.modelData.label
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    elide: Text.ElideRight
                }

                Text {
                    id: check
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingMd
                    anchors.verticalCenter: parent.verticalCenter
                    text: option.modelData.value === root.currentValue ? "✓" : ""
                    color: Theme.accent
                    font.family: Theme.fontFamilyUi
                    font.pixelSize: Theme.fontSizeSm
                    font.bold: true
                }

                MouseArea {
                    id: optionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.activated(option.modelData.value);
                        popup.close();
                    }
                }
            }
        }
    }
}
