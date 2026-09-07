#!/usr/bin/env bash
# file_picker.sh -- cross-desktop FILE selection dialog (open or save).
#
# Sibling of folder_picker.sh, same backend priority and exit-code
# contract, but picks a single file instead of a directory -- used by
# DiagnosticsPage.qml's Export/Import buttons so the profile backup
# actually goes wherever the user chooses instead of a hardcoded path.
#
# Usage: file_picker.sh <open|save> <title> <start path> [filter label] [filter pattern]
#   start path: a directory to open in, or a full path (dir + filename)
#               to pre-fill -- save dialogs use this as the suggested
#               file name.
#   filter label/pattern: optional, e.g. "JSON files" "*.json".
#
# Prints the chosen absolute path to stdout and exits 0.
# Exit 1  = user cancelled the dialog (stay quiet, this is normal).
# Exit 2+ = a real error -- stderr carries a human-readable message.

MODE="${1:-open}"
TITLE="${2:-Select File}"
START="${3:-$HOME}"
FILTER_LABEL="${4:-}"
FILTER_PATTERN="${5:-}"

START_DIR="$START"
[ -d "$START_DIR" ] || START_DIR="$(dirname -- "$START_DIR")"
mkdir -p "$START_DIR" 2>/dev/null

PID=$$
LOG="${LW_DEBUG_LOG:-/tmp/lwm_file_picker_debug.log}"
_dbg() {
    if [ "${LWM_DEBUG:-0}" = "1" ] || [ "${DEBUG:-0}" = "1" ]; then
        printf '[pid %s] %s %s\n' "$PID" "$(date -Iseconds)" "$1" >>"$LOG" 2>/dev/null
    fi
}

_dbg "file_picker.sh start: mode=\"$MODE\" title=\"$TITLE\" start=\"$START\""

result=""
status=1
backend=""

if command -v zenity >/dev/null 2>&1; then
    backend="zenity"
    _dbg "trying zenity"
    args=(--file-selection --title="$TITLE" --filename="$START")
    [ "$MODE" = "save" ] && args+=(--save --confirm-overwrite)
    [ -n "$FILTER_PATTERN" ] && args+=(--file-filter="${FILTER_LABEL:-Files} | $FILTER_PATTERN")
    result="$(zenity "${args[@]}" 2>>"$LOG")"
    status=$?

elif command -v kdialog >/dev/null 2>&1; then
    backend="kdialog"
    _dbg "trying kdialog"
    if [ "$MODE" = "save" ]; then
        result="$(kdialog --title "$TITLE" --getsavefilename "$START" "$FILTER_PATTERN" 2>>"$LOG")"
    else
        result="$(kdialog --title "$TITLE" --getopenfilename "$START" "$FILTER_PATTERN" 2>>"$LOG")"
    fi
    status=$?

elif command -v yad >/dev/null 2>&1; then
    backend="yad"
    _dbg "trying yad"
    args=(--file --title="$TITLE" --filename="$START")
    [ "$MODE" = "save" ] && args+=(--save --confirm-overwrite)
    [ -n "$FILTER_PATTERN" ] && args+=(--file-filter="${FILTER_LABEL:-Files} | $FILTER_PATTERN")
    result="$(yad "${args[@]}" 2>>"$LOG")"
    status=$?

elif command -v qarma >/dev/null 2>&1; then
    backend="qarma"
    _dbg "trying qarma"
    args=(--file-selection --title="$TITLE" --filename="$START")
    [ "$MODE" = "save" ] && args+=(--save --confirm-overwrite)
    [ -n "$FILTER_PATTERN" ] && args+=(--file-filter="${FILTER_LABEL:-Files} | $FILTER_PATTERN")
    result="$(qarma "${args[@]}" 2>>"$LOG")"
    status=$?

elif command -v python3 >/dev/null 2>&1 && python3 -c "import tkinter" >/dev/null 2>&1; then
    backend="python3/tkinter"
    _dbg "trying python3/tkinter"
    result="$(python3 - "$MODE" "$TITLE" "$START_DIR" "$(basename -- "$START")" "$FILTER_LABEL" "$FILTER_PATTERN" <<'PYEOF' 2>>"$LOG"
import sys, tkinter, tkinter.filedialog
mode, title, start_dir, start_name, filter_label, filter_pattern = sys.argv[1:7]
root = tkinter.Tk()
root.withdraw()
types = [(filter_label or "Files", filter_pattern)] if filter_pattern else [("All files", "*.*")]
if mode == "save":
    path = tkinter.filedialog.asksaveasfilename(title=title, initialdir=start_dir,
                                                 initialfile=start_name, filetypes=types)
else:
    path = tkinter.filedialog.askopenfilename(title=title, initialdir=start_dir, filetypes=types)
root.destroy()
print(path)
PYEOF
)"
    status=$?
    if [ -z "$result" ]; then status=1; fi
fi

_dbg "backend=\"$backend\" exit=$status result=\"$result\""

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
        echo "File picker ($backend) exited with an error (code $status)." >&2
        exit "$status"
    fi
fi

_dbg "no dialog backend found"
echo "No file picker found. Install zenity, kdialog, yad, or qarma." >&2
exit 2
