import QtQuick
import "../Services"

/*
 * PeaclockCavaVisualizer.qml
 * -----------------------------
 * Renderer for the Peaclock + Cava Dock's existing CAVA strip (see
 * Components/PeaclockCavaDock.qml). This intentionally mirrors
 * Components/MusicDock.qml's own "bars"/"waveform" rendering byte-for-
 * byte in every way that touches the DATA -- same raw CavaService.bars
 * values, same 0..255 -> 0..1 normalization (level / 255), same peak/
 * decay behavior (a plain Behavior/NumberAnimation, not a custom
 * envelope follower), same fill/opacity formula, same update rate (one
 * repaint per CavaService.bars change, no extra timers). There is no
 * second processing layer here -- this file only re-lays the exact same
 * original-Cava-pipeline output into Peaclock's own strip geometry and
 * its own independent color setting.
 *
 * Three render styles:
 *   - "bars"     -- thin bars, mirrored around the strip's vertical
 *                   center (MusicDock's are bottom-anchored only because
 *                   its strip sits directly above a "Nothing playing"
 *                   label with no room below; Peaclock's strip has
 *                   headroom on both sides, so bars grow from the middle
 *                   the same way this dock's strip always has -- this is
 *                   layout, not a data transformation).
 *   - "waveform" -- MusicDock's own mirrored filled trace (top+bottom
 *                   mirror of the same raw levels around a center
 *                   baseline), unchanged.
 *   - "line"     -- thin stroked zigzag trace (ECG/pulse-monitor look),
 *                   unfilled, alternating above/below the strip's
 *                   center baseline sample-to-sample -- new, additive,
 *                   see lineCanvas below. Shares "waveform"'s color
 *                   (CavaService.pcWaveformColor), not "bars"'.
 *
 * INDEPENDENCE CONTRACT (unchanged):
 *   - Reads CavaService.bars -- the exact same frame data / one shared
 *     cava pipeline Components/MusicDock.qml already reads. No second
 *     Cava process, no new backend, no new lifecycle hooks.
 *   - "bars" style reads CavaService.pcVisualizerColor exclusively --
 *     the existing Manual/Random/Rainbow color system already scoped to
 *     this dock. "waveform" style reads CavaService.pcWaveformColor --
 *     a second, independent Manual/Random/Rainbow color slot scoped only
 *     to the waveform trace (see that property's header in
 *     CavaService.qml) -- so the two render styles can use different
 *     colors and tuning one never affects the other.
 *   - Sensitivity (CavaService.pcSensitivity) is applied the same way
 *     MusicDock's real "Sensitivity" setting works conceptually -- a
 *     plain linear gain on the signal, not a reshaping curve. It is
 *     still a client-side multiplier (not fed into cava.conf) because
 *     that setting is shared with Music Dock and must stay untouched by
 *     this dock (see CavaService.qml's pcSensitivity header) -- but the
 *     math itself is now the same kind of plain multiply-and-clamp
 *     original Cava uses, not a per-level gamma/floor/ceiling curve.
 *     128 (default) == 1.0x == the exact same numbers MusicDock shows
 *     for the same raw bars frame.
 *   - Sized purely by its parent (see PeaclockCavaDock.qml's Item
 *     wrapper) -- this component never changes the dock's card size,
 *     spacing, or layout; it only changes what gets painted inside the
 *     existing CAVA strip.
 */
Item {
    id: root

    readonly property var _levels: CavaService.bars
    readonly property color _color: CavaService.pcVisualizerColor

    // Plain linear gain -- 128 (default) is exactly 1.0x, i.e. identical
    // numbers to the raw CavaService.bars frame (same as MusicDock shows
    // with no client-side scaling at all). 32/64/256 scale that same raw
    // signal down/up proportionally (0.25x / 0.5x / 2.0x) -- a multiply,
    // not a reshaping curve, matching how a real capture-gain/sensitivity
    // knob works.
    readonly property real _gain: CavaService.pcSensitivity / 128.0

    // Raw level -> normalized 0..1 fraction. This is the ENTIRE data
    // pipeline: real cava byte (0-255) / 255, times the plain gain above,
    // clamped. No envelope follower, no attack/release smoothing, no
    // gamma curve, no synthetic jitter -- identical in kind to
    // MusicDock.qml's own `(level / 255)` used directly in its bar
    // height/opacity and waveform amplitude.
    function _fracAt(i, n) {
        const src = root._levels;
        const srcLen = src.length;
        if (srcLen === 0 || n <= 0) return 0;
        const idx = Math.min(srcLen - 1, Math.floor(i * srcLen / n));
        const level = src[idx] || 0;
        const f = (level / 255) * root._gain;
        return Math.max(0, Math.min(1, f));
    }

    // Same display-density cap as before -- purely a "how many of the
    // real raw samples fit this strip's fixed width" choice (Peaclock's
    // strip is Layout.fillWidth, unlike MusicDock's own bar-count-sized
    // area), not a change to any sample's value.
    readonly property int _sampleCount: Math.max(1, Math.min(root._levels.length, 90))

    // -------------------- BARS (mirrored around center) --------------------
    // Same shape/formula as MusicDock.qml's bars Repeater --
    // height = max(2, frac * area.height), opacity = 0.55 + 0.45*frac,
    // same Behavior-based decay (120ms OutQuad, MusicDock's own default
    // "Animation speed") -- just mirrored around the strip's vertical
    // middle instead of bottom-anchored, since this strip has headroom on
    // both sides (a layout difference, not a data one).
    Row {
        id: barsRow
        anchors.fill: parent
        visible: CavaService.pcVisualizerStyle === "bars"
        spacing: Math.max(1, width / root._sampleCount * 0.18)

        Repeater {
            model: root._sampleCount
            delegate: Rectangle {
                id: barDelegate
                required property int index
                readonly property real frac: root._fracAt(index, root._sampleCount)
                anchors.verticalCenter: barsRow.verticalCenter
                width: Math.max(1, (barsRow.width - (root._sampleCount - 1) * barsRow.spacing) / root._sampleCount)
                radius: Math.min(1.5, width / 2)
                height: Math.max(2, frac * barsRow.height)
                color: root._color
                opacity: 0.55 + 0.45 * frac
                Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
        }
    }

    // -------------------- WAVEFORM (MusicDock's mirrored fill, unchanged) --
    // Byte-for-byte the same technique as Components/MusicDock.qml's own
    // waveform Canvas: a single closed path built from the real raw
    // levels mirrored above and below a center baseline, then filled --
    // not a stroked line, no interpolation between samples, no per-point
    // noise. One repaint per real CavaService.bars frame (onLevelsChanged
    // -> requestPaint()), same as MusicDock -- no extra timer/update
    // loop.
    Canvas {
        id: waveCanvas
        anchors.fill: parent
        visible: CavaService.pcVisualizerStyle === "waveform"
        readonly property var levels: root._levels
        // Dedicated waveform-only color (see CavaService.qml's "Peaclock
        // + Cava Dock: dedicated Waveform Color" header) -- intentionally
        // NOT root._color/pcVisualizerColor, so this never affects the
        // "bars" style above, which keeps reading pcVisualizerColor
        // unchanged.
        readonly property color waveColor: CavaService.pcWaveformColor
        readonly property real gain: root._gain

        onLevelsChanged: requestPaint()
        onWaveColorChanged: requestPaint()
        onGainChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        function _path(ctx, ampScale) {
            const n = root._sampleCount;
            const mid = height / 2;
            ctx.beginPath();
            for (let i = 0; i < n; i++) {
                const frac = root._fracAt(i, n);
                const amp = frac * mid * ampScale;
                const x = (n <= 1) ? 0 : (i / (n - 1)) * width;
                const y = mid - amp;
                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
            }
            for (let i = n - 1; i >= 0; i--) {
                const frac = root._fracAt(i, n);
                const amp = frac * mid * ampScale;
                const x = (n <= 1) ? 0 : (i / (n - 1)) * width;
                const y = mid + amp;
                ctx.lineTo(x, y);
            }
            ctx.closePath();
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            if (levels.length < 1) return;

            ctx.globalAlpha = 0.85;
            ctx.fillStyle = waveColor;
            _path(ctx, 1.0);
            ctx.fill();
        }
    }

    // -------------------- LINE (thin zigzag pulse trace) --------------------
    // Third render style: an unfilled, stroked trace that alternates
    // above/below the strip's center baseline -- the ECG/pulse-monitor
    // look, as opposed to "waveform" above's smooth filled mirror. Same
    // underlying data pipeline as every other style here (root._fracAt
    // -> the exact same real CavaService.bars levels, same gain) -- only
    // how those fractions are turned into points differs.
    //
    // Oversampled: the reference look is a FINE, dense zigzag texture
    // riding on top of the slower per-bar amplitude envelope (many small
    // teeth per bar, not one triangle per bar) -- so between each pair of
    // real adjacent bars this linearly interpolates `_oversample` extra
    // points and alternates the sign on every one of those finer points
    // (not just once per real bar).
    //
    // Per-point jitter: cava's own capture-side smoothing (monstercat,
    // in scripts/cava.conf -- shared with Music Dock's pipeline, so it
    // is never changed here) tends to cascade a single loud bar into one
    // smooth "mountain" across its neighbors. Left alone, that renders
    // as one smooth curve instead of the reference's dense, chaotic
    // texture. To match the reference without touching the shared
    // capture pipeline (which would also change Music Dock's bars), each
    // point's amplitude is multiplied by a bounded per-point randomizer
    // -- but that multiplier is applied ON TOP OF the real interpolated
    // magnitude, never in place of it, so a point where the real signal
    // is at/near zero still renders at/near zero regardless of the
    // randomizer (true digital silence still draws a flat line, it does
    // not fabricate activity). Shares CavaService.pcWaveformColor with
    // "waveform" above (both are waveform-family styles) -- picking a
    // Waveform Color still affects only these two styles, never "bars".
    Canvas {
        id: lineCanvas
        anchors.fill: parent
        visible: CavaService.pcVisualizerStyle === "line"
        readonly property var levels: root._levels
        readonly property color lineColor: CavaService.pcWaveformColor
        readonly property real gain: root._gain
        // Extra interpolated points drawn between each pair of real
        // samples -- purely a rendering density knob (finer teeth),
        // matching the fine jittery texture of a real pulse/ECG trace
        // instead of one wide triangle per bar.
        readonly property int oversample: 4

        onLevelsChanged: requestPaint()
        onLineColorChanged: requestPaint()
        onGainChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            if (levels.length < 1) return;

            const n = root._sampleCount;
            const mid = height / 2;
            // Small headroom so a full-amplitude spike never clips the
            // strip's edge -- purely a drawing margin, not a data change.
            const usable = mid * 0.92;
            const os = Math.max(1, lineCanvas.oversample);
            const totalPoints = Math.max(1, (n - 1) * os + 1);

            ctx.beginPath();
            for (let p = 0; p < totalPoints; p++) {
                // Which two real samples this finer point falls between,
                // and how far along (0..1) -- straight linear
                // interpolation of the real fraction, never synthetic
                // noise.
                const i0 = Math.min(n - 1, Math.floor(p / os));
                const i1 = Math.min(n - 1, i0 + 1);
                const t = (p / os) - i0;
                const f0 = root._fracAt(i0, n);
                const f1 = root._fracAt(i1, n);
                const frac = f0 + (f1 - f0) * t;
                // Bounded per-point texture (see header) -- scales the
                // REAL magnitude above, never substitutes for it.
                const jitter = 0.4 + 0.6 * Math.random();
                const amp = frac * usable * jitter;
                const sign = (p % 2 === 0) ? 1 : -1;
                const x = (totalPoints <= 1) ? 0 : (p / (totalPoints - 1)) * width;
                const y = mid - sign * amp;
                if (p === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
            }

            ctx.globalAlpha = 0.9;
            ctx.strokeStyle = lineColor;
            ctx.lineWidth = 1.5;
            ctx.lineJoin = "round";
            ctx.lineCap = "round";
            ctx.stroke();
        }
    }
}
