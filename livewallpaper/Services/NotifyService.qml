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

    property Process notifyProc: Process { id: notifyProc }
}
