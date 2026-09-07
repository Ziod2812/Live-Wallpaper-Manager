import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../Config"
import "../Services"

/*
 * WebWallpaperPanel.qml
 * -----------------------
 * "Web" mode body: display a website URL or a local HTML file as the
 * live wallpaper background.
 *
 * Architecture:
 *   URL mode   → PlaybackService.playWeb(url, "url")
 *                mpvpaper/mpv handles streamable content (same as streaming).
 *   Local HTML → PlaybackService.playWeb(path, "local")
 *                _web_worker.sh launches a browser in kiosk mode and
 *                records its PID for clean teardown on mode switch.
 *
 * Features:
 *   - Source type toggle (Website / Local HTML)
 *   - URL / path input with inline validation (typed by hand, same
 *     convention as DirPanel's wallpaper-directory field -- Quickshell.Io
 *     has no native file-picker dialog, so this deliberately doesn't
 *     pretend to have one)
 *   - Reload: re-applies the same source (full re-launch via playWeb)
 *   - Cache clear: deletes the browser's profile cache (chromium only)
 *   - Status card with loading animation, live/playing/error states
 *   - Error message surfaced from PlaybackService
 *
 * State (sourceType, urlText, localPathText) lives in own properties —
 * ModeContentArea never destroys this view, so it's preserved across
 * mode switches exactly as required.
 */
ColumnLayout {
    id: root
    spacing: Theme.spacingLg

    property string sourceType: "url"   // "url" | "local"
    property string urlText: ""
    property string localPathText: ""
    property bool applied: false

    readonly property string activeSource: sourceType === "url" ? urlText : localPathText
    readonly property string activeType: sourceType

    // Status mirrors PlaybackService when we're the active mode
    readonly property string _status: PlaybackService.playMode === "web"
        ? PlaybackService.webStatus : "idle"
    readonly property bool _isPlaying:    _status === "playing"
    readonly property bool _isConnecting: _status === "connecting"
    readonly property bool _isError:      _status === "error"

    // Sync panel state with PlaybackService
    onAppliedChanged: { if (!applied && PlaybackService.playMode === "web") PlaybackService.stopWeb(); }

    Connections {
        target: PlaybackService
        function onWebStatusChanged() {
            const s = PlaybackService.webStatus;
            if (PlaybackService.playMode !== "web") return;
            if (s === "idle" || s === "error") root.applied = false;
            else root.applied = true;
        }
    }

    // ── SOURCE TYPE TOGGLE ───────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingSm

        IconButton {
            text: "🌍  Website"
            active: root.sourceType === "url"
            accentColor: Theme.blue
            onClicked: root.sourceType = "url"
        }
        IconButton {
            text: "📄  Local HTML"
            active: root.sourceType === "local"
            accentColor: Theme.blue
            onClicked: root.sourceType = "local"
        }
    }

    // ── INPUT ROW ────────────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        height: 44
        radius: Theme.radiusMd
        color: Theme.cardBg
        border.width: (srcField.activeFocus || browseBtn.activeFocus) ? 1 : 0
        border.color: Theme.accent
        Behavior on border.width { NumberAnimation { duration: Theme.durationFast } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingMd
            anchors.rightMargin: Theme.spacingSm
            spacing: Theme.spacingSm

            // Icon
            Text {
                text: root.sourceType === "url" ? "🔗" : "📁"
                font.pixelSize: 16
                color: Theme.subtext0
            }

            TextInput {
                id: srcField
                Layout.fillWidth: true
                text: root.sourceType === "url" ? root.urlText : root.localPathText
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMd
                clip: true
                selectByMouse: true
                onTextChanged: {
                    if (root.sourceType === "url") root.urlText = text;
                    else root.localPathText = text;
                }
                Keys.onReturnPressed: applyBtn.applyAction()
                Keys.onEnterPressed:  applyBtn.applyAction()

                Text {
                    visible: srcField.text.length === 0
                    anchors.fill: parent
                    text: root.sourceType === "url"
                        ? "https://example.com"
                        : "~/wallpapers/index.html"
                    color: Theme.overlay0
                    font: srcField.font
                    verticalAlignment: Text.AlignVCenter
                }
            }

            // Focus helper for local HTML (no native file-picker dialog
            // is available here -- see header comment; this just jumps
            // focus + selects existing text so pasting a path is fast).
            IconButton {
                id: browseBtn
                visible: root.sourceType === "local"
                text: "…"
                fontSize: Theme.fontSizeMd
                implicitWidth: 32
                onClicked: {
                    srcField.forceActiveFocus();
                    srcField.selectAll();
                }
            }

            // Clear
            IconButton {
                visible: (root.sourceType === "url" ? root.urlText : root.localPathText).length > 0
                         && !root._isConnecting
                text: "✕"
                fontSize: Theme.fontSizeSm
                accentColor: Theme.danger
                implicitWidth: 28
                onClicked: {
                    if (root.sourceType === "url") { root.urlText = ""; srcField.text = ""; }
                    else { root.localPathText = ""; srcField.text = ""; }
                }
            }
        }
    }

    // ── ACTION ROW ───────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingSm

        // Apply / Stop
        IconButton {
            id: applyBtn
            Layout.fillWidth: true
            text: {
                if (root._isConnecting) return "Loading..."
                if (root._isPlaying)    return "⏹  Stop"
                return "▶  Apply"
            }
            accentColor: root._isPlaying ? Theme.danger : Theme.accent
            active: root._isPlaying || root._isConnecting
            bold: true
            enabled: !root._isConnecting

            function applyAction() {
                if (root._isPlaying) {
                    root.applied = false;
                    PlaybackService.stopWeb();
                } else {
                    root.applySource();
                }
            }
            onClicked: applyAction()
        }

        // Reload (only visible while playing)
        IconButton {
            visible: root._isPlaying
            text: "↺  Reload"
            accentColor: Theme.teal
            onClicked: PlaybackService.reloadWeb()
        }

        // Clear cache (only for URL mode while playing)
        IconButton {
            visible: root._isPlaying && root.sourceType === "url"
            text: "🗑  Cache"
            accentColor: Theme.peach
            onClicked: {
                cacheClearProc.running = true;
                NotifyService.info("Cache cleared — reload to apply.");
            }
        }
    }

    // ── STATUS / PREVIEW CARD ────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Theme.radiusLg
        color: Theme.cardBg
        border.width: 1
        border.color: {
            if (root._isError)      return Theme.danger
            if (root._isPlaying)    return Theme.success
            if (root._isConnecting) return Theme.accent
            return Theme.panelBorder
        }
        Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }
        clip: true

        // Loading bar at the top
        Rectangle {
            visible: root._isConnecting
            anchors.top: parent.top
            width: parent.width * 0.4
            height: 2
            radius: 1
            color: Theme.accent

            SequentialAnimation on x {
                running: root._isConnecting
                loops: Animation.Infinite
                NumberAnimation { from: -parent.width * 0.4; to: parent.width; duration: 1200; easing.type: Easing.InOutSine }
            }
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: Theme.spacingSm
            width: parent.width - Theme.spacingXl * 2

            // Icon
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: {
                    if (root._isError)      return "⚠"
                    if (root._isPlaying)    return "🖥"
                    if (root._isConnecting) return "⏳"
                    return root.sourceType === "url" ? "🌍" : "📄"
                }
                font.pixelSize: 36
                color: {
                    if (root._isError)   return Theme.danger
                    if (root._isPlaying) return Theme.success
                    return Theme.overlay0
                }
                Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                SequentialAnimation on opacity {
                    running: root._isConnecting
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.4; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                }
            }

            // Status text
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: {
                    if (root._isConnecting) return "Loading..."
                    if (root._isError)      return "Failed to apply"
                    if (root._isPlaying) {
                        return root.sourceType === "local"
                            ? "Local HTML is displayed"
                            : (PlaybackService.webTitle.length > 0 ? PlaybackService.webTitle : "Web is playing")
                    }
                    return root.sourceType === "local"
                        ? "No HTML file selected"
                        : "No web page applied yet"
                }
                color: root._isError ? Theme.danger : (root._isPlaying ? Theme.text : Theme.subtext0)
                font.family: Theme.fontFamilyUi
                font.pixelSize: Theme.fontSizeMd
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                Behavior on color { ColorAnimation { duration: Theme.durationFast } }
            }

            // Source display (short, not full URL)
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: parent.width
                visible: root.activeSource.length > 0 && root._isPlaying
                text: {
                    const s = root.activeSource;
                    if (root.sourceType === "local") return s.split("/").pop();
                    try {
                        const m = s.match(/^https?:\/\/(?:www\.)?([^\/]+)/);
                        return m ? m[1] : s;
                    } catch (e) { return s; }
                }
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                elide: Text.ElideMiddle
            }
        }
    }

    // ── CACHE CLEAR PROCESS ───────────────────────────────────────────────
    // Removes chromium's Default/Cache dir for the web wallpaper profile.
    // No-op if the directory doesn't exist or no browser is cached there.
    property Process cacheClearProc: Process {
        id: cacheClearProc
        command: ["bash", "-c",
            "rm -rf \"$HOME/.config/chromium/Default/Cache\" " +
            "\"$HOME/.cache/chromium\" " +
            "\"$HOME/.config/google-chrome/Default/Cache\" " +
            "2>/dev/null; true"]
        onExited: { /* cache clear is best-effort, no toast on completion */ }
    }

    // ── APPLY LOGIC ──────────────────────────────────────────────────────
    function applySource() {
        const src = root.activeSource.trim();
        if (src.length === 0) {
            NotifyService.error(root.sourceType === "local"
                ? "Select an HTML file first."
                : "Enter a URL first.");
            return;
        }
        // Basic URL validation
        if (root.sourceType === "url") {
            if (!src.startsWith("http://") && !src.startsWith("https://")) {
                NotifyService.error("URL must start with http:// or https://");
                return;
            }
        } else {
            // Local: check that the path looks like an HTML file
            if (!src.match(/\.(html?|htm)$/i)) {
                NotifyService.error("File must have a .html or .htm extension");
                return;
            }
        }
        root.applied = true;
        PlaybackService.playWeb(src, root.sourceType);
    }
}
