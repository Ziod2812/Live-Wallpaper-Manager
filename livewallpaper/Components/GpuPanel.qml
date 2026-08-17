import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Services"

/*
 * GpuPanel.qml
 * ---------------
 * GPU Switching feature, moved from the Toolbar into a dedicated card on
 * PerformancePage. This is a VIEW ONLY: it reuses Services/GPUManagerService.qml
 * (detection/selection/validation) and Components/GpuSelector.qml (the mode
 * dropdown) completely unmodified -- no GPU logic is duplicated here, and
 * GPUManagerService's architecture is untouched.
 *
 * Layout:
 *   - Info rows (StatRow, using the same "Label ......... Value" pattern
 *     already uses): Current GPU, Current Renderer, Graphics API,
 *     GPU Vendor, GPU Model, Detected GPUs, Current GPU Mode -- always
 *     shown, even on single-GPU systems, so the detected GPU is always
 *     visible read-only regardless of switching availability.
 *   - GpuSelector -- shown only when GPUManagerService.selectorVisible
 *     (2+ GPUs detected; root._multiGpu mirrors it). With 0/1 GPU the
 *     "Switch GPU" row is hidden entirely and replaced with an explicit
 *     "Only one GPU detected. GPU switching is unavailable." (or "No GPU
 *     detected...") notice -- there's nothing to switch between, so no
 *     control is shown for it. GpuSelector's own internal disabled-state
 *     rendering (unmodified) still applies if it's ever reused elsewhere.
 *   - Apply / Restart Wallpaper / Reset to Auto -- thin wrappers around
 *     existing methods only:
 *       Apply           -> GPUManagerService.setMode() with the already-
 *                          selected mode, then PlaybackService.reapplyForGpuChange()
 *                          so a change is guaranteed to take effect even if
 *                          selectedMode's value didn't itself change.
 *                          Disabled (root._multiGpu false) with 0/1 GPU --
 *                          there's no alternate mode to apply.
 *       Restart Wallpaper -> PlaybackService.reapplyForGpuChange() directly --
 *                          relaunch on the current GPU mode without touching
 *                          the selection.
 *       Reset to Auto     -> GPUManagerService.setMode("auto").
 *     None of these three add new GPU-switching behavior; they only call
 *     what GPUManagerService/PlaybackService already expose.
 *
 * "Current GPU" (the physical device presumed active) is derived, read-only,
 * from data GPUManagerService already exposes (gpus[] + selectedMode) --
 * no new detection is added. "Current Renderer" / "Current Graphics API"
 * are GPUManagerService.currentRenderer / currentApi as-is (best-effort
 * glxinfo/vulkaninfo read from gpu_manager.sh, already informational-only).
 *
 * LIVE STATS -- one row per detected GPU showing utilization / VRAM /
 * temperature, sourced from GPUManagerService.gpuStats (polled every 1s
 * from gpu_manager.sh's new `stats` action -- see that script's header).
 * Any metric a given GPU/vendor/driver doesn't expose comes back as
 * `null` and is shown as "Not available" / "Shared with system RAM"
 * (Intel VRAM) rather than a misleading 0 -- this is the "gracefully
 * degrade" requirement, handled once here via _fmtPct/_fmtVram/_fmtTemp
 * rather than reimplemented per row.
 */
Rectangle {
    id: root
    radius: Theme.radiusLg
    color: Theme.cardBg
    border.width: 1
    border.color: Theme.panelBorder
    implicitHeight: content.implicitHeight + Theme.spacingLg * 2

    readonly property var _modeLabels: ({
        "auto": "Auto",
        "intel": "Intel GPU",
        "amd": "AMD GPU",
        "nvidia": "NVIDIA GPU",
        "power-saving": "Power Saving",
        "high-performance": "High Performance"
    })
    function _modeLabel(mode) {
        return root._modeLabels[mode] || mode;
    }

    // "Current GPU" is only ever a DIRECT, unambiguous match against
    // data GPUManagerService already exposes -- either the single GPU on
    // a single-GPU box, or the one specific vendor the user picked
    // (intel/amd/nvidia). For "auto"/"power-saving"/"high-performance" on
    // a multi-GPU box there is deliberately no guess here: which physical
    // device those roles resolve to is gpu_manager.sh's
    // _lw_gpu_pick_role() heuristic (boot_vga / vendor-priority order,
    // re-evaluated fresh at launch time) -- reimplementing that logic
    // here would duplicate it and could drift out of sync with the real
    // resolution. Current Renderer/Current Graphics API below (read
    // straight from GPUManagerService.currentRenderer/currentApi) are the
    // actual live answer for those three modes.
    readonly property var _currentGpu: {
        const gpus = GPUManagerService.gpus;
        if (!gpus || gpus.length === 0) return null;
        if (gpus.length === 1) return gpus[0];
        const mode = GPUManagerService.selectedMode;
        if (mode === "intel" || mode === "amd" || mode === "nvidia") {
            return gpus.find(g => g.vendor === mode) || null;
        }
        return null; // auto / power-saving / high-performance -- see comment above
    }
    readonly property string _currentGpuLabel: {
        if (root._currentGpu) return root._currentGpu.label + " (" + root._currentGpu.render_node + ")";
        if (GPUManagerService.currentRenderer) return GPUManagerService.currentRenderer + " (see Current Renderer)";
        return "Resolved at launch — see Current Renderer";
    }
    readonly property string _detectedGpusLabel: {
        const gpus = GPUManagerService.gpus;
        if (!GPUManagerService.detected) return "Detecting…";
        if (!gpus || gpus.length === 0) return "None detected";
        return gpus.length + " — " + gpus.map(g => g.label).join(", ");
    }

    // GPU Vendor / GPU Model -- same direct-match rule as _currentGpu
    // above (single GPU, or an unambiguous intel/amd/nvidia pick on a
    // multi-GPU box); on auto/power-saving/high-performance with several
    // GPUs there's no single vendor/model to name, so this mirrors
    // _currentGpuLabel's fallback rather than guessing.
    readonly property var _vendorLabels: ({ "intel": "Intel", "amd": "AMD", "nvidia": "NVIDIA" })
    readonly property string _currentGpuVendor: root._currentGpu ? (root._vendorLabels[root._currentGpu.vendor] || root._currentGpu.vendor) : "Resolved at launch"
    readonly property string _currentGpuModel: root._currentGpu ? root._currentGpu.label : "Resolved at launch"

    readonly property bool _canRestart: PlaybackService.playMode === "wallpapers" && PlaybackService.currentPath !== ""

    // GPU switching (selector + Apply) only makes sense with 2+ GPUs --
    // mirrors GPUManagerService.selectorVisible (its own "more than one
    // GPU" check) so this card never re-derives that condition.
    readonly property bool _multiGpu: GPUManagerService.selectorVisible
    readonly property string _singleGpuMessage: {
        if (!GPUManagerService.detected) return "";
        if (GPUManagerService.gpus.length === 0) return "No GPU detected. GPU switching is unavailable.";
        return "Only one GPU detected. GPU switching is unavailable.";
    }

    // ── Live stats formatting -- centralizes the "null = not available"
    // graceful-degrade rule so no individual row has to special-case it. ──
    function _fmtPct(v) {
        return (v === null || v === undefined) ? "Not available" : Math.round(v) + "%";
    }
    function _fmtTemp(v) {
        return (v === null || v === undefined) ? "Not available" : v.toFixed(1) + "°C";
    }
    function _fmtVram(used, total, vendor) {
        if (vendor === "intel" && (used === null || used === undefined)) return "Shared with system RAM";
        if (used === null || used === undefined || total === null || total === undefined) return "Not available";
        return used + " / " + total + " MB";
    }

    function applyGpu() {
        // Re-asserts the persisted mode (in case it drifted, e.g. after a
        // detection refresh) and guarantees a relaunch even when
        // selectedMode's value doesn't itself change.
        GPUManagerService.setMode(GPUManagerService.selectedMode);
        PlaybackService.reapplyForGpuChange();
        NotifyService.info("GPU settings applied.");
    }

    function restartWallpaperNow() {
        PlaybackService.reapplyForGpuChange();
    }

    function resetToAuto() {
        GPUManagerService.setMode("auto");
    }

    ColumnLayout {
        id: content
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: Theme.spacingLg }
        spacing: Theme.spacingMd

        // ── Header ───────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            Text {
                text: "🎮 GPU"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMd
                font.bold: true
                Layout.fillWidth: true
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.panelBorder }

        // ── Info rows ────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            StatRow { label: "Current GPU";        value: root._currentGpuLabel }
            StatRow { label: "Current Renderer";    value: GPUManagerService.currentRenderer || "Unknown" }
            StatRow { label: "Graphics API";        value: GPUManagerService.currentApi || "Unknown" }
            StatRow { label: "GPU Vendor";          value: root._currentGpuVendor }
            StatRow { label: "GPU Model";           value: root._currentGpuModel }
            StatRow { label: "Detected GPUs";       value: root._detectedGpusLabel }
            StatRow {
                label: "Current GPU Mode"
                value: root._modeLabel(GPUManagerService.selectedMode)
                valueColor: Theme.accent
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.panelBorder }

        // ── Live per-GPU stats (utilization / VRAM / temperature) --
        // one block per detected GPU, refreshed every 1s while this page
        // is open (GPUManagerService.statsActive, set by PerformancePage).
        // Any field the current driver/vendor doesn't expose is shown as
        // "Not available" / "Shared with system RAM" -- never a fake 0. ──
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingMd

            Repeater {
                model: GPUManagerService.gpus
                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Theme.spacingXs

                    readonly property var _stats: GPUManagerService.statsFor(modelData.pci)

                    Text {
                        text: modelData.label + "  ·  " + modelData.render_node
                        color: Theme.subtext1
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        font.bold: true
                    }

                    StatRow {
                        label: "Utilization"
                        value: root._fmtPct(_stats ? _stats.utilization_pct : null)
                    }
                    StatRow {
                        label: "VRAM"
                        value: root._fmtVram(_stats ? _stats.vram_used_mb : null, _stats ? _stats.vram_total_mb : null, modelData.vendor)
                    }
                    StatRow {
                        label: "Temperature"
                        value: root._fmtTemp(_stats ? _stats.temp_c : null)
                    }
                }
            }
        }

        // ── Mode selector -- only meaningful with 2+ GPUs. On a
        // single/no-GPU system there's nothing to switch between, so the
        // selector row is replaced with an explicit, read-only notice
        // instead of presenting a control that can't do anything. ───────
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.panelBorder }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            visible: root._multiGpu

            Text {
                text: "Switch GPU"
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                Layout.fillWidth: true
            }

            GpuSelector {
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // Single/no-GPU notice -- GPU switching disabled, detected GPU
        // (if any) is shown read-only via the "Current GPU" info row above.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            visible: !root._multiGpu && GPUManagerService.detected

            Text {
                text: root._singleGpuMessage
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                font.italic: true
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.panelBorder }

        // ── Actions ──────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Item { Layout.fillWidth: true }

            IconButton {
                text: "Reset to Auto"
                fontSize: Theme.fontSizeSm
                enabled: GPUManagerService.selectedMode !== "auto"
                opacity: enabled ? 1.0 : 0.4
                onClicked: root.resetToAuto()
            }

            IconButton {
                text: "Restart Wallpaper"
                fontSize: Theme.fontSizeSm
                accentColor: Theme.yellow
                enabled: root._canRestart
                opacity: enabled ? 1.0 : 0.4
                onClicked: root.restartWallpaperNow()
            }

            IconButton {
                text: "Apply"
                fontSize: Theme.fontSizeSm
                accentColor: Theme.accent
                bold: true
                // Nothing to apply when there's only one (or zero) GPU --
                // there's no alternate mode the selector could have set.
                enabled: root._multiGpu
                opacity: enabled ? 1.0 : 0.4
                onClicked: root.applyGpu()
            }
        }
    }
}
