import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Services"

/*
 * StreamingPanel.qml
 * --------------------
 * "Streaming" mode body: play a live wallpaper from a remote URL
 * (YouTube / Twitch / Vimeo / Niconico / Bilibili / direct HLS / MP4).
 *
 * Architecture:
 *   - Calls PlaybackService.playUrl(url) — actual playback via mpvpaper/mpv
 *     with mpv's built-in yt-dlp handling stream resolution.
 *   - Calls PlaybackService.stopStream() to stop.
 *   - Thumbnail and title are resolved by PlaybackService via stream_info.sh
 *     in the background; the panel observes PlaybackService.stream* props.
 *   - History is session-local (stored in this component's ListModel, kept
 *     alive across mode switches because ModeContentArea never destroys views).
 *     Each entry stores the original URL + platform + title for display.
 *
 * Status badge reflects PlaybackService.streamStatus — and ONLY that;
 * never the URL, the platform guess, or whether the thumbnail/title has
 * arrived yet, so the badge can never say "Error" while mpvpaper is
 * genuinely playing, or get stuck on "Connecting" once it isn't. The
 * connecting -> playing/paused/buffering promotion itself is decided by
 * PlaybackService reading mpv's own IPC socket (real confirmation), not
 * by the launcher script's "I spawned the process" report:
 *   idle        → nothing playing                              "" (hidden)
 *   connecting  → dispatched, waiting for mpv IPC to answer      "Connecting"
 *   playing     → mpv IPC confirmed running, not live            "Playing"
 *   playing     → mpv IPC confirmed running, live source         "Live"
 *   buffering   → mpv IPC reports paused-for-cache                "Buffering"
 *   paused      → mpv IPC reports a user-initiated pause          "Paused"
 *   error       → mpvpaper/yt-dlp failed to start, OR mpvpaper    "Error"
 *                 died unexpectedly while playing/paused/buffering
 *   stopping    → stop in flight                                 "Stopping"
 *
 * Playback controls (time / seek bar / pause) only render once the
 * stream is actively playing/paused/buffering AND
 * PlaybackService.streamControlsReady is true, i.e. the mpv IPC socket
 * has actually answered at least once — never a fake ticking clock.
 */
ColumnLayout {
    id: root
    spacing: Theme.spacingLg

    // Own URL text buffer (preserved across mode switches)
    property string urlText: ""

    // ── Platform detection ───────────────────────────────────────────────
    readonly property var _platforms: [
        { key: "youtube",  label: "YouTube",   match: /youtu\.?be/i,        icon: "../assets/icons/youtube.svg",  color: "#f38ba8" },
        { key: "twitch",   label: "Twitch",    match: /twitch\.tv/i,         icon: "../assets/icons/twitch.svg",   color: "#cba6f7" },
        { key: "vimeo",    label: "Vimeo",     match: /vimeo\.com/i,         icon: "../assets/icons/vimeo.svg",    color: "#89b4fa" },
        { key: "bilibili", label: "Bilibili",  match: /bilibili\.com/i,      icon: "../assets/icons/bilibili.svg", color: "#89b4fa" },
        { key: "niconico", label: "Niconico",  match: /nicovideo\.jp/i,      icon: "../assets/icons/niconico.svg", color: "#fab387" },
        { key: "hls",      label: "HLS",       match: /\.m3u8(\?|$)/i,       icon: "../assets/icons/hls.svg",      color: "#94e2d5" },
        { key: "mp4",      label: "Direct",    match: /\.(mp4|webm|mkv)(\?|$)/i, icon: "../assets/icons/video.svg", color: "#89b4fa" }
    ]

    function _detectPlatform(url) {
        for (const p of _platforms) {
            if (p.match.test(url)) return p;
        }
        return url.length > 0
            ? { key: "generic", label: "Stream", icon: "../assets/icons/hls.svg", color: Theme.subtext0 }
            : null;
    }

    function _domainShort(url) {
        try {
            const m = url.match(/^https?:\/\/(?:www\.)?([^\/]+)/);
            return m ? m[1] : url;
        } catch (e) { return url; }
    }

    // Seconds -> "m:ss" or "h:mm:ss". Used by the seek bar's time labels.
    function _formatTime(totalSeconds) {
        const s = Math.max(0, Math.floor(totalSeconds || 0));
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        const sec = s % 60;
        const mm = h > 0 ? String(m).padStart(2, "0") : String(m);
        const ss = String(sec).padStart(2, "0");
        return h > 0 ? (h + ":" + mm + ":" + ss) : (mm + ":" + ss);
    }

    readonly property var detectedPlatform: _detectPlatform(urlText)

    // ── Internal state mirroring PlaybackService ─────────────────────────
    // streamStatus itself is the authoritative state PlaybackService
    // derives from real mpv IPC responses (see PlaybackService's
    // streamProgressProc) -- this panel only ever reads it, never
    // infers "playing"/"buffering"/"paused" from metadata, timers, or
    // the URL.
    readonly property string _status: PlaybackService.playMode === "streaming"
        ? PlaybackService.streamStatus : "idle"
    readonly property bool _isConnecting: _status === "connecting"
    readonly property bool _isPlaying:    _status === "playing"
    readonly property bool _isPaused:     _status === "paused"
    readonly property bool _isBuffering:  _status === "buffering"
    readonly property bool _isError:      _status === "error"
    readonly property bool _isStopping:   _status === "stopping"
    // "Actively streaming" -- mpv is genuinely up with a stream loaded,
    // whichever of the three sub-states it's currently in. Drives the
    // now-playing card, the playback toolbar, and the Play/Stop button.
    readonly property bool _isActive: _isPlaying || _isPaused || _isBuffering
    // streamIsLive comes from yt-dlp metadata -- never inferred from the
    // URL -- but only means anything once a stream is actually active.
    readonly property bool _isLive: _isActive && PlaybackService.streamIsLive

    readonly property string _statusLabel: {
        if (root._isError)      return "Error"
        if (root._isStopping)   return "Stopping"
        if (root._isPaused)     return "Paused"
        if (root._isBuffering)  return "Buffering"
        if (root._isLive)       return "Live"
        if (root._isPlaying)    return "Playing"
        if (root._isConnecting) return "Connecting"
        return ""
    }
    readonly property color _statusColor: {
        if (root._isError)      return Theme.danger
        if (root._isPaused)     return Theme.accent
        if (root._isBuffering)  return Theme.yellow
        if (root._isPlaying)    return Theme.success
        if (root._isConnecting) return Theme.accent
        return Theme.overlay0
    }

    // Session history (kept in memory, survives mode switches)
    ListModel { id: historyModel }

    function play() {
        const url = urlText.trim();
        if (url.length === 0) {
            NotifyService.error("Enter a URL before playing.");
            return;
        }
        // Add to history (dedup by URL, most recent first)
        let found = false;
        for (let i = 0; i < historyModel.count; i++) {
            if (historyModel.get(i).url === url) {
                historyModel.move(i, 0, 1);
                found = true;
                break;
            }
        }
        if (!found) {
            const pl = _detectPlatform(url);
            historyModel.insert(0, {
                url:      url,
                platform: pl ? pl.key   : "generic",
                label:    pl ? pl.label : "Stream",
                icon:     pl ? pl.icon  : "../assets/icons/hls.svg",
                accentColor: pl ? pl.color : Theme.subtext0,
                title:    ""
            });
            if (historyModel.count > 10) historyModel.remove(10);
        }
        PlaybackService.playUrl(url);
    }

    function stop() {
        PlaybackService.stopStream();
    }

    // Update history entry title when yt-dlp resolves it
    Connections {
        target: PlaybackService
        function onStreamTitleChanged() {
            const title = PlaybackService.streamTitle;
            const url   = PlaybackService.streamUrl;
            if (!title || !url) return;
            for (let i = 0; i < historyModel.count; i++) {
                if (historyModel.get(i).url === url) {
                    historyModel.setProperty(i, "title", title);
                    break;
                }
            }
        }
    }

    // ── URL INPUT ROW ────────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        height: 44
        radius: Theme.radiusMd
        color: Theme.cardBg
        border.width: urlField.activeFocus ? 1 : 0
        border.color: Theme.accent
        Behavior on border.width { NumberAnimation { duration: Theme.durationFast } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingMd
            anchors.rightMargin: Theme.spacingSm
            spacing: Theme.spacingSm

            // Platform icon
            Image {
                id: platformIcon
                source: root.detectedPlatform ? root.detectedPlatform.icon : "../assets/icons/hls.svg"
                width: 20; height: 20
                fillMode: Image.PreserveAspectFit
                opacity: root.detectedPlatform ? 1.0 : 0.4
                smooth: true
                Behavior on opacity { NumberAnimation { duration: Theme.durationFast } }
            }

            TextInput {
                id: urlField
                Layout.fillWidth: true
                text: root.urlText
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMd
                clip: true
                selectByMouse: true
                onTextChanged: root.urlText = text
                Keys.onReturnPressed: root.play()
                Keys.onEnterPressed: root.play()

                Text {
                    visible: urlField.text.length === 0
                    anchors.fill: parent
                    text: "YouTube, Twitch, Vimeo, .m3u8, .mp4 ..."
                    color: Theme.overlay0
                    font: urlField.font
                    verticalAlignment: Text.AlignVCenter
                }
            }

            // Clear button
            IconButton {
                visible: root.urlText.length > 0 && !root._isConnecting && !root._isActive
                text: "✕"
                fontSize: Theme.fontSizeSm
                accentColor: Theme.danger
                implicitWidth: 28
                onClicked: {
                    root.urlText = "";
                    urlField.text = "";
                }
            }
        }
    }

    // ── SOURCE ROW: platform pill · quality · loop · mute ─────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingSm

        // Platform label pill
        Rectangle {
            visible: root.detectedPlatform !== null
            height: 32
            radius: height / 2
            color: Qt.rgba(0, 0, 0, 0)
            border.width: 1
            border.color: root.detectedPlatform ? root.detectedPlatform.color : Theme.overlay0
            implicitWidth: platformLabelRow.implicitWidth + Theme.spacingMd * 2

            Row {
                id: platformLabelRow
                anchors.centerIn: parent
                spacing: 5

                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    source: root.detectedPlatform ? root.detectedPlatform.icon : ""
                    width: 16; height: 16
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.detectedPlatform ? root.detectedPlatform.label : ""
                    color: root.detectedPlatform ? root.detectedPlatform.color : Theme.overlay0
                    font.family: Theme.fontFamilyUi
                    font.pixelSize: Theme.fontSizeSm
                    font.bold: true
                }
            }
        }

        Item { Layout.fillWidth: true }

        // Quality stepper — "− 1080p FHD +". Caps yt-dlp's format
        // selection at that height (never upscales past what the source
        // actually offers); "Auto" leaves mpv/yt-dlp's own pick alone.
        // Persisted preference, applied live via relaunch just like
        // loop/mute below.
        Row {
            id: qualityStepper
            spacing: 4

            IconButton {
                text: "−"
                fontSize: Theme.fontSizeMd
                implicitWidth: 24
                enabled: PlaybackService.streamQualityIndex > 0
                opacity: enabled ? 1.0 : 0.35
                onClicked: PlaybackService.stepStreamQuality(-1)
            }

            Rectangle {
                width: qualityLbl.implicitWidth + 14
                height: 24
                anchors.verticalCenter: parent.verticalCenter
                radius: 6
                color: Theme.cardBg
                border.width: 1
                border.color: Theme.panelBorder

                Text {
                    id: qualityLbl
                    anchors.centerIn: parent
                    text: PlaybackService.streamQualityLabel
                    color: Theme.text
                    font.family: Theme.fontFamilyUi
                    font.pixelSize: Theme.fontSizeSm
                }
            }

            IconButton {
                text: "+"
                fontSize: Theme.fontSizeMd
                implicitWidth: 24
                enabled: PlaybackService.streamQualityIndex < PlaybackService.streamQualityLevels.length - 1
                opacity: enabled ? 1.0 : 0.35
                onClicked: PlaybackService.stepStreamQuality(1)
            }
        }

        // Loop toggle -- persisted preference (settings.json), also
        // applied live via a quick relaunch if a stream is already
        // playing/connecting. mpv silently ignores this for live streams.
        IconButton {
            id: loopBtn
            text: "󰑖"
            fontSize: Theme.fontSizeMd
            implicitWidth: 36
            active: PlaybackService.streamLoop
            accentColor: Theme.accent
            mutedColor: Theme.subtext0
            onClicked: PlaybackService.toggleStreamLoop()
        }

        // Mute toggle -- same persisted-preference + live-relaunch
        // behaviour as loop above.
        IconButton {
            id: muteBtn
            text: PlaybackService.streamMuted ? "🔇" : "🔊"
            fontSize: Theme.fontSizeMd
            implicitWidth: 36
            active: PlaybackService.streamMuted
            accentColor: Theme.danger
            mutedColor: Theme.subtext0
            onClicked: PlaybackService.toggleStreamMute()
        }
    }

    // ── PLAY / STOP BUTTON ───────────────────────────────────────────────
    IconButton {
        id: actionBtn
        Layout.fillWidth: true
        implicitHeight: 40
        text: {
            if (root._isStopping)   return "Stopping"
            if (root._isConnecting) return "Connecting"
            if (root._isActive)     return "⏹  Stop"
            return "▶  Play"
        }
        fontSize: Theme.fontSizeMd
        accentColor: root._isActive ? Theme.danger : Theme.success
        active: root._isActive || root._isConnecting
        bold: true
        enabled: !root._isConnecting && !root._isStopping

        onClicked: {
            if (root._isActive) root.stop();
            else root.play();
        }
    }

    // ── NOW PLAYING CARD ─────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        visible: PlaybackService.playMode === "streaming" && (_status !== "idle")
        height: 100
        radius: Theme.radiusLg
        color: Theme.cardBg
        border.width: 1
        border.color: root._status === "idle" ? Theme.panelBorder : root._statusColor
        Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }
        clip: true

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacingMd
            spacing: Theme.spacingMd

            // Thumbnail
            Rectangle {
                width: 120
                height: parent.height
                radius: Theme.radiusSm
                color: Theme.surface0
                clip: true

                Image {
                    id: thumbnailImg
                    anchors.fill: parent
                    source: PlaybackService.streamThumbnail
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    visible: status === Image.Ready

                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    onStatusChanged: opacity = (status === Image.Ready ? 1 : 0)
                }

                // Placeholder when no thumbnail
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    visible: thumbnailImg.status !== Image.Ready

                    Image {
                        anchors.centerIn: parent
                        source: root.detectedPlatform ? root.detectedPlatform.icon : "../assets/icons/hls.svg"
                        width: 40; height: 40
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        opacity: 0.5
                    }
                }

                // Live badge
                Rectangle {
                    visible: PlaybackService.streamIsLive && root._isActive
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: 4
                    width: liveLbl.implicitWidth + 8
                    height: 16
                    radius: 3
                    color: Theme.danger

                    Text {
                        id: liveLbl
                        anchors.centerIn: parent
                        text: "LIVE"
                        color: "#ffffff"
                        font.family: Theme.fontFamilyUi
                        font.pixelSize: 9
                        font.bold: true
                        font.letterSpacing: 0.5
                    }
                }
            }

            // Metadata
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 4

                // Status badge
                Row {
                    spacing: 6

                    Rectangle {
                        width: 8; height: 8; radius: 4
                        anchors.verticalCenter: parent.verticalCenter
                        color: root._statusColor
                        Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                        SequentialAnimation on opacity {
                            running: root._isConnecting || root._isBuffering
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.3; duration: 600; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root._statusLabel
                        color: root._statusColor
                        font.family: Theme.fontFamilyUi
                        font.pixelSize: Theme.fontSizeSm
                        font.bold: true
                    }
                }

                // Title
                Text {
                    Layout.fillWidth: true
                    text: PlaybackService.streamTitle || root._domainShort(PlaybackService.streamUrl)
                    color: Theme.text
                    font.family: Theme.fontFamilyUi
                    font.pixelSize: Theme.fontSizeMd
                    font.bold: true
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }

                // Uploader / source
                Text {
                    Layout.fillWidth: true
                    visible: PlaybackService.streamUploader.length > 0 || PlaybackService.streamUrl.length > 0
                    text: PlaybackService.streamUploader.length > 0
                        ? PlaybackService.streamUploader
                        : root._domainShort(PlaybackService.streamUrl)
                    color: Theme.subtext0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    elide: Text.ElideRight
                }

                // Quality info: source's own best-available resolution,
                // plus the active cap if the user set one below "Auto".
                Text {
                    Layout.fillWidth: true
                    visible: PlaybackService.streamHeightLabel.length > 0
                    text: "Source: " + PlaybackService.streamHeightLabel +
                          (PlaybackService.streamQuality !== "auto"
                              ? "  ·  Limit: " + PlaybackService.streamQualityLabel
                              : "")
                    color: Theme.subtext0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    elide: Text.ElideRight
                }

                Item { Layout.fillHeight: true }
            }
        }
    }

    // ── PLAYBACK CONTROLS ────────────────────────────────────────────────
    // Only appears once PlaybackService.streamControlsReady is true (the
    // mpv IPC socket has actually answered) AND the stream is actively
    // playing/paused/buffering -- never a fake/optimistic timer, and
    // never gated on the exact "playing" sub-state alone (that used to
    // make the whole toolbar disappear, and the pause button disable
    // itself, the instant the stream was merely paused).
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingXs
        visible: PlaybackService.playMode === "streaming" && root._isActive
                 && PlaybackService.streamControlsReady

        // Seek bar + pause/resume, on one row so it reads as a single
        // transport control rather than two disconnected widgets.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            IconButton {
                id: pauseBtn
                implicitWidth: 36
                fontSize: Theme.fontSizeMd
                text: PlaybackService.streamPaused ? "▶" : "⏸"
                accentColor: Theme.accent
                enabled: root._isActive
                onClicked: PlaybackService.toggleStreamPause()
            }

            // Current time (always shown once controls are ready, even
            // for live/unseekable sources -- it's still real elapsed
            // playback time from mpv, just with no fixed end point).
            Text {
                text: root._formatTime(PlaybackService.streamPosition)
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                horizontalAlignment: Text.AlignRight
                Layout.preferredWidth: 40
            }

            // Seek slider. Thin YouTube-style progress-bar look, wheel
            // support, and a generous hit area under the thin visible
            // track are all implemented exactly once in SettingSlider.qml
            // (also used by every MusicDockPanel.qml setting and by
            // MusicDock.qml's own progress slider) -- no hand-rolled
            // background/handle/wheel-MouseArea here anymore. inLayout:
            // true because this sits directly inside a real RowLayout
            // (unlike SettingRow's plain-Item slot), so the slider relies
            // on Layout.fillWidth for its width instead of anchors.
            //
            // Only shown when PlaybackService.streamSeekable is true,
            // i.e. duration is actually known and finite. Live sources
            // (or a VOD whose duration hasn't resolved yet) show the
            // LIVE badge below instead of a slider that could never
            // seek anywhere meaningful.
            SettingSlider {
                id: seekSlider
                inLayout: true
                barHeight: 24
                // Was 6/18 (the old always-visible chunky look) --
                // dropped down here too now that SettingSlider.qml's own
                // defaults (3px idle track, 11px idle thumb that's
                // hidden until hover/drag) are the thin YouTube-seek-bar
                // style every slider in the app uses.
                trackHeight: 3
                thumbSize: 11
                visible: PlaybackService.streamSeekable
                from: 0
                // Guard against from === to (duration momentarily 0
                // between a mode switch and the first IPC poll); the
                // slider is invisible in that state anyway.
                to: Math.max(PlaybackService.streamDuration, 0.001)

                // Deliberately NOT `value: PlaybackService.streamPosition`.
                // A plain property binding like that is destroyed the
                // instant the Slider itself writes to `value` (which
                // happens on the very first click/drag) -- QML binding
                // semantics, not a bug -- so every 1s IPC poll after
                // that would silently stop moving the handle. Instead,
                // position is pushed in imperatively, and ONLY while the
                // user isn't holding the handle, so the live poll and
                // the user's own drag can never fight over the same
                // property (no feedback loop, no jitter, no snap-back).
                Connections {
                    target: PlaybackService
                    function onStreamPositionChanged() {
                        if (!seekSlider.pressed) seekSlider.value = PlaybackService.streamPosition;
                    }
                    function onStreamDurationChanged() {
                        if (!seekSlider.pressed) seekSlider.value = PlaybackService.streamPosition;
                    }
                }
                Component.onCompleted: value = PlaybackService.streamPosition

                // Fires continuously as the handle moves -- covers both
                // "click to a position" and "drag" in one handler, same
                // as the old MouseArea's onPressed + onPositionChanged.
                // PlaybackService.seek() sets streamPosition optimistically
                // itself (corrected by the next IPC poll), so the current-
                // time label to the left updates in lockstep while dragging.
                onMoved: PlaybackService.seek(value)
            }

            // LIVE badge -- stands in for the slider whenever duration
            // isn't known/finite (live source, or a VOD whose length
            // hasn't resolved yet), instead of showing a slider stuck
            // at 0 that could never actually seek anywhere.
            Rectangle {
                visible: !PlaybackService.streamSeekable
                Layout.fillWidth: true
                Layout.preferredHeight: 20
                radius: height / 2
                color: "transparent"
                border.width: 1
                border.color: Theme.danger

                Row {
                    anchors.centerIn: parent
                    spacing: 5

                    Rectangle {
                        width: 6; height: 6; radius: 3
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.danger

                        SequentialAnimation on opacity {
                            running: PlaybackService.streamIsLive
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.3; duration: 600; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: PlaybackService.streamIsLive ? "LIVE" : "—"
                        color: Theme.danger
                        font.family: Theme.fontFamilyUi
                        font.pixelSize: Theme.fontSizeSm
                        font.bold: true
                        font.letterSpacing: 0.5
                    }
                }
            }

            // Total duration -- blank for live/unknown-length sources
            // rather than showing a misleading "0:00".
            Text {
                text: PlaybackService.streamSeekable ? root._formatTime(PlaybackService.streamDuration) : "--:--"
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                Layout.preferredWidth: 40
            }
        }
    }

    // ── HISTORY ──────────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingXs
        visible: historyModel.count > 0

        Text {
            text: "History"
            color: Theme.subtext0
            font.family: Theme.fontFamilyUi
            font.pixelSize: Theme.fontSizeSm
        }

        Repeater {
            model: historyModel
            delegate: Rectangle {
                required property string url
                required property string platform
                required property string label
                required property string icon
                required property var    accentColor
                required property string title
                required property int    index

                Layout.fillWidth: true
                height: 36
                radius: Theme.radiusSm
                color: hoverMouse.containsMouse ? Theme.cardHoverBg : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingSm
                    anchors.rightMargin: Theme.spacingXs
                    spacing: Theme.spacingSm

                    Image {
                        source: icon
                        width: 16; height: 16
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            Layout.fillWidth: true
                            text: title.length > 0 ? title : _domainShort(url)
                            color: Theme.text
                            font.family: Theme.fontFamilyUi
                            font.pixelSize: Theme.fontSizeSm
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: title.length > 0
                            text: _domainShort(url)
                            color: Theme.subtext0
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }

                    // Load button
                    IconButton {
                        text: "↺"
                        fontSize: Theme.fontSizeSm
                        implicitWidth: 28
                        mutedColor: Theme.subtext0
                        onClicked: {
                            root.urlText = url;
                            urlField.text = url;
                        }
                    }
                }

                MouseArea {
                    id: hoverMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                }
            }
        }
    }

    // Flexible spacer so the panel fills remaining height
    Item { Layout.fillWidth: true; Layout.fillHeight: true }
}
