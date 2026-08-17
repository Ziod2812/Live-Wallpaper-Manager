#!/usr/bin/env bash
#
# folder_picker.sh [title] [start_dir]
# -------------------------------------
# Robust, cross-desktop native folder picker with automatic backend
# detection. Written for DirPanel.qml's "Browse..." button, but kept
# fully standalone (no LWM-specific env vars required) so it can be
# reused anywhere else in this project that needs a folder chooser.
#
# Backend fallback chain (first one found on PATH/D-Bus wins):
#   1. xdg-desktop-portal   -- via gdbus, talks to org.freedesktop.portal
#                              .FileChooser directly. Works on GNOME, KDE,
#                              Hyprland/wlroots compositors with a portal
#                              backend running -- no extra GUI toolkit
#                              needed, which is exactly the case that was
#                              broken before (many Arch/CachyOS installs
#                              have neither zenity nor yad, but DO have a
#                              portal running for screenshot/screen-share).
#   2. zenity --file-selection --directory
#   3. yad --file --directory
#   4. kdialog --getexistingdirectory
#   5. Qt (QtQuick.Dialogs FolderDialog) via the `qml` runtime -- Quickshell
#      itself is Qt6-based, so `qml` is a reasonably likely last resort
#      even when none of the dedicated dialog tools are installed.
#
# Output contract:
#   stdout -> ONLY the selected absolute directory path on success.
#             Nothing else is ever written to stdout, so callers can
#             safely do: dir="$(folder_picker.sh)"
#   stderr -> diagnostics / errors (never the path).
#   exit 0 -> a folder was selected (path printed on stdout).
#   exit 1 -> the user cancelled the dialog (no error -- this is normal).
#   exit 2 -> no working backend was found on this system.
#
# Timeout guarantee: every non-interactive command (D-Bus probes/calls) is
# bounded by $LW_PROBE_TIMEOUT (5s) and every interactive GUI backend by
# $LW_INTERACTIVE_TIMEOUT (600s, generous, since a real dialog window is
# legitimately waiting on the user). A timed-out backend is treated as a
# failure and the chain falls through to the next one -- this script always
# terminates and never hangs indefinitely.
#
# Debug logging: set DEBUG=1 (or LWM_DEBUG=1) in the environment to print
# "Starting backend...", "Backend timeout...", "Backend failed...",
# "Backend succeeded...", and "Selected folder..." lines to stderr.
#
# Usage: folder_picker.sh [title] [start_dir]

set -u

TITLE="${1:-Select folder}"
START_DIR="${2:-$HOME}"
case "$START_DIR" in
    "~"|"~/"*) START_DIR="${HOME}${START_DIR#\~}" ;;
esac
[ -d "$START_DIR" ] || START_DIR="$HOME"

# ---------------------------------------------------------------------------
# Debug logging. Enable with DEBUG=1 (or LWM_DEBUG=1) in the environment.
# Goes to stderr (as before, never contaminating the stdout path contract)
# AND, when DEBUG is on, to a persistent file -- stderr is only visible to
# the caller on a non-zero exit (DirPanel.qml only surfaces browseErr.text
# in the error branch), so a plain-stderr-only log is invisible for the
# success/cancel/timeout paths that are exactly what we need to see here.
# Override the file with LW_DEBUG_LOG=/some/path if /tmp isn't writable.
# ---------------------------------------------------------------------------
DEBUG="${DEBUG:-${LWM_DEBUG:-0}}"
LW_DEBUG_LOG="${LW_DEBUG_LOG:-/tmp/lwm_folder_picker_debug.log}"
LW_SCRIPT_PID=$$
lw_ts() { date '+%H:%M:%S.%3N'; }
lw_log() {
    [ "$DEBUG" != "1" ] && return 0
    local line
    line="$(lw_ts) [pid $LW_SCRIPT_PID] $*"
    printf '[folder_picker] %s\n' "$line" >&2
    printf '%s\n' "$line" >>"$LW_DEBUG_LOG" 2>/dev/null
    return 0
}

# ---------------------------------------------------------------------------
# lw_dump_children -- diagnostic proof of item #5/#6/#9: list every process
# that still lists this script's PID as its parent AND every background job
# this shell knows about, right before the script actually exits. If this
# is ever non-empty, THAT is the process keeping Quickshell's Process from
# reaching onExited (a live child holding the inherited stdout/stderr pipe
# open prevents EOF even after this shell itself has returned control).
# ---------------------------------------------------------------------------
lw_dump_children() {
    [ "$DEBUG" != "1" ] && return 0
    local kids
    kids="$(pgrep -P "$LW_SCRIPT_PID" 2>/dev/null)"
    if [ -n "$kids" ]; then
        lw_log "WARNING: live child processes still parented to $LW_SCRIPT_PID at exit:"
        while IFS= read -r pid; do
            [ -n "$pid" ] && lw_log "  pid=$pid cmd=$(ps -o args= -p "$pid" 2>/dev/null)"
        done <<<"$kids"
    else
        lw_log "no live children parented to $LW_SCRIPT_PID at exit (good)"
    fi
    local jobcount
    jobcount="$(jobs -pr 2>/dev/null | wc -l)"
    lw_log "background jobs still running in this shell: $jobcount"
}

# Belt-and-suspenders: whatever exit path is taken (normal, timeout, signal),
# kill any background job this shell itself started (e.g. a leftover
# `gdbus monitor` if a future code path forgets to reap it) so nothing this
# script spawned can outlive it and keep the parent's stdout/stderr pipe open.
trap 'lw_dump_children; for _p in $(jobs -pr 2>/dev/null); do kill -- "-$_p" 2>/dev/null || kill "$_p" 2>/dev/null; done' EXIT

lw_log "script entered: pid=$LW_SCRIPT_PID title='$TITLE' start_dir='$START_DIR'"

# Hard ceiling (seconds) for any single external command that is NOT
# legitimately waiting on the user (i.e. probes and non-interactive D-Bus
# calls). If one of these doesn't answer within this window, something is
# broken -- never wait on it, just move on to the next backend.
LW_PROBE_TIMEOUT=5

# ---------------------------------------------------------------------------
# lw_urldecode <percent-encoded string> -> decoded string on stdout.
# Pure-bash percent-decoder (no python/perl dependency) for turning a
# file:// URI's path component back into a real path.
# ---------------------------------------------------------------------------
lw_urldecode() {
    local encoded="${1//+/ }"
    printf '%b' "${encoded//%/\\x}"
}

# ---------------------------------------------------------------------------
# Backend 1: xdg-desktop-portal (org.freedesktop.portal.FileChooser)
# ---------------------------------------------------------------------------
# gdbus call's OpenFile returns the request object path synchronously; the
# real result arrives asynchronously as a Response signal on that object.
# `gdbus monitor` is used to observe that one signal (each signal is
# printed as a single line, which keeps the parsing below simple and
# reliable), bounded by a hard timeout so a portal that never responds
# (or a headless/misconfigured session) can never hang the caller.
try_portal() {
    command -v gdbus >/dev/null 2>&1 || { lw_log "portal: gdbus not on PATH, skipping"; return 1; }
    lw_log "Starting backend: xdg-desktop-portal"

    # A quick liveness probe: if nothing owns the portal name, don't even
    # try (avoids a multi-second timeout on systems with gdbus installed
    # but no portal service running at all).
    #
    # ROOT CAUSE OF THE FREEZE: this call used to run with no timeout at
    # all. `gdbus call` performs a synchronous D-Bus method call and will
    # sit waiting for a reply for as long as the bus/service lets it --
    # there is no built-in ceiling. On several Hyprland setups
    # org.freedesktop.portal.Desktop IS owned (so a naive "is anything
    # there?" check would pass) but the FileChooser interface is not
    # actually wired up to a responding backend (no portal implementation
    # configured for that interface in portals.conf), so the call can
    # hang indefinitely. Because this happens inside a command
    # substitution in a script that Quickshell's Process runs to
    # completion, the script itself never returns, onExited never fires,
    # and the Browse button is left stuck in "Browsing..." (disabled)
    # forever -- indistinguishable from the app freezing. Every
    # non-interactive D-Bus call below is now wrapped in
    # `timeout $LW_PROBE_TIMEOUT` so this can never happen again.
    timeout "$LW_PROBE_TIMEOUT" gdbus call --session \
        --dest org.freedesktop.DBus \
        --object-path /org/freedesktop/DBus \
        --method org.freedesktop.DBus.GetNameOwner \
        org.freedesktop.portal.Desktop >/dev/null 2>&1
    local probe_rc=$?
    if [ "$probe_rc" -ne 0 ]; then
        if [ "$probe_rc" -eq 124 ]; then
            lw_log "Backend timeout: xdg-desktop-portal (liveness probe did not answer within ${LW_PROBE_TIMEOUT}s)"
        else
            lw_log "Backend failed: xdg-desktop-portal (no portal service on the session bus)"
        fi
        return 1
    fi

    local token watch_out watch_pid handle waited=0 line code uri path call_rc
    token="lwmpick$$_$RANDOM"
    watch_out="$(mktemp)"

    # Listen for the Response signal before dispatching OpenFile, so we
    # can never miss a very fast (already-remembered-folder) response.
    if command -v setsid >/dev/null 2>&1; then
        setsid timeout 120 gdbus monitor --session --dest org.freedesktop.portal.Desktop \
            </dev/null > "$watch_out" 2>/dev/null &
    else
        timeout 120 gdbus monitor --session --dest org.freedesktop.portal.Desktop \
            </dev/null > "$watch_out" 2>/dev/null &
    fi
    watch_pid=$!
    lw_log "backgrounded gdbus monitor pid=$watch_pid, own process group via setsid (stdin/stdout/stderr fully redirected, none inherited from caller)"
    sleep 0.3

    # Same fix as the liveness probe above: OpenFile only needs to hand
    # back a request handle synchronously (the actual folder selection
    # arrives later, asynchronously, via the Response signal watched for
    # below) -- if it hasn't replied within a few seconds the backend is
    # broken, not just slow, so bound it and move on.
    handle="$(timeout "$LW_PROBE_TIMEOUT" gdbus call --session \
        --dest org.freedesktop.portal.Desktop \
        --object-path /org/freedesktop/portal/desktop \
        --method org.freedesktop.portal.FileChooser.OpenFile \
        "" "$TITLE" \
        "{'handle_token': <'$token'>, 'directory': <true>, 'multiple': <false>, 'current_folder': <b'$START_DIR'>}" \
        2>/dev/null)"
    call_rc=$?

    if [ "$call_rc" -eq 124 ]; then
        lw_log "Backend timeout: xdg-desktop-portal (OpenFile did not reply within ${LW_PROBE_TIMEOUT}s)"
        kill -- "-$watch_pid" 2>/dev/null || kill "$watch_pid" 2>/dev/null; wait "$watch_pid" 2>/dev/null
        rm -f "$watch_out"
        return 1
    fi

    if [ -z "$handle" ]; then
        lw_log "Backend failed: xdg-desktop-portal (no request handle returned)"
        kill -- "-$watch_pid" 2>/dev/null || kill "$watch_pid" 2>/dev/null; wait "$watch_pid" 2>/dev/null
        rm -f "$watch_out"
        return 1
    fi

    # Poll the captured monitor output for our token (up to 120s of user
    # browsing time -- generous, since the user is actively driving a
    # dialog, not waiting on us).
    while [ "$waited" -lt 1200 ]; do
        grep -q "$token" "$watch_out" 2>/dev/null && break
        sleep 0.1
        waited=$((waited + 1))
    done

    kill -- "-$watch_pid" 2>/dev/null || kill "$watch_pid" 2>/dev/null
    wait "$watch_pid" 2>/dev/null
    line="$(grep "$token" "$watch_out" 2>/dev/null | head -1)"
    rm -f "$watch_out"

    if [ -z "$line" ]; then
        lw_log "Backend timeout: xdg-desktop-portal (no Response signal within 120s)"
        echo "xdg-desktop-portal: no response from the folder-selection dialog (timed out)." >&2
        return 1
    fi

    code="$(printf '%s' "$line" | grep -oE 'uint32 [0-9]+' | head -1 | awk '{print $2}')"
    if [ "$code" != "0" ]; then
        # 1 = user cancelled, 2 = dialog dismissed by other means -- both
        # are a normal "no folder chosen", not an error.
        lw_log "xdg-desktop-portal: user cancelled"
        return 3
    fi

    uri="$(printf '%s' "$line" | grep -oE "file://[^'\"]*" | head -1)"
    if [ -z "$uri" ]; then
        lw_log "Backend failed: xdg-desktop-portal (reported success but no URI)"
        echo "xdg-desktop-portal: dialog reported success but no folder URI was returned." >&2
        return 1
    fi
    path="$(lw_urldecode "${uri#file://}")"
    if [ -z "$path" ] || [ ! -d "$path" ]; then
        lw_log "Backend failed: xdg-desktop-portal (returned path does not exist: $path)"
        echo "xdg-desktop-portal: returned path does not exist: $path" >&2
        return 1
    fi
    lw_log "Backend succeeded: xdg-desktop-portal"
    lw_log "Selected folder: $path"
    printf '%s\n' "$path"
    return 0
}

# Belt-and-suspenders ceiling for the interactive GUI backends below.
# These are *expected* to block while a real dialog window is open and the
# user is actively browsing -- that is normal, not a freeze, since it runs
# in a separate OS process and never blocks the Quickshell UI thread. This
# timeout exists only as a last-resort safety net against a backend that
# fails to even show a window and hangs silently (e.g. a broken GTK/Qt
# install) -- generous enough to never interrupt real usage.
LW_INTERACTIVE_TIMEOUT=600

# ---------------------------------------------------------------------------
# Backend 2: zenity
# ---------------------------------------------------------------------------
try_zenity() {
    command -v zenity >/dev/null 2>&1 || { lw_log "zenity not on PATH, skipping"; return 1; }
    lw_log "Starting backend: zenity"
    local out status
    out="$(timeout "$LW_INTERACTIVE_TIMEOUT" zenity --file-selection --directory --title="$TITLE" --filename="$START_DIR/" 2>/dev/null)"
    status=$?
    if [ $status -eq 0 ] && [ -n "$out" ]; then
        lw_log "Backend succeeded: zenity"
        lw_log "Selected folder: $out"
        printf '%s\n' "$out"
        return 0
    fi
    if [ $status -eq 124 ]; then
        lw_log "Backend timeout: zenity (no response within ${LW_INTERACTIVE_TIMEOUT}s)"
        return 1
    fi
    if [ $status -eq 1 ]; then
        lw_log "zenity: user cancelled"
        return 3 # user cancelled
    fi
    lw_log "Backend failed: zenity (exit $status)"
    return 1
}

# ---------------------------------------------------------------------------
# Backend 3: yad
# ---------------------------------------------------------------------------
try_yad() {
    command -v yad >/dev/null 2>&1 || { lw_log "yad not on PATH, skipping"; return 1; }
    lw_log "Starting backend: yad"
    local out status
    out="$(timeout "$LW_INTERACTIVE_TIMEOUT" yad --file --directory --title="$TITLE" --filename="$START_DIR/" 2>/dev/null)"
    status=$?
    out="${out%|}" # yad appends a trailing '|' to its output
    if [ $status -eq 0 ] && [ -n "$out" ]; then
        lw_log "Backend succeeded: yad"
        lw_log "Selected folder: $out"
        printf '%s\n' "$out"
        return 0
    fi
    if [ $status -eq 124 ]; then
        lw_log "Backend timeout: yad (no response within ${LW_INTERACTIVE_TIMEOUT}s)"
        return 1
    fi
    if [ $status -eq 1 ]; then
        lw_log "yad: user cancelled"
        return 3
    fi
    lw_log "Backend failed: yad (exit $status)"
    return 1
}

# ---------------------------------------------------------------------------
# Backend 4: kdialog
# ---------------------------------------------------------------------------
try_kdialog() {
    command -v kdialog >/dev/null 2>&1 || { lw_log "kdialog not on PATH, skipping"; return 1; }
    lw_log "Starting backend: kdialog"
    local out status
    out="$(timeout "$LW_INTERACTIVE_TIMEOUT" kdialog --getexistingdirectory "$START_DIR" --title "$TITLE" 2>/dev/null)"
    status=$?
    if [ $status -eq 0 ] && [ -n "$out" ]; then
        lw_log "Backend succeeded: kdialog"
        lw_log "Selected folder: $out"
        printf '%s\n' "$out"
        return 0
    fi
    if [ $status -eq 124 ]; then
        lw_log "Backend timeout: kdialog (no response within ${LW_INTERACTIVE_TIMEOUT}s)"
        return 1
    fi
    if [ $status -eq 1 ]; then
        lw_log "kdialog: user cancelled"
        return 3
    fi
    lw_log "Backend failed: kdialog (exit $status)"
    return 1
}

# ---------------------------------------------------------------------------
# Backend 5: Qt FileDialog, run headless through the `qml` runtime.
# Last resort -- speculative (not every Qt install ships the `qml` CLI
# tool), but Quickshell itself is Qt6/QML-based, so it is a reasonably
# likely fallback specifically on the systems this project targets.
# ---------------------------------------------------------------------------
try_qt() {
    command -v qml >/dev/null 2>&1 || { lw_log "qml runtime not on PATH, skipping"; return 1; }
    lw_log "Starting backend: qt (qml FolderDialog)"
    local qml_file out status
    qml_file="$(mktemp --suffix=.qml)"
    cat > "$qml_file" <<QMLEOF
import QtQuick
import QtQuick.Dialogs

Item {
    FolderDialog {
        id: dlg
        title: "$TITLE"
        currentFolder: "file://$START_DIR"
        onAccepted: { console.log("LWM_FOLDER_PICKED:" + selectedFolder); Qt.exit(0); }
        onRejected: { Qt.exit(1); }
    }
    Component.onCompleted: dlg.open()
}
QMLEOF
    out="$(timeout 120 qml "$qml_file" 2>/dev/null)"
    status=$?
    rm -f "$qml_file"

    if [ $status -eq 124 ]; then
        lw_log "Backend timeout: qt (qml runtime did not exit within 120s)"
        return 1
    fi
    if [ $status -eq 1 ]; then
        lw_log "qt: user cancelled"
        return 3 # user cancelled
    fi
    local uri path
    uri="$(printf '%s' "$out" | grep 'LWM_FOLDER_PICKED:' | sed 's/^LWM_FOLDER_PICKED://' | tail -1)"
    if [ -z "$uri" ]; then
        lw_log "Backend failed: qt (no folder reported)"
        return 1
    fi
    path="$(lw_urldecode "${uri#file://}")"
    if [ -z "$path" ] || [ ! -d "$path" ]; then
        lw_log "Backend failed: qt (returned path does not exist: $path)"
        echo "Qt FileDialog: returned path does not exist: $path" >&2
        return 1
    fi
    lw_log "Backend succeeded: qt"
    lw_log "Selected folder: $path"
    printf '%s\n' "$path"
    return 0
}

# ---------------------------------------------------------------------------
# Run the chain in order. Each try_* function's return code means:
#   0 -> success, path already printed
#   3 -> user cancelled (stop the whole chain -- don't fall through to a
#        different backend just because the user closed the dialog)
#   1 -> backend unavailable OR it genuinely failed -- try the next one
# ---------------------------------------------------------------------------
for backend in try_portal try_zenity try_yad try_kdialog try_qt; do
    lw_log "entering backend: $backend"
    "$backend"
    rc=$?
    lw_log "backend exited: $backend rc=$rc"
    case $rc in
        0) lw_log "before exit: code=0 (success)"; exit 0 ;;
        3) lw_log "User cancelled via $backend"; lw_log "before exit: code=1 (cancel)"; exit 1 ;;
        *) continue ;;
    esac
done

lw_log "No backend succeeded -- exhausted the full fallback chain"
echo "No folder-selection backend available. Install one of: xdg-desktop-portal (with a running portal backend), zenity, yad, or kdialog." >&2
lw_log "before exit: code=2 (no backend available)"
exit 2
