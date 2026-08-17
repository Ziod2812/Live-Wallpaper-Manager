#!/usr/bin/env bash
#
# gpu_manager.sh <detect|env> [mode]
# -------------------------------------
# Backend for the GPU Switching feature (Services/GPUManagerService.qml).
# Everything here is READ-ONLY hardware detection plus printing a handful
# of environment-variable assignments -- it never writes to any system
# file, never touches PRIME/udev/Xorg/Hyprland config, and never launches
# or kills anything itself. The only consumer of its "env" output is
# utils.sh's lw_launch_mpvpaper(), which prefixes THAT ONE mpvpaper
# invocation with the printed vars. Nothing else on the system is ever
# affected.
#
#   gpu_manager.sh detect
#       Prints one JSON object describing every GPU found via
#       /sys/class/drm (vendor, driver, PCI id, render node, whether it's
#       the boot/primary VGA device), whether this is a hybrid
#       (multi-vendor) system, and a best-effort read of the CURRENTLY
#       active OpenGL/Vulkan renderer + graphics API (via glxinfo /
#       vulkaninfo, when installed -- purely informational, never
#       required for the env action below):
#         {
#           "gpus": [{"vendor","label","render_node","pci","driver","boot_vga"}, ...],
#           "system_type": "intel-only"|"amd-only"|"nvidia-only"|"hybrid"|"multi-<vendor>"|"none",
#           "hybrid": bool,
#           "current_renderer": "...",
#           "current_api": "OpenGL"|"Vulkan"|"Unknown"
#         }
#
#   gpu_manager.sh env <mode>
#       mode is one of: auto | intel | amd | nvidia | power-saving | high-performance
#       Prints zero or more "KEY=VALUE" lines (one per line) -- the
#       environment mpvpaper should be launched with to render on the
#       requested GPU. Prints NOTHING for "auto" (i.e. leave mpvpaper's
#       default GPU selection alone -- identical to pre-feature
#       behavior), and prints NOTHING (exit code 3) if <mode> can't be
#       resolved to a GPU that's actually present -- callers MUST treat
#       empty output as "no override, do not fail the launch".
#
#   gpu_manager.sh stats
#       Read-only, live, per-GPU utilization/VRAM/temperature snapshot --
#       backs Services/GPUManagerService.qml's 1s poll for the System
#       Resources GPU card. Deliberately does NOT call glxinfo/vulkaninfo
#       (those are relatively slow external processes; renderer/API only
#       need to be read once at detect time, not every second) -- only
#       cheap sysfs reads plus, ONLY when an NVIDIA GPU is present, one
#       batched nvidia-smi call. Any metric that isn't available for a
#       given vendor/GPU (no sysfs node, tool not installed, read fails)
#       is printed as JSON null -- callers MUST treat null as "not
#       supported here", never as zero:
#         {
#           "gpus": [
#             {"pci":"...", "vendor":"intel"|"amd"|"nvidia"|"unknown",
#              "utilization_pct": <0-100 int|null>,
#              "vram_used_mb": <int|null>, "vram_total_mb": <int|null>,
#              "temp_c": <number|null>}, ...
#           ]
#         }
#
# Vendor detection is done purely from sysfs (PCI vendor IDs under
# /sys/class/drm/renderD*/device/vendor) -- no dependency on lspci,
# glxinfo, or any GPU driver actually being loaded correctly.
#
# LW_GPU_SYSFS_DRM overrides the sysfs base dir (default /sys/class/drm).
# Production behavior is completely unchanged (the env var is normally
# unset); this exists solely so tests/run_gpu_manager_tests.sh can point
# detection at a fixture tree instead of the real machine's hardware --
# no other line in this file changed to support it.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

LW_GPU_SYSFS_DRM="${LW_GPU_SYSFS_DRM:-/sys/class/drm}"

# ---------------------------------------------------------------------------
# _lw_gpu_list_json -> prints just the "gpus" array (see detect's header
# for the shape of each item). Pure sysfs, no external processes -- this
# is the part BOTH `detect` and `stats` need, factored out so `stats`
# (polled every 1s by GPUManagerService.qml) never has to pay for
# `detect`'s glxinfo/vulkaninfo calls just to know which GPUs exist.
# ---------------------------------------------------------------------------
_lw_gpu_list_json() {
    local items=() dev devdir vendor_hex pci driver boot_vga vendor vlabel render_node item

    for dev in "$LW_GPU_SYSFS_DRM"/renderD*; do
        [ -d "$dev" ] || continue
        devdir="$dev/device"
        [ -r "$devdir/vendor" ] || continue

        vendor_hex="$(cat "$devdir/vendor" 2>/dev/null)"
        pci="$(basename "$(readlink -f "$devdir" 2>/dev/null)" 2>/dev/null)"
        [ -n "$pci" ] || continue

        # readlink -e (not -f) here on purpose: -f canonicalizes a path
        # even when the final component doesn't exist, so a GPU whose
        # driver isn't bound (missing/broken "driver" symlink -- e.g. a
        # kernel module that failed to claim the device) would resolve to
        # the literal string "driver" instead of falling through to the
        # "unknown" default below. -e requires the whole path to actually
        # resolve, so a missing symlink correctly yields "" here.
        driver="$(basename "$(readlink -e "$devdir/driver" 2>/dev/null)" 2>/dev/null)"
        [ -n "$driver" ] || driver="unknown"

        boot_vga="false"
        [ -r "$devdir/boot_vga" ] && [ "$(cat "$devdir/boot_vga" 2>/dev/null)" = "1" ] && boot_vga="true"

        case "$vendor_hex" in
            0x8086) vendor="intel";  vlabel="Intel" ;;
            0x1002|0x1022) vendor="amd"; vlabel="AMD" ;;
            0x10de) vendor="nvidia"; vlabel="NVIDIA" ;;
            *) vendor="unknown"; vlabel="Unknown" ;;
        esac

        render_node="/dev/dri/$(basename "$dev")"

        item="$(jq -cn \
            --arg vendor "$vendor" \
            --arg label "$vlabel" \
            --arg render_node "$render_node" \
            --arg pci "$pci" \
            --arg driver "$driver" \
            --argjson boot_vga "$boot_vga" \
            '{vendor:$vendor,label:$label,render_node:$render_node,pci:$pci,driver:$driver,boot_vga:$boot_vga}')"
        items+=("$item")
    done

    if [ "${#items[@]}" -gt 0 ]; then
        (IFS=,; echo "[${items[*]}]")
    else
        echo "[]"
    fi
}

# ---------------------------------------------------------------------------
# _lw_gpu_detect_json -> prints the full detect JSON object (see header).
# ---------------------------------------------------------------------------
_lw_gpu_detect_json() {
    local gpus_json count uniq_vendors system_type hybrid
    gpus_json="$(_lw_gpu_list_json)"
    count="$(echo "$gpus_json" | jq 'length')"
    uniq_vendors="$(echo "$gpus_json" | jq -r '[.[].vendor] | unique | length')"

    if [ "$count" -eq 0 ]; then
        system_type="none"; hybrid="false"
    elif [ "$uniq_vendors" -gt 1 ]; then
        system_type="hybrid"; hybrid="true"
    elif [ "$count" -gt 1 ]; then
        system_type="multi-$(echo "$gpus_json" | jq -r '.[0].vendor')"; hybrid="false"
    else
        system_type="$(echo "$gpus_json" | jq -r '.[0].vendor')-only"; hybrid="false"
    fi

    # Best-effort, informational only -- never required for "env" to work.
    local current_renderer="" current_api="Unknown"
    if command -v glxinfo >/dev/null 2>&1; then
        current_renderer="$(glxinfo -B 2>/dev/null | grep -m1 'OpenGL renderer string:' | sed 's/^OpenGL renderer string:[[:space:]]*//')"
        [ -n "$current_renderer" ] && current_api="OpenGL"
    fi
    if [ -z "$current_renderer" ] && command -v vulkaninfo >/dev/null 2>&1; then
        current_renderer="$(vulkaninfo --summary 2>/dev/null | grep -m1 'deviceName' | sed -E 's/.*=[[:space:]]*//')"
        [ -n "$current_renderer" ] && current_api="Vulkan"
    fi

    jq -n \
        --argjson gpus "$gpus_json" \
        --arg system_type "$system_type" \
        --argjson hybrid "$hybrid" \
        --arg current_renderer "$current_renderer" \
        --arg current_api "$current_api" \
        '{gpus:$gpus, system_type:$system_type, hybrid:$hybrid, current_renderer:$current_renderer, current_api:$current_api}'
}

# ---------------------------------------------------------------------------
# _lw_gpu_card_dir_for_pci <pci> -> prints the /sys/class/drm/cardN path
# whose device resolves to <pci>, or nothing if none found. Needed because
# the per-GPU utilization/VRAM/temp sysfs nodes (gpu_busy_percent,
# mem_info_vram_*, hwmon/*/temp1_input) live under the "cardN" sysfs
# entries, not "renderDN" (which is all _lw_gpu_list_json needs).
# ---------------------------------------------------------------------------
_lw_gpu_card_dir_for_pci() {
    local pci="$1" c cpci
    for c in "$LW_GPU_SYSFS_DRM"/card[0-9]*; do
        [ -d "$c/device" ] || continue
        # Skip card connector subdirs like cardN-DP-1 -- only bare cardN.
        case "$(basename "$c")" in card[0-9]*-*) continue ;; esac
        cpci="$(basename "$(readlink -f "$c/device" 2>/dev/null)" 2>/dev/null)"
        [ "$cpci" = "$pci" ] && { echo "$c"; return 0; }
    done
    return 1
}

# _lw_gpu_hwmon_temp_c <carddir> -> prints temp in °C (e.g. "54.2"), or
# nothing if this device exposes no hwmon temperature sensor. Works the
# same way for Intel (i915, newer kernels) and AMD (amdgpu) -- both
# expose their sensor the same way once bound, so no vendor branch needed.
_lw_gpu_hwmon_temp_c() {
    local carddir="$1" hw raw
    for hw in "$carddir"/device/hwmon/hwmon*/temp1_input; do
        [ -r "$hw" ] || continue
        raw="$(cat "$hw" 2>/dev/null)"
        [ -n "$raw" ] || continue
        awk -v m="$raw" 'BEGIN{printf "%.1f", m/1000}'
        return 0
    done
    return 1
}

# ---------------------------------------------------------------------------
# _lw_gpu_stats_json -> prints the full `stats` JSON object (see header).
# One cheap sysfs pass per GPU; nvidia-smi is invoked AT MOST ONCE total
# (batched, all NVIDIA GPUs in one call), and only if an NVIDIA GPU was
# actually detected -- never spawned on Intel/AMD-only systems.
# ---------------------------------------------------------------------------
_lw_gpu_stats_json() {
    local gpus_json items=() g pci vendor carddir
    gpus_json="$(_lw_gpu_list_json)"

    # Batch-fetch NVIDIA metrics once (if any nvidia GPU is present) rather
    # than shelling out per-GPU -- nvidia-smi startup cost is the same
    # whether queried for one GPU or all of them.
    local nvidia_smi_out=""
    if echo "$gpus_json" | jq -e 'any(.[]; .vendor == "nvidia")' >/dev/null 2>&1 \
        && command -v nvidia-smi >/dev/null 2>&1; then
        nvidia_smi_out="$(nvidia-smi --query-gpu=pci.bus_id,utilization.gpu,memory.used,memory.total,temperature.gpu \
            --format=csv,noheader,nounits 2>/dev/null)"
    fi

    # _nvidia_field_for_pci <pci> <field_index 1-4> -> matches nvidia-smi's
    # bus_id (format "00000000:01:00.0") against our short pci id
    # ("0000:01:00.0") by comparing the bus:device.function suffix.
    _nvidia_field_for_pci() {
        local wantpci="$1" idx="$2" suffix line
        suffix="${wantpci#*:}" # "01:00.0"
        [ -n "$nvidia_smi_out" ] || return 1
        line="$(echo "$nvidia_smi_out" | grep -i ":${suffix}$" | head -1)"
        [ -n "$line" ] || return 1
        echo "$line" | awk -F', *' -v i="$((idx + 1))" '{gsub(/^ +| +$/,"",$i); print $i}'
    }

    while IFS= read -r g; do
        [ -n "$g" ] || continue
        pci="$(echo "$g" | jq -r '.pci')"
        vendor="$(echo "$g" | jq -r '.vendor')"

        local util="null" vram_used="null" vram_total="null" temp="null" v

        case "$vendor" in
            nvidia)
                if v="$(_nvidia_field_for_pci "$pci" 1)" && [ -n "$v" ] && [ "$v" != "[N/A]" ]; then util="$v"; fi
                if v="$(_nvidia_field_for_pci "$pci" 2)" && [ -n "$v" ] && [ "$v" != "[N/A]" ]; then vram_used="$v"; fi
                if v="$(_nvidia_field_for_pci "$pci" 3)" && [ -n "$v" ] && [ "$v" != "[N/A]" ]; then vram_total="$v"; fi
                if v="$(_nvidia_field_for_pci "$pci" 4)" && [ -n "$v" ] && [ "$v" != "[N/A]" ]; then temp="$v"; fi
                ;;
            amd)
                if carddir="$(_lw_gpu_card_dir_for_pci "$pci")"; then
                    if [ -r "$carddir/device/gpu_busy_percent" ]; then
                        v="$(cat "$carddir/device/gpu_busy_percent" 2>/dev/null)"
                        [ -n "$v" ] && util="$v"
                    fi
                    if [ -r "$carddir/device/mem_info_vram_used" ]; then
                        v="$(cat "$carddir/device/mem_info_vram_used" 2>/dev/null)"
                        [ -n "$v" ] && vram_used=$((v / 1024 / 1024))
                    fi
                    if [ -r "$carddir/device/mem_info_vram_total" ]; then
                        v="$(cat "$carddir/device/mem_info_vram_total" 2>/dev/null)"
                        [ -n "$v" ] && vram_total=$((v / 1024 / 1024))
                    fi
                    if v="$(_lw_gpu_hwmon_temp_c "$carddir")"; then temp="$v"; fi
                fi
                ;;
            intel)
                # Intel iGPU: VRAM is shared system RAM (no dedicated VRAM
                # concept -- deliberately left null, UI shows "Shared").
                # Utilization needs intel_gpu_top's perf-event access
                # (usually root-only) -- not attempted here to avoid a
                # permission-denied spawn on every 1s poll; left null
                # (graceful degrade). Temperature IS commonly exposed via
                # hwmon on newer kernels, so that one's real when present.
                if carddir="$(_lw_gpu_card_dir_for_pci "$pci")"; then
                    if v="$(_lw_gpu_hwmon_temp_c "$carddir")"; then temp="$v"; fi
                fi
                ;;
        esac

        items+=("$(jq -cn \
            --arg pci "$pci" --arg vendor "$vendor" \
            --argjson util "$util" --argjson vram_used "$vram_used" \
            --argjson vram_total "$vram_total" --argjson temp "$temp" \
            '{pci:$pci, vendor:$vendor, utilization_pct:$util, vram_used_mb:$vram_used, vram_total_mb:$vram_total, temp_c:$temp}')")
    done < <(echo "$gpus_json" | jq -c '.[]')

    if [ "${#items[@]}" -gt 0 ]; then
        jq -cn --argjson gpus "$(IFS=,; echo "[${items[*]}]")" '{gpus:$gpus}'
    else
        echo '{"gpus":[]}'
    fi
}

# ---------------------------------------------------------------------------
# _lw_gpu_pick_role <role> <gpus_json> -> prints ONE gpu object (compact
# JSON) matching <role>, or nothing if it can't be resolved.
#   intel|amd|nvidia   -> first gpu with that vendor
#   power-saving        -> the boot_vga (primary/integrated, lowest-power)
#                           gpu if there's more than one gpu; empty if only
#                           one gpu exists (nothing to switch to)
#   high-performance     -> the best non-boot_vga discrete gpu (nvidia >
#                           amd > intel priority), else empty if only one
#                           gpu exists
# ---------------------------------------------------------------------------
_lw_gpu_pick_role() {
    local role="$1" gpus_json="$2" count
    count="$(echo "$gpus_json" | jq 'length')"

    case "$role" in
        intel|amd|nvidia)
            echo "$gpus_json" | jq -c --arg v "$role" '[.[] | select(.vendor == $v)][0] // empty'
            ;;
        power-saving)
            [ "$count" -le 1 ] && return
            echo "$gpus_json" | jq -c '
                ([.[] | select(.boot_vga == true)][0]) //
                ([.[] | select(.vendor == "intel" or .vendor == "amd")][0]) // empty'
            ;;
        high-performance)
            [ "$count" -le 1 ] && return
            echo "$gpus_json" | jq -c '
                ([.[] | select(.vendor == "nvidia")][0]) //
                ([.[] | select(.boot_vga == false and .vendor == "amd")][0]) //
                ([.[] | select(.boot_vga == false)][0]) //
                empty'
            ;;
    esac
}

# ---------------------------------------------------------------------------
# _lw_gpu_emit_env <gpu_json> -> prints the KEY=VALUE lines for that gpu.
# ---------------------------------------------------------------------------
_lw_gpu_emit_env() {
    local gpu="$1" vendor pci pci_id
    vendor="$(echo "$gpu" | jq -r '.vendor')"
    pci="$(echo "$gpu" | jq -r '.pci')"
    # Mesa's documented DRI_PRIME PCI-id form: "pci-DOMAIN_BUS_DEV_FUNC"
    # (colons/dots replaced with underscores), e.g.
    # "0000:01:00.0" -> "pci-0000_01_00_0".
    pci_id="pci-$(echo "$pci" | tr ':.' '__')"

    case "$vendor" in
        nvidia)
            # NVIDIA (proprietary driver) render-offload: runs ONLY the
            # launched process (mpvpaper) on the NVIDIA GPU while the
            # rest of the desktop/compositor stays exactly where it was.
            # This is the standard, well-documented "prime-run"-style
            # per-process offload mechanism -- it does not touch
            # /etc/prime-discrete, udev, or any global PRIME setting.
            echo "__NV_PRIME_RENDER_OFFLOAD=1"
            echo "__GLX_VENDOR_LIBRARY_NAME=nvidia"
            echo "__VK_LAYER_NV_optimus=NVIDIA_only"
            # Harmless fallback for the (less common) case mpv ends up on
            # a Mesa/nouveau stack instead of the proprietary driver.
            echo "DRI_PRIME=$pci_id"
            ;;
        intel|amd)
            # Mesa multi-GPU selection -- affects only the process it's
            # set for.
            echo "DRI_PRIME=$pci_id"
            ;;
        *)
            echo "DRI_PRIME=$pci_id"
            ;;
    esac
}

ACTION="${1:-detect}"

case "$ACTION" in
    detect)
        _lw_gpu_detect_json
        ;;
    stats)
        _lw_gpu_stats_json
        ;;
    env)
        MODE="${2:-auto}"
        if [ "$MODE" = "auto" ] || [ -z "$MODE" ]; then
            exit 0 # no override -- pre-feature behavior, untouched
        fi

        GPUS_JSON="$(_lw_gpu_detect_json | jq -c '.gpus')"
        PICKED="$(_lw_gpu_pick_role "$MODE" "$GPUS_JSON")"

        if [ -z "$PICKED" ]; then
            lw_log_warn "gpu_manager.sh: mode '$MODE' could not be resolved to an available GPU -- no override applied"
            exit 3
        fi

        _lw_gpu_emit_env "$PICKED"
        ;;
    *)
        echo "Usage: gpu_manager.sh <detect|env|stats> [mode]" >&2
        exit 1
        ;;
esac
