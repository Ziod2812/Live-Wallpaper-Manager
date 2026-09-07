import QtQuick
import QtQuick.Window
import QtMultimedia
import Qt.labs.platform as Platform

/*
 * main.qml -- Live Wallpaper Manager bridge for KDE Plasma
 * ----------------------------------------------------------------------
 * WHY THIS FILE EXISTS
 *
 * Live Wallpaper Manager's normal playback path is mpvpaper, which
 * renders via the Wayland wlr-layer-shell protocol, which requires a
 * Wayland session outright (it cannot connect to X11 at all) and which
 * KWin (KDE Plasma's compositor) does not support the way wlroots
 * compositors (Hyprland, Sway, ...) do even on Wayland -- a wlr-layer-shell
 * wallpaper surface can visibly break (go blank) on KDE Plasma Wayland
 * when the desktop containment regains input, e.g. on a click -- this
 * is a known upstream limitation, not something fixable by changing
 * mpvpaper's launch flags.
 *
 * This file sidesteps that entirely: it is a genuine Plasma Wallpaper
 * KPackage plugin (see ../../metadata.json), loaded by plasmashell
 * itself through KDE's OWN wallpaper plugin system -- the same
 * mechanism the built-in "Image"/"Slideshow" wallpapers use. Nothing
 * here talks to wlr-layer-shell or mpvpaper, so it renders identically
 * on Plasma Wayland AND Plasma X11 (KWin X11) -- on X11 it's the only
 * way to get video wallpaper at all, since mpvpaper cannot run there.
 *
 * WHAT IT DOES
 *
 * It does not run mpv/mpvpaper at all. It just reads the SAME state
 * files scripts/utils.sh already writes (the per-monitor "current"
 * file, plus settings.json) and plays whatever is there with Qt's own
 * QtMultimedia, styled to match this screen's real output name.
 *
 * WHAT IT DOES NOT DO (scope, read before reporting something as broken)
 *
 *   - Streaming mode: only a DIRECT, already-playable URL (http(s)
 *     pointing straight at raw video/HLS, e.g. a Twitch HLS link or a
 *     plain .mp4 URL) can play here. A youtube.com/twitch.tv/etc PAGE
 *     URL needs yt-dlp to resolve first -- that resolution happens in
 *     scripts/_stream_worker.sh (a shell script), and plain QML in a
 *     Plasma wallpaper plugin has no facility to shell out to yt-dlp
 *     itself, so those stay unplayed here (this instance just holds on
 *     black) until Live Wallpaper Manager's own resolved-URL support
 *     is extended to also publish a QtMultimedia-playable URL.
 *   - Web wallpaper mode (kiosk browser / arbitrary HTML): not a video
 *     source at all, out of scope for this bridge.
 *   - Any of the Manager window's own playback controls (next/prev/
 *     pause seek bar etc.) still only work while the underlying
 *     mpvpaper/browser process they were built for is actually the one
 *     playing -- this bridge is read-only, it never launches or
 *     controls anything, it only mirrors whatever state is already on
 *     disk.
 *
 * VERIFICATION STATUS: written from KDE/Qt6/Plasma6 documentation and
 * established QML patterns, but NOT exercised against a live
 * plasmashell session (none available in the environment this was
 * written in). Please report the exact behaviour (including anything
 * printed by `plasmashell --replace` in a terminal) so this can be
 * corrected against reality rather than assumption.
 */

Item {
    id: root
    anchors.fill: parent

    // ── Paths -- MUST mirror scripts/utils.sh's LW_* layout exactly ────
    readonly property string homeDir: {
        var u = Platform.StandardPaths.writableLocation(Platform.StandardPaths.HomeLocation).toString();
        return u.replace("file://", "");
    }
    readonly property string cacheDir: homeDir + "/.cache/livewallpaper"
    readonly property string stateDir: cacheDir + "/state"
    readonly property string settingsFile: homeDir + "/.config/quickshell/livewallpaper/data/settings.json"

    // Mirrors scripts/utils.sh's lw_sanitize_monitor_name(): anything
    // outside [A-Za-z0-9._-] becomes "_", so this resolves to the exact
    // same per-monitor directory the app's own scripts write to.
    function sanitizeMonitorName(name) {
        return (name || "").replace(/[^A-Za-z0-9._-]/g, "_");
    }

    readonly property string screenName: (typeof Window !== "undefined" && Window.screen) ? Window.screen.name : ""
    // lw_monitor_state_dir() treats "" (no monitor resolved) as the
    // legacy top-level cache dir, not an error -- matched here too.
    readonly property string monitorDir: screenName.length > 0
        ? (stateDir + "/" + sanitizeMonitorName(screenName))
        : cacheDir
    readonly property string currentFile: monitorDir + "/current"

    // ── Small synchronous local-file reads (state/settings only -- small
    // files, polled a few times a minute, not a hot path) ──────────────
    function readFile(path) {
        var xhr = new XMLHttpRequest();
        try {
            xhr.open("GET", "file://" + path, false);
            xhr.send();
        } catch (e) {
            return "";
        }
        if (xhr.status === 200 || xhr.status === 0) return xhr.responseText;
        return "";
    }

    property string mediaSource: ""
    // "wallpaper" (local video, always silent -- matches mpv_opts'
    // hard-coded "no-audio" for this mode in utils.sh) | "stream"
    // (direct playable URL, honors the app's volume/mute settings) | ""
    property string modeKind: ""
    property var settingsData: ({})

    function refresh() {
        var raw = readFile(root.currentFile).replace(/^\s+|\s+$/g, "");

        var settingsText = readFile(root.settingsFile);
        try {
            root.settingsData = settingsText ? JSON.parse(settingsText) : {};
        } catch (e) {
            root.settingsData = {};
        }

        var src = "";
        var kind = "";

        if (raw.length === 0) {
            src = "";
        } else if (raw.indexOf("stream:") === 0) {
            var url = raw.substring("stream:".length);
            var needsResolution = /youtu\.?be|twitch\.tv|vimeo\.com|nicovideo\.jp|bilibili\.com|dailymotion\.com/i.test(url);
            if (!needsResolution && /^https?:\/\//i.test(url)) {
                src = url;
                kind = "stream";
            }
            // else: page URL that needs yt-dlp resolution -- see the
            // header comment. Left blank on purpose rather than handed
            // to QtMultimedia, which cannot open it either way.
        } else if (raw.indexOf("web:") === 0 || raw.indexOf("web-local:") === 0) {
            // Web wallpaper mode -- not a video source, out of scope.
            src = "";
        } else {
            // Local video wallpaper mode: a plain filesystem path.
            src = "file://" + raw;
            kind = "wallpaper";
        }

        root.mediaSource = src;
        root.modeKind = kind;
    }

    Timer {
        interval: 1500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // ── Settings mirrored from settings.json ────────────────────────────
    // Local video wallpaper mode is always silent in this project (see
    // utils.sh's mpv_opts="loop no-audio ..."), so only "stream" mode
    // reads the volume/mute settings at all.
    readonly property bool streamMuted: root.settingsData && root.settingsData.enable_video_sound !== true
    readonly property real streamVolume: {
        var v = root.settingsData ? root.settingsData.video_volume : undefined;
        return (typeof v === "number") ? Math.max(0, Math.min(100, v)) / 100 : 1.0;
    }
    readonly property bool cropFill: root.settingsData && root.settingsData.mpvpaper_fill_type === "Crop"

    readonly property bool effectiveMuted: root.modeKind === "wallpaper" ? true : root.streamMuted
    readonly property real effectiveVolume: root.modeKind === "wallpaper" ? 0 : root.streamVolume

    // ── Playback ─────────────────────────────────────────────────────
    MediaPlayer {
        id: player
        source: root.mediaSource
        loops: MediaPlayer.Infinite
        audioOutput: AudioOutput {
            muted: root.effectiveMuted
            volume: root.effectiveVolume
        }
        videoOutput: videoOut
        onSourceChanged: {
            if (source && source.toString().length > 0) play();
            else stop();
        }
        // A dead/unreachable stream URL, a codec QtMultimedia's backend
        // can't decode, etc. -- surface it in the wallpaper's own log
        // stream (journalctl --user -u plasma-plasmashell, or whatever
        // captures plasmashell's stderr) rather than failing silently.
        onErrorOccurred: (error, errorString) => {
            console.warn("Live Wallpaper Manager (KDE bridge): playback error:", errorString, "for", root.mediaSource);
        }
    }

    VideoOutput {
        id: videoOut
        anchors.fill: parent
        fillMode: root.cropFill ? VideoOutput.PreserveAspectCrop : VideoOutput.PreserveAspectFit
        visible: root.mediaSource.length > 0
    }

    // Fallback fill so an idle/unsupported state (nothing applied, web
    // mode, an unresolved stream URL) isn't left showing Plasma's
    // default checkerboard/transparent view.
    Rectangle {
        anchors.fill: parent
        color: "black"
        visible: !videoOut.visible
    }
}
