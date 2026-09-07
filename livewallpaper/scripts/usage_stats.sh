#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"
lw_ensure_dirs
[ -s "$LW_HISTORY_FILE" ] || echo '[]' > "$LW_HISTORY_FILE"

# History is intentionally compact. A gap is attributed to the wallpaper
# until the next switch, capped so an overnight idle session is not counted.
jq --argjson total "$(jq 'if length < 2 then 0 else [range(0;length-1) as $i | ((.[ $i].timestamp - .[$i+1].timestamp) | if . > 14400 then 14400 elif . < 0 then 0 else . end)] | add // 0 end' "$LW_HISTORY_FILE" 2>/dev/null || echo 0)" '
  . as $h | (group_by(.path) | map({path:.[0].path,uses:length}) | sort_by(-.uses)) as $items |
  {total_seconds:$total,top:($items[0] // {path:"",uses:0}),items:$items}
' "$LW_HISTORY_FILE" 2>/dev/null || echo '{"total_seconds":0,"top":{"path":"","uses":0},"items":[]}'