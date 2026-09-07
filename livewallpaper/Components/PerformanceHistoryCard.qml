import QtQuick
import QtQuick.Layouts
import "../Config"
import "../Services"

Rectangle {
    id: root
    Layout.fillWidth: true
    implicitHeight: 300
    radius: Theme.radiusLg
    color: Theme.cardBg
    border.width: 1
    border.color: Theme.panelBorder

    property int historyMinutes: Number(SettingsService.settings.performance_history_minutes || 5)
    property int maxSamples: Math.max(60, Math.min(7200, historyMinutes * 60))
    property var historyOptions: [1,5,15,30,60,120]
    property var samples: PerformanceHistoryService.samples

    // Independent history countdown. This timer is deliberately not linked
    // to PlaylistService: it only controls the history card itself.
    property bool historyTimerEnabled: true
    property int historySecondsRemaining: Math.max(60, historyMinutes * 60)

    function formatCountdown(seconds) {
        const s = Math.max(0, Math.floor(seconds));
        const mins = Math.floor(s / 60);
        const secs = s % 60;
        return String(mins).padStart(2, "0") + ":" + String(secs).padStart(2, "0");
    }

    function updateHistory() {
        const gpuList = GPUManagerService.gpuStats || [];
        let gpu = 0;
        for (const s of gpuList) {
            const v = Number(s && s.utilization_pct);
            if (!isNaN(v))
                gpu = Math.max(gpu, Math.max(0, Math.min(100, v)));
        }
        const cpu = Math.max(0, Math.min(100, Number(SystemStatsService.cpuPercent) || 0));
        const ram = Math.max(0, Math.min(100, Number(SystemStatsService.memPercent) || 0));
        PerformanceHistoryService.maxSamples = maxSamples;
        PerformanceHistoryService.addSample(gpu, cpu, ram);
        canvas.requestPaint();
    }


    function resetHistory() {
        PerformanceHistoryService.samples = []
        root.historySecondsRemaining = Math.max(60, root.historyMinutes * 60)
        canvas.requestPaint()
    }

    function setHistoryRange(minutes) {
        historyMinutes = minutes
        maxSamples = Math.max(60, Math.min(7200, minutes * 60))
        PerformanceHistoryService.maxSamples = maxSamples
        while (PerformanceHistoryService.samples.length > maxSamples)
            PerformanceHistoryService.samples.shift()

        historySecondsRemaining = Math.max(60, minutes * 60)
        canvas.requestPaint()
    }

    Timer {
        id: historySampleTimer
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.updateHistory()
    }

    Timer {
        id: historyCountdownTimer
        interval: 1000
        repeat: true
        running: root.historyTimerEnabled
        onTriggered: {
            if (root.historySecondsRemaining > 0) {
                root.historySecondsRemaining--
            } else {
                root.resetHistory()
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingLg
        spacing: Theme.spacingMd

        RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: "Performance History"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeLg
                    font.bold: true
                }

                Text {
                    text: historyMinutes + " minute history · GPU / CPU / RAM"
                    color: Theme.subtext0
                    font.family: Theme.fontFamilyUi
                    font.pixelSize: Theme.fontSizeSm
                }
            }

            ColumnLayout {
                spacing: 1
                Repeater {
                    model: Math.max(1, GPUManagerService.gpuStats.length)
                    delegate: Text {
                        readonly property var s: GPUManagerService.gpuStats.length > index ? GPUManagerService.gpuStats[index] : null
                        text: (GPUManagerService.gpuStats.length > 1 ? "GPU" + (index + 1) : "GPU") + " " + (() => {
                            if (s && s.utilization_pct !== null && s.utilization_pct !== undefined)
                                return Math.round(Number(s.utilization_pct)) + "%";
                            const list = GPUManagerService.gpuStats || [];
                            let peak = 0;
                            for (const g of list) {
                                const v = Number(g && g.utilization_pct);
                                if (!isNaN(v))
                                    peak = Math.max(peak, v);
                            }
                            return list.length === 1 ? Math.round(peak) + "%" : "—";
                        })()
                        color: index === 0 ? Theme.mauve : (index === 1 ? Theme.pink : Theme.green)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                    }
                }
                Text {
                    text: "CPU " + Math.round(Number(SystemStatsService.cpuPercent) || 0) + "%"
                    color: Theme.blue
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }
                Text {
                    text: "RAM " + Math.round(Number(SystemStatsService.memPercent) || 0) + "%"
                    color: Theme.peach
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Text {
                text: root.historyTimerEnabled
                    ? "next in " + root.formatCountdown(root.historySecondsRemaining)
                    : "next in --:--"
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
            }

            IconButton {
                text: root.historyTimerEnabled ? "On" : "Off"
                fontSize: Theme.fontSizeSm
                mutedColor: Theme.subtext0
                accentColor: Theme.accent
                active: root.historyTimerEnabled
                onClicked: {
                    root.historyTimerEnabled = !root.historyTimerEnabled
                    if (root.historyTimerEnabled && root.historySecondsRemaining <= 0)
                        root.historySecondsRemaining = Math.max(60, root.historyMinutes * 60)
                }
            }

            Item { Layout.fillWidth: true }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Text {
                text: "History:"
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
            }

            Repeater {
                model: root.historyOptions
                delegate: IconButton {
                    text: modelData >= 60 ? (modelData / 60) + "h" : modelData + "m"
                    fontSize: Theme.fontSizeSm
                    active: root.historyMinutes === modelData
                    mutedColor: Theme.subtext0
                    accentColor: Theme.accent
                    onClicked: root.setHistoryRange(modelData)
                }
            }

            IconButton {
                text: "Reset"
                fontSize: Theme.fontSizeSm
                mutedColor: Theme.subtext0
                accentColor: Theme.accent
                onClicked: root.resetHistory()
            }

            Item { Layout.fillWidth: true }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusMd
            color: Qt.rgba(Theme.crust.r, Theme.crust.g, Theme.crust.b, 0.42)
            border.width: 1
            border.color: Qt.rgba(Theme.panelBorder.r, Theme.panelBorder.g, Theme.panelBorder.b, 0.65)

            Canvas {
                id: canvas
                anchors.fill: parent
                anchors.margins: Theme.spacingSm
                antialiasing: true

                onPaint: {
                    const ctx = getContext("2d");
                    const w = width;
                    const h = height;
                    ctx.clearRect(0, 0, w, h);

                    ctx.strokeStyle = Qt.rgba(Theme.overlay0.r, Theme.overlay0.g, Theme.overlay0.b, 0.22);
                    ctx.lineWidth = 1;

                    for (let i = 0; i <= 4; i++) {
                        const y = Math.round((h - 1) * i / 4) + 0.5;
                        ctx.beginPath();
                        ctx.moveTo(0, y);
                        ctx.lineTo(w, y);
                        ctx.stroke();
                    }

                    const data = PerformanceHistoryService.samples || [];
                    if (data.length < 2)
                        return;

                    function drawLine(key, color) {
                        ctx.strokeStyle = color;
                        ctx.lineWidth = 2;
                        ctx.beginPath();

                        for (let i = 0; i < data.length; i++) {
                            const x = (data.length === 1) ? 0 : (i / (data.length - 1)) * (w - 1);
                            const val = Math.max(0, Math.min(100, Number(data[i][key]) || 0));
                            const y = h - (val / 100) * (h - 1);

                            if (i === 0)
                                ctx.moveTo(x, y);
                            else
                                ctx.lineTo(x, y);
                        }
                        ctx.stroke();
                    }

                    drawLine("gpu", Theme.mauve);
                    drawLine("cpu", Theme.blue);
                    drawLine("ram", Theme.peach);
                }

                Connections {
                    target: PerformanceHistoryService
                    function onSamplesChanged() { canvas.requestPaint(); }
                }
            }

            Row {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: Theme.spacingSm
                spacing: Theme.spacingMd

                Text { text: "GPU"; color: Theme.mauve; font.family: Theme.fontFamilyUi; font.pixelSize: Theme.fontSizeSm }
                Text { text: "CPU"; color: Theme.blue; font.family: Theme.fontFamilyUi; font.pixelSize: Theme.fontSizeSm }
                Text { text: "RAM"; color: Theme.peach; font.family: Theme.fontFamilyUi; font.pixelSize: Theme.fontSizeSm }
            }
        }
    }
}
