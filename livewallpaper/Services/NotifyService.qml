pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

/*
 * NotifyService.qml
 * --------------------
 * Small helper for surfacing short-lived messages (errors, "Directory
 * changed", "Cache cleared", ...). Emits `toast(message, isError)` for
 * Components/Toast.qml to display inline in the panel, and optionally
 * mirrors it to the desktop via notify-send for messages that happen
 * while the panel itself is closed (e.g. an autostart failure).
 */
QtObject {
    id: service

    signal toast(string message, bool isError)

    function info(message) {
        toast(message, false);
    }

    function error(message) {
        toast(message, true);
    }

    function desktop(message, urgent) {
        // PHASE 4 -- "Notifications" setting (SettingsPage.qml's new
        // Application section). Defaults to true so behavior is
        // unchanged for existing users who never touch the new toggle.
        if (SettingsService.settings.notifications_enabled === false) return;
        notifyProc.command = ["bash", "-c",
            "command -v notify-send >/dev/null 2>&1 && notify-send " +
            (urgent ? "-u critical " : "") +
            "'Live Wallpaper' " + JSON.stringify(message)];
        notifyProc.running = true;
    }

    property Process notifyProc: Process { id: notifyProc }
}
