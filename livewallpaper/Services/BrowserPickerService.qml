pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

/*
 * BrowserPickerService.qml
 * ---------------------------
 * Detects installed web browsers (scripts/browser_picker.sh, which scans
 * the standard XDG application dirs for WebBrowser .desktop entries) so
 * Components/FileConverterPanel.qml's "Open File Converter" button can
 * offer a "choose a browser" popup instead of always going through
 * whatever Qt.openUrlExternally() resolves as the desktop's single
 * default. Same "small script + Paths.script() call, parse JSON via
 * StdioCollector" shape GPUManagerService.qml already uses.
 *
 *   browsers: [{id, name, exec, icon}, ...] -- detected once at startup
 *             (installed browsers essentially never change mid-session)
 *             and on-demand via refresh(). The system default browser
 *             (when resolvable) is sorted first by browser_picker.sh
 *             itself -- nothing to re-sort here.
 *   detected: false until the first detection pass completes (even if it
 *             finds zero browsers) -- lets the popup distinguish "still
 *             detecting" from "genuinely none found" rather than showing
 *             an empty list right at startup.
 *   launch(id, url): re-resolves <id> on the bash side (never trusts a
 *             stale Exec= string round-tripped back through QML) and
 *             opens it detached. Reports a NotifyService.error() if the
 *             browser can't be launched (e.g. uninstalled since the list
 *             was last refreshed).
 */
QtObject {
    id: service

    property var browsers: []       // [{id,name,exec,icon}, ...]
    property bool detected: false

    function refresh() {
        if (listProc.running) return;
        listProc.running = true;
    }

    property Process listProc: Process {
        command: ["bash", Paths.script("browser_picker.sh"), "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text);
                    service.browsers = Array.isArray(r) ? r : [];
                } catch (e) {
                    console.warn("BrowserPickerService: failed to parse list output:", e);
                    service.browsers = [];
                }
                service.detected = true;
            }
        }
    }

    // Fire-and-forget: browser_picker.sh's "launch" subcommand backgrounds
    // the actual browser process itself (setsid + disown), so this
    // Process only needs to run long enough to hand the request off --
    // it never blocks the UI.
    function launch(id, url) {
        launchProc.command = ["bash", Paths.script("browser_picker.sh"), "launch", id, url];
        launchProc.running = true;
    }

    property Process launchProc: Process {
        stderr: StdioCollector { id: launchErr }
        onExited: (code, status) => {
            if (code !== 0) {
                const msg = launchErr.text.trim();
                NotifyService.error(msg.length > 0 ? msg : "Couldn't open that browser -- it may have been uninstalled.");
            }
        }
    }

    Component.onCompleted: refresh()
}
