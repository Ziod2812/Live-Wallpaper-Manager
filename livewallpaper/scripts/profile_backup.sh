#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# The report directory is created before any output redirection or archive
# generation.  Use an explicit argument when provided; otherwise resolve it
# from the current user's XDG state/home environment.
TARGET_DIR="${1:-${XDG_STATE_HOME:-$HOME/.local/state}/LiveWallpaperLogs}"
if [ -z "$TARGET_DIR" ]; then
    echo "profile_backup.sh: empty target directory" >&2
    exit 1
fi

mkdir -p -- "$TARGET_DIR" || {
    echo "profile_backup.sh: failed to create target directory: $TARGET_DIR" >&2
    exit 1
}

chmod 755 -- "$TARGET_DIR" 2>/dev/null || true

action="${2:-report}"
target="${3:-$TARGET_DIR/livewallpaper-profile.json}"

case "$action" in
  report)
    OUTPUT_FILE="$TARGET_DIR/wallpaper_report_$(date +%F_%H%M%S).log"

    {
      printf '%s\n' "Live Wallpaper Manager Log Report"
      printf 'Generated: %s\n' "$(date '+%F %T %Z')"
      printf 'User: %s\n' "${USER:-unknown}"
      printf 'Home: %s\n' "${HOME:-unknown}"
      printf '\n%s\n' '=== Runtime ==='
      command -v quickshell 2>&1 || true
      command -v mpvpaper 2>&1 || true
      command -v mpv 2>&1 || true
      command -v hyprctl 2>&1 || true
      printf '\n%s\n' '=== Environment ==='
      env | sort 2>&1
    } > "$OUTPUT_FILE" || {
      echo "profile_backup.sh: failed to write report: $OUTPUT_FILE" >&2
      exit 1
    }

    chmod 644 -- "$OUTPUT_FILE" || {
      echo "profile_backup.sh: failed to chmod report: $OUTPUT_FILE" >&2
      exit 1
    }

    printf '%s\n' "$OUTPUT_FILE"
    ;;

  export)
    target_parent="$(dirname -- "$target")"
    mkdir -p -- "$target_parent" || {
      echo "Failed to create profile output directory: $target_parent" >&2
      exit 1
    }
    jq -n \
      --slurpfile settings "$LW_SETTINGS_FILE" \
      --slurpfile wallpapers "$LW_DB_FILE" \
      --slurpfile history "$LW_HISTORY_FILE" \
      '{version:1,exported_at:now|todate,settings:($settings[0]//{}),wallpapers:($wallpapers[0]//[]),history:($history[0]//[])}' \
      > "$target" || exit 1
    chmod 644 -- "$target" || exit 1
    ;;
  import)
    jq -e '.settings and (.settings|type=="object")' "$target" >/dev/null || {
      echo "Invalid profile" >&2
      exit 1
    }
    jq '.settings' "$target" > "$LW_SETTINGS_FILE"
    [ "$(jq -r 'has("wallpapers")' "$target")" = true ] && jq '.wallpapers' "$target" > "$LW_DB_FILE"
    [ "$(jq -r 'has("history")' "$target")" = true ] && jq '.history' "$target" > "$LW_HISTORY_FILE"
    ;;
  *)
    echo "Usage: profile_backup.sh <target-dir> <export|import> <file>" >&2
    exit 2
    ;;
esac

echo "$target"
