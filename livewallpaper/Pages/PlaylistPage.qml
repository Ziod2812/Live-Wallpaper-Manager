import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../Config"
import "../Components"
import "../Services"

/*
 * PlaylistPage.qml
 * -------------------
 * Playlist controls, plus two merged-in sections that used to be their
 * own nav pages:
 *   - Time-of-day rules (from the former Schedule page) -- Schedule's
 *     Location and Weather-based wallpaper sections were dropped, not
 *     moved, so this page only keeps the rules editor.
 *   - Collections management (from the former Collections page) --
 *     Collections exists mainly to feed Playlist's "Custom" mode (and
 *     the rules above) a saved pool of wallpapers, so managing them
 *     lives right here now. Filing a wallpaper into a collection from
 *     its "+" button (WallpapersModeContent.qml's AddToCollectionDialog)
 *     is unaffected -- that flow never went through either old page.
 */
Flickable {
    id: root
    anchors.fill: parent
    contentWidth: width
    contentHeight: content.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    property string expandedCollectionName: ""

    ColumnLayout {
        id: content
        width: root.width
        spacing: Theme.spacingLg

        // REMOVED (GIF Playlist section): PlaylistService.advanceNow()
        // now auto-detects MP4 vs GIF from whatever is actually playing
        // (see PlaylistService.qml's own comment, and the matching fix in
        // PlaybackService.qml's next()/previous()/random()), so this one
        // bar already advances GIFs when a GIF is playing and wallpapers
        // when a wallpaper is playing. The separate "GIF Playlist" bar
        // (its own on/off + interval + mode, backed by
        // GifPlaylistService's now-removed auto-advance timer) was left
        // over from before that fix and duplicated the same schedule for
        // no reason -- deleted rather than kept as dead UI.
        PlaylistBar {
            id: wallpaperPlaylist
            Layout.fillWidth: true
            title: "Playlist"
            service: PlaylistService
        }

        // ── Time-of-day rules (merged from the former standalone
        // Schedule page) ────────────────────────────────────────────────
        // The Schedule page's Location and Weather-based wallpaper
        // sections were dropped rather than moved (explicitly requested)
        // -- only this rules editor came along. "sunrise"/"sunset" as a
        // rule boundary still works if a location was set previously
        // (SettingsService.location_lat/lng), there's just no UI here to
        // change it anymore.
        ColumnLayout {
            id: newRuleHelper
            Layout.fillWidth: true
            spacing: Theme.spacingMd

            function newRuleId() {
                return "rule_" + Date.now() + "_" + Math.floor(Math.random() * 1000);
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: "Time-of-day rules"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeLg
                    font.bold: true
                }
                ToggleSwitch {
                    checked: SettingsService.scheduleEnabled
                    onToggled: SettingsService.set("schedule_enabled", !checked)
                }
            }

            Text {
                Layout.fillWidth: true
                text: "The first rule whose window contains the current time wins. Use \"sunrise\"/\"sunset\" as a start or end instead of a fixed time to follow daylight (needs a location set previously)."
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: SettingsService.scheduleRules
                delegate: ScheduleRuleRow {
                    Layout.fillWidth: true
                    ruleData: modelData
                    isActive: SchedulerService.activeRuleId === (modelData.id || "")
                    collectionNames: CollectionService.names
                    onChanged: updated => {
                        const rules = SettingsService.scheduleRules.slice();
                        rules[index] = updated;
                        SettingsService.setScheduleRules(rules);
                    }
                    onRemoveRequested: {
                        const rules = SettingsService.scheduleRules.slice();
                        rules.splice(index, 1);
                        SettingsService.setScheduleRules(rules);
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSm

                IconButton {
                    text: "+ Add rule"
                    fontSize: Theme.fontSizeSm
                    onClicked: {
                        const rules = SettingsService.scheduleRules.slice();
                        rules.push({
                            id: newRuleHelper.newRuleId(),
                            label: "New rule",
                            start: "06:00",
                            end: "18:00",
                            source_type: "collection",
                            source: CollectionService.names.length > 0 ? CollectionService.names[0] : ""
                        });
                        SettingsService.setScheduleRules(rules);
                    }
                }

                IconButton {
                    text: "Shuffle now"
                    fontSize: Theme.fontSizeSm
                    enabled: SettingsService.scheduleEnabled
                    onClicked: SchedulerService.reshuffleNow()
                }

                Item { Layout.fillWidth: true }

                Text {
                    visible: SchedulerService.appliedPath.length > 0
                    text: "Active: " + SchedulerService.appliedPath.split("/").pop()
                    color: Theme.subtext0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    elide: Text.ElideMiddle
                    Layout.maximumWidth: 240
                }
            }
        }

        // ── Collections (merged from the former standalone Collections
        // page) ─────────────────────────────────────────────────────────
        Text {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacingSm
            text: "Collections"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXl
            font.bold: true
        }

        Text {
            Layout.fillWidth: true
            text: "Group wallpapers so Playlist's Custom mode (and Schedule) can pick randomly from just one theme."
            color: Theme.subtext0
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            wrapMode: Text.WordWrap
        }

        // ── Create new ───────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Rectangle {
                Layout.fillWidth: true
                height: 38
                radius: Theme.radiusMd
                color: Theme.cardBg
                border.width: nameInput.activeFocus ? 1 : 0
                border.color: Theme.accent

                TextInput {
                    id: nameInput
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingMd
                    anchors.rightMargin: Theme.spacingMd
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMd
                    clip: true
                    onAccepted: {
                        if (text.trim().length === 0) return;
                        CollectionService.create(text.trim());
                        text = "";
                    }
                }
                Text {
                    visible: nameInput.text.length === 0
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingMd
                    anchors.verticalCenter: parent.verticalCenter
                    text: "e.g. Anime, Nature, Cyberpunk, Minimal…"
                    color: Theme.subtext0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMd
                }
            }

            IconButton {
                text: "+ New collection"
                bold: true
                fontSize: Theme.fontSizeSm
                onClicked: nameInput.accepted()
            }
        }

        // ── List ────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingMd

            Repeater {
                model: CollectionService.names
                delegate: Rectangle {
                    id: collCard
                    // Captured explicitly because the inner Repeater below
                    // (over this collection's member paths) shadows the
                    // outer `modelData` with its own.
                    property string collName: modelData

                    Layout.fillWidth: true
                    implicitHeight: cardCol.implicitHeight + Theme.spacingMd * 2
                    radius: Theme.radiusLg
                    color: Theme.cardBg
                    border.width: 1
                    border.color: Theme.panelBorder

                    ColumnLayout {
                        id: cardCol
                        anchors.fill: parent
                        anchors.margins: Theme.spacingMd
                        spacing: Theme.spacingSm

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSm

                            Rectangle {
                                id: colorDot
                                width: 16; height: 16; radius: 8
                                color: (CollectionService.collections[modelData] && CollectionService.collections[modelData].color) || Theme.accent
                                border.width: 1
                                border.color: Theme.panelBorder
                                scale: dotMouse.containsMouse ? 1.2 : 1.0
                                Behavior on scale {
                                    NumberAnimation { duration: Theme.durationFast }
                                }

                                MouseArea {
                                    id: dotMouse
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        recolorDialog.targetName = modelData;
                                        recolorDialog.currentColor = colorDot.color.toString();
                                        recolorDialog.open = true;
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: modelData
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeMd
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                text: CollectionService.pathCount(modelData) + " wallpapers"
                                color: Theme.subtext0
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                            }

                            IconButton {
                                text: root.expandedCollectionName === modelData ? "▲ Hide" : "▼ Show"
                                fontSize: Theme.fontSizeSm
                                onClicked: root.expandedCollectionName = (root.expandedCollectionName === modelData ? "" : modelData)
                            }

                            IconButton {
                                text: "Rename"
                                fontSize: Theme.fontSizeSm
                                onClicked: {
                                    renameDialog.targetName = modelData;
                                    renameDialog.open = true;
                                }
                            }

                            IconButton {
                                text: "Delete"
                                danger: true
                                fontSize: Theme.fontSizeSm
                                onClicked: {
                                    deleteDialog.targetName = modelData;
                                    deleteDialog.open = true;
                                }
                            }
                        }

                        // Expanded member list (paths only -- thumbnails
                        // are the Wallpapers page's job; this is just
                        // "what's in here" bookkeeping with a quick
                        // remove).
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: root.expandedCollectionName === modelData
                            spacing: 2

                            Repeater {
                                model: (CollectionService.collections[modelData] && CollectionService.collections[modelData].paths) || []
                                delegate: RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingSm
                                    Text {
                                        Layout.fillWidth: true
                                        text: String(modelData).split("/").pop()
                                        color: Theme.subtext1
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSm
                                        elide: Text.ElideMiddle
                                    }
                                    IconButton {
                                        text: "✕"
                                        fontSize: Theme.fontSizeSm
                                        implicitWidth: 26
                                        onClicked: CollectionService.removeWallpaper(collCard.collName, modelData)
                                    }
                                }
                            }

                            Text {
                                visible: !(CollectionService.collections[modelData] && CollectionService.collections[modelData].paths && CollectionService.collections[modelData].paths.length > 0)
                                text: "Empty — add wallpapers from the \"+\" button on any wallpaper card."
                                color: Theme.subtext0
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: CollectionService.names.length === 0
                text: "No collections yet."
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
            }
        }

        // ── Wallpaper Transitions ───────────────────────────────────
        // Moved here from Settings so playlist/collection behavior and
        // visual switching controls live together in one place.
        Rectangle {
            id: transitionSection
            Layout.fillWidth: true
            radius: Theme.radiusLg
            color: Theme.cardBg
            border.width: 1
            border.color: Theme.panelBorder
            implicitHeight: transitionContent.implicitHeight + Theme.spacingLg * 2

            ColumnLayout {
                id: transitionContent
                anchors.fill: parent
                anchors.margins: Theme.spacingLg
                spacing: Theme.spacingMd

                Text {
                    text: "Wallpaper Transitions"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeLg
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    text: "AWWW transitions are used for GIF wallpapers and for MP4/live wallpapers via a frame extracted from the video. The existing mpvpaper player is reused; the desktop is never screen-captured."
                    color: Theme.subtext0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    wrapMode: Text.WordWrap
                }

                SettingRow {
                    id: transitionEnabledRow
                    label: "Enable transitions"
                    ToggleSwitch {
                        checked: SettingsService.transitionEnabled
                        onToggled: SettingsService.set("transition_enabled", !SettingsService.transitionEnabled)
                    }
                }

                SettingRow {
                    id: transitionTypeRow
                    label: "Transition"
                    Layout.fillWidth: true

                    TransitionPicker {
                        id: transitionPicker
                        Layout.preferredWidth: 180
                        enabled: SettingsService.transitionEnabled
                        currentValue: SettingsService.transitionType
                        model: [
                            { label: "Fade", value: "fade" },
                            { label: "Simple", value: "simple" },
                            { label: "Slide Left", value: "left" },
                            { label: "Slide Right", value: "right" },
                            { label: "Slide Up", value: "top" },
                            { label: "Slide Down", value: "bottom" },
                            { label: "Wipe", value: "wipe" },
                            { label: "Wave", value: "wave" },
                            { label: "Grow", value: "grow" },
                            { label: "Center", value: "center" },
                            { label: "Any", value: "any" },
                            { label: "Outer", value: "outer" },
                            { label: "Random", value: "random" },
                            { label: "None", value: "none" }
                        ]
                        onActivated: (value) => SettingsService.set("transition_type", value)
                    }
                }

                SliderRow {
                    id: transitionDurationSlider
                    label: "Duration"
                    from: 0.15
                    to: 3.0
                    stepSize: 0.05
                    value: SettingsService.transitionDuration
                    suffix: " s"
                    enabled: SettingsService.transitionEnabled && SettingsService.transitionType !== "none" && SettingsService.transitionType !== "simple"
                    onMoved: SettingsService.set("transition_duration", Number(value.toFixed(2)))
                }

                Text {
                    Layout.fillWidth: true
                    text: "AWWW transitions also apply to MP4/video changes using a frame extracted directly from the video. No desktop screenshot is used."
                    color: Theme.overlay0
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    ConfirmDialog {
        id: deleteDialog
        anchors.fill: parent
        property string targetName: ""
        title: "Delete '" + targetName + "'?"
        message: "This removes the collection, not the wallpaper files."
        confirmText: "Delete"
        danger: true
        onAccepted: { CollectionService.remove(targetName); open = false; }
        onCancelled: open = false
    }

    RenameCollectionDialog {
        id: renameDialog
        anchors.fill: parent
    }

    RecolorCollectionDialog {
        id: recolorDialog
        anchors.fill: parent
    }
}
