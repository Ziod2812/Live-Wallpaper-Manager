#!/usr/bin/env bash
#
# run_performance_profiles_tests.sh
# -------------------------------------------------------
# Test suite for performance_profiles.sh -- backs
# Services/WallpaperProfileService.qml's per-wallpaper/per-monitor FPS +
# Resolution overrides (WallpaperPreviewDialog.qml's "Performance
# profile" block, MonitorPerformanceProfilePanel.qml).
#
# Same fixture-via-env-override approach as run_gpu_manager_tests.sh /
# run_gpu_stats_tests.sh: point LW_DATA_DIR (which utils.sh already
# reads via ${LW_DATA_DIR:-...}) at a throwaway /tmp directory per test
# case, so this never touches a real install's performance_profiles.json
# and needs no root.
#
# Covers:
#   - Fresh file is auto-created with the {"wallpapers":{},"monitors":{}} shape
#   - set_wallpaper / get_wallpaper round-trip both fields
#   - set_wallpaper patching only fps clears resolution (documented
#     "pass current value to preserve it" contract -- WallpaperProfileService
#     callers rely on this)
#   - set_wallpaper with both args empty clears the entry to {}
#   - clear_wallpaper removes the key entirely
#   - set_monitor / get_monitor / clear_monitor mirror the above
#   - get_* on a key that was never set returns {}, not an error
#   - A corrupt file is reset to the default shape instead of crashing
#   - Unknown action exits non-zero
#
# Usage: bash tests/run_performance_profiles_tests.sh
# Exits 0 if every test passes, 1 if any test fails.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SCRIPTS_DIR="$PROJECT_DIR/scripts"
FIXTURE_ROOT="/tmp/lw_perf_profiles_test_fixtures.$$"

PASS=0
FAIL=0
FAILED_NAMES=()

pass() { PASS=$((PASS+1)); echo "  ✅ PASS: $1"; }
fail() { FAIL=$((FAIL+1)); FAILED_NAMES+=("$1"); echo "  ❌ FAIL: $1"; [ -n "${2:-}" ] && echo "         $2"; }

cleanup() { rm -rf "$FIXTURE_ROOT"; }
trap cleanup EXIT

# mk_fixture <name> -- fresh, empty LW_DATA_DIR for one test case.
mk_fixture() {
    local name="$1"
    FIXTURE_DIR="$FIXTURE_ROOT/$name"
    rm -rf "$FIXTURE_DIR"
    mkdir -p "$FIXTURE_DIR"
    export LW_DATA_DIR="$FIXTURE_DIR"
    PROFILES_FILE="$FIXTURE_DIR/performance_profiles.json"
}

run() {
    bash "$SCRIPTS_DIR/performance_profiles.sh" "$@" 2>/tmp/lw_perf_profiles_test_stderr.$$
}

jq_field() {
    printf '%s' "$1" | jq -r "$2" 2>/dev/null
}

# ---------------------------------------------------------------------
echo "[1] Fresh file is auto-created with the default shape"
mk_fixture fresh
out="$(run list)"
[ "$(jq_field "$out" '.wallpapers')" = "{}" ] && [ "$(jq_field "$out" '.monitors')" = "{}" ] \
    && pass "list on a brand-new install returns {wallpapers:{},monitors:{}}" \
    || fail "fresh file shape" "$out"

# ---------------------------------------------------------------------
echo "[2] set_wallpaper / get_wallpaper round-trip both fields"
mk_fixture wallpaper_roundtrip
run set_wallpaper "/videos/anime.mp4" 60 1080p >/dev/null
out="$(run get_wallpaper "/videos/anime.mp4")"
[ "$(jq_field "$out" '.fps')" = "60" ] && [ "$(jq_field "$out" '.resolution')" = "1080p" ] \
    && pass "set_wallpaper then get_wallpaper returns fps=60 resolution=1080p" \
    || fail "wallpaper round-trip" "$out"

# ---------------------------------------------------------------------
echo "[3] Patching fps only (empty resolution arg) clears resolution"
mk_fixture wallpaper_patch
run set_wallpaper "/videos/heavy.mp4" 30 720p >/dev/null
run set_wallpaper "/videos/heavy.mp4" 15 "" >/dev/null
out="$(run get_wallpaper "/videos/heavy.mp4")"
[ "$(jq_field "$out" '.fps')" = "15" ] && [ "$(jq_field "$out" 'has("resolution")')" = "false" ] \
    && pass "empty resolution arg clears resolution while updating fps" \
    || fail "fps-only patch" "$out"

# ---------------------------------------------------------------------
echo "[4] set_wallpaper with both args empty clears the entry to {}"
mk_fixture wallpaper_both_empty
run set_wallpaper "/videos/anime.mp4" 60 1080p >/dev/null
run set_wallpaper "/videos/anime.mp4" "" "" >/dev/null
out="$(run get_wallpaper "/videos/anime.mp4")"
[ "$out" = "{}" ] \
    && pass "both args empty leaves an empty {} entry" \
    || fail "both-empty patch" "$out"

# ---------------------------------------------------------------------
echo "[5] clear_wallpaper removes the key entirely"
mk_fixture wallpaper_clear
run set_wallpaper "/videos/anime.mp4" 60 1080p >/dev/null
run clear_wallpaper "/videos/anime.mp4" >/dev/null
whole="$(run list)"
[ "$(jq_field "$whole" '.wallpapers | has("/videos/anime.mp4")')" = "false" ] \
    && pass "clear_wallpaper removes the key from wallpapers{}" \
    || fail "clear_wallpaper" "$whole"

# ---------------------------------------------------------------------
echo "[6] set_monitor / get_monitor / clear_monitor mirror the wallpaper case"
mk_fixture monitor_roundtrip
run set_monitor "eDP-1" 15 720p >/dev/null
out="$(run get_monitor "eDP-1")"
[ "$(jq_field "$out" '.fps')" = "15" ] && [ "$(jq_field "$out" '.resolution')" = "720p" ] \
    && pass "set_monitor then get_monitor round-trips" \
    || fail "monitor round-trip" "$out"
run clear_monitor "eDP-1" >/dev/null
whole="$(run list)"
[ "$(jq_field "$whole" '.monitors | has("eDP-1")')" = "false" ] \
    && pass "clear_monitor removes the key from monitors{}" \
    || fail "clear_monitor" "$whole"

# ---------------------------------------------------------------------
echo "[7] get_* on a never-set key returns {} rather than erroring"
mk_fixture never_set
out_w="$(run get_wallpaper "/nope.mp4")"
out_m="$(run get_monitor "HDMI-9")"
[ "$out_w" = "{}" ] && [ "$out_m" = "{}" ] \
    && pass "get_wallpaper/get_monitor on unknown keys return {}" \
    || fail "never-set get" "w=$out_w m=$out_m"

# ---------------------------------------------------------------------
echo "[8] A corrupt file is reset to the default shape instead of crashing"
mk_fixture corrupt
mkdir -p "$FIXTURE_DIR"
echo "{not valid json" > "$PROFILES_FILE"
out="$(run list)"
[ "$(jq_field "$out" '.wallpapers')" = "{}" ] && [ -f "$PROFILES_FILE.corrupt" ] \
    && pass "corrupt performance_profiles.json is reset (with a .corrupt backup kept)" \
    || fail "corrupt file recovery" "$out"

# ---------------------------------------------------------------------
echo "[9] Unknown action exits non-zero"
mk_fixture bad_action
run bogus_action >/dev/null 2>&1
code=$?
[ "$code" -ne 0 ] \
    && pass "an unrecognized action exits non-zero" \
    || fail "unknown action exit code" "exit=$code"

echo ""
echo "=================================================="
echo " Results: $PASS passed, $FAIL failed"
echo "=================================================="
rm -f /tmp/lw_perf_profiles_test_stderr.$$
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
