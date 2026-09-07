import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Services"

Rectangle {
    id: root

    radius: Theme.radiusLg
    color: Theme.cardBg
    border.width: 1
    border.color: Theme.panelBorder
    implicitHeight: content.implicitHeight + Theme.spacingLg * 2

    function applyPreset(name) {
        if (name === "performance") {
            SettingsService.set("adaptive_fps_enabled", true)
            SettingsService.set("adaptive_fps_min", 30)
            SettingsService.set("adaptive_fps_max", 60)
            SettingsService.set("adaptive_gpu_low", 30)
            SettingsService.set("adaptive_gpu_high", 75)
            SettingsService.set("thermal_protection_enabled", true)
            SettingsService.set("thermal_warning_c", 75)
            SettingsService.set("thermal_critical_c", 85)
            SettingsService.set("thermal_warning_fps", 30)
            SettingsService.set("battery_profiles_enabled", true)
            SettingsService.set("battery_fps", 60)
            SettingsService.set("low_battery_threshold", 20)
            SettingsService.set("low_battery_fps", 30)
        } else if (name === "balanced") {
            SettingsService.set("adaptive_fps_enabled", true)
            SettingsService.set("adaptive_fps_min", 24)
            SettingsService.set("adaptive_fps_max", 60)
            SettingsService.set("adaptive_gpu_low", 30)
            SettingsService.set("adaptive_gpu_high", 75)
            SettingsService.set("thermal_protection_enabled", true)
            SettingsService.set("thermal_warning_c", 75)
            SettingsService.set("thermal_critical_c", 85)
            SettingsService.set("thermal_warning_fps", 30)
            SettingsService.set("battery_profiles_enabled", true)
            SettingsService.set("battery_fps", 30)
            SettingsService.set("low_battery_threshold", 20)
            SettingsService.set("low_battery_fps", 20)
        } else if (name === "battery") {
            SettingsService.set("adaptive_fps_enabled", true)
            SettingsService.set("adaptive_fps_min", 20)
            SettingsService.set("adaptive_fps_max", 45)
            SettingsService.set("adaptive_gpu_low", 20)
            SettingsService.set("adaptive_gpu_high", 60)
            SettingsService.set("thermal_protection_enabled", true)
            SettingsService.set("thermal_warning_c", 70)
            SettingsService.set("thermal_critical_c", 80)
            SettingsService.set("thermal_warning_fps", 20)
            SettingsService.set("battery_profiles_enabled", true)
            SettingsService.set("battery_fps", 20)
            SettingsService.set("low_battery_threshold", 10)
            SettingsService.set("low_battery_fps", 15)
        } else if (name === "silent") {
            SettingsService.set("adaptive_fps_enabled", true)
            SettingsService.set("adaptive_fps_min", 15)
            SettingsService.set("adaptive_fps_max", 24)
            SettingsService.set("adaptive_gpu_low", 10)
            SettingsService.set("adaptive_gpu_high", 50)
            SettingsService.set("thermal_protection_enabled", true)
            SettingsService.set("thermal_warning_c", 60)
            SettingsService.set("thermal_critical_c", 75)
            SettingsService.set("thermal_warning_fps", 15)
            SettingsService.set("battery_profiles_enabled", true)
            SettingsService.set("battery_fps", 15)
            SettingsService.set("low_battery_threshold", 5)
            SettingsService.set("low_battery_fps", 10)
        } else if (name === "reset") {
            SettingsService.set("adaptive_fps_enabled", false)
            SettingsService.set("adaptive_fps_min", 24)
            SettingsService.set("adaptive_fps_max", 60)
            SettingsService.set("adaptive_gpu_low", 30)
            SettingsService.set("adaptive_gpu_high", 75)
            SettingsService.set("thermal_protection_enabled", true)
            SettingsService.set("thermal_warning_c", 75)
            SettingsService.set("thermal_critical_c", 85)
            SettingsService.set("thermal_warning_fps", 30)
            SettingsService.set("battery_profiles_enabled", true)
            SettingsService.set("battery_fps", 30)
            SettingsService.set("low_battery_threshold", 20)
            SettingsService.set("low_battery_fps", 20)
        }
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Theme.spacingLg
        spacing: Theme.spacingMd

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "⚡ Advanced Performance"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMd
                font.bold: true
                Layout.fillWidth: true
            }

            Text {
                text: PerformanceService.stateText
                color: PerformanceService.thermalState === "critical"
                    ? Theme.danger
                    : (PerformanceService.thermalState === "warning"
                        ? Theme.peach
                        : Theme.subtext0)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
            }
        }

        Text {
            Layout.fillWidth: true
            text: "Choose values with the quick options below. These settings affect runtime wallpaper performance."
            color: Theme.overlay0
            font.family: Theme.fontFamilyUi
            font.pixelSize: Theme.fontSizeSm
            wrapMode: Text.WordWrap
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.panelBorder }

        SettingRow {
            label: "Adaptive FPS"
            ToggleSwitch {
                checked: SettingsService.adaptiveFpsEnabled
                onToggled: SettingsService.set("adaptive_fps_enabled", !SettingsService.adaptiveFpsEnabled)
            }
        }

        Text {
            Layout.fillWidth: true
            text: "GPU " + (PerformanceService.currentGpuPercent >= 0
                ? Math.round(PerformanceService.currentGpuPercent) + "%"
                : "N/A")
                + " → target "
                + (PerformanceService.adaptiveTargetFps > 0
                    ? PerformanceService.adaptiveTargetFps + " FPS"
                    : "user FPS")
            color: Theme.subtext0
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
        }

        PerformancePresetRow {
            label: "Minimum FPS"
            suffix: " FPS"
            options: [15, 24, 30, 45, 60]
            currentValue: SettingsService.adaptiveFpsMin
            enabled: SettingsService.adaptiveFpsEnabled
            onSelected: (value) => SettingsService.set("adaptive_fps_min", value)
        }

        PerformancePresetRow {
            label: "Maximum FPS"
            suffix: " FPS"
            options: [24, 30, 45, 60, 90, 120]
            currentValue: SettingsService.adaptiveFpsMax
            enabled: SettingsService.adaptiveFpsEnabled
            onSelected: (value) => SettingsService.set("adaptive_fps_max", value)
        }

        PerformancePresetRow {
            label: "GPU Low Threshold"
            suffix: "%"
            options: [10, 20, 30, 40, 50, 60]
            currentValue: SettingsService.adaptiveGpuLow
            enabled: SettingsService.adaptiveFpsEnabled
            onSelected: (value) => SettingsService.set("adaptive_gpu_low", value)
        }

        PerformancePresetRow {
            label: "GPU High Threshold"
            suffix: "%"
            options: [50, 60, 75, 85, 95]
            currentValue: SettingsService.adaptiveGpuHigh
            enabled: SettingsService.adaptiveFpsEnabled
            onSelected: (value) => SettingsService.set("adaptive_gpu_high", value)
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.panelBorder }

        SettingRow {
            label: "Thermal Protection"
            ToggleSwitch {
                checked: SettingsService.thermalProtectionEnabled
                onToggled: SettingsService.set("thermal_protection_enabled", !SettingsService.thermalProtectionEnabled)
            }
        }

        PerformancePresetRow {
            label: "Warning Temperature"
            suffix: "°C"
            options: [60, 65, 75, 80, 85]
            currentValue: SettingsService.thermalWarningC
            enabled: SettingsService.thermalProtectionEnabled
            onSelected: (value) => SettingsService.set("thermal_warning_c", value)
        }

        PerformancePresetRow {
            label: "Critical Temperature"
            suffix: "°C"
            options: [80, 85, 90, 95, 100]
            currentValue: SettingsService.thermalCriticalC
            enabled: SettingsService.thermalProtectionEnabled
            onSelected: (value) => SettingsService.set("thermal_critical_c", value)
        }

        PerformancePresetRow {
            label: "Warning FPS Cap"
            suffix: " FPS"
            options: [15, 20, 30, 45, 60]
            currentValue: SettingsService.thermalWarningFps
            enabled: SettingsService.thermalProtectionEnabled
            onSelected: (value) => SettingsService.set("thermal_warning_fps", value)
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.panelBorder }

        SettingRow {
            label: "Battery Profiles"
            ToggleSwitch {
                checked: SettingsService.batteryProfilesEnabled
                onToggled: SettingsService.set("battery_profiles_enabled", !SettingsService.batteryProfilesEnabled)
            }
        }

        PerformancePresetRow {
            label: "Battery FPS"
            suffix: " FPS"
            options: [20, 30, 45, 60]
            currentValue: SettingsService.batteryFps
            enabled: SettingsService.batteryProfilesEnabled
            onSelected: (value) => SettingsService.set("battery_fps", value)
        }

        PerformancePresetRow {
            label: "Low Battery Threshold"
            suffix: "%"
            options: [5, 10, 20, 30, 40]
            currentValue: SettingsService.lowBatteryThreshold
            enabled: SettingsService.batteryProfilesEnabled
            onSelected: (value) => SettingsService.set("low_battery_threshold", value)
        }

        PerformancePresetRow {
            label: "Low Battery FPS"
            suffix: " FPS"
            options: [10, 15, 20, 24, 30]
            currentValue: SettingsService.lowBatteryFps
            enabled: SettingsService.batteryProfilesEnabled
            onSelected: (value) => SettingsService.set("low_battery_fps", value)
        }

        Text {
            Layout.fillWidth: true
            text: PowerService.hasBattery
                ? ("Battery: "
                    + (PowerService.batteryPercent >= 0
                        ? PowerService.batteryPercent + "%"
                        : "unknown")
                    + (PowerService.onBattery
                        ? " · on battery"
                        : (PowerService.charging
                            ? " · charging"
                            : " · plugged in")))
                : "Battery: no battery detected"
            color: Theme.overlay0
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.panelBorder }

        Text {
            text: "Presets"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeMd
            font.bold: true
        }

        Text {
            Layout.fillWidth: true
            text: "Quickly apply a complete performance profile."
            color: Theme.subtext0
            font.family: Theme.fontFamilyUi
            font.pixelSize: Theme.fontSizeSm
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Text {
                text: "Preset:"
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
            }

            Repeater {
                model: [
                    { key: "performance", label: "Performance" },
                    { key: "balanced", label: "Balanced" },
                    { key: "battery", label: "Battery Saver" },
                    { key: "silent", label: "Silent" },
                    { key: "reset", label: "Reset" }
                ]

                delegate: IconButton {
                    required property var modelData
                    text: modelData.label
                    fontSize: Theme.fontSizeSm
                    mutedColor: Theme.subtext0
                    accentColor: Theme.accent
                    onClicked: root.applyPreset(modelData.key)
                }
            }

            Item { Layout.fillWidth: true }
        }
    }
}
