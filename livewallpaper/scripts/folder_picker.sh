#!/usr/bin/env bash
# folder_picker.sh -- cross-desktop folder SELECTION dialog.
#
# Prints the chosen absolute path to stdout and exits 0.
# Exit 1  = user cancelled the dialog (stay quiet, this is normal).
# Exit 2+ = a real error -- stderr carries a human-readable message,
#           which DirPanel.qml forwards to NotifyService.error().
#
# TIER 1 -- native folder-selection dialogs (auto-return the chosen
# path, no manual copy/paste needed): zenity -> kdialog -> yad -> qarma
# -> python3/tkinter. These are the lightweight dialog backends behind
# GNOME/XFCE/Cinnamon (zenity), KDE (kdialog), and LXDE/LXQt/minimal
# setups (yad/qarma/tkinter) -- normally already present alongside the
# matching file manager without installing anything extra.
#
# TIER 2 -- if NONE of the above are installed, fall back to simply
# opening the user's actual file manager so they can at least browse
# and copy the path by hand, tried in this fixed priority:
#   Nautilus (GNOME Files) -> Dolphin (KDE) -> Thunar (XFCE)
#   -> Nemo (Cinnamon) -> PCManFM (LXDE/LXQt)
# This tier can't auto-return a path (these apps have no "pick and
# print" CLI mode), so it just echoes back the starting directory and
# leaves the window open for the user to navigate/copy manually.
#
# NOTE ON xdg-desktop-portal: an earlier version of this script drove
# the folder chooser through the desktop portal (a raw gdbus call with
# no timeout). A wedged/slow portal service could hang it indefinitely
# -- this was the documented ROOT CAUSE OF THE FREEZE referenced from
# smart_playback_poll.sh. Deliberately not reintroduced here.

TITLE="${1:-Select Folder}"
START="${2:-$HOME}"
mkdir -p "$START" 2>/dev/null

PID=$$
LOG="${LW_DEBUG_LOG:-/tmp/lwm_folder_picker_debug.log}"
_dbg() {
    if [ "${LWM_DEBUG:-0}" = "1" ] || [ "${DEBUG:-0}" = "1" ]; then
        printf '[pid %s] %s %s\n' "$PID" "$(date -Iseconds)" "$1" >>"$LOG" 2>/dev/null
    fi
}

_dbg "folder_picker.sh start: title=\"$TITLE\" start=\"$START\""

# zenity/yad want the start dir to end in / to browse *into* it rather
# than pre-select a sibling of that name.
case "$START" in
    */) START_SLASH="$START" ;;
    *) START_SLASH="$START/" ;;
esac

result=""
status=1
backend=""

if command -v zenity >/dev/null 2>&1; then
    backend="zenity"
    _dbg "trying zenity"
    result="$(zenity --file-selection --directory --title="$TITLE" --filename="$START_SLASH" 2>>"$LOG")"
    status=$?

elif command -v kdialog >/dev/null 2>&1; then
    backend="kdialog"
    _dbg "trying kdialog"
    result="$(kdialog --title "$TITLE" --getexistingdirectory "$START" 2>>"$LOG")"
    status=$?

elif command -v yad >/dev/null 2>&1; then
    backend="yad"
    _dbg "trying yad"
    result="$(yad --file --directory --title="$TITLE" --filename="$START_SLASH" 2>>"$LOG")"
    status=$?

elif command -v qarma >/dev/null 2>&1; then
    backend="qarma"
    _dbg "trying qarma"
    result="$(qarma --file-selection --directory --title="$TITLE" --filename="$START_SLASH" 2>>"$LOG")"
    status=$?

elif command -v python3 >/dev/null 2>&1 && python3 -c "import tkinter" >/dev/null 2>&1; then
    backend="python3/tkinter"
    _dbg "trying python3/tkinter"
    result="$(python3 - "$TITLE" "$START" <<'PYEOF' 2>>"$LOG"
import sys, tkinter, tkinter.filedialog
title, start = sys.argv[1], sys.argv[2]
root = tkinter.Tk()
root.withdraw()
path = tkinter.filedialog.askdirectory(title=title, initialdir=start, mustexist=True)
root.destroy()
print(path)
PYEOF
)"
    status=$?
    if [ -z "$result" ]; then status=1; fi
fi

_dbg "tier1 backend=\"$backend\" exit=$status result=\"$result\""

if [ -n "$backend" ]; then
    if [ "$status" -eq 0 ] && [ -n "$result" ]; then
        printf '%s\n' "$result"
        _dbg "success via $backend: \"$result\""
        exit 0
    elif [ "$status" -eq 1 ] || [ -z "$result" ]; then
        _dbg "cancelled by user ($backend)"
        exit 1
    else
        _dbg "$backend error, exit=$status"
        echo "Folder picker ($backend) exited with an error (code $status)." >&2
        exit "$status"
    fi
fi

# ---- TIER 2: no native dialog backend installed -- open a file
# manager instead, in the fixed priority below. This can't capture a
# selection, so it just echoes the starting directory back; the user
# navigates and copies the path manually.
_dbg "no dialog backend found, falling back to file managers"

for fm in nautilus dolphin thunar nemo pcmanfm; do
    if command -v "$fm" >/dev/null 2>&1; then
        _dbg "opening file manager fallback: $fm"
        nohup "$fm" "$START" >/dev/null 2>&1 &
        disown 2>/dev/null || true
        printf '%s\n' "$START"
        exit 0
    fi
done

_dbg "no file manager found either, trying xdg-open"
if command -v xdg-open >/dev/null 2>&1; then
    nohup xdg-open "$START" >/dev/null 2>&1 &
    disown 2>/dev/null || true
    printf '%s\n' "$START"
    exit 0
fi

_dbg "nothing available at all"
echo "No folder picker or file manager found. Install zenity, kdialog, yad, qarma, or a file manager." >&2
exit 2
