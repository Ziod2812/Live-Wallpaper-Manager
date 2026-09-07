import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQCB
import "../Config"

Item {
    id: root

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight + Theme.spacingLg
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: content
            width: flick.width
            spacing: Theme.spacingLg

            Rectangle {
                Layout.fillWidth: true
                radius: Theme.radiusLg
                color: Theme.cardBg
                border.width: 1
                border.color: Theme.panelBorder
                implicitHeight: heroContent.implicitHeight + Theme.spacingXl * 2

                ColumnLayout {
                    id: heroContent
                    anchors.fill: parent
                    anchors.margins: Theme.spacingXl
                    spacing: Theme.spacingMd

                    Text {
                        text: "Live Wallpaper Manager"
                        color: Theme.text
                        font.family: Theme.fontFamilyUi
                        font.pixelSize: 28
                        font.bold: true
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "A Quickshell-based live wallpaper manager for Hyprland using mpvpaper."
                        color: Theme.subtext0
                        font.family: Theme.fontFamilyUi
                        font.pixelSize: Theme.fontSizeMd
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        textFormat: Text.RichText
                        text: "<a href=\"https://github.com/Ziod2812/Live-Wallpaper-Manager.git\">Current release</a>"
                        color: Theme.accent
                        linkColor: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        font.bold: true
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: parent.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                            acceptedButtons: Qt.NoButton
                        }
                        onLinkActivated: (link) => Qt.openUrlExternally(link)
                    }

                    Text {
                        text: "Open-source • MIT License"
                        color: Theme.text
                        font.family: Theme.fontFamilyUi
                        font.pixelSize: Theme.fontSizeMd
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: Theme.radiusLg
                color: Theme.cardBg
                border.width: 1
                border.color: Theme.panelBorder
                implicitHeight: featuresContent.implicitHeight + Theme.spacingLg * 2

                ColumnLayout {
                    id: featuresContent
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLg
                    spacing: Theme.spacingSm

                    Text {
                        text: "Features"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeLg
                        font.bold: true
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "• Local video wallpapers with search, favorites, tags, and history\n• Streaming and Web modes, with a web wallpaper browser and download manager\n• Collections, Time-of-day scheduling (with Sunrise/Sunset), and Weather-based wallpapers\n• Multi-monitor support with GPU selection and performance controls\n• Wallpaper transitions: fade, crossfade, slide, wipe, zoom, grow, and random\n• Playlist scheduling: Sequential, Random, and Favorites\n• Music Dock, Cava, and Peaclock + Cava\n• Smart Playback, cache management, system tray, and login autostart"
                        color: Theme.subtext0
                        font.family: Theme.fontFamilyUi
                        font.pixelSize: Theme.fontSizeSm
                        lineHeight: 1.35
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: Theme.radiusLg
                color: Theme.cardBg
                border.width: 1
                border.color: Theme.panelBorder
                implicitHeight: linksContent.implicitHeight + Theme.spacingLg * 2

                ColumnLayout {
                    id: linksContent
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLg
                    spacing: Theme.spacingMd

                    Text {
                        text: "License & Credits"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeLg
                        font.bold: true
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Licensed under the MIT License. The project was developed independently and some open-source GitHub projects were reviewed as technical references during development."
                        color: Theme.subtext0
                        font.family: Theme.fontFamilyUi
                        font.pixelSize: Theme.fontSizeSm
                        wrapMode: Text.WordWrap
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSm
                        Text {
                            text: "Testers"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeMd
                            font.bold: true
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        textFormat: Text.RichText
                        text: "• <a href=\"https://github.com/minh23102011\">minh23102011</a> — general testing and feedback<br/>• <a href=\"https://www.youtube.com/@prodepxser\">@prodepxser</a> — general testing and feedback<br/>• <a href=\"https://github.com/Trypezz\">Trypezz</a> — general testing and feedback<br/>• A real-life friend — general testing"
                        color: Theme.subtext0
                        linkColor: Theme.accent
                        font.family: Theme.fontFamilyUi
                        font.pixelSize: Theme.fontSizeSm
                        lineHeight: 1.3
                        onLinkActivated: (link) => Qt.openUrlExternally(link)
                    }


        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Text {
                text: "AI Assistance"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMd
                font.bold: true
            }

            Text {
                Layout.fillWidth: true
                text: "AI-assisted development with Claude Code and ChatGPT"
                color: Theme.subtext0
                font.family: Theme.fontFamilyUi
                font.pixelSize: Theme.fontSizeSm
                lineHeight: 1.3
                wrapMode: Text.WordWrap
            }
        }
                }
            }
        }
    }
}
