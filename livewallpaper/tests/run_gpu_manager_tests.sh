#!/usr/bin/env bash
#
# run_gpu_manager_tests.sh
# -------------------------------------------------------
# Test suite for the GPU Switching feature's backend (scripts/gpu_manager.sh).
#
# Mocks /sys/class/drm entirely via LW_GPU_SYSFS_DRM (an env var
# gpu_manager.sh reads instead of the hardcoded path -- see its header
# comment; unset/default behavior on a real machine is unchanged) pointed
# at a fixture tree built by mk_gpu() below, so this never touches the
# real machine's GPU hardware and needs no root/actual driver.
#
# Covers:
#   - detect: single Intel / single AMD / single NVIDIA / no GPU
#   - detect: hybrid Intel+NVIDIA, hybrid Intel+AMD, multi-NVIDIA (2x)
#   - detect: unknown vendor ID, missing driver symlink (regression --
#     see gpu_manager.sh's readlink -e comment), missing boot_vga file
#   - env: auto (no output/exit 0), intel/amd/nvidia present + absent,
#     power-saving / high-performance on hybrid + single-GPU + AMD-hybrid
#
# Usage:
#   bash tests/run_gpu_manager_tests.sh
#
# Exits 0 if every test passes, 1 if any test fails (prints a summary
# either way).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SCRIPTS_DIR="$PROJECT_DIR/scripts"
FIXTURE_ROOT="/tmp/lw_gpu_test_fixtures.$$"

PASS=0
FAIL=0
FAILED_NAMES=()

pass() { PASS=$((PASS+1)); echo "  ✅ PASS: $1"; }
fail() { FAIL=$((FAIL+1)); FAILED_NAMES+=("$1"); echo "  ❌ FAIL: $1"; [ -n "${2:-}" ] && echo "         $2"; }

cleanup() { rm -rf "$FIXTURE_ROOT"; }
trap cleanup EXIT

# ---------------------------------------------------------------------
# Fixture builder -- fakes just enough of /sys/class/drm's shape for
# gpu_manager.sh's detection to work against: a renderD<N>/device symlink
# pointing at a PCI-id-named directory containing vendor/boot_vga files
# and its own driver symlink, exactly what _lw_gpu_detect_json() reads.
# ---------------------------------------------------------------------
mk_fixture() {
    local name="$1"
    FIXTURE_DIR="$FIXTURE_ROOT/$name"
    rm -rf "$FIXTURE_DIR"
    mkdir -p "$FIXTURE_DIR/drm"
    export LW_GPU_SYSFS_DRM="$FIXTURE_DIR/drm"
}

# mk_gpu <render_num> <vendor_hex> <pci_id> <driver_name> <boot_vga:0|1>
mk_gpu() {
    local num="$1" vendor_hex="$2" pci_id="$3" driver="$4" boot_vga="$5"
    local pcidir="$FIXTURE_DIR/pci/$pci_id"
    mkdir -p "$pcidir"
    echo "$vendor_hex" > "$pcidir/vendor"
    echo "$boot_vga" > "$pcidir/boot_vga"
    mkdir -p "$FIXTURE_DIR/drivers/$driver"
    ln -sfn "../../drivers/$driver" "$pcidir/driver"
    mkdir -p "$FIXTURE_DIR/drm/renderD$num"
    ln -sfn "../../pci/$pci_id" "$FIXTURE_DIR/drm/renderD$num/device"
}

run_detect() { bash "$SCRIPTS_DIR/gpu_manager.sh" detect 2>/tmp/lw_gpu_test_stderr.$$; }
run_env()    { bash "$SCRIPTS_DIR/gpu_manager.sh" env "$1" 2>/tmp/lw_gpu_test_stderr.$$; }

jq_field() { echo "$1" | jq -r "$2" 2>/dev/null; }

echo "=================================================="
echo " GPU Manager Test Suite"
echo "=================================================="
echo ""

# ---------------------------------------------------------------------
echo "[1] Single Intel GPU"
mk_fixture single_intel
mk_gpu 128 0x8086 0000:00:02.0 i915 1
out="$(run_detect)"
[ "$(jq_field "$out" '.gpus | length')" = "1" ] && \
[ "$(jq_field "$out" '.gpus[0].vendor')" = "intel" ] && \
[ "$(jq_field "$out" '.system_type')" = "intel-only" ] && \
[ "$(jq_field "$out" '.hybrid')" = "false" ] \
    && pass "single Intel GPU detected correctly (intel-only, hybrid=false)" \
    || fail "single Intel GPU detection" "$out"

# ---------------------------------------------------------------------
echo "[2] Single AMD GPU"
mk_fixture single_amd
mk_gpu 128 0x1002 0000:00:02.0 amdgpu 1
out="$(run_detect)"
[ "$(jq_field "$out" '.gpus[0].vendor')" = "amd" ] && \
[ "$(jq_field "$out" '.system_type')" = "amd-only" ] \
    && pass "single AMD GPU detected correctly (amd-only)" \
    || fail "single AMD GPU detection" "$out"

# ---------------------------------------------------------------------
echo "[3] Single NVIDIA GPU"
mk_fixture single_nvidia
mk_gpu 128 0x10de 0000:01:00.0 nvidia 1
out="$(run_detect)"
[ "$(jq_field "$out" '.gpus[0].vendor')" = "nvidia" ] && \
[ "$(jq_field "$out" '.system_type')" = "nvidia-only" ] \
    && pass "single NVIDIA GPU detected correctly (nvidia-only)" \
    || fail "single NVIDIA GPU detection" "$out"

# ---------------------------------------------------------------------
echo "[4] No GPUs at all"
mk_fixture none
out="$(run_detect)"
[ "$(jq_field "$out" '.gpus | length')" = "0" ] && \
[ "$(jq_field "$out" '.system_type')" = "none" ] \
    && pass "zero GPUs -> system_type=none, empty gpus[]" \
    || fail "zero-GPU detection" "$out"

# ---------------------------------------------------------------------
echo "[5] Hybrid Intel + NVIDIA (laptop-style, Intel = boot_vga)"
mk_fixture hybrid_intel_nvidia
mk_gpu 128 0x8086 0000:00:02.0 i915 1
mk_gpu 129 0x10de 0000:01:00.0 nvidia 0
out="$(run_detect)"
[ "$(jq_field "$out" '.gpus | length')" = "2" ] && \
[ "$(jq_field "$out" '.hybrid')" = "true" ] && \
[ "$(jq_field "$out" '.system_type')" = "hybrid" ] \
    && pass "hybrid Intel+NVIDIA detected correctly (hybrid=true)" \
    || fail "hybrid Intel+NVIDIA detection" "$out"

# ---------------------------------------------------------------------
echo "[6] Hybrid Intel + AMD"
mk_fixture hybrid_intel_amd
mk_gpu 128 0x8086 0000:00:02.0 i915 1
mk_gpu 129 0x1002 0000:03:00.0 amdgpu 0
out="$(run_detect)"
[ "$(jq_field "$out" '.hybrid')" = "true" ] && \
[ "$(jq_field "$out" '.system_type')" = "hybrid" ] \
    && pass "hybrid Intel+AMD detected correctly (hybrid=true)" \
    || fail "hybrid Intel+AMD detection" "$out"

# ---------------------------------------------------------------------
echo "[7] Multi-NVIDIA (2x NVIDIA, not hybrid -- single vendor)"
mk_fixture multi_nvidia
mk_gpu 128 0x10de 0000:01:00.0 nvidia 1
mk_gpu 129 0x10de 0000:02:00.0 nvidia 0
out="$(run_detect)"
[ "$(jq_field "$out" '.gpus | length')" = "2" ] && \
[ "$(jq_field "$out" '.hybrid')" = "false" ] && \
[ "$(jq_field "$out" '.system_type')" = "multi-nvidia" ] \
    && pass "multi-NVIDIA detected correctly (hybrid=false, multi-nvidia)" \
    || fail "multi-NVIDIA detection" "$out"

# ---------------------------------------------------------------------
echo "[8] Unknown/unrecognized vendor ID -> classified 'unknown', no crash"
mk_fixture unknown_vendor
mk_gpu 128 0xdead 0000:00:02.0 somedrv 1
out="$(run_detect)"
[ "$(jq_field "$out" '.gpus[0].vendor')" = "unknown" ] && \
[ "$(jq_field "$out" '.gpus[0].label')" = "Unknown" ] \
    && pass "unrecognized vendor hex classified as unknown, script doesn't crash" \
    || fail "unknown vendor handling" "$out"

# ---------------------------------------------------------------------
echo "[9] Missing driver symlink (unbound/unloaded driver) -> 'unknown', not 'driver'"
mk_fixture missing_driver
mk_gpu 128 0x8086 0000:00:02.0 i915 1
rm "$FIXTURE_DIR/pci/0000:00:02.0/driver"
out="$(run_detect)"
driver_val="$(jq_field "$out" '.gpus[0].driver')"
[ "$driver_val" = "unknown" ] \
    && pass "missing driver symlink correctly reports driver=unknown (regression: was reporting literal 'driver')" \
    || fail "missing driver symlink handling" "got driver='$driver_val', expected 'unknown' -- $out"

# ---------------------------------------------------------------------
echo "[10] Missing boot_vga file (older kernel / restricted sysfs) -> defaults false, no crash"
mk_fixture missing_bootvga
mk_gpu 128 0x8086 0000:00:02.0 i915 1
rm "$FIXTURE_DIR/pci/0000:00:02.0/boot_vga"
out="$(run_detect)"
[ "$(jq_field "$out" '.gpus[0].boot_vga')" = "false" ] && \
[ "$(jq_field "$out" '.gpus | length')" = "1" ] \
    && pass "missing boot_vga file defaults to false without crashing" \
    || fail "missing boot_vga file handling" "$out"

# ---------------------------------------------------------------------
echo "[11] env auto -> no output, exit 0 (pre-feature behavior, untouched)"
mk_fixture hybrid_for_env
mk_gpu 128 0x8086 0000:00:02.0 i915 1
mk_gpu 129 0x10de 0000:01:00.0 nvidia 0
out="$(run_env auto)"; rc=$?
[ -z "$out" ] && [ "$rc" -eq 0 ] \
    && pass "env auto emits nothing, exit 0" \
    || fail "env auto" "output='$out' exit=$rc"

# ---------------------------------------------------------------------
echo "[12] env intel on hybrid Intel+NVIDIA -> DRI_PRIME for Intel's PCI id"
out="$(run_env intel)"; rc=$?
echo "$out" | grep -q '^DRI_PRIME=pci-0000_00_02_0$' && [ "$rc" -eq 0 ] \
    && pass "env intel resolves to Intel's DRI_PRIME" \
    || fail "env intel" "output='$out' exit=$rc"

# ---------------------------------------------------------------------
echo "[13] env nvidia on hybrid Intel+NVIDIA -> PRIME render-offload vars"
out="$(run_env nvidia)"; rc=$?
echo "$out" | grep -q '^__NV_PRIME_RENDER_OFFLOAD=1$' && \
echo "$out" | grep -q '^__GLX_VENDOR_LIBRARY_NAME=nvidia$' && \
echo "$out" | grep -q '^DRI_PRIME=pci-0000_01_00_0$' && [ "$rc" -eq 0 ] \
    && pass "env nvidia resolves to NVIDIA PRIME offload vars + DRI_PRIME fallback" \
    || fail "env nvidia" "output='$out' exit=$rc"

# ---------------------------------------------------------------------
echo "[14] env amd on Intel+NVIDIA hybrid (AMD not present) -> exit 3, no output"
out="$(run_env amd)"; rc=$?
[ -z "$out" ] && [ "$rc" -eq 3 ] \
    && pass "env amd on a system with no AMD GPU correctly fails (exit 3, empty -- 'no override')" \
    || fail "env amd unavailable" "output='$out' exit=$rc"

# ---------------------------------------------------------------------
echo "[15] env power-saving on hybrid Intel+NVIDIA -> picks Intel (boot_vga)"
out="$(run_env power-saving)"; rc=$?
echo "$out" | grep -q '^DRI_PRIME=pci-0000_00_02_0$' && [ "$rc" -eq 0 ] \
    && pass "env power-saving picks the boot_vga (Intel) GPU" \
    || fail "env power-saving (hybrid)" "output='$out' exit=$rc"

# ---------------------------------------------------------------------
echo "[16] env high-performance on hybrid Intel+NVIDIA -> picks NVIDIA"
out="$(run_env high-performance)"; rc=$?
echo "$out" | grep -q '^__NV_PRIME_RENDER_OFFLOAD=1$' && [ "$rc" -eq 0 ] \
    && pass "env high-performance picks NVIDIA" \
    || fail "env high-performance (hybrid Intel+NVIDIA)" "output='$out' exit=$rc"

# ---------------------------------------------------------------------
echo "[17] env high-performance on hybrid Intel+AMD (no NVIDIA) -> picks AMD (non-boot_vga)"
mk_fixture hybrid_intel_amd_env
mk_gpu 128 0x8086 0000:00:02.0 i915 1
mk_gpu 129 0x1002 0000:03:00.0 amdgpu 0
out="$(run_env high-performance)"; rc=$?
echo "$out" | grep -q '^DRI_PRIME=pci-0000_03_00_0$' && [ "$rc" -eq 0 ] \
    && pass "env high-performance falls back to non-boot_vga AMD when there's no NVIDIA" \
    || fail "env high-performance (Intel+AMD, no NVIDIA)" "output='$out' exit=$rc"

# ---------------------------------------------------------------------
echo "[18] env power-saving/high-performance on a SINGLE-GPU system -> exit 3, no output"
mk_fixture single_for_env
mk_gpu 128 0x8086 0000:00:02.0 i915 1
out1="$(run_env power-saving)"; rc1=$?
out2="$(run_env high-performance)"; rc2=$?
[ -z "$out1" ] && [ "$rc1" -eq 3 ] && [ -z "$out2" ] && [ "$rc2" -eq 3 ] \
    && pass "power-saving/high-performance correctly no-op (exit 3) with only one GPU -- nothing to switch to" \
    || fail "single-GPU power-saving/high-performance" "ps: out='$out1' rc=$rc1 / hp: out='$out2' rc=$rc2"

# ---------------------------------------------------------------------
echo "[19] env intel when NO GPU at all is present -> exit 3, no output (never fails the caller)"
mk_fixture none_env
out="$(run_env intel)"; rc=$?
[ -z "$out" ] && [ "$rc" -eq 3 ] \
    && pass "env on a system with no GPUs at all resolves to 'no override' (exit 3), not a crash" \
    || fail "env with zero GPUs" "output='$out' exit=$rc"

# ---------------------------------------------------------------------
echo ""
echo "=================================================="
echo " Results: $PASS passed, $FAIL failed"
echo "=================================================="
if [ "$FAIL" -gt 0 ]; then
    echo "Failed tests:"
    for n in "${FAILED_NAMES[@]}"; do echo "  - $n"; done
    exit 1
fi
exit 0
