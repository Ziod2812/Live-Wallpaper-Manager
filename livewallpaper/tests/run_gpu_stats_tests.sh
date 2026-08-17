#!/usr/bin/env bash
#
# run_gpu_stats_tests.sh
# -------------------------------------------------------
# Test suite for gpu_manager.sh's `stats` action (System Resources' live
# GPU utilization/VRAM/temperature card -- Services/GPUManagerService.qml's
# statsFor()/gpuStats, Components/GpuPanel.qml's live-stats rows).
#
# Same fixture-tree-via-LW_GPU_SYSFS_DRM approach as
# run_gpu_manager_tests.sh (never touches real hardware, no root needed),
# extended with "cardN" sysfs entries (gpu_busy_percent,
# mem_info_vram_used/total, hwmon/*/temp1_input) since `stats` reads those
# in addition to what `detect`'s renderD-based fixtures already cover.
#
# Covers:
#   - AMD: utilization/VRAM/temp all read correctly from sysfs
#   - Intel: no sysfs util/VRAM node -> both null (graceful degrade),
#     temp still read when a hwmon node IS present
#   - No GPU at all -> {"gpus":[]}, no crash
#   - `detect` and `env` still behave identically after the
#     _lw_gpu_list_json/_lw_gpu_detect_json refactor (non-regression)
#
# Usage: bash tests/run_gpu_stats_tests.sh
# Exits 0 if every test passes, 1 if any test fails.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SCRIPTS_DIR="$PROJECT_DIR/scripts"
FIXTURE_ROOT="/tmp/lw_gpu_stats_test_fixtures.$$"

PASS=0
FAIL=0
FAILED_NAMES=()

pass() { PASS=$((PASS+1)); echo "  ✅ PASS: $1"; }
fail() { FAIL=$((FAIL+1)); FAILED_NAMES+=("$1"); echo "  ❌ FAIL: $1"; [ -n "${2:-}" ] && echo "         $2"; }

cleanup() { rm -rf "$FIXTURE_ROOT"; }
trap cleanup EXIT

mk_fixture() {
    local name="$1"
    FIXTURE_DIR="$FIXTURE_ROOT/$name"
    rm -rf "$FIXTURE_DIR"
    mkdir -p "$FIXTURE_DIR/drm"
    export LW_GPU_SYSFS_DRM="$FIXTURE_DIR/drm"
}

# mk_gpu <render_num> <card_num> <vendor_hex> <pci_id> <driver_name> <boot_vga:0|1>
mk_gpu() {
    local rnum="$1" cnum="$2" vendor_hex="$3" pci_id="$4" driver="$5" boot_vga="$6"
    local pcidir="$FIXTURE_DIR/pci/$pci_id"
    mkdir -p "$pcidir"
    echo "$vendor_hex" > "$pcidir/vendor"
    echo "$boot_vga" > "$pcidir/boot_vga"
    mkdir -p "$FIXTURE_DIR/drivers/$driver"
    ln -sfn "../../drivers/$driver" "$pcidir/driver"
    mkdir -p "$FIXTURE_DIR/drm/renderD$rnum"
    ln -sfn "../../pci/$pci_id" "$FIXTURE_DIR/drm/renderD$rnum/device"
    mkdir -p "$FIXTURE_DIR/drm/card$cnum"
    ln -sfn "../../pci/$pci_id" "$FIXTURE_DIR/drm/card$cnum/device"
}

# mk_amd_sensors <pci_id> <busy_pct> <vram_used_bytes> <vram_total_bytes> <temp_millideg>
mk_amd_sensors() {
    local pci_id="$1" busy="$2" vused="$3" vtotal="$4" tempmilli="$5"
    local pcidir="$FIXTURE_DIR/pci/$pci_id"
    echo "$busy" > "$pcidir/gpu_busy_percent"
    echo "$vused" > "$pcidir/mem_info_vram_used"
    echo "$vtotal" > "$pcidir/mem_info_vram_total"
    mkdir -p "$pcidir/hwmon/hwmon0"
    echo "$tempmilli" > "$pcidir/hwmon/hwmon0/temp1_input"
}

# mk_hwmon_only <pci_id> <temp_millideg> -- Intel-style: only a temp sensor,
# no gpu_busy_percent / mem_info_vram_* nodes.
mk_hwmon_only() {
    local pci_id="$1" tempmilli="$2"
    local pcidir="$FIXTURE_DIR/pci/$pci_id"
    mkdir -p "$pcidir/hwmon/hwmon0"
    echo "$tempmilli" > "$pcidir/hwmon/hwmon0/temp1_input"
}

run_stats()  { bash "$SCRIPTS_DIR/gpu_manager.sh" stats 2>/tmp/lw_gpu_stats_test_stderr.$$; }
run_detect() { bash "$SCRIPTS_DIR/gpu_manager.sh" detect 2>/tmp/lw_gpu_stats_test_stderr.$$; }
run_env()    { bash "$SCRIPTS_DIR/gpu_manager.sh" env "$1" 2>/tmp/lw_gpu_stats_test_stderr.$$; }

jq_field() { echo "$1" | jq -r "$2" 2>/dev/null; }

echo "=================================================="
echo " GPU Stats Test Suite"
echo "=================================================="
echo ""

# ---------------------------------------------------------------------
echo "[1] AMD: utilization / VRAM / temperature all read from sysfs"
mk_fixture amd_full
mk_gpu 128 0 0x1002 0000:03:00.0 amdgpu 0
mk_amd_sensors 0000:03:00.0 42 536870912 8589934592 54200
out="$(run_stats)"
[ "$(jq_field "$out" '.gpus | length')" = "1" ] && \
[ "$(jq_field "$out" '.gpus[0].vendor')" = "amd" ] && \
[ "$(jq_field "$out" '.gpus[0].utilization_pct')" = "42" ] && \
[ "$(jq_field "$out" '.gpus[0].vram_used_mb')" = "512" ] && \
[ "$(jq_field "$out" '.gpus[0].vram_total_mb')" = "8192" ] && \
[ "$(jq_field "$out" '.gpus[0].temp_c')" = "54.2" ] \
    && pass "AMD utilization/VRAM/temp read correctly from sysfs" \
    || fail "AMD stats" "$out"

# ---------------------------------------------------------------------
echo "[2] Intel: no utilization/VRAM sysfs nodes -> null (graceful degrade), temp still read"
mk_fixture intel_partial
mk_gpu 128 0 0x8086 0000:00:02.0 i915 1
mk_hwmon_only 0000:00:02.0 48500
out="$(run_stats)"
[ "$(jq_field "$out" '.gpus[0].vendor')" = "intel" ] && \
[ "$(jq_field "$out" '.gpus[0].utilization_pct')" = "null" ] && \
[ "$(jq_field "$out" '.gpus[0].vram_used_mb')" = "null" ] && \
[ "$(jq_field "$out" '.gpus[0].vram_total_mb')" = "null" ] && \
[ "$(jq_field "$out" '.gpus[0].temp_c')" = "48.5" ] \
    && pass "Intel gracefully degrades util/VRAM to null while still reading temp" \
    || fail "Intel partial stats" "$out"

# ---------------------------------------------------------------------
echo "[3] Intel: no sensors exposed at all -> everything null, no crash"
mk_fixture intel_none
mk_gpu 128 0 0x8086 0000:00:02.0 i915 1
out="$(run_stats)"
[ "$(jq_field "$out" '.gpus[0].utilization_pct')" = "null" ] && \
[ "$(jq_field "$out" '.gpus[0].vram_used_mb')" = "null" ] && \
[ "$(jq_field "$out" '.gpus[0].temp_c')" = "null" ] \
    && pass "Intel with zero exposed sensors -> all null, script doesn't crash" \
    || fail "Intel no-sensor stats" "$out"

# ---------------------------------------------------------------------
echo "[4] No GPU at all -> {\"gpus\":[]}, no crash"
mk_fixture none
out="$(run_stats)"
[ "$(jq_field "$out" '.gpus | length')" = "0" ] \
    && pass "no GPUs -> empty gpus[] from stats, no crash" \
    || fail "no-GPU stats" "$out"

# ---------------------------------------------------------------------
echo "[5] Non-regression: detect still works after _lw_gpu_list_json refactor"
mk_fixture regress_detect
mk_gpu 128 0 0x1002 0000:03:00.0 amdgpu 1
out="$(run_detect)"
[ "$(jq_field "$out" '.gpus[0].vendor')" = "amd" ] && \
[ "$(jq_field "$out" '.system_type')" = "amd-only" ] \
    && pass "detect still returns correct vendor/system_type after refactor" \
    || fail "detect non-regression" "$out"

# ---------------------------------------------------------------------
echo "[6] Non-regression: env still works after _lw_gpu_list_json refactor"
mk_fixture regress_env
mk_gpu 128 0 0x1002 0000:03:00.0 amdgpu 1
out="$(run_env amd)"
echo "$out" | grep -q "DRI_PRIME=pci-0000_03_00_0" \
    && pass "env amd still resolves DRI_PRIME correctly after refactor" \
    || fail "env non-regression" "$out"

echo ""
echo "=================================================="
echo " Results: $PASS passed, $FAIL failed"
echo "=================================================="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
